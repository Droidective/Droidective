import ADBKit
import Foundation
import Testing

@testable import DaemonCore

/// The deep-link, bug-report and toolchain routes without a device.
///
/// What is worth defending: a launch answers *per device* rather than
/// collapsing to one verdict, a write replaces one app's list and no other's,
/// and the Doctor's list comes back in a stable order — a dictionary's
/// iteration order is not an order, and a Doctor whose rows shuffle between
/// refreshes reads as broken.
@Suite struct DiagnosticsRouteTests {
    private struct Refusal: Error, CustomStringConvertible {
        let description: String
    }

    private actor Store {
        private(set) var map: DeepLinksMap
        private(set) var launches: [(String, String)] = []
        private(set) var reports: [(String, String?, String)] = []

        init(_ map: DeepLinksMap = [:]) { self.map = map }

        func write(_ packageId: String, _ links: [DeepLink]) { map[packageId] = links }
        func launch(_ serial: String, _ url: String) { launches.append((serial, url)) }
        func report(_ serial: String, _ packageId: String?, _ destination: String) {
            reports.append((serial, packageId, destination))
        }
    }

    private struct StubBackend: DaemonBackend {
        let store: Store
        var launchFails: Set<String> = []
        var refusal: Refusal?
        var tools: [Tool: ToolStatus] = [:]

        func deepLinks(packageId: String) async -> [DeepLink] {
            await store.map[packageId] ?? []
        }

        func writeDeepLinks(packageId: String, links: [DeepLink]) async throws {
            if let refusal { throw refusal }
            await store.write(packageId, links)
        }

        func launchDeepLink(serial: String, url: String) async throws -> FeatureResult {
            if launchFails.contains(serial) { throw Refusal(description: "adb not found") }
            await store.launch(serial, url)
            return FeatureResult(ok: true, message: "Launched \(url)")
        }

        func createBugReport(
            serial: String, packageId: String?, destination: String
        ) async throws -> String {
            if let refusal { throw refusal }
            await store.report(serial, packageId, destination)
            return "\(destination)/bug-report_2026-08-22.zip"
        }

        func detectTools() async -> [Tool: ToolStatus] { tools }
    }

    private func body(_ value: some Encodable) -> Data { DaemonProtocol.encoded(value) }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    private func link(_ label: String, _ url: String) -> DiagnosticsProtocol.Link {
        DiagnosticsProtocol.Link(id: "id-\(label)", label: label, url: url, createdAt: 1)
    }

    // MARK: - Reading

    @Test func readsOneAppsLinks() async throws {
        let backend = StubBackend(store: Store([
            "com.example.app": [DeepLink(id: "a", label: "Orders", url: "app://orders", createdAt: 7)],
            "com.other.app": [DeepLink(id: "b", label: "Other", url: "other://x", createdAt: 8)],
        ]))
        let answer = await DiagnosticsRoutes.linksRead(
            body: body(DiagnosticsProtocol.LinksRequest(packageId: "com.example.app")),
            backend: backend)

        #expect(answer.status == 200)
        let response = try decode(DiagnosticsProtocol.LinksResponse.self, answer.body)
        #expect(response.links.map(\.url) == ["app://orders"])
        #expect(response.links.first?.createdAt == 7)
    }

    @Test func anAppWithNoLinksIsAnEmptyListNotAnError() async throws {
        let answer = await DiagnosticsRoutes.linksRead(
            body: body(DiagnosticsProtocol.LinksRequest(packageId: "com.nothing")),
            backend: StubBackend(store: Store()))
        #expect(answer.status == 200)
        let response = try decode(DiagnosticsProtocol.LinksResponse.self, answer.body)
        #expect(response.links.isEmpty)
    }

    @Test func aReadWithoutAPackageIsRefused() async {
        let answer = await DiagnosticsRoutes.linksRead(
            body: body(DiagnosticsProtocol.LinksRequest(packageId: "")),
            backend: StubBackend(store: Store()))
        #expect(answer.status == 400)
    }

    // MARK: - Writing

    @Test func aWriteReplacesOneAppsListAndLeavesTheRest() async throws {
        // The map is shared with the Mac app's own file, so a write that took
        // the whole map would be a write that could lose another app's links.
        let store = Store(["com.other.app": [DeepLink(id: "b", label: "Other", url: "o://x", createdAt: 8)]])
        let answer = await DiagnosticsRoutes.linksWrite(
            body: body(DiagnosticsProtocol.LinksWriteRequest(
                packageId: "com.example.app", links: [link("Orders", "app://orders")])),
            backend: StubBackend(store: store))

        #expect(answer.status == 200)
        #expect(await store.map["com.example.app"]?.map(\.url) == ["app://orders"])
        #expect(await store.map["com.other.app"]?.count == 1)
    }

    @Test func anEmptyListIsAValidWrite() async throws {
        // Deleting the last link is a write of nothing, not a missing request.
        let store = Store(["com.example.app": [DeepLink(id: "a", label: "x", url: "a://b", createdAt: 1)]])
        let answer = await DiagnosticsRoutes.linksWrite(
            body: body(DiagnosticsProtocol.LinksWriteRequest(packageId: "com.example.app", links: [])),
            backend: StubBackend(store: store))
        #expect(answer.status == 200)
        #expect(await store.map["com.example.app"]?.isEmpty == true)
    }

    @Test func aStoreThatWillNotWriteIsAFiveHundredNotAFiveOhTwo() async {
        // Nothing reached a device: this is the daemon's own disk.
        let answer = await DiagnosticsRoutes.linksWrite(
            body: body(DiagnosticsProtocol.LinksWriteRequest(
                packageId: "com.example.app", links: [link("Orders", "app://orders")])),
            backend: StubBackend(store: Store(), refusal: Refusal(description: "read-only")))
        #expect(answer.status == 500)
    }

    // MARK: - Launching

    @Test func launchesOnEveryNamedDevice() async throws {
        let store = Store()
        let answer = await DiagnosticsRoutes.linksLaunch(
            body: body(DiagnosticsProtocol.LaunchRequest(
                serials: ["A", "B"], url: "app://orders/123")),
            backend: StubBackend(store: store))

        #expect(answer.status == 200)
        let response = try decode(DiagnosticsProtocol.LaunchResponse.self, answer.body)
        #expect(response.outcomes.map(\.serial) == ["A", "B"])
        #expect(response.outcomes.allSatisfy { $0.ok })
        #expect(await store.launches.map(\.0) == ["A", "B"])
    }

    @Test func oneDeviceFailingDoesNotStopTheOthersOrHideItself() async throws {
        // The Mac toasts once per target for exactly this reason: two phones
        // where one has no handler for the scheme is a partial success.
        let answer = await DiagnosticsRoutes.linksLaunch(
            body: body(DiagnosticsProtocol.LaunchRequest(serials: ["A", "B"], url: "app://x")),
            backend: StubBackend(store: Store(), launchFails: ["A"]))

        let response = try decode(DiagnosticsProtocol.LaunchResponse.self, answer.body)
        #expect(response.outcomes.count == 2)
        #expect(response.outcomes.first?.ok == false)
        #expect(response.outcomes.last?.ok == true)
    }

    @Test func aLaunchWithNoTargetOrNoUrlIsRefused() async {
        for request in [
            DiagnosticsProtocol.LaunchRequest(serials: [], url: "app://x"),
            DiagnosticsProtocol.LaunchRequest(serials: ["A"], url: ""),
        ] {
            let answer = await DiagnosticsRoutes.linksLaunch(
                body: body(request), backend: StubBackend(store: Store()))
            #expect(answer.status == 400)
        }
    }

    // MARK: - Bug report

    @Test func buildsTheReportWhereTheClientAsked() async throws {
        // The daemon never picks where a caller's files go — the same rule
        // `/v1/files/pull` follows.
        let store = Store()
        let answer = await DiagnosticsRoutes.bugReport(
            body: body(DiagnosticsProtocol.BugReportRequest(
                serial: "R58M4XYZ", packageId: "com.example.app", destination: "/tmp/reports")),
            backend: StubBackend(store: store))

        #expect(answer.status == 200)
        let response = try decode(DiagnosticsProtocol.BugReportResponse.self, answer.body)
        #expect(response.path.hasPrefix("/tmp/reports/"))
        #expect(await store.reports.first?.2 == "/tmp/reports")
        #expect(await store.reports.first?.1 == "com.example.app")
    }

    @Test func thePackageIsOptionalContext() async throws {
        let store = Store()
        _ = await DiagnosticsRoutes.bugReport(
            body: body(DiagnosticsProtocol.BugReportRequest(
                serial: "R58M4XYZ", destination: "/tmp/reports")),
            backend: StubBackend(store: store))
        #expect(await store.reports.first?.1 == nil)
    }

    @Test func aReportWithNoSerialOrNoDestinationIsRefused() async {
        for request in [
            DiagnosticsProtocol.BugReportRequest(serial: "", destination: "/tmp"),
            DiagnosticsProtocol.BugReportRequest(serial: "A", destination: ""),
        ] {
            let answer = await DiagnosticsRoutes.bugReport(
                body: body(request), backend: StubBackend(store: Store()))
            #expect(answer.status == 400)
        }
    }

    @Test func aReportThatCouldNotBeBuiltCarriesTheReason() async throws {
        // A host with no `zip`, or a device that went away mid-collect.
        let answer = await DiagnosticsRoutes.bugReport(
            body: body(DiagnosticsProtocol.BugReportRequest(serial: "A", destination: "/tmp")),
            backend: StubBackend(store: Store(), refusal: Refusal(description: "no /usr/bin/zip")))

        #expect(answer.status == 502)
        // Decoded rather than matched against the raw body: JSON escapes the
        // slashes in a path, so a substring check on the bytes would pass or
        // fail for reasons that have nothing to do with the message.
        let error = try decode(DaemonProtocol.ErrorBody.self, answer.body)
        #expect(error.error.detail?.contains("no /usr/bin/zip") == true)
    }

    // MARK: - The toolchain

    @Test func reportsEveryToolInTheEnumsOwnOrder() async throws {
        // Not the dictionary's, which has none — a Doctor whose rows shuffle
        // between refreshes reads as broken.
        let backend = StubBackend(store: Store(), tools: Dictionary(
            uniqueKeysWithValues: Tool.allCases.map {
                ($0, ToolStatus(installed: true, path: "/usr/bin/\($0.rawValue)",
                                version: "1.0", installHint: "hint"))
            }))
        let answer = await DiagnosticsRoutes.tools(backend: backend)

        #expect(answer.status == 200)
        let response = try decode(DiagnosticsProtocol.ToolsResponse.self, answer.body)
        #expect(response.tools.map(\.id) == Tool.allCases.map(\.rawValue))
    }

    @Test func aMissingToolCarriesItsHintAndNoPath() async throws {
        let backend = StubBackend(store: Store(), tools: [
            .adb: ToolStatus(
                installed: false, path: nil, version: nil,
                installHint: "Install Android platform-tools"),
        ])
        let answer = await DiagnosticsRoutes.tools(backend: backend)
        let response = try decode(DiagnosticsProtocol.ToolsResponse.self, answer.body)

        #expect(response.tools.count == 1)
        #expect(response.tools.first?.installed == false)
        #expect(response.tools.first?.path == nil)
        #expect(response.tools.first?.installHint == "Install Android platform-tools")
    }

    @Test func aToolTheDetectorSaidNothingAboutIsLeftOutRatherThanGuessed() async throws {
        // Better an absent row than one claiming a tool is missing when nothing
        // actually looked for it.
        let answer = await DiagnosticsRoutes.tools(backend: StubBackend(store: Store()))
        let response = try decode(DiagnosticsProtocol.ToolsResponse.self, answer.body)
        #expect(response.tools.isEmpty)
    }
}
