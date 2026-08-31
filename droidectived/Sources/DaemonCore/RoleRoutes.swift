import ADBKit
import Foundation

/// The role picker's catalogue.
///
/// Served rather than re-listed in the client, and that is the whole point: a
/// role is six lists of feature ids in `FeatureRegistry.featuresByRole`, and a
/// second copy in TypeScript would drift the first time a feature is added to
/// a role — silently, because nothing would fail. The client renders what it is
/// given and applies it to its own layout.
///
/// Static, so it takes no backend and touches no device, exactly like
/// `ActionProtocol.features()`.
public enum RoleProtocol {
    /// One role, as a picker card needs it.
    public struct Role: Codable, Equatable, Sendable {
        public let id: String
        public let label: String
        /// The line under the role name on its card.
        public let blurb: String
        /// The features this role turns on, in the order they lead the sidebar.
        public let featureIDs: [String]
        /// The grouped sidebar's section order for this role — each category in
        /// the order its first curated feature appears, which is `seedRole`'s
        /// rule rather than the fixed display order.
        public let categoryOrder: [String]
        /// The device platforms the role works with, so a client can hide the
        /// ones it never wants to see.
        public let platforms: [String]

        // `icon` is deliberately absent, for the same reason it is absent from
        // `FeatureSummary`: an SF Symbol name means nothing off Apple, and
        // shipping it invites a web UI to depend on something it cannot render.
    }

    public struct RolesResponse: Codable, Equatable, Sendable {
        public let roles: [Role]
        /// The stack tools the picker's "I work with React Native" toggle adds
        /// to whatever role is chosen — a React Native QA is both.
        public let reactNativeStackIDs: [String]
    }

    public static func roles() -> RolesResponse {
        RolesResponse(
            roles: UserRole.allCases.map { role in
                Role(
                    id: role.rawValue,
                    label: role.label,
                    blurb: role.blurb,
                    featureIDs: FeatureRegistry.featureIDs(for: role),
                    categoryOrder: FeatureRegistry.categoryOrder(for: role),
                    platforms: FeatureRegistry.visiblePlatforms(for: role)
                        .map(\.rawValue).sorted())
            },
            reactNativeStackIDs: FeatureRegistry.reactNativeStackIDs)
    }
}
