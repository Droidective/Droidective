import Foundation

// MARK: - Status codes

public enum HttpStatus: Sendable {
    /// Reason phrase from the IANA registry. Kept as a table rather than
    /// `HTTPURLResponse.localizedString(forStatusCode:)` so the same text comes
    /// back on every platform (that API lives in FoundationNetworking off-Apple
    /// and localises, which makes assertions locale-dependent).
    public static func text(for code: Int) -> String {
        switch code {
        case 100: return "Continue"
        case 101: return "Switching Protocols"
        case 102: return "Processing"
        case 103: return "Early Hints"
        case 200: return "OK"
        case 201: return "Created"
        case 202: return "Accepted"
        case 203: return "Non-Authoritative Information"
        case 204: return "No Content"
        case 205: return "Reset Content"
        case 206: return "Partial Content"
        case 207: return "Multi-Status"
        case 208: return "Already Reported"
        case 226: return "IM Used"
        case 300: return "Multiple Choices"
        case 301: return "Moved Permanently"
        case 302: return "Found"
        case 303: return "See Other"
        case 304: return "Not Modified"
        case 305: return "Use Proxy"
        case 307: return "Temporary Redirect"
        case 308: return "Permanent Redirect"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 402: return "Payment Required"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 406: return "Not Acceptable"
        case 407: return "Proxy Authentication Required"
        case 408: return "Request Timeout"
        case 409: return "Conflict"
        case 410: return "Gone"
        case 411: return "Length Required"
        case 412: return "Precondition Failed"
        case 413: return "Content Too Large"
        case 414: return "URI Too Long"
        case 415: return "Unsupported Media Type"
        case 416: return "Range Not Satisfiable"
        case 417: return "Expectation Failed"
        case 418: return "I'm a Teapot"
        case 421: return "Misdirected Request"
        case 422: return "Unprocessable Content"
        case 423: return "Locked"
        case 424: return "Failed Dependency"
        case 425: return "Too Early"
        case 426: return "Upgrade Required"
        case 428: return "Precondition Required"
        case 429: return "Too Many Requests"
        case 431: return "Request Header Fields Too Large"
        case 451: return "Unavailable For Legal Reasons"
        case 500: return "Internal Server Error"
        case 501: return "Not Implemented"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        case 504: return "Gateway Timeout"
        case 505: return "HTTP Version Not Supported"
        case 506: return "Variant Also Negotiates"
        case 507: return "Insufficient Storage"
        case 508: return "Loop Detected"
        case 510: return "Not Extended"
        case 511: return "Network Authentication Required"
        default: return category(for: code)
        }
    }

    public static func category(for code: Int) -> String {
        switch code {
        case 100..<200: return "Informational"
        case 200..<300: return "Success"
        case 300..<400: return "Redirection"
        case 400..<500: return "Client Error"
        case 500..<600: return "Server Error"
        default: return "Unknown"
        }
    }
}

// MARK: - Timing and redirects

/// Per-phase timings when the transport reports them. All values in ms.
public struct ApiTiming: Sendable, Equatable {
    public var dns: Double?
    public var connect: Double?
    public var tls: Double?
    public var firstByte: Double?
    public var total: Double

    public init(
        dns: Double? = nil,
        connect: Double? = nil,
        tls: Double? = nil,
        firstByte: Double? = nil,
        total: Double
    ) {
        self.dns = dns
        self.connect = connect
        self.tls = tls
        self.firstByte = firstByte
        self.total = total
    }
}

public struct RedirectHop: Sendable, Equatable {
    public var statusCode: Int
    public var from: String
    public var to: String

    public init(statusCode: Int, from: String, to: String) {
        self.statusCode = statusCode
        self.from = from
        self.to = to
    }
}

// MARK: - Cookies

public struct ApiCookie: Sendable, Equatable, Identifiable {
    public var name: String
    public var value: String
    public var domain: String
    public var path: String
    public var expires: String
    public var maxAge: String
    public var httpOnly: Bool
    public var secure: Bool
    public var sameSite: String

    public var id: String { "\(domain)|\(path)|\(name)" }

    public init(
        name: String, value: String, domain: String = "", path: String = "",
        expires: String = "", maxAge: String = "", httpOnly: Bool = false,
        secure: Bool = false, sameSite: String = ""
    ) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.expires = expires
        self.maxAge = maxAge
        self.httpOnly = httpOnly
        self.secure = secure
        self.sameSite = sameSite
    }

    /// Parses one `Set-Cookie` value. Returns nil when there is no `name=`
    /// pair, which is the only part of the header that is mandatory.
    public static func parse(_ header: String) -> ApiCookie? {
        let parts = header.components(separatedBy: ";")
        guard let first = parts.first else { return nil }
        guard let equals = first.firstIndex(of: "=") else { return nil }
        let name = String(first[first.startIndex..<equals]).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        var cookie = ApiCookie(
            name: name,
            value: String(first[first.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
        )
        for attribute in parts.dropFirst() {
            let trimmed = attribute.trimmingCharacters(in: .whitespaces)
            let name: String
            let value: String
            if let equals = trimmed.firstIndex(of: "=") {
                name = String(trimmed[trimmed.startIndex..<equals]).lowercased()
                value = String(trimmed[trimmed.index(after: equals)...])
                    .trimmingCharacters(in: .whitespaces)
            } else {
                name = trimmed.lowercased()
                value = ""
            }
            switch name {
            case "domain": cookie.domain = value
            case "path": cookie.path = value
            case "expires": cookie.expires = value
            case "max-age": cookie.maxAge = value
            case "httponly": cookie.httpOnly = true
            case "secure": cookie.secure = true
            case "samesite": cookie.sameSite = value
            default: break
            }
        }
        return cookie
    }
}

// MARK: - Body format

public enum ResponseFormat: String, Sendable, CaseIterable {
    case json
    case xml
    case html
    case text
    case image
    case binary

    public var isTextual: Bool {
        switch self {
        case .json, .xml, .html, .text: return true
        case .image, .binary: return false
        }
    }
}

// MARK: - Response

public struct ApiResponse: Sendable {
    public let statusCode: Int
    public let statusText: String
    /// In wire order, duplicates preserved (`Set-Cookie` repeats).
    public let headers: [(key: String, value: String)]
    public let body: Data
    public let elapsedMs: Double
    /// Bytes received. Equals `body.count` unless the response was truncated.
    public let size: Int
    /// True when the body hit `RequestSettings.maxResponseBytes` and was cut.
    public let truncated: Bool
    public let redirects: [RedirectHop]
    public let timing: ApiTiming?
    /// The URL that actually produced this response, after any redirects.
    public let finalURL: String

    public init(
        statusCode: Int,
        statusText: String? = nil,
        headers: [(key: String, value: String)],
        body: Data,
        elapsedMs: Double,
        size: Int? = nil,
        truncated: Bool = false,
        redirects: [RedirectHop] = [],
        timing: ApiTiming? = nil,
        finalURL: String = ""
    ) {
        self.statusCode = statusCode
        self.statusText = statusText ?? HttpStatus.text(for: statusCode)
        self.headers = headers
        self.body = body
        self.elapsedMs = elapsedMs
        self.size = size ?? body.count
        self.truncated = truncated
        self.redirects = redirects
        self.timing = timing
        self.finalURL = finalURL
    }

    // MARK: Headers

    /// Case-insensitive lookup. Repeated headers join with `, ` the way HTTP
    /// allows them to be combined.
    public func headerValue(_ name: String) -> String? {
        let wanted = name.lowercased()
        let matches = headers.filter { $0.key.lowercased() == wanted }.map(\.value)
        return matches.isEmpty ? nil : matches.joined(separator: ", ")
    }

    public var contentType: String? { headerValue("Content-Type") }

    /// The media type without parameters, lowercased.
    public var mediaType: String {
        (contentType ?? "")
            .components(separatedBy: ";")
            .first?
            .trimmingCharacters(in: .whitespaces)
            .lowercased() ?? ""
    }

    public var charsetName: String? {
        guard let contentType else { return nil }
        for parameter in contentType.components(separatedBy: ";").dropFirst() {
            let trimmed = parameter.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("charset") else { continue }
            guard let equals = trimmed.firstIndex(of: "=") else { continue }
            return String(trimmed[trimmed.index(after: equals)...])
                .trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                .lowercased()
        }
        return nil
    }

    public var cookies: [ApiCookie] {
        headers
            .filter { $0.key.lowercased() == "set-cookie" }
            .compactMap { ApiCookie.parse($0.value) }
    }

    public var isSuccess: Bool { (200..<300).contains(statusCode) }

    // MARK: Body

    /// Decoded with the charset the server declared, falling back to UTF-8 and
    /// then Latin-1 (which cannot fail) so text is never lost to a bad label.
    public var bodyString: String? {
        if body.isEmpty { return "" }
        if let name = charsetName, let encoding = ApiResponse.encoding(forCharset: name),
           let text = String(data: body, encoding: encoding) {
            return text
        }
        if let text = String(data: body, encoding: .utf8) { return text }
        if format.isTextual { return String(data: body, encoding: .isoLatin1) }
        return nil
    }

    static func encoding(forCharset name: String) -> String.Encoding? {
        switch name {
        case "utf-8", "utf8": return .utf8
        case "utf-16", "utf16": return .utf16
        case "utf-16le", "utf16le": return .utf16LittleEndian
        case "utf-16be", "utf16be": return .utf16BigEndian
        case "utf-32", "utf32": return .utf32
        case "iso-8859-1", "iso8859-1", "latin1", "latin-1": return .isoLatin1
        case "iso-8859-2", "iso8859-2", "latin2": return .isoLatin2
        case "windows-1250", "cp1250": return .windowsCP1250
        case "windows-1251", "cp1251": return .windowsCP1251
        case "windows-1252", "cp1252": return .windowsCP1252
        case "windows-1253", "cp1253": return .windowsCP1253
        case "windows-1254", "cp1254": return .windowsCP1254
        case "us-ascii", "ascii": return .ascii
        case "shift_jis", "shift-jis", "sjis": return .shiftJIS
        case "euc-jp", "eucjp": return .japaneseEUC
        default: return nil
        }
    }

    /// Content-Type first, then a sniff of the leading bytes — plenty of APIs
    /// return JSON labelled `text/plain`.
    public var format: ResponseFormat {
        let type = mediaType
        if type.hasPrefix("image/") { return .image }
        if type.contains("json") { return .json }
        if type.contains("xml") { return .xml }
        if type.contains("html") { return .html }
        if !type.isEmpty, !type.hasPrefix("text/"), !ApiResponse.textualTypes.contains(type) {
            return .binary
        }
        return ApiResponse.sniffFormat(body)
    }

    static let textualTypes: Set<String> = [
        "application/javascript", "application/x-javascript", "application/graphql",
        "application/x-www-form-urlencoded", "application/csv", "application/x-ndjson",
    ]

    static func sniffFormat(_ data: Data) -> ResponseFormat {
        let head = data.prefix(1024)
        if head.isEmpty { return .text }
        if head.contains(0) { return .binary }
        guard let text = String(data: head, encoding: .utf8) else { return .binary }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") { return .json }
        if trimmed.lowercased().hasPrefix("<!doctype html") { return .html }
        if trimmed.hasPrefix("<?xml") { return .xml }
        if trimmed.hasPrefix("<") { return trimmed.lowercased().contains("<html") ? .html : .xml }
        return .text
    }

    public var isJSON: Bool { format == .json }

    /// Re-indented body for the viewer, or nil when the format has no pretty
    /// form. JSON keys keep the server's order — sorting them would misrepresent
    /// the payload you are inspecting.
    public var prettyBody: String? {
        guard let text = bodyString, !text.isEmpty else { return nil }
        switch format {
        case .json: return JSONFormatter.prettyPrint(text)
        case .xml, .html: return XMLFormatter.prettyPrint(text)
        case .text, .image, .binary: return nil
        }
    }

    /// Kept for the response pane's "Pretty" toggle on JSON specifically.
    public var prettyJSON: String? {
        guard let text = bodyString else { return nil }
        return JSONFormatter.prettyPrint(text)
    }

    public var sizeText: String { ApiResponse.formatBytes(size) }

    public static func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1_048_576 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        if bytes < 1_073_741_824 { return String(format: "%.1f MB", Double(bytes) / 1_048_576) }
        return String(format: "%.2f GB", Double(bytes) / 1_073_741_824)
    }

    public static func statusText(for code: Int) -> String { HttpStatus.text(for: code) }
}

// MARK: - JSON formatting

public enum JSONFormatter: Sendable {

    /// Re-indents valid JSON while preserving key order and number formatting.
    /// Returns nil for anything that isn't valid JSON, so the caller can show
    /// the raw text instead of a mangled reformat.
    public static func prettyPrint(_ text: String, indent: String = "  ") -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isValidJSON(trimmed) else { return nil }

        var out = ""
        out.reserveCapacity(trimmed.count + trimmed.count / 4)
        var depth = 0
        var inString = false
        var escaped = false
        let characters = Array(trimmed)
        var index = 0

        func newline(_ level: Int) {
            out.append("\n")
            out.append(String(repeating: indent, count: max(0, level)))
        }

        func nextMeaningful(after position: Int) -> Character? {
            var probe = position + 1
            while probe < characters.count, characters[probe].isJSONWhitespace { probe += 1 }
            return probe < characters.count ? characters[probe] : nil
        }

        while index < characters.count {
            let character = characters[index]

            if inString {
                out.append(character)
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                index += 1
                continue
            }

            switch character {
            case "\"":
                inString = true
                out.append(character)
            case "{", "[":
                out.append(character)
                let closer: Character = character == "{" ? "}" : "]"
                if nextMeaningful(after: index) == closer {
                    // Keep `{}` and `[]` compact.
                    var probe = index + 1
                    while probe < characters.count, characters[probe].isJSONWhitespace { probe += 1 }
                    out.append(closer)
                    index = probe + 1
                    continue
                }
                depth += 1
                newline(depth)
            case "}", "]":
                depth -= 1
                newline(depth)
                out.append(character)
            case ",":
                out.append(character)
                newline(depth)
            case ":":
                out.append(": ")
            default:
                if !character.isJSONWhitespace { out.append(character) }
            }
            index += 1
        }
        return out
    }

    /// Compacts JSON onto one line — the inverse toggle in the body editor.
    public static func minify(_ text: String) -> String? {
        guard isValidJSON(text) else { return nil }
        var out = ""
        var inString = false
        var escaped = false
        for character in text {
            if inString {
                out.append(character)
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
                continue
            }
            if character == "\"" { inString = true; out.append(character); continue }
            if !character.isJSONWhitespace { out.append(character) }
        }
        return out
    }

    public static func isValidJSON(_ text: String) -> Bool {
        let data = Data(text.utf8)
        guard !data.isEmpty else { return false }
        return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
    }
}

extension Character {
    var isJSONWhitespace: Bool { self == " " || self == "\n" || self == "\r" || self == "\t" }
}

// MARK: - XML / HTML formatting

public enum XMLFormatter: Sendable {

    /// Indents markup one element per line. Text-only elements stay on a single
    /// line, and declarations, comments and CDATA are passed through intact.
    public static func prettyPrint(_ text: String, indent: String = "  ") -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("<") else { return nil }

        var lines: [String] = []
        var depth = 0
        var index = trimmed.startIndex

        func append(_ content: String, at level: Int) {
            guard !content.isEmpty else { return }
            lines.append(String(repeating: indent, count: max(0, level)) + content)
        }

        while index < trimmed.endIndex {
            if trimmed[index] == "<" {
                guard let close = closingBracket(of: trimmed, from: index) else {
                    append(String(trimmed[index...]).trimmingCharacters(in: .whitespaces), at: depth)
                    break
                }
                let tag = String(trimmed[index...close])
                let kind = classify(tag)
                switch kind {
                case .closing:
                    depth -= 1
                    append(tag, at: depth)
                case .opening:
                    // An element whose entire content is text collapses onto one line.
                    let afterTag = trimmed.index(after: close)
                    if let inlineEnd = inlineTextElementEnd(trimmed, contentStart: afterTag, tag: tag) {
                        append(String(trimmed[index..<inlineEnd]), at: depth)
                        index = inlineEnd
                        continue
                    }
                    append(tag, at: depth)
                    depth += 1
                case .selfContained:
                    append(tag, at: depth)
                }
                index = trimmed.index(after: close)
            } else {
                let textEnd = trimmed[index...].firstIndex(of: "<") ?? trimmed.endIndex
                let content = String(trimmed[index..<textEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
                append(content, at: depth)
                index = textEnd
            }
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private enum TagKind {
        case opening
        case closing
        case selfContained
    }

    private static func classify(_ tag: String) -> TagKind {
        if tag.hasPrefix("</") { return .closing }
        if tag.hasPrefix("<?") || tag.hasPrefix("<!") { return .selfContained }
        if tag.hasSuffix("/>") { return .selfContained }
        if let name = elementName(tag), voidElements.contains(name.lowercased()) {
            return .selfContained
        }
        return .opening
    }

    /// Honours quoted attribute values and CDATA so a `>` inside either doesn't
    /// end the tag early.
    private static func closingBracket(of text: String, from start: String.Index) -> String.Index? {
        if text[start...].hasPrefix("<![CDATA[") {
            if let end = text.range(of: "]]>", range: start..<text.endIndex) {
                return text.index(before: end.upperBound)
            }
            return nil
        }
        if text[start...].hasPrefix("<!--") {
            if let end = text.range(of: "-->", range: start..<text.endIndex) {
                return text.index(before: end.upperBound)
            }
            return nil
        }
        var index = start
        var quote: Character?
        while index < text.endIndex {
            let character = text[index]
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == ">" {
                return index
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func elementName(_ tag: String) -> String? {
        var name = ""
        var index = tag.startIndex
        index = tag.index(after: index)  // skip "<"
        if index < tag.endIndex, tag[index] == "/" { index = tag.index(after: index) }
        while index < tag.endIndex {
            let character = tag[index]
            if character.isWhitespace || character == ">" || character == "/" { break }
            name.append(character)
            index = tag.index(after: index)
        }
        return name.isEmpty ? nil : name
    }

    /// End index of `<tag>text</tag>` when the content holds no child element.
    private static func inlineTextElementEnd(
        _ text: String, contentStart: String.Index, tag: String
    ) -> String.Index? {
        guard let name = elementName(tag) else { return nil }
        guard let nextBracket = text[contentStart...].firstIndex(of: "<") else { return nil }
        let closing = "</\(name)"
        guard text[nextBracket...].lowercased().hasPrefix(closing.lowercased()) else { return nil }
        guard let close = closingBracket(of: text, from: nextBracket) else { return nil }
        let content = text[contentStart..<nextBracket]
        guard !content.contains("\n") else { return nil }
        return text.index(after: close)
    }

    /// HTML elements that never have a closing tag.
    static let voidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input",
        "link", "meta", "param", "source", "track", "wbr",
    ]
}
