@testable import ADBKit
import Testing

/// `ConsoleANSI` — terminal escape sequences in console text.
struct ConsoleANSITests {
    /// The real React Native dev-server notice, verbatim off the wire.
    @Test func stripsTheReactNativeDevServerNotice() {
        let raw = "\u{1B}[48;2;253;247;231m\u{1B}[30m\u{1B}[1mNOTE:\u{1B}[22m You are using an "
            + "unsupported debugging client.\u{1B}[39m\u{1B}[49m"
        #expect(ConsoleANSI.strip(raw) == "NOTE: You are using an unsupported debugging client.")
    }

    @Test func leavesPlainTextUntouched() {
        #expect(ConsoleANSI.strip("plain text") == "plain text")
        #expect(ConsoleANSI.strip("") == "")
        #expect(ConsoleANSI.strip("brackets [1m] survive") == "brackets [1m] survive")
        #expect(!ConsoleANSI.containsEscapes("plain"))
        #expect(ConsoleANSI.containsEscapes("\u{1B}[1mbold"))
    }

    @Test func stripsEveryEscapeForm() {
        // CSI with intermediates, cursor moves, erase.
        #expect(ConsoleANSI.strip("a\u{1B}[2Jb\u{1B}[1;31mc\u{1B}[Kd") == "abcd")
        // OSC terminated by BEL and by ST.
        #expect(ConsoleANSI.strip("a\u{1B}]0;title\u{07}b") == "ab")
        #expect(ConsoleANSI.strip("a\u{1B}]8;;https://x\u{1B}\\b") == "ab")
        // Two-byte C1.
        #expect(ConsoleANSI.strip("a\u{1B}Mb") == "ab")
    }

    /// A truncated sequence must not swallow the rest of the message — the text
    /// after it is the part worth reading.
    @Test func unterminatedSequencesKeepTheirText() {
        #expect(ConsoleANSI.strip("head\u{1B}[48;2") == "head\u{1B}[48;2")
        #expect(ConsoleANSI.strip("head\u{1B}]0;no-terminator") == "head\u{1B}]0;no-terminator")
        #expect(ConsoleANSI.strip("trailing\u{1B}") == "trailing\u{1B}")
    }

    @Test func multiByteTextSurvives() {
        #expect(ConsoleANSI.strip("\u{1B}[32m✅ déjà vu — 日本語\u{1B}[0m") == "✅ déjà vu — 日本語")
    }

    /// Console rows, search text, and copies all read the stripped form, so a
    /// pasted log carries the message rather than the escapes.
    @Test func consoleValuesRenderStripped() {
        let object = RemoteObject(json: .object([
            "type": .string("string"),
            "value": .string("\u{1B}[1mNOTE:\u{1B}[22m hello"),
        ]))
        #expect(object.inlineSummary(style: .consoleArgument) == "NOTE: hello")
        #expect(object.inlineSummary == "'NOTE: hello'")
        #expect(object.inlineSummary(limit: 200, style: .consoleArgument) == "NOTE: hello")
    }
}
