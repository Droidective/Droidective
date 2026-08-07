import Foundation

/// Terminal escape sequences in console text.
///
/// React Native's own dev-server notices arrive coloured for a terminal
/// (`\u{1B}[1mNOTE:\u{1B}[22m You are using an unsupported debugging client…`),
/// and so does anything logged through a library that formats for stdout.
/// Chrome's console renders those sequences as styling; printing them verbatim
/// buries the message in `[48;2;253;247;231m[30m[1m` noise, so they come out
/// here instead.
public enum ConsoleANSI {
    private static let escape: UInt8 = 0x1B
    private static let bell: UInt8 = 0x07

    /// Whether the text carries an escape at all — the cheap guard before
    /// rebuilding a string that almost never needs it.
    public static func containsEscapes(_ text: String) -> Bool {
        text.utf8.contains(escape)
    }

    /// The text without its escape sequences: CSI (`ESC [ … final`), OSC
    /// (`ESC ] … BEL` or `ESC ] … ESC \`), and the two-byte C1 forms. Anything
    /// that isn't a recognised sequence is left alone, so a lone `ESC` in real
    /// data survives rather than eating the rest of the line.
    public static func strip(_ text: String) -> String {
        guard containsEscapes(text) else { return text }
        var out: [UInt8] = []
        out.reserveCapacity(text.utf8.count)
        let bytes = Array(text.utf8)
        var index = 0
        while index < bytes.count {
            guard bytes[index] == escape, index + 1 < bytes.count else {
                out.append(bytes[index])
                index += 1
                continue
            }
            switch bytes[index + 1] {
            case UInt8(ascii: "["):
                // CSI: parameter and intermediate bytes, then one final byte.
                var cursor = index + 2
                while cursor < bytes.count, (0x30 ... 0x3F).contains(bytes[cursor]) { cursor += 1 }
                while cursor < bytes.count, (0x20 ... 0x2F).contains(bytes[cursor]) { cursor += 1 }
                if cursor < bytes.count, (0x40 ... 0x7E).contains(bytes[cursor]) {
                    index = cursor + 1
                } else {
                    // Unterminated — keep it rather than swallowing the tail.
                    out.append(bytes[index])
                    index += 1
                }
            case UInt8(ascii: "]"):
                // OSC: runs to BEL or the ST pair.
                var cursor = index + 2
                var terminated = false
                while cursor < bytes.count {
                    if bytes[cursor] == bell {
                        cursor += 1
                        terminated = true
                        break
                    }
                    if bytes[cursor] == escape, cursor + 1 < bytes.count,
                       bytes[cursor + 1] == UInt8(ascii: "\\") {
                        cursor += 2
                        terminated = true
                        break
                    }
                    cursor += 1
                }
                if terminated {
                    index = cursor
                } else {
                    out.append(bytes[index])
                    index += 1
                }
            case 0x40 ... 0x5F:
                index += 2
            default:
                out.append(bytes[index])
                index += 1
            }
        }
        return String(decoding: out, as: UTF8.self)
    }
}
