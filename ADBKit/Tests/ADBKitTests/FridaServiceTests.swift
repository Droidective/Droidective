import Foundation
import Testing
@testable import ADBKit

@Suite struct FridaServiceTests {
    @Test func mapsAbiListToFridaArch() {
        #expect(FridaArch.from(abilist: "arm64-v8a,armeabi-v7a,armeabi") == "arm64")
        #expect(FridaArch.from(abilist: "armeabi-v7a,armeabi") == "arm")
        #expect(FridaArch.from(abilist: "x86_64,x86") == "x86_64")
        #expect(FridaArch.from(abilist: "x86") == "x86")
        #expect(FridaArch.from(abilist: "mips,unknown") == nil)
    }

    @Test func serverArgumentsQuoteDeviceShellValues() {
        #expect(FridaService.pushArguments(localPath: "/tmp/frida-server")
            == ["push", "/tmp/frida-server", "/data/local/tmp/frida-server"])
        #expect(FridaService.chmodArguments() == ["shell", "chmod", "755", "'/data/local/tmp/frida-server'"])
        #expect(FridaService.startArguments()
            == ["shell", "su", "-c", "'setsid /data/local/tmp/frida-server </dev/null >/dev/null 2>&1 &'"])
        #expect(FridaService.stopArguments() == ["shell", "su", "-c", "'pkill -f frida-server'"])
        #expect(FridaService.statusArguments() == ["shell", "pidof", "frida-server"])
    }

    @Test func deviceArchReadsAbilistProp() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1", "shell", "getprop", "ro.product.cpu.abilist"], stdout: "arm64-v8a,armeabi-v7a\n")
        let service = FridaService(client: await makeTestClient(runner: runner))
        #expect(try await service.deviceArch(serial: "S1") == "arm64")
    }

    @Test func installServerPushesThenChmods() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1"], stdout: "")
        let service = FridaService(client: await makeTestClient(runner: runner))
        _ = try await service.installServer(localPath: "/tmp/fs", serial: "S1")
        #expect(runner.invocations.contains { $0.arguments == ["-s", "S1", "push", "/tmp/fs", "/data/local/tmp/frida-server"] })
        #expect(runner.invocations.contains { $0.arguments == ["-s", "S1", "shell", "chmod", "755", "'/data/local/tmp/frida-server'"] })
    }

    @Test func serverRunningReflectsPidof() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1", "shell", "pidof"], stdout: "12345\n")
        let service = FridaService(client: await makeTestClient(runner: runner))
        #expect(try await service.isServerRunning(serial: "S1"))
    }

    @Test func serverNotRunningWhenPidofEmpty() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1", "shell", "pidof"], stdout: "\n")
        let service = FridaService(client: await makeTestClient(runner: runner))
        let running = try await service.isServerRunning(serial: "S1")
        #expect(!running)
    }
}
