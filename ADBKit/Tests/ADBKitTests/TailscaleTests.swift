import Foundation
import Testing
@testable import ADBKit

// MARK: - Parser

/// `tailscale status --json`, trimmed to the fields that matter and with every
/// name, address and key invented. The shape is Tailscale's `ipnstate.Status`.
@Suite struct TailscalePeersParserTests {
    static let running = """
    {
      "Version": "1.96.5-t0000000-g0000000",
      "BackendState": "Running",
      "Self": { "ID": "nSELF", "HostName": "work-mac", "DNSName": "work-mac.example-tailnet.ts.net.",
                "OS": "macOS", "Online": true, "TailscaleIPs": ["100.100.1.1", "fd7a:115c:a1e0::1"] },
      "Peer": {
        "nodekey:aaaa": {
          "ID": "nPIXEL", "PublicKey": "nodekey:aaaa", "HostName": "Pixel 7",
          "DNSName": "pixel-7.example-tailnet.ts.net.", "OS": "android", "Online": true,
          "TailscaleIPs": ["100.101.102.103", "fd7a:115c:a1e0::2"]
        },
        "nodekey:bbbb": {
          "ID": "nOFFLINE", "PublicKey": "nodekey:bbbb", "HostName": "old-tablet",
          "DNSName": "old-tablet.example-tailnet.ts.net.", "OS": "android", "Online": false,
          "TailscaleIPs": ["100.101.102.104"]
        },
        "nodekey:cccc": {
          "ID": "nLAPTOP", "PublicKey": "nodekey:cccc", "HostName": "linux-box",
          "DNSName": "linux-box.example-tailnet.ts.net.", "OS": "linux", "Online": true,
          "TailscaleIPs": ["100.101.102.105"]
        },
        "nodekey:dddd": {
          "ID": "nGALAXY", "PublicKey": "nodekey:dddd", "HostName": "localhost",
          "DNSName": "galaxy-s24.example-tailnet.ts.net.", "OS": "android", "Online": true,
          "TailscaleIPs": ["fd7a:115c:a1e0::5", "100.88.0.9"]
        },
        "nodekey:eeee": {
          "ID": "nV6ONLY", "PublicKey": "nodekey:eeee", "HostName": "v6-phone",
          "DNSName": "v6-phone.example-tailnet.ts.net.", "OS": "android", "Online": true,
          "TailscaleIPs": ["fd7a:115c:a1e0::6"]
        }
      }
    }
    """

    @Test func keepsOnlyOnlineAndroidPeersWithATailnetIPv4() throws {
        let network = try #require(TailscalePeers.parse(Self.running))
        #expect(network.backendState == "Running")
        // The offline phone, the Linux box and the IPv6-only phone are gone.
        #expect(network.androidPeers.map(\.id) == ["nGALAXY", "nPIXEL"])
    }

    @Test func aPeerIsNamedByItsMagicDNSLabelAndReachedByItsIPv4() throws {
        let network = try #require(TailscalePeers.parse(Self.running))
        let galaxy = try #require(network.androidPeers.first { $0.id == "nGALAXY" })
        // The DNS label carries an admin-console rename; "localhost" does not.
        #expect(galaxy.name == "galaxy-s24")
        // The IPv4, even when the IPv6 is listed first.
        #expect(galaxy.ipv4 == "100.88.0.9")
        #expect(galaxy.adbEndpoint == "100.88.0.9:5555")
    }

    @Test func theNameFallsBackToTheHostNameThenTheAddress() {
        #expect(TailscalePeers.displayName(dnsName: "", hostName: "Pixel 7", fallback: "x") == "Pixel 7")
        #expect(TailscalePeers.displayName(dnsName: nil, hostName: " ", fallback: "100.64.0.1")
            == "100.64.0.1")
    }

    @Test func androidIsMatchedWhateverItsCase() throws {
        let json = """
        {"BackendState":"Running","Peer":{"k":{"ID":"n1","HostName":"p","OS":"Android",
         "Online":true,"TailscaleIPs":["100.64.0.7"]}}}
        """
        #expect(try #require(TailscalePeers.parse(json)).androidPeers.map(\.ipv4) == ["100.64.0.7"])
    }

    @Test func aStoppedTailnetHasNoPeersRatherThanFailing() throws {
        // tailscaled answers `"Peer": null` while it is stopped.
        let json = #"{"BackendState":"Stopped","Peer":null,"Self":{"OS":"macOS"}}"#
        let network = try #require(TailscalePeers.parse(json))
        #expect(network.backendState == "Stopped")
        #expect(network.androidPeers.isEmpty)
    }

    @Test func emptyMalformedOrForeignTextIsNoNetwork() {
        #expect(TailscalePeers.parse("") == nil)
        #expect(TailscalePeers.parse("{") == nil)
        #expect(TailscalePeers.parse("failed to connect to local tailscaled; it doesn't appear to be running") == nil)
        // JSON, but not a status document.
        #expect(TailscalePeers.parse(#"{"devices":{}}"#) == nil)
    }

    @Test func crlfLineEndingsParseTheSame() throws {
        let crlf = Self.running.replacingOccurrences(of: "\n", with: "\r\n")
        let fromCRLF = try #require(TailscalePeers.parse(crlf))
        #expect(fromCRLF.androidPeers.count == 2)
        #expect(fromCRLF == TailscalePeers.parse(Self.running))
    }

    @Test func peersAreSortedByNameThenAddress() throws {
        let json = """
        {"BackendState":"Running","Peer":{
         "a":{"ID":"n1","DNSName":"zeta.t.ts.net.","OS":"android","Online":true,"TailscaleIPs":["100.64.0.1"]},
         "b":{"ID":"n2","DNSName":"alpha.t.ts.net.","OS":"android","Online":true,"TailscaleIPs":["100.64.0.3"]},
         "c":{"ID":"n3","DNSName":"alpha.t.ts.net.","OS":"android","Online":true,"TailscaleIPs":["100.64.0.2"]}}}
        """
        let peers = try #require(TailscalePeers.parse(json)).androidPeers
        #expect(peers.map(\.id) == ["n3", "n2", "n1"])
    }

    @Test func peersAlreadyInAdbAreNotOfferedAgain() throws {
        let peers = try #require(TailscalePeers.parse(Self.running)).androidPeers
        let devices = [
            Device(serial: "100.101.102.103:5555", state: "offline", model: nil, product: nil,
                   transportId: nil, label: "x", isWireless: true),
            Device(serial: "emulator-5554", state: "device", model: nil, product: nil,
                   transportId: nil, label: "y", isWireless: false),
        ]
        #expect(TailscalePeers.connectable(peers, devices: devices).map(\.id) == ["nGALAXY"])
    }
}

// MARK: - Tailnet addresses

@Suite struct TailnetAddressTests {
    @Test func theRangeIs100Point64Slash10() {
        #expect(TailscalePeers.isTailnetAddress("100.64.0.0"))
        #expect(TailscalePeers.isTailnetAddress("100.127.255.255"))
        #expect(!TailscalePeers.isTailnetAddress("100.63.255.255"))
        #expect(!TailscalePeers.isTailnetAddress("100.128.0.0"))
        #expect(!TailscalePeers.isTailnetAddress("192.168.1.20"))
    }

    @Test func notQuiteAnAddressIsNotATailnetAddress() {
        #expect(!TailscalePeers.isTailnetAddress("100.64.1"))
        #expect(!TailscalePeers.isTailnetAddress("100.64.1.256"))
        #expect(!TailscalePeers.isTailnetAddress("100.64.1.1.1"))
        #expect(!TailscalePeers.isTailnetAddress("100.64..1"))
        // Fullwidth digits, which `isNumber` would wave through, and a sign,
        // which `Int` would.
        #expect(!TailscalePeers.isTailnetAddress("１００.64.1.1"))
        #expect(!TailscalePeers.isTailnetAddress("100.+64.1.1"))
        #expect(!TailscalePeers.isTailnet(serial: "100.64.1.1:+5555"))
        #expect(!TailscalePeers.isTailnetAddress(""))
    }

    @Test func onlyAnIPPortSerialOnTheTailnetIsRemote() {
        #expect(TailscalePeers.isTailnet(serial: "100.101.102.103:5555"))
        #expect(!TailscalePeers.isTailnet(serial: "192.168.1.20:5555"))
        #expect(!TailscalePeers.isTailnet(serial: "100.101.102.103"))
        #expect(!TailscalePeers.isTailnet(serial: "100.101.102.103:"))
        #expect(!TailscalePeers.isTailnet(serial: "emulator-5554"))
        #expect(!TailscalePeers.isTailnet(serial: "R58M123ABC"))
        #expect(!TailscalePeers.isTailnet(serial: "adb-R58M-abc._adb-tls-connect._tcp"))
    }
}

// MARK: - Finding the CLI

@Suite struct TailscaleCLITests {
    @Test func aStandaloneCLIRunsAsItself() {
        let cli = TailscaleCLI(path: "/usr/local/bin/tailscale", flavor: .standalone)
        let call = cli.invocation(["status", "--json"])
        #expect(call.executable == "/usr/local/bin/tailscale")
        #expect(call.arguments == ["status", "--json"])
    }

    @Test func theAppBundleIsToldToBeTheCLIThroughEnv() {
        // `env` adds the one variable and keeps the rest of the environment,
        // which `SystemProcessRunner(environment:)` would replace.
        let cli = TailscaleCLI(path: TailscaleCLI.macAppBundlePath, flavor: .appBundle)
        let call = cli.invocation(["status", "--json"])
        #expect(call.executable == "/usr/bin/env")
        #expect(call.arguments == [
            "TAILSCALE_BE_CLI=1", "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
            "status", "--json",
        ])
    }

    private func makeLocator(
        runner: MockProcessRunner, clock: ToolLocatorCacheTests.FakeClock,
        executables: Set<String>
    ) -> ToolLocator {
        ToolLocator(
            runner: runner, environment: ToolLocatorCacheTests.searchPathEnvironment,
            now: { clock.now },
            isExecutableFile: { executables.contains($0) })
    }

    #if os(macOS)
    @Test func aCLIOnThePathWinsOverTheAppBundle() async {
        let locator = makeLocator(
            runner: MockProcessRunner(), clock: .init(),
            executables: ["/usr/local/bin/tailscale", TailscaleCLI.macAppBundlePath])
        #expect(await locator.tailscaleCLI()
            == TailscaleCLI(path: "/usr/local/bin/tailscale", flavor: .standalone))
    }

    @Test func theAppStoreBuildIsFoundByItsBundle() async {
        let locator = makeLocator(
            runner: MockProcessRunner(), clock: .init(),
            executables: [TailscaleCLI.macAppBundlePath])
        #expect(await locator.tailscaleCLI()
            == TailscaleCLI(path: TailscaleCLI.macAppBundlePath, flavor: .appBundle))
    }
    #endif

    #if !os(Windows)
    @Test func theLoginShellIsAskedLastAndItsAnswerIsStandalone() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-lc"], stdout: "/nix/profile/bin/tailscale\n")
        let locator = makeLocator(
            runner: runner, clock: .init(), executables: ["/nix/profile/bin/tailscale"])
        #expect(await locator.tailscaleCLI()
            == TailscaleCLI(path: "/nix/profile/bin/tailscale", flavor: .standalone))
        #expect(runner.invocations.last?.arguments == ["-lc", "command -v tailscale"])
    }
    #endif

    #if !os(Windows)
    @Test func notFoundIsCachedThenRetriedAfterTheTTL() async {
        // The device menu asks on every open; a miss must not spawn a login
        // shell each time, and an install mid-session must still be noticed.
        let runner = MockProcessRunner()  // the login shell finds nothing
        let clock = ToolLocatorCacheTests.FakeClock()
        let locator = makeLocator(runner: runner, clock: clock, executables: [])
        #expect(await locator.tailscaleCLI() == nil)
        #expect(await locator.tailscaleCLI() == nil)
        #expect(runner.invocations.count == 1)

        clock.advance(by: ToolLocator.notFoundTTL + 1)
        #expect(await locator.tailscaleCLI() == nil)
        #expect(runner.invocations.count == 2)
    }
    #endif
}

// MARK: - Service

@Suite struct TailscaleServiceTests {
    private func makeService(
        _ runner: MockProcessRunner, cli: TailscaleCLI? = .init(
            path: TailscaleCLI.macAppBundlePath, flavor: .appBundle)
    ) async -> TailscaleService {
        let client = await makeTestClient(runner: runner)
        await client.locator.seedTailscale(cli)
        return TailscaleService(
            client: client, locator: client.locator, monitor: DeviceMonitor(client: client))
    }

    @Test func statusRunsTheCLIAndListsOnlineAndroidPeers() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["TAILSCALE_BE_CLI=1"], stdout: TailscalePeersParserTests.running)
        let status = try #require(await makeService(runner).status())

        #expect(runner.invocations.first == .init(
            executable: "/usr/bin/env",
            arguments: ["TAILSCALE_BE_CLI=1", TailscaleCLI.macAppBundlePath, "status", "--json"]))
        #expect(status.flavor == .appBundle)
        #expect(status.isRunning)
        #expect(status.androidPeers.map(\.name) == ["galaxy-s24", "pixel-7"])
        #expect(status.notice == nil)
    }

    @Test func noCLIMeansNoTailscaleSection() async {
        let runner = MockProcessRunner()
        #expect(await makeService(runner, cli: nil).status() == nil)
        #expect(runner.invocations.isEmpty)
    }

    @Test func aTailscaledThatCannotBeReachedSaysSo() async throws {
        let runner = MockProcessRunner()
        runner.script(
            argsPrefix: ["status"], stderr: "failed to connect to local tailscaled", exitCode: 1)
        let service = await makeService(
            runner, cli: .init(path: "/usr/local/bin/tailscale", flavor: .standalone))
        let status = try #require(await service.status())
        #expect(status.backendState == nil)
        #expect(status.notice == "Tailscale isn't running")
    }

    @Test func peersOnlyCountWhileTailscaleIsRunning() async throws {
        // A document can list peers while logged out; none of them are reachable.
        let runner = MockProcessRunner()
        runner.script(
            argsPrefix: ["TAILSCALE_BE_CLI=1"],
            stdout: TailscalePeersParserTests.running.replacingOccurrences(
                of: #""BackendState": "Running""#, with: #""BackendState": "NeedsLogin""#))
        let status = try #require(await makeService(runner).status())
        #expect(status.androidPeers.isEmpty)
        #expect(status.notice == "Tailscale needs you to log in")
    }

    @Test func noticesNameTheState() {
        func notice(_ state: String?, peers: [TailscalePeer] = []) -> String? {
            TailscaleStatus(flavor: .standalone, backendState: state, androidPeers: peers).notice
        }
        #expect(notice("Stopped") == "Tailscale is stopped")
        #expect(notice("Starting") == "Tailscale is starting")
        #expect(notice("NeedsMachineAuth") == "This Mac is waiting for approval in your tailnet")
        #expect(notice("Running") == "No Android devices online in your tailnet")
        #expect(notice("Running", peers: [.init(id: "n", name: "p", ipv4: "100.64.0.1")]) == nil)
        #expect(notice("InUseOtherUser") == "Tailscale is inuseotheruser")
    }

    @Test func prepareIsTcpipAndNothingElse() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "R58M123ABC", "tcpip"], stdout: "restarting in TCP mode port: 5555\n")
        let result = try await makeService(runner).prepare(serial: "R58M123ABC")

        #expect(result.ok)
        // `ConnectionService.enableTcpip` would go on to read wlan0 and connect
        // over Wi-Fi; here the phone is reached over the tailnet instead.
        let adbCalls = runner.invocations.filter { $0.executable == "/fake/adb" }
        #expect(adbCalls.map(\.arguments).first == ["-s", "R58M123ABC", "tcpip", "5555"])
        #expect(!adbCalls.contains { $0.arguments.contains("connect") || $0.arguments.contains("shell") })
    }

    @Test func onlyAReadyUSBPhoneCanBePrepared() {
        func device(_ serial: String, state: String = "device", wireless: Bool = false,
                    platform: DevicePlatform = .android) -> Device {
            Device(serial: serial, state: state, model: nil, product: nil, transportId: nil,
                   label: serial, isWireless: wireless, platform: platform)
        }
        #expect(TailscaleService.canPrepare(device("R58M123ABC")))
        #expect(!TailscaleService.canPrepare(device("R58M123ABC", state: "unauthorized")))
        #expect(!TailscaleService.canPrepare(device("192.168.1.20:5555", wireless: true)))
        #expect(!TailscaleService.canPrepare(device("100.101.102.103:5555", wireless: true)))
        #expect(!TailscaleService.canPrepare(device("emulator-5554")))
        #expect(!TailscaleService.canPrepare(device("AAAA-1111", platform: .iosSimulator)))
    }

    @Test func aRefusedPrepareSaysWhy() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "R58M123ABC", "tcpip"], stderr: "error: device unauthorized.", exitCode: 1)
        let result = try await makeService(runner).prepare(serial: "R58M123ABC")
        #expect(!result.ok)
        #expect(result.message == "Device is unauthorized — accept the USB debugging prompt.")
    }

    @Test func connectUsesTheTailnetIPv4OnTheAdbPort() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["connect"], stdout: "connected to 100.101.102.103:5555\n")
        let peer = TailscalePeer(id: "nPIXEL", name: "pixel-7", ipv4: "100.101.102.103")
        let result = try await makeService(runner).connect(peer)

        #expect(runner.invocations.first { $0.executable == "/fake/adb" }?.arguments
            == ["connect", "100.101.102.103:5555"])
        #expect(result.ok)
        #expect(result.message == "Connected to pixel-7 over Tailscale")
    }

    @Test func connectOutcomesReadAdbsWords() {
        func outcome(_ stdout: String) -> FeatureResult {
            TailscaleService.connectOutcome(
                AdbResult(stdout: stdout, stderr: "", exitCode: 0, timedOut: false), peerName: "pixel-7")
        }
        #expect(outcome("already connected to 100.64.0.1:5555").ok)
        let refused = outcome("failed to connect to '100.64.0.1:5555': Connection refused")
        #expect(!refused.ok)
        #expect(refused.message.contains("Prepare for Tailscale"))
        let timedOut = outcome("failed to connect to '100.64.0.1:5555': Operation timed out")
        #expect(!timedOut.ok)
        #expect(timedOut.message == "failed to connect to '100.64.0.1:5555': Operation timed out")
        #expect(outcome("").message == "Couldn't connect to pixel-7.")
    }
}

// MARK: - Remote link

@Suite struct RemoteLinkTests {
    private let tailnet = "100.101.102.103:5555"

    @Test func aTailnetMirrorIsCappedToTheRemotePreset() {
        let full = ScrcpyServerParams(scid: 1, maxSize: 0, videoBitRate: 0, maxFps: 0)
        let capped = RemoteLink.mirrorParams(full, serial: tailnet)
        #expect(capped.videoBitRate == 2_000_000)
        #expect(capped.maxSize == 1280)
        #expect(capped.maxFps == 30)
        #expect(capped.parameters().contains("video_bit_rate=2000000"))
    }

    @Test func capsOnlyEverLower() {
        let tile = ScrcpyServerParams(scid: 1, maxSize: 640, videoBitRate: 1_000_000, maxFps: 24)
        #expect(RemoteLink.mirrorParams(tile, serial: tailnet) == tile)
        let large = ScrcpyServerParams(scid: 1, maxSize: 1920, videoBitRate: 8_000_000, maxFps: 60)
        let capped = RemoteLink.mirrorParams(large, serial: tailnet)
        #expect((capped.maxSize, capped.videoBitRate, capped.maxFps) == (1280, 2_000_000, 30))
    }

    @Test func aLocalMirrorIsLeftAlone() {
        let params = ScrcpyServerParams(scid: 1, maxSize: 1280)
        #expect(RemoteLink.mirrorParams(params, serial: "R58M123ABC") == params)
        #expect(RemoteLink.mirrorParams(params, serial: "192.168.1.20:5555") == params)
    }

    @Test func aFlaggedFeatureAsksFirstOnlyOnATailnetDevice() {
        #expect(RemoteLink.asksFirst(featureID: "wifi", serials: [tailnet]))
        #expect(RemoteLink.asksFirst(featureID: "network-toggles", serials: ["R58M123ABC", tailnet]))
        #expect(!RemoteLink.asksFirst(featureID: "wifi", serials: ["R58M123ABC"]))
        #expect(!RemoteLink.asksFirst(featureID: "wifi", serials: []))
        #expect(!RemoteLink.asksFirst(featureID: "screenshot", serials: [tailnet]))
    }

    @Test func theQuestionNamesTheDeviceAndTheRisk() throws {
        let question = try #require(
            RemoteLink.confirmation(featureID: "wifi", serials: [tailnet], deviceName: "pixel-7"))
        #expect(question.title == "pixel-7 is connected over Tailscale")
        #expect(question.message.hasPrefix(try #require(FeatureRegistry.remoteLinkWarnings["wifi"])))
        #expect(RemoteLink.confirmation(featureID: "wifi", serials: ["R58M123ABC"], deviceName: "x") == nil)
    }
}
