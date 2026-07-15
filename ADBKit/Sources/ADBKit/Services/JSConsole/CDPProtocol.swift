import Foundation

/// Chrome DevTools Protocol message framing and typed decoders for the bits a
/// JavaScript console needs: `Runtime.evaluate`, `Runtime.getProperties`, and
/// the `Runtime.consoleAPICalled` / `Runtime.exceptionThrown` events. All pure
/// and `Sendable` — the request builders and decoders are unit-tested with
/// recorded payloads, no socket required. The transport lives in
/// `JSConsoleClient`.
public enum CDP {
    // MARK: - Outbound requests

    /// A `{ id, method, params }` request envelope.
    public static func request(id: Int, method: String, params: [String: JSONValue]) -> JSONValue {
        .object([
            "id": .number(Double(id)),
            "method": .string(method),
            "params": .object(params),
        ])
    }

    /// REPL-flavored `Runtime.evaluate` params. `replMode` allows `let`
    /// re-declaration and top-level `await`; `includeCommandLineAPI` exposes
    /// `$_` and friends; `generatePreview` returns inline object previews so the
    /// common log line renders without a follow-up `getProperties`; the object
    /// is kept in the `console` group (not returned by value) so it can be
    /// expanded lazily and released together on clear.
    public static func evaluateParams(expression: String) -> [String: JSONValue] {
        [
            "expression": .string(expression),
            "objectGroup": .string("console"),
            "includeCommandLineAPI": .bool(true),
            "replMode": .bool(true),
            "generatePreview": .bool(true),
            "userGesture": .bool(true),
            "awaitPromise": .bool(true),
            "returnByValue": .bool(false),
        ]
    }

    public static func releaseObjectGroupParams(_ group: String) -> [String: JSONValue] {
        ["objectGroup": .string(group)]
    }

    /// Minimal `Runtime.evaluate` params for the connection keepalive: a no-op
    /// expression, `silent` so it can never surface an exception event, and
    /// `returnByValue` so the runtime never creates (or retains) a remote
    /// object handle for the result.
    public static func keepaliveParams() -> [String: JSONValue] {
        [
            "expression": .string("void 0"),
            "silent": .bool(true),
            "returnByValue": .bool(true),
            "generatePreview": .bool(false),
        ]
    }

    public static func callFunctionOnParams(objectId: String, functionDeclaration: String) -> [String: JSONValue] {
        [
            "objectId": .string(objectId),
            "functionDeclaration": .string(functionDeclaration),
            "returnByValue": .bool(true),
            "awaitPromise": .bool(true),
        ]
    }

    /// Runs in the device's JS context (via `callFunctionOn`, `this` = the object)
    /// to produce a faithful deep JSON string for "Copy as JSON" — handling the
    /// types `JSON.stringify` drops or chokes on (bigint, functions, symbols,
    /// Map/Set, RegExp) and circular references. Dates serialize to ISO via their
    /// own `toJSON`.
    public static let deepStringifyFunction = """
    function () {
      const seen = new WeakSet();
      const replacer = (key, value) => {
        if (typeof value === 'bigint') return value.toString() + 'n';
        if (typeof value === 'number' && !Number.isFinite(value)) {
          return value > 0 ? 'Infinity' : value < 0 ? '-Infinity' : 'NaN';
        }
        if (Object.is(value, -0)) return '-0';
        if (typeof value === 'undefined') return '[undefined]';
        if (typeof value === 'function') return '[Function ' + (value.name || 'anonymous') + ']';
        if (typeof value === 'symbol') return value.toString();
        if (value instanceof Error) return { name: value.name, message: value.message, stack: value.stack };
        if (value instanceof Map) return { dataType: 'Map', entries: Array.from(value.entries()) };
        if (value instanceof Set) return { dataType: 'Set', values: Array.from(value.values()) };
        if (value instanceof RegExp) return value.toString();
        if (value && typeof value === 'object') {
          if (seen.has(value)) return '[Circular]';
          seen.add(value);
        }
        return value;
      };
      try { return JSON.stringify(this, replacer, 2); } catch (e) { return String(this); }
    }
    """

    /// Runs in the device's JS context (via `callFunctionOn`, `this` = the object)
    /// to produce a *bounded, ordered, type-tagged* tree for expanding a logged
    /// value, serialized to a single JSON string (`SnapNode`).
    ///
    /// This exists because `Runtime.getProperties` crashes Hermes's VM (a native
    /// null-deref in its RemoteObject converter) when it recursively serializes
    /// some values — expanding e.g. a 200-element array killed the app. Building
    /// the tree entirely in JS and returning a single *string* never goes through
    /// that native converter (the return is a primitive), so it can't trip the
    /// bug. Object entries are emitted as an ordered array so insertion order is
    /// preserved (a plain JSON object would be reordered by the decoder). The
    /// depth / breadth / string caps keep a huge or deeply nested payload
    /// bounded, and `truncated` marks where a level was cut.
    public static let boundedSnapshotFunction = """
    function () {
      const MAX_DEPTH = 6, MAX_ITEMS = 500, MAX_STRING = 10000, MAX_NODES = 20000;
      const seen = new WeakSet();
      let budget = MAX_NODES;
      const prim = (type, text) => ({ type: type, text: text });
      const build = (value, depth) => {
        // Total-node cap: per-level caps alone (depth × breadth) are
        // multiplicatively unbounded, so a wide-and-deep graph could still
        // produce a huge string. Stop emitting once the whole snapshot is big.
        if (budget <= 0) return prim('string', '…(truncated)');
        budget--;
        const t = typeof value;
        if (value === null) return prim('null', 'null');
        if (t === 'string') return prim('string', value.length > MAX_STRING ? value.slice(0, MAX_STRING) + '…(+' + (value.length - MAX_STRING) + ' chars)' : value);
        if (t === 'number') return prim('number', Number.isFinite(value) ? String(value) : (value > 0 ? 'Infinity' : value < 0 ? '-Infinity' : 'NaN'));
        if (t === 'boolean') return prim('boolean', String(value));
        if (t === 'undefined') return prim('undefined', 'undefined');
        if (t === 'bigint') return prim('bigint', value.toString() + 'n');
        if (t === 'symbol') return prim('symbol', value.toString());
        if (t === 'function') return prim('function', '\\u0192 ' + (value.name || 'anonymous') + '()');
        if (value instanceof Error) return prim('string', value.stack || (value.name + ': ' + value.message));
        if (value instanceof RegExp) return prim('string', value.toString());
        if (depth >= MAX_DEPTH) return prim('string', Array.isArray(value) ? 'Array(' + value.length + ')' : 'Object');
        if (seen.has(value)) return prim('string', '[Circular]');
        seen.add(value);
        try {
          let src = value, ctor = 'Object';
          if (value instanceof Map) src = { dataType: 'Map', entries: Array.from(value.entries()) };
          else if (value instanceof Set) src = { dataType: 'Set', values: Array.from(value.values()) };
          if (Array.isArray(src)) {
            const items = [];
            const n = Math.min(src.length, MAX_ITEMS);
            for (let i = 0; i < n; i++) { try { items.push(build(src[i], depth + 1)); } catch (e) { items.push(prim('string', '[threw]')); } }
            return { type: 'array', length: src.length, truncated: src.length > MAX_ITEMS, items: items };
          }
          try { ctor = (src.constructor && src.constructor.name) || 'Object'; } catch (e) {}
          const keys = Object.keys(src);
          const n = Math.min(keys.length, MAX_ITEMS);
          const entries = [];
          for (let i = 0; i < n; i++) {
            const k = keys[i];
            let child;
            try { child = build(src[k], depth + 1); } catch (e) { child = prim('string', '[threw]'); }
            entries.push({ name: k, node: child });
          }
          return { type: 'object', ctor: ctor, truncated: keys.length > MAX_ITEMS, entries: entries };
        } finally { seen.delete(value); }
      };
      try { return JSON.stringify(build(this, 0)); } catch (e) { return JSON.stringify(prim('string', String(e))); }
    }
    """

    // MARK: - Inbound messages

    /// A decoded inbound frame: either a reply to one of our requests (`id`) or
    /// an unsolicited event (`method`).
    public enum Incoming: Sendable, Equatable {
        case response(id: Int, result: JSONValue?, error: CDPError?)
        case event(method: String, params: JSONValue)
    }

    public static func parseIncoming(_ data: Data) -> Incoming? {
        guard let root = try? JSONDecoder().decode(JSONValue.self, from: data) else { return nil }
        if let id = root["id"]?.intValue {
            return .response(id: id, result: root["result"], error: CDPError(json: root["error"]))
        }
        if let method = root["method"]?.stringValue {
            return .event(method: method, params: root["params"] ?? .object([:]))
        }
        return nil
    }
}

/// A protocol-level error (`{ code, message }`) — distinct from a JavaScript
/// exception, which arrives as `exceptionDetails` inside a successful reply.
public struct CDPError: Sendable, Equatable {
    public let code: Int
    public let message: String

    public init?(json: JSONValue?) {
        guard let json, let message = json["message"]?.stringValue else { return nil }
        code = json["code"]?.intValue ?? 0
        self.message = message
    }
}

/// A CDP `Runtime.RemoteObject` — a reference to (or value of) a JS value. For
/// objects/functions, `objectId` is the handle passed to `Runtime.getProperties`
/// to expand it; `preview` is the inline collapsed rendering.
public struct RemoteObject: Sendable, Equatable {
    public let type: String
    public let subtype: String?
    public let className: String?
    public let value: JSONValue?
    public let unserializableValue: String?
    public let description: String?
    public let objectId: String?
    public let preview: ObjectPreview?

    public init(json: JSONValue) {
        type = json["type"]?.stringValue ?? "undefined"
        subtype = json["subtype"]?.stringValue
        className = json["className"]?.stringValue
        value = json["value"]
        unserializableValue = json["unserializableValue"]?.stringValue
        description = json["description"]?.stringValue
        objectId = json["objectId"]?.stringValue
        preview = json["preview"].map(ObjectPreview.init(json:))
    }

    /// Has a handle that can be expanded with `getProperties`.
    public var isExpandable: Bool {
        objectId != nil && (type == "object" || type == "function") && subtype != "null"
    }
}

/// A collapsed inline preview of an object/array (CDP `ObjectPreview`).
public struct ObjectPreview: Sendable, Equatable {
    public let type: String
    public let subtype: String?
    public let description: String?
    public let overflow: Bool
    public let properties: [PropertyPreview]

    public init(json: JSONValue) {
        type = json["type"]?.stringValue ?? "object"
        subtype = json["subtype"]?.stringValue
        description = json["description"]?.stringValue
        overflow = json["overflow"]?.boolValue ?? false
        properties = (json["properties"]?.arrayValue ?? []).map(PropertyPreview.init(json:))
    }
}

public struct PropertyPreview: Sendable, Equatable {
    public let name: String
    public let type: String
    public let value: String?
    public let subtype: String?

    public init(json: JSONValue) {
        name = json["name"]?.stringValue ?? ""
        type = json["type"]?.stringValue ?? "string"
        value = json["value"]?.stringValue
        subtype = json["subtype"]?.stringValue
    }
}

/// A `Runtime.consoleAPICalled` event — one `console.*` call from the app.
public struct ConsoleAPICall: Sendable, Equatable {
    public let type: String
    public let args: [RemoteObject]
    public let timestamp: Double?
    public let stackTrace: CDPStackTrace?

    public init(params: JSONValue) {
        type = params["type"]?.stringValue ?? "log"
        args = (params["args"]?.arrayValue ?? []).map(RemoteObject.init(json:))
        timestamp = params["timestamp"]?.doubleValue
        stackTrace = params["stackTrace"].map(CDPStackTrace.init(json:))
    }
}

/// Details of a thrown JS error, from `Runtime.exceptionThrown` or the
/// `exceptionDetails` of a `Runtime.evaluate` reply.
public struct ExceptionDetails: Sendable, Equatable {
    public let text: String
    public let exception: RemoteObject?
    public let lineNumber: Int?
    public let columnNumber: Int?
    public let url: String?
    public let stackTrace: CDPStackTrace?

    public init(json: JSONValue) {
        text = json["text"]?.stringValue ?? "Uncaught"
        exception = json["exception"].map(RemoteObject.init(json:))
        lineNumber = json["lineNumber"]?.intValue
        columnNumber = json["columnNumber"]?.intValue
        url = json["url"]?.stringValue
        stackTrace = json["stackTrace"].map(CDPStackTrace.init(json:))
    }

    /// The error's full message (and embedded stack, for an Error object) — what
    /// to render as the failure line.
    public var message: String {
        exception?.description ?? text
    }
}

public struct CDPStackTrace: Sendable, Equatable {
    public let callFrames: [CDPCallFrame]

    public init(json: JSONValue) {
        callFrames = (json["callFrames"]?.arrayValue ?? []).map(CDPCallFrame.init(json:))
    }
}

public struct CDPCallFrame: Sendable, Equatable, Identifiable {
    public let functionName: String
    public let url: String
    public let lineNumber: Int
    public let columnNumber: Int

    public var id: String { "\(functionName)@\(url):\(lineNumber):\(columnNumber)" }

    public init(json: JSONValue) {
        functionName = json["functionName"]?.stringValue ?? ""
        url = json["url"]?.stringValue ?? ""
        lineNumber = json["lineNumber"]?.intValue ?? 0
        columnNumber = json["columnNumber"]?.intValue ?? 0
    }

    /// `functionName  file:line` — CDP line numbers are 0-based, shown 1-based.
    public var display: String {
        let fn = functionName.isEmpty ? "(anonymous)" : functionName
        guard !url.isEmpty else { return fn }
        return "\(fn)  \(url):\(lineNumber + 1)"
    }
}

/// The outcome of a `Runtime.evaluate`: a value, or a JavaScript exception. A
/// thrown JS error comes back in the *successful* reply as `exceptionDetails`,
/// so this never collapses a JS throw into a transport error.
public enum EvalOutcome: Sendable, Equatable {
    case value(RemoteObject)
    case error(ExceptionDetails)

    public static func from(result: JSONValue?) -> EvalOutcome {
        if let details = result?["exceptionDetails"] {
            return .error(ExceptionDetails(json: details))
        }
        let object = result?["result"] ?? .object(["type": .string("undefined")])
        return .value(RemoteObject(json: object))
    }
}
