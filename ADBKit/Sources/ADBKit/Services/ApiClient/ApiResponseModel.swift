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
        case .json: return JSONFormatter.prettyPrint(text) ?? JSONFormatter.prettyPrintLines(text)
        case .xml, .html: return XMLFormatter.prettyPrint(text)
        case .text: return ApiResponse.prettyPlainText(text)
        case .image, .binary: return nil
        }
    }

    /// `text/plain` covers a lot of ground: servers mislabel JSON, stream
    /// JSON Lines, and answer form posts in kind. Recognising those is what
    /// puts the Pretty toggle in front of a body that can use it — anything
    /// genuinely unstructured returns nil and shows as-is.
    static func prettyPlainText(_ text: String) -> String? {
        if let json = JSONFormatter.prettyPrint(text) { return json }
        if let lines = JSONFormatter.prettyPrintLines(text) { return lines }
        return FormFormatter.prettyPrint(text)
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

    /// Pretty-prints JSON Lines / NDJSON — one document per line, as log and
    /// streaming endpoints emit. Returns nil unless *every* non-empty line
    /// parses, so a stray line of prose doesn't get a half-formatted body.
    public static func prettyPrintLines(_ text: String, indent: String = "  ") -> String? {
        let rows = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard rows.count > 1 else { return nil }
        var out: [String] = []
        for row in rows {
            // Objects and arrays only — a column of bare numbers is a text
            // file, and "prettifying" it would just be a toggle that does
            // nothing.
            guard row.hasPrefix("{") || row.hasPrefix("[") else { return nil }
            guard let pretty = prettyPrint(row, indent: indent) else { return nil }
            out.append(pretty)
        }
        return out.joined(separator: "\n")
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

// MARK: - Form-encoded formatting

public enum FormFormatter: Sendable {

    /// Breaks `a=1&b=hello%20world` into one decoded `name = value` per line.
    /// Returns nil for anything that isn't a single line of `&`-joined pairs,
    /// so ordinary prose never gets sliced up on a stray `=`.
    public static func prettyPrint(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isNewline) else { return nil }
        let pairs = trimmed.components(separatedBy: "&")
        guard pairs.count > 1 || trimmed.contains("=") else { return nil }

        var rows: [String] = []
        for pair in pairs {
            guard let separator = pair.firstIndex(of: "=") else { return nil }
            let name = String(pair[pair.startIndex..<separator])
            let value = String(pair[pair.index(after: separator)...])
            guard !name.isEmpty, !name.contains(" ") else { return nil }
            rows.append("\(decode(name)) = \(decode(value))")
        }
        return rows.isEmpty ? nil : rows.joined(separator: "\n")
    }

    private static func decode(_ text: String) -> String {
        let plus = text.replacingOccurrences(of: "+", with: " ")
        return plus.removingPercentEncoding ?? plus
    }
}

// MARK: - XML / HTML formatting

public enum XMLFormatter: Sendable {

    /// Indents markup one element per line. Text-only elements stay on a single
    /// line, and declarations, comments and CDATA are passed through intact.
    ///
    /// Real pages are not well-formed XML, so two rules keep the indentation
    /// honest on them. A raw-text element (`<script>`, `<style>`) has its body
    /// taken verbatim to the matching close tag — minified JS is full of `<`,
    /// and parsing it as markup both mangles the source and runs the depth
    /// away. And a close tag unwinds to the element it actually closes rather
    /// than assuming the innermost one, so the unclosed `<p>`/`<li>` that HTML
    /// permits can't leave the rest of the document drifting right.
    public static func prettyPrint(_ text: String, indent: String = "  ") -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("<") else { return nil }

        var lines: [String] = []
        var open: [String] = []
        var index = trimmed.startIndex

        func append(_ content: String, at level: Int) {
            guard !content.isEmpty else { return }
            lines.append(String(repeating: indent, count: max(0, level)) + content)
        }

        while index < trimmed.endIndex {
            if trimmed[index] == "<" {
                guard let close = closingBracket(of: trimmed, from: index) else {
                    append(String(trimmed[index...]).trimmingCharacters(in: .whitespaces), at: open.count)
                    break
                }
                let tag = String(trimmed[index...close])
                let name = elementName(tag)?.lowercased()
                switch classify(tag) {
                case .closing:
                    // Unwind to the element this tag closes. A stray close with
                    // nothing matching it stays where it is rather than pulling
                    // the whole document a level left.
                    if let name, let match = open.lastIndex(of: name) {
                        open.removeSubrange(match...)
                        append(tag, at: open.count)
                    } else {
                        append(tag, at: open.count)
                    }
                case .opening:
                    if let name, rawTextElements.contains(name) {
                        index = appendRawTextElement(
                            trimmed, tagStart: index, tagEnd: close, name: name,
                            depth: open.count, indent: indent, into: &lines
                        )
                        continue
                    }
                    // An element whose entire content is text collapses onto one line.
                    let afterTag = trimmed.index(after: close)
                    if let inlineEnd = inlineTextElementEnd(trimmed, contentStart: afterTag, tag: tag) {
                        append(String(trimmed[index..<inlineEnd]), at: open.count)
                        index = inlineEnd
                        continue
                    }
                    // HTML lets a sibling stand in for the close tag this
                    // element never got (`<li>a<li>b`, `<tr>` after an open
                    // `<td>` — which unwinds the cell and then the row).
                    if let name, let closedBy = implicitlyClosedBy[name] {
                        while let last = open.last, closedBy.contains(last) { open.removeLast() }
                    }
                    append(tag, at: open.count)
                    if let name { open.append(name) }
                case .selfContained:
                    append(tag, at: open.count)
                }
                index = trimmed.index(after: close)
            } else {
                let textEnd = trimmed[index...].firstIndex(of: "<") ?? trimmed.endIndex
                let content = String(trimmed[index..<textEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
                append(content, at: open.count)
                index = textEnd
            }
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// Emits `<script>…</script>` with its body untouched apart from indentation,
    /// and answers where parsing resumes. An unterminated element takes the rest
    /// of the document, which is what a truncated response looks like.
    private static func appendRawTextElement(
        _ text: String, tagStart: String.Index, tagEnd: String.Index, name: String,
        depth: Int, indent: String, into lines: inout [String]
    ) -> String.Index {
        let pad = String(repeating: indent, count: max(0, depth))
        let contentStart = text.index(after: tagEnd)
        let terminator = text.range(
            of: "</\(name)", options: [.caseInsensitive], range: contentStart..<text.endIndex
        )
        let contentEnd = terminator?.lowerBound ?? text.endIndex
        let body = String(text[contentStart..<contentEnd])

        // A one-line body reads better beside its tags, exactly as
        // `inlineTextElementEnd` treats an ordinary text-only element.
        guard body.contains(where: \.isNewline) else {
            let closeTag = terminator.flatMap { closingBracket(of: text, from: $0.lowerBound) }
            let end = closeTag.map(text.index(after:)) ?? text.endIndex
            lines.append(pad + String(text[tagStart..<end]))
            return end
        }

        lines.append(pad + String(text[tagStart...tagEnd]))
        lines.append(contentsOf: dedented(body, to: pad + indent))
        guard let terminator, let closeTag = closingBracket(of: text, from: terminator.lowerBound)
        else { return text.endIndex }
        lines.append(pad + String(text[terminator.lowerBound...closeTag]))
        return text.index(after: closeTag)
    }

    /// Re-indents a raw-text body under `pad`, preserving the relative shape the
    /// author wrote by stripping the block's own common indentation first.
    private static func dedented(_ body: String, to pad: String) -> [String] {
        let rows = body.components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "\t", with: "    ") }
        let common =
            rows
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.prefix(while: { $0 == " " }).count }
            .min() ?? 0
        var out: [String] = []
        for row in rows {
            let stripped = String(row.dropFirst(min(common, row.prefix(while: { $0 == " " }).count)))
            let trailingTrimmed = String(
                stripped.reversed().drop(while: { $0 == " " }).reversed()
            )
            if trailingTrimmed.isEmpty {
                // Keep blank lines the author wrote, but never trailing padding.
                if !out.isEmpty { out.append("") }
            } else {
                out.append(pad + trailingTrimmed)
            }
        }
        while out.last?.isEmpty == true { out.removeLast() }
        return out
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

    /// Elements whose content is character data rather than markup. Anything
    /// between the tags belongs to the script/stylesheet, `<` included.
    static let rawTextElements: Set<String> = ["script", "style", "textarea"]

    /// The open elements an HTML start tag is allowed to close on its own. Only
    /// the cases that actually appear without close tags in the wild — enough
    /// to keep a list or a table from stair-stepping off the right edge.
    static let implicitlyClosedBy: [String: Set<String>] = [
        "li": ["li"],
        "dt": ["dt", "dd"],
        "dd": ["dt", "dd"],
        "p": ["p"],
        "tr": ["td", "th", "tr"],
        "td": ["td", "th"],
        "th": ["td", "th"],
        "option": ["option"],
        "thead": ["td", "th", "tr"],
        "tbody": ["td", "th", "tr"],
    ]
}
