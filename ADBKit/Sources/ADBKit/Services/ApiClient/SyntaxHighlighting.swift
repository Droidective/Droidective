import Foundation

/// A coloured run of a response body. Offsets are UTF-16 so the App layer can
/// hand them straight to an `NSTextStorage` without recomputing anything, and
/// the tokenizer stays here where it can be tested without a view.
public struct SyntaxToken: Sendable, Equatable {

    public enum Kind: String, Sendable, CaseIterable {
        /// A JSON object key, before its colon.
        case key
        case string
        case number
        /// `true`, `false`, `null`.
        case literal
        case punctuation
        /// The element name inside a tag, `<` and `>` included.
        case tag
        case attribute
        /// A quoted attribute value.
        case value
        case comment
        /// `<!doctype …>`, `<?xml …?>`.
        case declaration
    }

    public let kind: Kind
    public let location: Int
    public let length: Int

    public init(kind: Kind, location: Int, length: Int) {
        self.kind = kind
        self.location = location
        self.length = length
    }
}

/// Colours a response body by structure. Both tokenizers are forgiving: a
/// truncated or malformed body still yields tokens for the part that parsed,
/// because a 16 MB cap or a dropped connection is a normal thing to be looking
/// at in an API client.
public enum SyntaxHighlighter: Sendable {

    /// Above this the highlight is skipped and the body renders plain. Walking
    /// a multi-megabyte body is cheap, but the attribute runs it produces are
    /// not, and a viewer that stalls is worse than one that isn't coloured.
    public static let maxHighlightableLength = 512 * 1024

    public static func tokens(for text: String, format: ResponseFormat) -> [SyntaxToken] {
        guard text.utf16.count <= maxHighlightableLength else { return [] }
        switch format {
        case .json: return jsonTokens(text)
        case .xml, .html: return markupTokens(text)
        case .text, .image, .binary: return []
        }
    }

    // MARK: - JSON

    /// Also handles JSON Lines, since concatenated documents tokenize the same
    /// way one does.
    public static func jsonTokens(_ text: String) -> [SyntaxToken] {
        var tokens: [SyntaxToken] = []
        var offset = 0
        var pendingString: (location: Int, length: Int)?
        let characters = Array(text)
        var index = 0

        func flushPendingString(asKey: Bool) {
            guard let pending = pendingString else { return }
            tokens.append(
                SyntaxToken(
                    kind: asKey ? .key : .string, location: pending.location, length: pending.length
                )
            )
            pendingString = nil
        }

        while index < characters.count {
            let character = characters[index]
            switch character {
            case "\"":
                flushPendingString(asKey: false)
                let start = offset
                var length = character.utf16.count
                var escaped = false
                index += 1
                offset += character.utf16.count
                while index < characters.count {
                    let inner = characters[index]
                    length += inner.utf16.count
                    offset += inner.utf16.count
                    index += 1
                    if escaped {
                        escaped = false
                    } else if inner == "\\" {
                        escaped = true
                    } else if inner == "\"" {
                        break
                    }
                }
                // Whether this string was a key is only knowable at the colon.
                pendingString = (start, length)
                continue
            case ":":
                flushPendingString(asKey: true)
                tokens.append(SyntaxToken(kind: .punctuation, location: offset, length: 1))
            case "{", "}", "[", "]", ",":
                flushPendingString(asKey: false)
                tokens.append(SyntaxToken(kind: .punctuation, location: offset, length: 1))
            case "t", "f", "n":
                flushPendingString(asKey: false)
                if let word = literalWord(characters, at: index) {
                    tokens.append(SyntaxToken(kind: .literal, location: offset, length: word))
                    index += word
                    offset += word
                    continue
                }
            default:
                if character == "-" || character.isNumber {
                    flushPendingString(asKey: false)
                    let length = numberLength(characters, at: index)
                    if length > 0 {
                        tokens.append(SyntaxToken(kind: .number, location: offset, length: length))
                        index += length
                        offset += length
                        continue
                    }
                }
            }
            offset += character.utf16.count
            index += 1
        }
        flushPendingString(asKey: false)
        return tokens
    }

    private static func literalWord(_ characters: [Character], at index: Int) -> Int? {
        for word in ["true", "false", "null"] where matches(characters, at: index, word: word) {
            return word.count
        }
        return nil
    }

    private static func matches(_ characters: [Character], at index: Int, word: String) -> Bool {
        let letters = Array(word)
        guard index + letters.count <= characters.count else { return false }
        for offset in 0..<letters.count where characters[index + offset] != letters[offset] {
            return false
        }
        return true
    }

    /// Length in characters of the JSON number starting here — all ASCII, so it
    /// is also the UTF-16 length.
    private static func numberLength(_ characters: [Character], at index: Int) -> Int {
        var cursor = index
        if characters[cursor] == "-" { cursor += 1 }
        var digits = 0
        while cursor < characters.count, characters[cursor].isNumber {
            cursor += 1
            digits += 1
        }
        guard digits > 0 else { return 0 }
        if cursor < characters.count, characters[cursor] == "." {
            cursor += 1
            while cursor < characters.count, characters[cursor].isNumber { cursor += 1 }
        }
        if cursor < characters.count, characters[cursor] == "e" || characters[cursor] == "E" {
            var probe = cursor + 1
            if probe < characters.count, characters[probe] == "+" || characters[probe] == "-" {
                probe += 1
            }
            var exponentDigits = 0
            while probe < characters.count, characters[probe].isNumber {
                probe += 1
                exponentDigits += 1
            }
            if exponentDigits > 0 { cursor = probe }
        }
        return cursor - index
    }

    // MARK: - XML / HTML

    public static func markupTokens(_ text: String) -> [SyntaxToken] {
        var tokens: [SyntaxToken] = []
        var offset = 0
        let characters = Array(text)
        var index = 0

        while index < characters.count {
            guard characters[index] == "<" else {
                offset += characters[index].utf16.count
                index += 1
                continue
            }
            if matches(characters, at: index, word: "<!--") {
                let span = spanLength(characters, from: index, until: "-->")
                tokens.append(SyntaxToken(kind: .comment, location: offset, length: span.utf16))
                index += span.characters
                offset += span.utf16
                continue
            }
            if matches(characters, at: index, word: "<![CDATA[") {
                let span = spanLength(characters, from: index, until: "]]>")
                tokens.append(SyntaxToken(kind: .string, location: offset, length: span.utf16))
                index += span.characters
                offset += span.utf16
                continue
            }
            let isDeclaration =
                matches(characters, at: index, word: "<!") || matches(characters, at: index, word: "<?")
            let span = tagSpan(characters, from: index)
            if isDeclaration {
                tokens.append(SyntaxToken(kind: .declaration, location: offset, length: span.utf16))
            } else {
                tokens.append(
                    contentsOf: tagTokens(characters, from: index, span: span, offset: offset)
                )
            }
            index += span.characters
            offset += span.utf16
        }
        return tokens
    }

    /// Splits one `<tag attr="value">` into its name, attribute names and
    /// quoted values. Everything not otherwise classified stays uncoloured so
    /// stray punctuation can't be mistaken for structure.
    private static func tagTokens(
        _ characters: [Character], from start: Int, span: (characters: Int, utf16: Int), offset: Int
    ) -> [SyntaxToken] {
        var tokens: [SyntaxToken] = []
        let end = start + span.characters
        var index = start
        var cursor = offset

        // `<`, `</` and the element name.
        var nameLength = 0
        var namePrefix = characters[index].utf16.count
        index += 1
        if index < end, characters[index] == "/" {
            namePrefix += 1
            index += 1
        }
        while index < end, !characters[index].isWhitespace, characters[index] != ">",
            characters[index] != "/" {
            nameLength += characters[index].utf16.count
            index += 1
        }
        tokens.append(SyntaxToken(kind: .tag, location: cursor, length: namePrefix + nameLength))
        cursor += namePrefix + nameLength

        while index < end {
            let character = characters[index]
            if character.isWhitespace || character == "=" || character == "/" || character == ">" {
                cursor += character.utf16.count
                index += 1
                continue
            }
            if character == "\"" || character == "'" {
                var length = character.utf16.count
                index += 1
                while index < end, characters[index] != character {
                    length += characters[index].utf16.count
                    index += 1
                }
                if index < end {
                    length += characters[index].utf16.count
                    index += 1
                }
                tokens.append(SyntaxToken(kind: .value, location: cursor, length: length))
                cursor += length
                continue
            }
            var length = 0
            while index < end, !characters[index].isWhitespace, characters[index] != "=",
                characters[index] != ">", characters[index] != "/" {
                length += characters[index].utf16.count
                index += 1
            }
            if length > 0 {
                tokens.append(SyntaxToken(kind: .attribute, location: cursor, length: length))
                cursor += length
            }
        }
        return tokens
    }

    /// The tag from `<` through its `>`, honouring quoted attribute values so a
    /// `>` inside one doesn't end it early. An unterminated tag runs to the end.
    private static func tagSpan(
        _ characters: [Character], from start: Int
    ) -> (characters: Int, utf16: Int) {
        var index = start
        var utf16 = 0
        var quote: Character?
        while index < characters.count {
            let character = characters[index]
            utf16 += character.utf16.count
            index += 1
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == ">" {
                break
            }
        }
        return (index - start, utf16)
    }

    private static func spanLength(
        _ characters: [Character], from start: Int, until terminator: String
    ) -> (characters: Int, utf16: Int) {
        var index = start
        var utf16 = 0
        while index < characters.count {
            if matches(characters, at: index, word: terminator) {
                for offset in 0..<terminator.count {
                    utf16 += characters[index + offset].utf16.count
                }
                index += terminator.count
                return (index - start, utf16)
            }
            utf16 += characters[index].utf16.count
            index += 1
        }
        return (index - start, utf16)
    }
}
