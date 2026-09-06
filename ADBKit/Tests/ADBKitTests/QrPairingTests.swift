import Testing
@testable import ADBKit

@Suite struct QrPairingPayloadTests {
    @Test func payloadIsTheWpa3AdbForm() {
        let request = QrPairingRequest(serviceName: "droidective-abc123", password: "s3cret")
        #expect(request.payload == "WIFI:T:ADB;S:droidective-abc123;P:s3cret;;")
    }

    @Test func randomRequestsCarryTheNamePrefixAndTheDeclaredLengths() {
        let request = QrPairingRequest.random()
        #expect(request.serviceName.hasPrefix("droidective-"))
        #expect(request.serviceName.count == "droidective-".count + 10)
        #expect(request.password.count == 12)
    }

    @Test func randomRequestsNeedNoWpa3Escaping() {
        // `\`, `;`, `,`, `:` and `"` are special inside a WPA3 QR field, so a
        // generated value containing one would have to be escaped. The
        // alphabet exists to make that impossible.
        for _ in 0..<200 {
            let request = QrPairingRequest.random()
            let generated = request.serviceName.dropFirst("droidective-".count) + request.password
            #expect(generated.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) })
        }
    }

    @Test func randomRequestsDoNotRepeat() {
        // The name is the correlation key and the password is a bearer
        // credential — a repeat of either is a bug, not a coincidence.
        var names: Set<String> = []
        var passwords: Set<String> = []
        for _ in 0..<200 {
            let request = QrPairingRequest.random()
            names.insert(request.serviceName)
            passwords.insert(request.password)
        }
        #expect(names.count == 200)
        #expect(passwords.count == 200)
    }
}

@Suite struct PairingServiceMatchTests {
    private let services = ConnectionService.parseMdnsServices("""
    List of discovered mdns services
    adb-R58M4-QXjCrW\t_adb-tls-pairing._tcp\t192.168.1.99:33861
    droidective-aB3xY9zQ1p\t_adb-tls-pairing._tcp\t192.168.1.42:37123
    droidective-aB3xY9zQ1p\t_adb-tls-connect._tcp\t192.168.1.42:40913
    """)

    @Test func matchesOurRequestedNameAndOnlyThePairingService() {
        let match = ConnectionService.matchPairingService(
            services, requestedName: "droidective-aB3xY9zQ1p")
        #expect(match?.endpoint == WirelessEndpoint(host: "192.168.1.42", port: "37123"))
        // The connect row shares the name — taking it would pair against the
        // wrong port and fail with adb's unhelpful "connection reset".
        #expect(match?.type.hasPrefix("_adb-tls-pairing") == true)
    }

    @Test func ignoresAnotherHostsPairingSession() {
        // A phone pairing with Android Studio next to us advertises too.
        #expect(ConnectionService.matchPairingService(
            services, requestedName: "droidective-NEVERUSED") == nil)
    }

    @Test func toleratesTheSuffixTheMdnsBackendAppends() {
        // adb's mDNS backend decorates instance names with a random suffix,
        // so the name on the wire is not the name we asked for — which is why
        // the match is by prefix. (A suffix carrying a *space* would defeat
        // `parseMdnsServices`, which splits on spaces as well as tabs; that
        // only happens on an outright name collision, which the 10 random
        // characters in the name make vanishingly unlikely.)
        let decorated = ConnectionService.parseMdnsServices(
            "droidective-aB3xY9zQ1p-QXjCrW\t_adb-tls-pairing._tcp\t192.168.1.42:37123")
        #expect(ConnectionService.matchPairingService(
            decorated, requestedName: "droidective-aB3xY9zQ1p")?.endpoint.port == "37123")
    }

    @Test func anEmptyNameMatchesNothing() {
        // Prefix matching means "" would otherwise match the first row.
        #expect(ConnectionService.matchPairingService(services, requestedName: "") == nil)
    }
}

@Suite struct QrPairingFlowTests {
    private let request = QrPairingRequest(
        // Twelve alphanumerics like the real thing, but patterned rather than
        // random: a high-entropy literal here reads as a leaked credential to
        // the gitleaks pre-commit hook.
        serviceName: "droidective-aB3xY9zQ1p", password: "aaaabbbbcccc")

    private let fast = QrPairingTiming(
        scanAttempts: 2, scanDelay: .milliseconds(1),
        connectAttempts: 2, connectDelay: .milliseconds(1))

    private func makeService(runner: MockProcessRunner) async -> ConnectionService {
        let client = await makeTestClient(runner: runner)
        return ConnectionService(client: client, monitor: DeviceMonitor(client: client))
    }

    private func phases(
        _ service: ConnectionService, _ timing: QrPairingTiming
    ) async -> [QrPairingPhase] {
        var seen: [QrPairingPhase] = []
        for await phase in service.pairByQrCode(request, timing: timing) { seen.append(phase) }
        return seen
    }

    @Test func pairsWithTheAdvertisedPortThenConnectsOnTheConnectPort() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["mdns"], stdout: """
        List of discovered mdns services
        droidective-aB3xY9zQ1p\t_adb-tls-pairing._tcp\t192.168.1.42:37123
        droidective-aB3xY9zQ1p\t_adb-tls-connect._tcp\t192.168.1.42:40913
        """)
        runner.script(argsPrefix: ["pair"], stdout: "Successfully paired to 192.168.1.42:37123")
        runner.script(argsPrefix: ["connect"], stdout: "connected to 192.168.1.42:40913")
        runner.script(argsPrefix: ["devices"], stdout: "List of devices attached\n")
        let service = await makeService(runner: runner)

        let seen = await phases(service, fast)
        #expect(seen == [
            .waitingForScan,
            .pairing(endpoint: WirelessEndpoint(host: "192.168.1.42", port: "37123")),
            .connecting(endpoint: WirelessEndpoint(host: "192.168.1.42", port: "37123")),
            .connected(address: "192.168.1.42:40913"),
        ])
        // The generated password is what goes on the wire, against the
        // *pairing* port — and the connect uses the connect port, not it.
        #expect(runner.invocations.contains {
            $0.arguments == ["pair", "192.168.1.42:37123", "aaaabbbbcccc"]
        })
        #expect(runner.invocations.contains {
            $0.arguments == ["connect", "192.168.1.42:40913"]
        })
    }

    @Test func reportsNoScanWhenNobodyAdvertisesOurName() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["mdns"], stdout: """
        List of discovered mdns services
        adb-R58M4-QXjCrW\t_adb-tls-pairing._tcp\t192.168.1.99:33861
        """)
        let service = await makeService(runner: runner)

        let seen = await phases(service, fast)
        #expect(seen.count == 2)
        #expect(seen.first == .waitingForScan)
        if case .failed(let message) = seen.last {
            #expect(message.contains("No device scanned the code"))
        } else {
            Issue.record("expected a failure phase, got \(String(describing: seen.last))")
        }
        // It polled every attempt rather than giving up on the first miss.
        #expect(runner.invocations.filter { $0.arguments == ["mdns", "services"] }.count == 2)
        #expect(!runner.invocations.contains { $0.arguments.first == "pair" })
    }

    @Test func aFailingMdnsQueryKeepsPollingRatherThanEndingTheWait() async {
        // `adb mdns services` exiting non-zero — an adb server restarting
        // under a five-minute wait — must not read as "nobody scanned". It
        // doesn't, because `AdbClient.run` only *throws* for a missing adb and
        // hands back a failed result for everything else; this pins that,
        // because the loop's `else { return nil }` reads at a glance like it
        // aborts on any hiccup and it is a long way from where it would show.
        let runner = MockProcessRunner()
        runner.script(
            argsPrefix: ["mdns"], stderr: "adb: failed to check server version", exitCode: 1)
        let service = await makeService(runner: runner)

        let found = await service.discoverPairingEndpoint(
            serviceName: "droidective-aB3xY9zQ1p", attempts: 3, delay: .milliseconds(1))
        #expect(found == nil)
        #expect(runner.invocations.filter { $0.arguments == ["mdns", "services"] }.count == 3)
    }

    @Test func surfacesAdbsOwnPairingFailure() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["mdns"], stdout:
            "droidective-aB3xY9zQ1p\t_adb-tls-pairing._tcp\t192.168.1.42:37123")
        runner.script(argsPrefix: ["pair"], stderr: "failed: wrong code", exitCode: 1)
        let service = await makeService(runner: runner)

        let seen = await phases(service, fast)
        #expect(seen.last == .failed(message: "failed: wrong code"))
        #expect(!runner.invocations.contains { $0.arguments.first == "connect" })
    }

    @Test func staysPairedWhenTheConnectPortNeverArrives() async {
        // adb's own auto-connect may have taken the device already, and the
        // pairing is real either way — reporting this as a failure would send
        // the user back to re-pair a device that is already trusted.
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["mdns"], stdout:
            "droidective-aB3xY9zQ1p\t_adb-tls-pairing._tcp\t192.168.1.42:37123")
        runner.script(argsPrefix: ["pair"], stdout: "Successfully paired to 192.168.1.42:37123")
        let service = await makeService(runner: runner)

        let seen = await phases(service, fast)
        #expect(seen.last == .pairedWithoutConnecting(host: "192.168.1.42"))
        #expect(!runner.invocations.contains { $0.arguments.first == "connect" })
    }

    @Test func cancellingTheConsumerStopsThePolling() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["mdns"], stdout: "List of discovered mdns services\n")
        let service = await makeService(runner: runner)

        // A long scan window, abandoned after the first phase — what closing
        // the sheet does. Without the stream's onTermination cancelling its
        // task, this polls adb for five minutes after the UI is gone.
        let timing = QrPairingTiming(scanAttempts: 300, scanDelay: .milliseconds(20))
        for await phase in service.pairByQrCode(request, timing: timing) {
            #expect(phase == .waitingForScan)
            break
        }
        let afterBreak = runner.invocations.count
        try? await Task.sleep(for: .milliseconds(150))
        #expect(runner.invocations.count - afterBreak <= 1)
    }
}
