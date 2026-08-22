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
                subscribe(id: 1, topic: .logcat, serial: "emulator-5554"), active: [:])
                == nil)
        #expect(StreamProtocol.validate(subscribe(id: 1, topic: .devices), active: [:]) == nil)
    }

    @Test func rejectsAReusedID() {
        // Correlation ids are how one socket serves many streams; reusing a
        // live one would silently cross two streams' events.
        #expect(
            StreamProtocol.validate(subscribe(id: 7, topic: .devices), active: [7: .devices])
                == .duplicateID)
    }

    @Test func rejectsASubscribeWithNoTopic() {
        #expect(StreamProtocol.validate(subscribe(id: 1, topic: nil), active: [:]) == .missingTopic)
    }

    @Test func rejectsADeviceScopedTopicWithNoSerial() {
        #expect(
            StreamProtocol.validate(subscribe(id: 1, topic: .logcat), active: [:])
                == .missingSerial)
        #expect(
            StreamProtocol.validate(subscribe(id: 1, topic: .logcat, serial: ""), active: [:])
                == .missingSerial)
    }

    @Test func hostWideTopicsNeedNoSerial() {
        #expect(!StreamProtocol.Topic.devices.needsSerial, "the device list is the host's, not a device's")
        #expect(StreamProtocol.Topic.logcat.needsSerial)
        // A shell runs on the host. Requiring a device would mean no terminal
        // until something is plugged in, which is when one is most wanted.
        #expect(!StreamProtocol.Topic.pty.needsSerial)
    }

    @Test func unsubscribingAnUnknownIDIsNotAnError() {
        // A client racing its own teardown against an `ended` event is doing
        // the right thing and must not see a spurious failure.
        let command = StreamProtocol.Command(op: .unsubscribe, id: 99)
        #expect(StreamProtocol.validate(command, active: [:]) == nil)
    }

    // MARK: - writing into a subscription

    private func write(id: Int, data: String?) -> StreamProtocol.Command {
        StreamProtocol.Command(
            op: .write, id: id, params: StreamProtocol.Command.Params(data: data))
    }

    private func resize(id: Int, columns: Int?, rows: Int?) -> StreamProtocol.Command {
        StreamProtocol.Command(
            op: .resize, id: id,
            params: StreamProtocol.Command.Params(columns: columns, rows: rows))
    }

    @Test func acceptsAWriteAndAResizeAgainstATerminal() {
        let active: [Int: StreamProtocol.Topic] = [3: .pty]
        #expect(StreamProtocol.validate(write(id: 3, data: "bHM=" /* ls */), active: active) == nil)
        #expect(StreamProtocol.validate(resize(id: 3, columns: 120, rows: 40), active: active) == nil)
    }

    @Test func rejectsInputAgainstATopicThatOnlyObserves() {
        // Typing at a logcat stream has no meaning to fall back on, and a
        // client doing it has the wrong id — worth saying so.
        #expect(
            StreamProtocol.validate(write(id: 3, data: "bHM="), active: [3: .logcat])
                == .notInteractive)
        #expect(
            StreamProtocol.validate(resize(id: 3, columns: 80, rows: 24), active: [3: .devices])
                == .notInteractive)
    }

    @Test func rejectsInputAgainstAnIDThatIsNotSubscribed() {
        // Unlike `unsubscribe`, which is lenient on purpose: a write that lands
        // nowhere presents as a terminal ignoring the keyboard.
        #expect(StreamProtocol.validate(write(id: 3, data: "bHM="), active: [:]) == .unknownSubscription)
        #expect(
            StreamProtocol.validate(resize(id: 3, columns: 80, rows: 24), active: [:])
                == .unknownSubscription)
    }

    @Test func rejectsAWriteWithNothingToWrite() {
        #expect(StreamProtocol.validate(write(id: 3, data: nil), active: [3: .pty]) == .missingData)
        #expect(StreamProtocol.validate(write(id: 3, data: ""), active: [3: .pty]) == .missingData)
    }

    @Test func rejectsAWriteThatIsNotBase64() {
        // The failure this catches is a client that forgot to encode: the bytes
        // would otherwise be dropped, and only for input that happened not to
        // be valid base64 by accident.
        #expect(
            StreamProtocol.validate(write(id: 3, data: "not base64!"), active: [3: .pty])
                == .invalidData)
    }

    @Test func rejectsAResizeMissingHalfOfTheSize() {
        #expect(
            StreamProtocol.validate(resize(id: 3, columns: 120, rows: nil), active: [3: .pty])
                == .missingSize)
        #expect(
            StreamProtocol.validate(resize(id: 3, columns: nil, rows: 40), active: [3: .pty])
                == .missingSize)
    }

    @Test func aWritesBytesAreDecodedOnce() {
        // Validation and the write itself must not disagree about what arrived,
        // which is why one computed property answers for both.
        let params = StreamProtocol.Command.Params(data: Data("ls -la\n".utf8).base64EncodedString())
        #expect(params.bytes == Data("ls -la\n".utf8))
        // Base64 carries the control codes a JSON string could not: this is
        // Ctrl-C, which is the whole reason the field is not plain text.
        let interrupt = StreamProtocol.Command.Params(data: Data([0x03]).base64EncodedString())
        #expect(interrupt.bytes == Data([0x03]))
    }

    @Test func aRequestedSizeIsClampedByTheTimeItIsRead() {
        #expect(
            StreamProtocol.Command.Params(columns: 0, rows: 0).size
                == PtySize(columns: 1, rows: 1))
        #expect(StreamProtocol.Command.Params(columns: nil, rows: 24).size == nil)
    }

    @Test func onlyTheTerminalTakesInput() {
        // The registry-invariant shape: a new topic that forgot to answer would
        // fall into whichever arm it was added to, and the default is wrong for
        // exactly one of them.
        for topic in StreamProtocol.Topic.allCases {
            switch topic {
            case .pty: #expect(topic.acceptsInput)
            case .devices, .logcat, .performance, .netspeed: #expect(!topic.acceptsInput)
            }
        }
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

    @Test func terminalCommandsRoundTripThroughJSON() throws {
        let opened = try JSONDecoder().decode(
            StreamProtocol.Command.self,
            from: Data(
                #"{"op":"subscribe","id":1,"topic":"pty","params":{"columns":120,"rows":40}}"#.utf8))
        #expect(opened.topic == .pty)
        #expect(opened.params?.size == PtySize(columns: 120, rows: 40))

        let typed = try JSONDecoder().decode(
            StreamProtocol.Command.self,
            from: Data(#"{"op":"write","id":1,"params":{"data":"bHMK"}}"#.utf8))
        #expect(typed.op == .write)
        #expect(typed.params?.bytes == Data("ls\n".utf8))

        let resized = try JSONDecoder().decode(
            StreamProtocol.Command.self,
            from: Data(#"{"op":"resize","id":1,"params":{"columns":80,"rows":24}}"#.utf8))
        #expect(resized.op == .resize)
        #expect(resized.params?.size == .standard)
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
