import ADBKit
import Foundation

/// Wire shapes for the feature surface.
///
/// Actions route straight through `FeatureEngine.run`, so the daemon carries
/// **no feature knowledge of its own**: a new registry action is reachable over
/// HTTP the day it lands, with no daemon change. That is the same property
/// `implementedIDs` already gives the Mac app, and it is why this is a thin
/// pass-through rather than a hand-maintained endpoint per action.
public enum ActionProtocol {
    /// A form field's value. JSON has no tagged unions, so this decodes from a
    /// bare string, number or bool — what a UI would naturally send — rather
    /// than demanding `{"type":"string","value":…}`.
    public struct Value: Codable, Equatable, Sendable {
        public let feature: FeatureValue

        public init(_ feature: FeatureValue) { self.feature = feature }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            // Bool before number: `JSONDecoder` will happily read `true` as 1.
            if let bool = try? container.decode(Bool.self) {
                feature = .bool(bool)
            } else if let number = try? container.decode(Double.self) {
                feature = .number(number)
            } else {
                feature = .string(try container.decode(String.self))
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch feature {
            case .string(let value): try container.encode(value)
            case .number(let value): try container.encode(value)
            case .bool(let value): try container.encode(value)
            }
        }
    }

    public struct RunRequest: Codable, Equatable, Sendable {
        public let featureId: String
        public let serial: String
        /// Defaults to Android — the overwhelmingly common case, and omitting
        /// it should not be an error for a client that only drives phones.
        public let platform: String?
        public let fields: [String: Value]?

        public init(
            featureId: String, serial: String, platform: String? = nil,
            fields: [String: Value]? = nil
        ) {
            self.featureId = featureId
            self.serial = serial
            self.platform = platform
            self.fields = fields
        }

        /// `nil` for an unrecognised platform string, so it is rejected rather
        /// than silently treated as Android.
        public var resolvedPlatform: DevicePlatform? {
            switch platform {
            case nil, "android": return .android
            case "iosSimulator", "ios-simulator": return .iosSimulator
            default: return nil
            }
        }

        public var featureValues: [String: FeatureValue] {
            (fields ?? [:]).mapValues(\.feature)
        }
    }

    public struct RunResponse: Codable, Equatable, Sendable {
        public let ok: Bool
        public let message: String
        public let copyText: String?
        public let revealPath: String?
        public let needsAdbKeyboard: Bool

        public init(_ result: FeatureResult) {
            ok = result.ok
            message = result.message
            copyText = result.copyText
            revealPath = result.revealPath
            needsAdbKeyboard = result.needsAdbKeyboard
        }
    }

    /// A feature as a UI needs it: enough to render a row and a form, and
    /// nothing that is Mac-specific.
    public struct FeatureSummary: Codable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let subtitle: String?
        /// The search vocabulary `FeatureDef.relevance` ranks on. Without it a
        /// client can only match titles, and the registry's discoverability —
        /// "battery" finding the Simulate hub — does not survive the wire.
        public let keywords: [String]
        public let category: String
        public let kind: String
        public let implemented: Bool
        public let needsDevice: Bool
        public let needsBundle: Bool
        /// Worth a confirmation step. A client that cannot tell "Take
        /// Screenshot" from "Clear App Data" will eventually run the wrong one.
        public let isDestructive: Bool
        /// True when a hub screen owns this feature on the Mac. Whether to
        /// show it standalone is the client's call, but it cannot make that
        /// call if the registry's answer never reaches it.
        public let isAbsorbedByHub: Bool
        public let fields: [Field]

        public struct Field: Codable, Equatable, Sendable {
            public let name: String
            public let label: String
            public let control: String
            public let options: [Option]
            public let placeholder: String?
            public let description: String?
            public let defaultValue: Value?
            public let optional: Bool
            /// Set for `slider` and some `number` fields. A slider without
            /// bounds is not renderable, so these are not decoration.
            public let min: Double?
            public let max: Double?
            public let step: Double?

            /// Both halves of a choice. The value is what the runner wants;
            /// the label is what a person can read — "ar-EG" against
            /// "Arabic (Egypt) — RTL".
            public struct Option: Codable, Equatable, Sendable {
                public let value: String
                public let label: String
            }
        }
    }

    public struct FeaturesResponse: Codable, Equatable, Sendable {
        public let features: [FeatureSummary]
    }

    /// The registry, flattened for the wire.
    ///
    /// `icon` is deliberately dropped: it is an SF Symbol name, which means
    /// nothing off Apple, and shipping it would invite a web UI to depend on
    /// something it cannot render.
    public static func features() -> FeaturesResponse {
        let implemented = FeatureEngine.implementedIDs
        return FeaturesResponse(
            features: FeatureRegistry.all.map { def in
                FeatureSummary(
                    id: def.id,
                    title: def.title,
                    subtitle: def.subtitle,
                    keywords: def.keywords,
                    category: String(describing: def.category),
                    kind: String(describing: def.kind),
                    implemented: implemented.contains(def.id),
                    needsDevice: def.needsDevice,
                    needsBundle: def.needsBundle,
                    isDestructive: def.isDestructive,
                    isAbsorbedByHub: def.isAbsorbedByHub,
                    fields: def.fields.map { field in
                        FeatureSummary.Field(
                            name: field.name, label: field.label,
                            control: String(describing: field.control),
                            options: field.options.map {
                                FeatureSummary.Field.Option(value: $0.value, label: $0.label)
                            },
                            placeholder: field.placeholder,
                            description: field.description,
                            defaultValue: field.defaultValue.map(Value.init),
                            optional: field.optional,
                            min: field.min, max: field.max, step: field.step)
                    })
            })
    }
}
