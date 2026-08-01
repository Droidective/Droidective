// ReactotronMCP serves the Reactotron relay's data, and that relay is
// `Network.framework`-based, so this whole target is Apple-only until the
// listener moves to NIO or raw sockets (a port follow-up). Gated rather than
// stubbed: off-Apple the module simply exposes nothing.
#if canImport(Network)

import ADBKit
import Foundation
import MCP

/// Bridging between ADBKit's `JSONValue` (the Reactotron payload type) and
/// the MCP SDK's `Value` (JSON-RPC arguments/results). Both are plain JSON
/// trees; the only care points are `Value`'s int/double split and its binary
/// case, which JSON can't carry.
extension JSONValue {
    var mcpValue: Value {
        switch self {
        case .null: .null
        case let .bool(flag): .bool(flag)
        case let .number(number):
            number.truncatingRemainder(dividingBy: 1) == 0 && abs(number) < 9e15
                ? .int(Int(number)) : .double(number)
        case let .string(text): .string(text)
        case let .array(items): .array(items.map(\.mcpValue))
        case let .object(dict): .object(dict.mapValues(\.mcpValue))
        }
    }
}

extension Value {
    var jsonValue: JSONValue {
        switch self {
        case .null: .null
        case let .bool(flag): .bool(flag)
        case let .int(number): .number(Double(number))
        case let .double(number): .number(number)
        case let .string(text): .string(text)
        case let .data(_, data): .string(data.base64EncodedString())
        case let .array(items): .array(items.map(\.jsonValue))
        case let .object(dict): .object(dict.mapValues(\.jsonValue))
        }
    }
}

extension [String: Value] {
    var jsonObject: [String: JSONValue] { mapValues(\.jsonValue) }
}

#endif
