import Testing
@testable import ADBKit

@Suite struct WifiConnectArgTests {
    @Test func connectQuotesSsidAndPassword() async throws {
        // SSIDs routinely contain spaces/quotes; both the SSID and the password
        // must reach the device shell as single quoted arguments.
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s"], stdout: "")
        let service = WifiService(client: await makeTestClient(runner: runner))

        _ = try await service.connect(serial: "S1", ssid: "Cafe ' x", security: "wpa2", password: "p w")
        #expect(runner.invocations.last?.arguments == [
            "-s", "S1", "shell", "cmd", "wifi", "connect-network", "'Cafe '\\'' x'", "wpa2", "'p w'",
        ])
    }
}

@Suite struct WifiServiceTests {
    @Test func parsesConnectedStatusFromCmdWifi() {
        let status = WifiService.parseStatus(
            cmdStatus: """
            Wifi is enabled
            Wifi is connected to "HomeNet"
            WifiInfo: SSID: "HomeNet", BSSID: aa:bb:cc:dd:ee:ff, MAC: 02:00:00:00:00:00, \
            Supplicant state: COMPLETED, RSSI: -52, Link speed: 780Mbps, \
            Tx Link speed: 780Mbps, Frequency: 5180MHz, Net ID: 0
            """,
            dumpsys: "",
            ipAddr: "12: wlan0: <BROADCAST> inet 192.168.0.42/24 brd 192.168.0.255 scope global wlan0"
        )
        #expect(status.enabled)
        #expect(status.connected)
        #expect(status.ssid == "HomeNet")
        #expect(status.ipAddress == "192.168.0.42")
        #expect(status.linkSpeed == "780 Mbps")
        #expect(status.frequency == "5180 MHz")
        #expect(status.signal == "-52 dBm")
    }

    @Test func parsesDisabledStatus() {
        let status = WifiService.parseStatus(cmdStatus: "Wifi is disabled", dumpsys: "", ipAddr: "")
        #expect(!status.enabled)
        #expect(!status.connected)
        #expect(status.ssid == nil)
    }

    @Test func parsesSavedNetworksSkippingHeader() {
        let networks = WifiService.parseSavedNetworks("""
        Network Id      SSID                          Security type
        0               HomeNet                       PSK
        2               CoffeeShop                    OPEN
        """)
        #expect(networks.count == 2)
        #expect(networks[0].networkId == 0)
        #expect(networks[0].ssid == "HomeNet")
        #expect(networks[0].security == "PSK")
        #expect(networks[1].ssid == "CoffeeShop")
    }

    @Test func parsesConfigStorePasswords() {
        let creds = WifiService.parseConfigStore("""
        <WifiConfigStoreData>
        <NetworkList>
        <Network>
        <WifiConfiguration>
        <string name="SSID">&quot;HomeNet&quot;</string>
        <string name="PreSharedKey">&quot;s3cr3tpass&quot;</string>
        </WifiConfiguration>
        </Network>
        <Network>
        <WifiConfiguration>
        <string name="SSID">&quot;CoffeeShop&quot;</string>
        <null name="PreSharedKey" />
        </WifiConfiguration>
        </Network>
        </NetworkList>
        </WifiConfigStoreData>
        """)
        #expect(creds.count == 2)
        #expect(creds[0].ssid == "HomeNet")
        #expect(creds[0].password == "s3cr3tpass")
        #expect(creds[0].security == "PSK")
        #expect(creds[1].ssid == "CoffeeShop")
        #expect(creds[1].password == nil)
        #expect(creds[1].security == "open")
    }

    @Test func twoNetworksSharingAnIdStillGetDistinctIdentities() {
        // Real emulator output: `cmd wifi list-networks` prints the same
        // network id twice, once per security type. Two rows sharing an
        // `Identifiable.id` is undefined behaviour in a `ForEach` and a
        // duplicate-key warning in the desktop app, so the security type is
        // part of the identity.
        let networks = WifiService.parseSavedNetworks("""
        Network Id      SSID                         Security type
        0            AndroidWifi                      open
        0            AndroidWifi                      owe^
        """)

        #expect(networks.count == 2)
        #expect(networks[0].id != networks[1].id)
    }

    @Test func anIdentityIsStableAcrossRefetches() {
        // A watch poll re-reads the same listing; an id that changed between
        // reads would move the selection every time.
        let text = """
        Network Id      SSID                         Security type
        3            HomeNet                          WPA2
        """
        #expect(WifiService.parseSavedNetworks(text).first?.id
            == WifiService.parseSavedNetworks(text).first?.id)
    }

    @Test func decodeConfigStringUnescapesAndStripsQuotes() {
        #expect(WifiService.decodeConfigString("&quot;HomeNet&quot;") == "HomeNet")
        #expect(WifiService.decodeConfigString("&quot;p&amp;ss&quot;") == "p&ss")
        // A raw hex PSK is stored unquoted and must survive untouched.
        let hex = String(repeating: "a1b2", count: 16)
        #expect(WifiService.decodeConfigString(hex) == hex)
    }
}
