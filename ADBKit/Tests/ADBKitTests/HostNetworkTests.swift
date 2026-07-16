import Foundation
import Testing
@testable import ADBKit

@Suite struct HostNetworkTests {
    private func candidate(_ interface: String, _ address: String) -> HostNetwork.Candidate {
        HostNetwork.Candidate(interface: interface, address: address)
    }

    @Test func prefersEnInterfacesOverVirtualOnes() {
        let picked = HostNetwork.pickPrimary(from: [
            candidate("utun3", "10.8.0.2"),
            candidate("en0", "192.168.1.23"),
            candidate("bridge100", "192.168.64.1"),
        ])
        #expect(picked == "192.168.1.23")
    }

    @Test func lowestEnNumberWins() {
        let picked = HostNetwork.pickPrimary(from: [
            candidate("en12", "192.168.5.9"),
            candidate("en0", "192.168.1.23"),
            candidate("en2", "10.0.0.4"),
        ])
        #expect(picked == "192.168.1.23")
    }

    @Test func numericSuffixOrderingBeatsLexicographic() {
        // "en10" < "en2" as strings — the rank must compare numbers.
        let picked = HostNetwork.pickPrimary(from: [
            candidate("en10", "192.168.5.9"),
            candidate("en2", "10.0.0.4"),
        ])
        #expect(picked == "10.0.0.4")
    }

    @Test func linkLocalAddressesNeverWin() {
        let picked = HostNetwork.pickPrimary(from: [
            candidate("en0", "169.254.10.20"),
            candidate("utun1", "10.8.0.2"),
        ])
        #expect(picked == "10.8.0.2")
    }

    @Test func onlyLinkLocalMeansNoAddress() {
        let picked = HostNetwork.pickPrimary(from: [candidate("en0", "169.254.10.20")])
        #expect(picked == nil)
    }

    @Test func emptyMeansNoAddress() {
        #expect(HostNetwork.pickPrimary(from: []) == nil)
    }

    @Test func virtualInterfaceTiesKeepTheFirst() {
        let picked = HostNetwork.pickPrimary(from: [
            candidate("utun0", "10.8.0.2"),
            candidate("utun1", "10.9.0.2"),
        ])
        #expect(picked == "10.8.0.2")
    }
}
