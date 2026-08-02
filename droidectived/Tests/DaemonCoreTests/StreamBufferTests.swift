import Foundation
import Testing

@testable import DaemonCore

/// The drop policy is a decision, not an implementation detail, so it is
/// pinned here rather than left to whatever the queue happens to do under load.
@Suite struct StreamBufferTests {
    @Test func holdsEverythingUnderCapacity() {
        var buffer = StreamBuffer<Int>(capacity: 5)
        buffer.append(contentsOf: [1, 2, 3])

        let drained = buffer.drain()
        #expect(drained.items == [1, 2, 3])
        #expect(drained.dropped == 0, "nothing was over capacity, so nothing was lost")
    }

    @Test func dropsOldestNotNewest() {
        // A log tail is read from the bottom: the newest lines are the ones
        // worth keeping, so overflow must discard from the front.
        var buffer = StreamBuffer<Int>(capacity: 3)
        buffer.append(contentsOf: [1, 2, 3, 4, 5])

        let drained = buffer.drain()
        #expect(drained.items == [3, 4, 5])
        #expect(drained.dropped == 2)
    }

    @Test func neverExceedsCapacityAcrossManyAppends() {
        var buffer = StreamBuffer<Int>(capacity: 4)
        for batch in 0..<50 {
            buffer.append(contentsOf: [batch * 2, batch * 2 + 1])
            #expect(buffer.pending.count <= 4, "the buffer is what bounds daemon memory")
        }
        let drained = buffer.drain()
        #expect(drained.items == [96, 97, 98, 99], "the newest survive")
        #expect(drained.dropped == 96)
    }

    @Test func reportsTheGapWithTheBatchItPrecedes() {
        // The count rides with the batch so the UI can place the gap: these
        // items arrived *after* that many were lost.
        var buffer = StreamBuffer<Int>(capacity: 2)
        buffer.append(contentsOf: [1, 2, 3])

        let first = buffer.drain()
        #expect(first.items == [2, 3])
        #expect(first.dropped == 1)

        buffer.append(contentsOf: [4])
        let second = buffer.drain()
        #expect(second.items == [4])
        #expect(second.dropped == 0, "the gap is reported once, not carried forward")
    }

    @Test func drainingLeavesItEmpty() {
        var buffer = StreamBuffer<Int>(capacity: 3)
        buffer.append(contentsOf: [1, 2, 3, 4])
        _ = buffer.drain()

        #expect(buffer.isEmpty)
        let again = buffer.drain()
        #expect(again.items.isEmpty)
        #expect(again.dropped == 0)
    }

    @Test func aSingleOversizedBatchIsTruncatedNotRejected() {
        // A burst larger than the whole buffer must still deliver its tail —
        // dropping the batch entirely would lose the most recent lines, which
        // is the opposite of the policy.
        var buffer = StreamBuffer<Int>(capacity: 3)
        buffer.append(contentsOf: Array(1...100))

        let drained = buffer.drain()
        #expect(drained.items == [98, 99, 100])
        #expect(drained.dropped == 97)
    }

    @Test func emptyAppendChangesNothing() {
        var buffer = StreamBuffer<Int>(capacity: 3)
        buffer.append(contentsOf: [1])
        buffer.append(contentsOf: [])

        let drained = buffer.drain()
        #expect(drained.items == [1])
        #expect(drained.dropped == 0)
    }

    @Test func capacityOfOneKeepsOnlyTheLatest() {
        var buffer = StreamBuffer<Int>(capacity: 1)
        buffer.append(contentsOf: [1, 2, 3])

        let drained = buffer.drain()
        #expect(drained.items == [3])
        #expect(drained.dropped == 2)
    }
}

@Suite struct StreamProtocolTests {
    private func subscribe(
        id: Int, topic: StreamProtocol.Topic?, serial: String? = nil
    ) -> StreamProtocol.Command {
        StreamProtocol.Command(
            op: .subscribe, id: id, topic: topic,
            params: serial.map { StreamProtocol.Command.Params(serial: $0) })
    }

    @Test func acceptsAWellFormedSubscription() {
        #expect(
            StreamProtocol.validate(
                subscribe(id: 1, topic: .logcat, serial: "emulator-5554"), activeIDs: [])
                == nil)
        #expect(StreamProtocol.validate(subscribe(id: 1, topic: .devices), activeIDs: []) == nil)
    }

    @Test func rejectsAReusedID() {
        // Correlation ids are how one socket serves many streams; reusing a
        // live one would silently cross two streams' events.
        #expect(
            StreamProtocol.validate(subscribe(id: 7, topic: .devices), activeIDs: [7])
                == .duplicateID)
    }

    @Test func rejectsASubscribeWithNoTopic() {
        #expect(StreamProtocol.validate(subscribe(id: 1, topic: nil), activeIDs: []) == .missingTopic)
    }

    @Test func rejectsADeviceScopedTopicWithNoSerial() {
        #expect(
            StreamProtocol.validate(subscribe(id: 1, topic: .logcat), activeIDs: [])
                == .missingSerial)
        #expect(
            StreamProtocol.validate(subscribe(id: 1, topic: .logcat, serial: ""), activeIDs: [])
                == .missingSerial)
    }

    @Test func hostWideTopicsNeedNoSerial() {
        #expect(!StreamProtocol.Topic.devices.needsSerial, "the device list is the host's, not a device's")
        #expect(StreamProtocol.Topic.logcat.needsSerial)
    }

    @Test func unsubscribingAnUnknownIDIsNotAnError() {
        // A client racing its own teardown against an `ended` event is doing
        // the right thing and must not see a spurious failure.
        let command = StreamProtocol.Command(op: .unsubscribe, id: 99)
        #expect(StreamProtocol.validate(command, activeIDs: []) == nil)
    }

    @Test func commandsRoundTripThroughJSON() throws {
        let json = Data(
            #"{"op":"subscribe","id":3,"topic":"logcat","params":{"serial":"R58M","filter":"E"}}"#
                .utf8)
        let decoded = try JSONDecoder().decode(StreamProtocol.Command.self, from: json)
        #expect(decoded.op == .subscribe)
        #expect(decoded.id == 3)
        #expect(decoded.topic == .logcat)
        #expect(decoded.params?.serial == "R58M")
        #expect(decoded.params?.filter == "E")
    }

    @Test func eventsEncodeTheShapeTheUIParses() throws {
        func encoded(_ event: StreamProtocol.Event<Int>) throws -> String {
            String(decoding: try DaemonProtocol.encode(event), as: UTF8.self)
        }
        #expect(try encoded(.batch(id: 1, items: [7])) == #"{"event":"batch","id":1,"items":[7]}"#)
        #expect(try encoded(.dropped(id: 1, count: 12)) == #"{"count":12,"event":"dropped","id":1}"#)
        #expect(
            try encoded(.ended(id: 1, reason: .deviceDisconnected))
                == #"{"event":"ended","id":1,"reason":"device_disconnected"}"#)
    }
}
