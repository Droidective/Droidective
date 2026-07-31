import Foundation

/// Outcome of importing a cURL command: the request, plus anything that
/// couldn't be represented so the UI can say so instead of losing it quietly.
public struct CurlImport: Sendable, Equatable {
    public var request: SavedRequest
    public var warnings: [String]

    public init(request: SavedRequest, warnings: [String] = []) {
        self.request = request
        self.warnings = warnings
    }
}

public enum CurlParser: Sendable {

    // MARK: - Flag tables

    /// Flags consumed for their meaning. Anything here takes the next token as
    /// its value, so the value can never be mistaken for the URL.
    static let handledValuedFlags: Set<String> = [
        "-X", "--request",
        "-H", "--header",
        "-d", "--data", "--data-raw", "--data-ascii", "--data-binary", "--data-urlencode",
        "--json",
        "-F", "--form", "--form-string",
        "-u", "--user",
        "-b", "--cookie",
        "-e", "--referer", "--referrer",
        "-A", "--user-agent",
        "--url", "--url-query",
        "-m", "--max-time",
        "--max-redirs",
        "-T", "--upload-file",
        "--oauth2-bearer",
    ]

    /// Flags that take a value we deliberately drop. Listing them is the whole
    /// point: an unlisted value-taking flag would leave its value looking like a
    /// positional URL.
    static let ignoredValuedFlags: Set<String> = [
        "-o", "--output", "-w", "--write-out", "--connect-timeout",
        "--retry", "--retry-delay", "--retry-max-time",
        "--limit-rate", "--interface", "--resolve", "--dns-servers",
        "-E", "--cert", "--cert-type", "--key", "--key-type", "--pass",
        "--cacert", "--capath", "--pinnedpubkey", "--ciphers", "--curves",
        "-x", "--proxy", "--preproxy", "--proxy-user", "-U", "--proxy-header",
        "--proxy-cacert", "--proxy-cert", "--proxy-key", "--proxy-service-name",
        "--socks4", "--socks4a", "--socks5", "--socks5-hostname", "--socks5-gssapi-service",
        "-c", "--cookie-jar", "--local-port", "--max-filesize", "--noproxy",
        "-r", "--range", "-z", "--time-cond", "--stderr", "--trace", "--trace-ascii",
        "--unix-socket", "--abstract-unix-socket", "--libcurl", "--login-options",
        "--mail-from", "--mail-rcpt", "--netrc-file", "--engine", "--krb",
        "--tlsuser", "--tlspassword", "--tlsauthtype", "--service-name",
        "--happy-eyeballs-timeout-ms", "--expect100-timeout", "--keepalive-time",
        "--output-dir", "--aws-sigv4", "--hostpubmd5",
        "--continue-at", "-C", "--create-file-mode", "--delegation", "--egd-file",
        "--ftp-account", "--ftp-alternative-to-user", "--ftp-port", "-P",
        "--quote", "-Q", "--random-file", "--sasl-authzid", "--tftp-blksize",
    ]

    /// Value-taking short flags, for the attached form (`-XPOST`) and bundles.
    static let valuedShortFlags: Set<Character> = [
        "X", "H", "d", "F", "u", "b", "e", "A", "m", "o", "w", "T", "E", "r", "z",
        "U", "c", "x", "C", "P", "Q", "K", "Y", "y",
    ]

    // MARK: - Parse

    public static func parse(_ curl: String) -> SavedRequest? {
        parseWithWarnings(curl)?.request
    }

    /// Parses a cURL command line. Returns nil when the text isn't a curl
    /// invocation or carries no URL.
    public static func parseWithWarnings(_ curl: String) -> CurlImport? {
        var tokens = tokenize(curl)
        // Tolerate a copied shell prompt.
        while let first = tokens.first, first == "$" || first == ">" || first == "#" {
            tokens.removeFirst()
        }
        guard let command = tokens.first, isCurlCommand(command) else { return nil }
        tokens.removeFirst()

        var state = ParseState()
        var index = 0
        while index < tokens.count {
            index = consume(tokens, at: index, into: &state)
        }
        return finish(state)
    }

    static func isCurlCommand(_ token: String) -> Bool {
        let name = URL(fileURLWithPath: token).lastPathComponent.lowercased()
        return name == "curl" || name == "curl.exe"
    }

    // MARK: - Accumulated state

    struct ParseState {
        var method: HttpMethod?
        var url = ""
        var positionals: [String] = []
        var headers: [ApiKeyValue] = []
        var dataParts: [String] = []
        var urlEncodedDataParts: [(name: String, value: String)] = []
        var formFields: [ApiFormField] = []
        var queryFromFlags: [ApiKeyValue] = []
        var auth = AuthSpec()
        var settings = RequestSettings()
        var forceGet = false
        var headOnly = false
        var uploadFilePath = ""
        var jsonShorthand = false
        var warnings: [String] = []
    }

    // MARK: - Token dispatch

    /// Handles the token at `index` and returns the next index to read.
    private static func consume(
        _ tokens: [String], at index: Int, into state: inout ParseState
    ) -> Int {
        let token = tokens[index]

        guard token.hasPrefix("-"), token != "-", token != "--" else {
            state.positionals.append(token)
            return index + 1
        }

        // `--flag=value`
        if token.hasPrefix("--"), let equals = token.firstIndex(of: "=") {
            let name = String(token[token.startIndex..<equals])
            let value = String(token[token.index(after: equals)...])
            if handledValuedFlags.contains(name) {
                apply(flag: name, value: value, into: &state)
                return index + 1
            }
            if ignoredValuedFlags.contains(name) { return index + 1 }
            applyBoolean(flag: name, into: &state)
            return index + 1
        }

        // Attached short-flag value (`-XPOST`) or a bundle (`-sSL`).
        if !token.hasPrefix("--"), token.count > 2 {
            let characters = Array(token.dropFirst())
            if let first = characters.first, valuedShortFlags.contains(first) {
                let name = "-\(first)"
                let value = String(characters.dropFirst())
                if handledValuedFlags.contains(name) {
                    apply(flag: name, value: value, into: &state)
                }
                return index + 1
            }
            for character in characters {
                applyBoolean(flag: "-\(character)", into: &state)
            }
            return index + 1
        }

        if handledValuedFlags.contains(token) {
            guard index + 1 < tokens.count else {
                state.warnings.append("\(token) had no value and was ignored.")
                return index + 1
            }
            apply(flag: token, value: tokens[index + 1], into: &state)
            return index + 2
        }

        if ignoredValuedFlags.contains(token) {
            return index + 2 <= tokens.count ? index + 2 : index + 1
        }

        applyBoolean(flag: token, into: &state)
        return index + 1
    }

    private static func applyBoolean(flag: String, into state: inout ParseState) {
        switch flag {
        case "-G", "--get":
            state.forceGet = true
        case "-I", "--head":
            state.headOnly = true
        case "-k", "--insecure":
            state.settings.validateTLS = false
        case "-L", "--location", "--location-trusted":
            state.settings.followRedirects = true
        default:
            break
        }
    }

    private static func apply(flag: String, value: String, into state: inout ParseState) {
        switch flag {
        case "-X", "--request":
            if let method = HttpMethod(rawValue: value.uppercased()) {
                state.method = method
            } else {
                state.warnings.append("\(value.uppercased()) isn't a method Droidective can send.")
            }

        case "-H", "--header":
            addHeader(value, into: &state)

        case "-d", "--data", "--data-raw", "--data-ascii":
            if value.hasPrefix("@") {
                state.warnings.append("\(flag) \(value) reads a file; the text was kept as written.")
            }
            state.dataParts.append(value)

        case "--data-binary":
            if value.hasPrefix("@") {
                let path = String(value.dropFirst())
                state.uploadFilePath = path
                state.warnings.append("--data-binary @\(path) became a binary body from that file.")
            } else {
                state.dataParts.append(value)
            }

        case "--data-urlencode":
            appendURLEncodedData(value, into: &state)

        case "--json":
            state.dataParts.append(value)
            state.jsonShorthand = true

        case "-F", "--form", "--form-string":
            appendFormField(value, literal: flag == "--form-string", into: &state)

        case "-u", "--user":
            let credential = splitCredential(value)
            state.auth = AuthSpec(
                type: .basic,
                basicUsername: credential.user,
                basicPassword: credential.password
            )

        case "--oauth2-bearer":
            state.auth = AuthSpec(type: .bearer, bearerToken: value)

        case "-b", "--cookie":
            if value.contains("=") {
                setHeader("Cookie", value, into: &state)
            } else {
                state.warnings.append("Cookie file \(value) can't be read; no Cookie header was set.")
            }

        case "-e", "--referer", "--referrer":
            setHeader("Referer", value.replacingOccurrences(of: ";auto", with: ""), into: &state)

        case "-A", "--user-agent":
            setHeader("User-Agent", value, into: &state)

        case "--url":
            state.url = value

        case "--url-query":
            appendURLQuery(value, into: &state)

        case "-m", "--max-time":
            if let seconds = Double(value) { state.settings.timeoutSeconds = seconds }

        case "--max-redirs":
            if let count = Int(value) { state.settings.maxRedirects = count }

        case "-T", "--upload-file":
            state.uploadFilePath = value
            if state.method == nil { state.method = .put }

        default:
            break
        }
    }

    // MARK: - Flag helpers

    private static func addHeader(_ raw: String, into state: inout ParseState) {
        // `-H "X-Foo;"` sends an empty header; `-H "X-Foo:"` removes one.
        if raw.hasSuffix(";"), !raw.contains(":") {
            let name = String(raw.dropLast()).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { state.headers.append(ApiKeyValue(key: name, value: "")) }
            return
        }
        guard let colon = raw.firstIndex(of: ":") else { return }
        let name = String(raw[raw.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
        let value = String(raw[raw.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if value.isEmpty {
            state.headers.removeAll { $0.key.lowercased() == name.lowercased() }
            return
        }
        state.headers.append(ApiKeyValue(key: name, value: value))
    }

    private static func setHeader(_ name: String, _ value: String, into state: inout ParseState) {
        state.headers.removeAll { $0.key.lowercased() == name.lowercased() }
        state.headers.append(ApiKeyValue(key: name, value: value))
    }

    /// `name=value` urlencodes the value; `=value` urlencodes the whole thing;
    /// the `@file` forms read from disk, which an import can't do.
    private static func appendURLEncodedData(_ raw: String, into state: inout ParseState) {
        if raw.contains("@") && !raw.contains("=") {
            state.warnings.append("--data-urlencode \(raw) reads a file and was skipped.")
            return
        }
        guard let equals = raw.firstIndex(of: "=") else {
            state.urlEncodedDataParts.append((name: "", value: raw))
            return
        }
        let name = String(raw[raw.startIndex..<equals])
        let value = String(raw[raw.index(after: equals)...])
        if value.hasPrefix("@") {
            state.warnings.append("--data-urlencode \(raw) reads a file and was skipped.")
            return
        }
        state.urlEncodedDataParts.append((name: name, value: value))
    }

    private static func appendURLQuery(_ raw: String, into state: inout ParseState) {
        guard let equals = raw.firstIndex(of: "=") else {
            state.queryFromFlags.append(ApiKeyValue(key: raw, value: ""))
            return
        }
        state.queryFromFlags.append(
            ApiKeyValue(
                key: String(raw[raw.startIndex..<equals]),
                value: String(raw[raw.index(after: equals)...])
            )
        )
    }

    /// `-F name=value`, `-F name=@path`, `-F name=@path;type=image/png`,
    /// `-F name=<path` (contents inline).
    private static func appendFormField(
        _ raw: String, literal: Bool, into state: inout ParseState
    ) {
        guard let equals = raw.firstIndex(of: "=") else {
            state.warnings.append("Form field \"\(raw)\" has no `=` and was skipped.")
            return
        }
        let name = String(raw[raw.startIndex..<equals])
        var value = String(raw[raw.index(after: equals)...])
        var contentType = ""

        if !literal, let marker = value.range(of: ";type=") {
            contentType = String(value[marker.upperBound...])
            value = String(value[value.startIndex..<marker.lowerBound])
        }

        if !literal, value.hasPrefix("@") || value.hasPrefix("<") {
            let path = String(value.dropFirst())
            state.formFields.append(
                ApiFormField(key: name, value: path, kind: .file, contentType: contentType)
            )
            return
        }
        state.formFields.append(
            ApiFormField(key: name, value: value, kind: .text, contentType: contentType)
        )
    }

    static func splitCredential(_ value: String) -> (user: String, password: String) {
        guard let colon = value.firstIndex(of: ":") else { return (value, "") }
        return (
            String(value[value.startIndex..<colon]),
            String(value[value.index(after: colon)...])
        )
    }

    // MARK: - Assembly

    private static func finish(_ state: ParseState) -> CurlImport? {
        var state = state
        if state.url.isEmpty {
            guard let picked = pickURL(from: state.positionals) else { return nil }
            state.url = picked
        }
        for leftover in state.positionals where leftover != state.url {
            state.warnings.append("Ignored unrecognised argument \"\(leftover)\".")
        }

        var queryParams = state.queryFromFlags
        var url = state.url
        // Split an inline query string into the params table so it's editable.
        if let mark = url.firstIndex(of: "?") {
            let queryString = String(url[url.index(after: mark)...])
            let parsed = parseQueryString(queryString)
            if !parsed.pairs.isEmpty {
                queryParams = parsed.pairs + queryParams
                url = String(url[url.startIndex..<mark])
                if !parsed.fragment.isEmpty { url += "#" + parsed.fragment }
            }
        }

        let method = resolveMethod(state)
        let body = buildBody(state, method: method, queryParams: &queryParams)

        if state.jsonShorthand {
            if !state.headers.contains(where: { $0.key.lowercased() == "content-type" }) {
                state.headers.append(ApiKeyValue(key: "Content-Type", value: "application/json"))
            }
            if !state.headers.contains(where: { $0.key.lowercased() == "accept" }) {
                state.headers.append(ApiKeyValue(key: "Accept", value: "application/json"))
            }
        }

        let request = SavedRequest(
            name: nameFromURL(url),
            method: method,
            url: url,
            headers: state.headers,
            queryParams: queryParams,
            body: body,
            auth: state.auth,
            settings: state.settings
        )
        return CurlImport(request: request, warnings: state.warnings)
    }

    private static func resolveMethod(_ state: ParseState) -> HttpMethod {
        if let explicit = state.method { return explicit }
        if state.headOnly { return .head }
        if state.forceGet { return .get }
        if !state.uploadFilePath.isEmpty { return .put }
        let hasBody = !state.dataParts.isEmpty
            || !state.urlEncodedDataParts.isEmpty
            || !state.formFields.isEmpty
        return hasBody ? .post : .get
    }

    private static func buildBody(
        _ state: ParseState, method: HttpMethod, queryParams: inout [ApiKeyValue]
    ) -> RequestBodySpec {
        if !state.uploadFilePath.isEmpty {
            return RequestBodySpec(type: .binary, binaryFilePath: state.uploadFilePath)
        }
        if !state.formFields.isEmpty {
            return RequestBodySpec(type: .multipart, multipartFields: state.formFields)
        }

        let encodedParts = state.urlEncodedDataParts.map { part -> String in
            let escaped = part.value
                .addingPercentEncoding(withAllowedCharacters: HttpRequestBuilder.unreserved)
                ?? part.value
            return part.name.isEmpty ? escaped : "\(part.name)=\(escaped)"
        }
        let raw = (state.dataParts + encodedParts).joined(separator: "&")
        guard !raw.isEmpty else { return RequestBodySpec() }

        // `-G` sends the accumulated data as query parameters instead.
        if state.forceGet || method == .head {
            queryParams += parseQueryString(raw).pairs
            return RequestBodySpec()
        }

        let declared = state.headers
            .firstValue(forKeyIgnoringCase: "content-type")?
            .lowercased() ?? ""

        if declared.contains("json") || (declared.isEmpty && JSONFormatter.isValidJSON(raw)) {
            return RequestBodySpec(type: .json, jsonText: raw)
        }
        if declared.contains("x-www-form-urlencoded")
            || (declared.isEmpty && looksLikeFormPairs(raw)) {
            let pairs = parseQueryString(raw).pairs
            if !pairs.isEmpty { return RequestBodySpec(type: .formUrlEncoded, formFields: pairs) }
        }
        if declared.contains("xml") {
            return RequestBodySpec(type: .raw, rawText: raw, rawLanguage: .xml)
        }
        if declared.contains("html") {
            return RequestBodySpec(type: .raw, rawText: raw, rawLanguage: .html)
        }
        return RequestBodySpec(type: .raw, rawText: raw, rawLanguage: .text)
    }

    /// `a=1&b=2` — every segment carries a key. A bare `hello` or a JSON blob
    /// doesn't qualify, so it stays a raw body.
    static func looksLikeFormPairs(_ raw: String) -> Bool {
        guard raw.contains("="), !raw.contains("\n") else { return false }
        let segments = raw.components(separatedBy: "&")
        return segments.allSatisfy { segment in
            guard let equals = segment.firstIndex(of: "=") else { return false }
            return equals != segment.startIndex
        }
    }

    /// Percent-decodes a query string into pairs, keeping empty values and
    /// splitting off a trailing fragment.
    static func parseQueryString(_ query: String) -> (pairs: [ApiKeyValue], fragment: String) {
        var working = query
        var fragment = ""
        if let hash = working.firstIndex(of: "#") {
            fragment = String(working[working.index(after: hash)...])
            working = String(working[working.startIndex..<hash])
        }
        guard !working.isEmpty else { return ([], fragment) }

        var pairs: [ApiKeyValue] = []
        for segment in working.components(separatedBy: "&") where !segment.isEmpty {
            if let equals = segment.firstIndex(of: "=") {
                let key = String(segment[segment.startIndex..<equals])
                let value = String(segment[segment.index(after: equals)...])
                pairs.append(ApiKeyValue(key: percentDecode(key), value: percentDecode(value)))
            } else {
                pairs.append(ApiKeyValue(key: percentDecode(segment), value: ""))
            }
        }
        return (pairs, fragment)
    }

    /// `+` means space in a query string; `removingPercentEncoding` alone
    /// doesn't know that.
    static func percentDecode(_ value: String) -> String {
        let spaced = value.replacingOccurrences(of: "+", with: " ")
        return spaced.removingPercentEncoding ?? spaced
    }

    /// Chooses the URL among the positional arguments. Anything that doesn't
    /// look like a URL is left for the caller to report, which is what stops a
    /// stray flag value from becoming the request target.
    static func pickURL(from positionals: [String]) -> String? {
        if let match = positionals.first(where: looksLikeURL) { return match }
        return positionals.first
    }

    static func looksLikeURL(_ candidate: String) -> Bool {
        guard !candidate.isEmpty, !candidate.contains(" ") else { return false }
        if candidate.contains("://") { return true }
        if candidate.hasPrefix("[") { return true }

        let host = candidate
            .components(separatedBy: "/").first?
            .components(separatedBy: "?").first?
            .components(separatedBy: "@").last ?? ""
        guard !host.isEmpty, !host.contains("=") else { return false }

        let bare = host.components(separatedBy: ":").first ?? host
        if bare.lowercased() == "localhost" { return true }
        let labels = bare.components(separatedBy: ".")
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }) else { return false }
        if labels.allSatisfy({ Int($0) != nil }) { return labels.count == 4 }
        guard let last = labels.last else { return false }
        return last.count >= 2 && last.allSatisfy { $0.isLetter }
    }

    public static func nameFromURL(_ url: String) -> String {
        let withoutQuery = url.components(separatedBy: "?").first ?? url
        guard let components = URLComponents(string: withoutQuery) else {
            return withoutQuery.isEmpty ? "Request" : withoutQuery
        }
        let segment = components.path.split(separator: "/").last.map(String.init) ?? ""
        if segment.isEmpty { return components.host ?? "Request" }
        return segment
    }

    // MARK: - Tokenizer

    /// Splits a command line the way a POSIX shell would, plus the two forms
    /// browsers emit: `$'…'` ANSI-C quoting and Windows `^` continuations.
    public static func tokenize(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var produced = false
        var inSingle = false
        var inDouble = false
        let characters = Array(input)
        var index = 0

        func flush() {
            if produced || !current.isEmpty { tokens.append(current) }
            current = ""
            produced = false
        }

        while index < characters.count {
            let character = characters[index]

            if inSingle {
                if character == "'" {
                    inSingle = false
                } else {
                    current.append(character)
                }
                index += 1
                continue
            }

            // `$'...'`: escapes are interpreted.
            if character == "$", !inDouble, index + 1 < characters.count,
               characters[index + 1] == "'" {
                let decoded = decodeAnsiCQuoted(characters, from: index + 2)
                current += decoded.text
                produced = true
                index = decoded.next
                continue
            }

            switch character {
            case "\\":
                let next = index + 1
                guard next < characters.count else { index += 1; continue }
                let escaped = characters[next]
                if escaped == "\n" {
                    index = next + 1  // line continuation
                } else if inDouble, !"\"\\$`\n".contains(escaped) {
                    // In double quotes a backslash is literal before anything else.
                    current.append(character)
                    index += 1
                } else {
                    current.append(escaped)
                    produced = true
                    index = next + 1
                }
            case "^" where !inDouble:
                // Windows `cmd` continuation; a lone `^` elsewhere is literal.
                if index + 1 < characters.count, characters[index + 1] == "\n" {
                    index += 2
                } else {
                    current.append(character)
                    index += 1
                }
            case "'":
                inSingle = true
                produced = true
                index += 1
            case "\"":
                inDouble.toggle()
                produced = true
                index += 1
            case " ", "\t", "\n", "\r":
                if inDouble {
                    current.append(character)
                } else {
                    flush()
                }
                index += 1
            default:
                current.append(character)
                index += 1
            }
        }
        flush()
        return tokens
    }

    /// Decodes the body of a `$'…'` string, returning the text and the index
    /// just past the closing quote.
    private static func decodeAnsiCQuoted(
        _ characters: [Character], from start: Int
    ) -> (text: String, next: Int) {
        // Accumulated as bytes, not characters: `\xNN` escapes are individual
        // bytes, and a multi-byte UTF-8 codepoint arrives as a run of them
        // (Chrome writes `é` as `\xc3\xa9`).
        var bytes: [UInt8] = []
        var index = start

        func append(_ text: String) { bytes.append(contentsOf: Array(text.utf8)) }

        while index < characters.count {
            let character = characters[index]
            if character == "'" {
                return (String(decoding: bytes, as: UTF8.self), index + 1)
            }
            guard character == "\\", index + 1 < characters.count else {
                append(String(character))
                index += 1
                continue
            }
            let escaped = characters[index + 1]
            switch escaped {
            case "n": bytes.append(0x0A); index += 2
            case "t": bytes.append(0x09); index += 2
            case "r": bytes.append(0x0D); index += 2
            case "e": bytes.append(0x1B); index += 2
            case "a": bytes.append(0x07); index += 2
            case "b": bytes.append(0x08); index += 2
            case "f": bytes.append(0x0C); index += 2
            case "v": bytes.append(0x0B); index += 2
            case "\\", "'", "\"", "?":
                append(String(escaped))
                index += 2
            case "x":
                let digits = hexDigits(characters, from: index + 2, max: 2)
                if !digits.isEmpty, let value = UInt8(digits, radix: 16) {
                    bytes.append(value)
                    index += 2 + digits.count
                } else {
                    append("x")
                    index += 2
                }
            case "u", "U":
                let width = escaped == "u" ? 4 : 8
                let digits = hexDigits(characters, from: index + 2, max: width)
                if !digits.isEmpty, let value = UInt32(digits, radix: 16),
                   let scalar = Unicode.Scalar(value) {
                    append(String(Character(scalar)))
                    index += 2 + digits.count
                } else {
                    append(String(escaped))
                    index += 2
                }
            default:
                append(String(escaped))
                index += 2
            }
        }
        return (String(decoding: bytes, as: UTF8.self), index)
    }

    private static func hexDigits(_ characters: [Character], from start: Int, max: Int) -> String {
        var digits = ""
        var index = start
        while index < characters.count, digits.count < max, characters[index].isHexDigit {
            digits.append(characters[index])
            index += 1
        }
        return digits
    }
}
