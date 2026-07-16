import Testing
@testable import ADBKit

@Suite struct WirelessEndpointParserTests {
    @Test func splitsHostAndPort() {
        #expect(
            ConnectionService.parseEndpoint("192.168.1.42:37123")
                == WirelessEndpoint(host: "192.168.1.42", port: "37123"))
    }

    @Test func bareHostHasNoPort() {
        #expect(
            ConnectionService.parseEndpoint("192.168.1.42")
                == WirelessEndpoint(host: "192.168.1.42", port: nil))
    }

    @Test func trimsSurroundingWhitespace() {
        #expect(
            ConnectionService.parseEndpoint("  192.168.1.42:5555\n")
                == WirelessEndpoint(host: "192.168.1.42", port: "5555"))
    }

    @Test func acceptsHostnames() {
        #expect(
            ConnectionService.parseEndpoint("pixel.local:5555")
                == WirelessEndpoint(host: "pixel.local", port: "5555"))
    }

    @Test func bracketedIPv6KeepsBrackets() {
        #expect(
            ConnectionService.parseEndpoint("[fe80::1]:37123")
                == WirelessEndpoint(host: "[fe80::1]", port: "37123"))
        #expect(
            ConnectionService.parseEndpoint("[fe80::1]")
                == WirelessEndpoint(host: "[fe80::1]", port: nil))
    }

    @Test func bareIPv6GetsBracketed() {
        #expect(
            ConnectionService.parseEndpoint("fe80::aa:1")
                == WirelessEndpoint(host: "[fe80::aa:1]", port: nil))
    }

    @Test func connectParseDefaultsBareHostToPort5555() {
        #expect(
            ConnectionService.parseConnectEndpoint("10.158.128.7")
                == WirelessEndpoint(host: "10.158.128.7", port: "5555"))
        #expect(
            ConnectionService.parseConnectEndpoint("pixel.local")
                == WirelessEndpoint(host: "pixel.local", port: "5555"))
        #expect(
            ConnectionService.parseConnectEndpoint("fe80::aa:1")
                == WirelessEndpoint(host: "[fe80::aa:1]", port: "5555"))
        #expect(
            ConnectionService.parseConnectEndpoint("[fe80::1]")
                == WirelessEndpoint(host: "[fe80::1]", port: "5555"))
    }

    @Test func connectParseKeepsAnExplicitPort() {
        #expect(
            ConnectionService.parseConnectEndpoint("192.168.1.42:40913")
                == WirelessEndpoint(host: "192.168.1.42", port: "40913"))
        #expect(
            ConnectionService.parseConnectEndpoint("[fe80::1]:37123")
                == WirelessEndpoint(host: "[fe80::1]", port: "37123"))
    }

    @Test func connectParseStillRejectsGarbage() {
        #expect(ConnectionService.parseConnectEndpoint("") == nil)
        #expect(ConnectionService.parseConnectEndpoint("192.168.1.42:") == nil)
        #expect(ConnectionService.parseConnectEndpoint("192.168.1.42 :5555") == nil)
    }

    @Test func rejectsImplausibleHosts() {
        #expect(ConnectionService.parseEndpoint("1.1.1") == nil)
        #expect(ConnectionService.parseEndpoint("1.1.1.") == nil)
        #expect(ConnectionService.parseEndpoint("1.1.1.1.1") == nil)
        #expect(ConnectionService.parseEndpoint("256.1.1.1:5555") == nil)
        #expect(ConnectionService.parseEndpoint("192.168.1:5555") == nil)
        #expect(ConnectionService.parseEndpoint("1234.1.1.1") == nil)
        #expect(ConnectionService.parseConnectEndpoint("1.1.1") == nil)
        #expect(ConnectionService.parseEndpoint("[not-an-address]:5555") == nil)
        #expect(ConnectionService.parseEndpoint("-bad-.local:5555") == nil)
        #expect(ConnectionService.parseEndpoint("a..b:5555") == nil)
    }

    @Test func rejectsOutOfRangePorts() {
        #expect(ConnectionService.parseEndpoint("192.168.1.42:0") == nil)
        #expect(ConnectionService.parseEndpoint("192.168.1.42:65536") == nil)
        #expect(ConnectionService.parseEndpoint("192.168.1.42:99999") == nil)
        #expect(ConnectionService.parseConnectEndpoint("192.168.1.42:0") == nil)
        #expect(
            ConnectionService.parseEndpoint("192.168.1.42:65535")
                == WirelessEndpoint(host: "192.168.1.42", port: "65535"))
    }

    @Test func rejectsURLPastes() {
        #expect(ConnectionService.parseEndpoint("http://1.2.3.4:5555") == nil)
        #expect(ConnectionService.parseEndpoint("http://x") == nil)
        #expect(ConnectionService.parseConnectEndpoint("http://1.2.3.4:5555") == nil)
    }

    @Test func acceptsZonedIPv6() {
        #expect(
            ConnectionService.parseEndpoint("[fe80::1%en0]:5555")
                == WirelessEndpoint(host: "[fe80::1%en0]", port: "5555"))
    }

    @Test func rejectsGarbage() {
        #expect(ConnectionService.parseEndpoint("") == nil)
        #expect(ConnectionService.parseEndpoint("   ") == nil)
        #expect(ConnectionService.parseEndpoint("192.168.1.42:") == nil)
        #expect(ConnectionService.parseEndpoint(":5555") == nil)
        #expect(ConnectionService.parseEndpoint("192.168.1.42:port") == nil)
        #expect(ConnectionService.parseEndpoint("192.168.1.42:123456") == nil)
        #expect(ConnectionService.parseEndpoint("192.168.1.42 :5555") == nil)
        #expect(ConnectionService.parseEndpoint("[fe80::1") == nil)
        #expect(ConnectionService.parseEndpoint("[fe80::1]5555") == nil)
    }
}

@Suite struct ConnectionServiceArgTests {
    private func makeService(runner: MockProcessRunner) async -> ConnectionService {
        let client = await makeTestClient(runner: runner)
        return ConnectionService(client: client, monitor: DeviceMonitor(client: client))
    }

    @Test func pairSendsHostPortAndCode() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["pair"], stdout: "Successfully paired to 192.168.1.42:37123")
        let service = await makeService(runner: runner)

        let result = try await service.pair(host: "192.168.1.42", port: "37123", code: "123456")
        #expect(result.ok)
        #expect(runner.invocations.contains {
            $0.arguments == ["pair", "192.168.1.42:37123", "123456"]
        })
    }

    @Test func pairFailureSurfacesAdbReason() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["pair"], stderr: "failed: wrong code", exitCode: 1)
        let service = await makeService(runner: runner)

        let result = try await service.pair(host: "192.168.1.42", port: "37123", code: "000000")
        #expect(!result.ok)
        #expect(result.message == "failed: wrong code")
    }

    @Test func connectSendsHostPort() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["connect"], stdout: "connected to 192.168.1.42:5555")
        runner.script(argsPrefix: ["devices"], stdout: "List of devices attached\n")
        let service = await makeService(runner: runner)

        let result = try await service.connect(host: "192.168.1.42", port: "5555")
        #expect(result.ok)
        #expect(runner.invocations.contains {
            $0.arguments == ["connect", "192.168.1.42:5555"]
        })
    }

    @Test func connectFailureSurfacesAdbOutput() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["connect"], stdout: "failed to connect to 192.168.1.42:5555")
        runner.script(argsPrefix: ["devices"], stdout: "List of devices attached\n")
        let service = await makeService(runner: runner)

        let result = try await service.connect(host: "192.168.1.42", port: "5555")
        #expect(!result.ok)
        #expect(result.message == "failed to connect to 192.168.1.42:5555")
    }
}
