import Testing
@testable import ADBKit

@Suite struct ShowTouchesTests {
    @Test func setWritesTheSystemSetting() async throws {
        let runner = MockProcessRunner()
        let service = ShowTouches(client: await makeTestClient(runner: runner))
        try await service.set(true, serial: "S1")
        try await service.set(false, serial: "S1")
        #expect(runner.invocations.contains {
            $0.arguments == ["-s", "S1", "shell", "settings", "put", "system", "show_touches", "1"]
        })
        #expect(runner.invocations.contains {
            $0.arguments == ["-s", "S1", "shell", "settings", "put", "system", "show_touches", "0"]
        })
    }
}
