import ADBKit
import Foundation
import Testing

@testable import DaemonCore

/// The role catalogue is served rather than re-listed in the client, so these
/// are the invariants that make that worth doing: every role reaches the wire,
/// every id it names is a real feature, and the order the sidebar needs
/// survives the trip.
@Suite struct RoleRouteTests {
    @Test func everyRoleReachesTheWire() throws {
        let response = RoleProtocol.roles()
        #expect(response.roles.count == UserRole.allCases.count)
        #expect(Set(response.roles.map(\.id)) == Set(UserRole.allCases.map(\.rawValue)))
        for role in response.roles {
            #expect(!role.label.isEmpty, "\(role.id) has no label")
            #expect(!role.blurb.isEmpty, "\(role.id) has no blurb")
            #expect(!role.featureIDs.isEmpty, "\(role.id) curates nothing")
        }
    }

    /// The registry-invariant shape: a role naming an id that no longer exists
    /// would curate a sidebar with a hole in it, and nothing would say so.
    @Test func everyCuratedIDIsARealFeature() throws {
        for role in RoleProtocol.roles().roles {
            for id in role.featureIDs {
                #expect(FeatureRegistry.byID[id] != nil, "\(role.id) names a missing \(id)")
            }
        }
        for id in RoleProtocol.roles().reactNativeStackIDs {
            #expect(FeatureRegistry.byID[id] != nil, "the RN stack names a missing \(id)")
        }
    }

    /// `seedRole` orders the sidebar's sections by where each category's first
    /// curated feature falls, not by the fixed display order. A client that
    /// re-derived this would get a different sidebar from the Mac's.
    @Test func theCategoryOrderIsTheOneSeedRoleWouldApply() throws {
        for role in UserRole.allCases {
            let served = RoleProtocol.roles().roles.first { $0.id == role.rawValue }
            #expect(served?.categoryOrder == FeatureRegistry.categoryOrder(for: role))
        }
    }

    /// The picker hides device platforms a role never works with, so the answer
    /// has to cross the wire — iOS Developer is simulator-only and React Native
    /// spans both.
    @Test func platformsCrossTheWire() throws {
        let byID = Dictionary(
            uniqueKeysWithValues: RoleProtocol.roles().roles.map { ($0.id, $0) })
        #expect(byID["ios-dev"]?.platforms == ["ios-simulator"])
        #expect(byID["rn-dev"]?.platforms == ["android", "ios-simulator"])
        #expect(byID["qa"]?.platforms == ["android"])
    }
}
