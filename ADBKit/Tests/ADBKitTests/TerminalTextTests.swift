import Foundation
import Testing
@testable import ADBKit

@Suite struct TerminalTextTests {
    // MARK: - Collapsed-rail badges

    @Test func badgeIsTheFirstTwoCharacters() {
        #expect(TerminalText.railBadge(for: "Terminal 1") == "Te")
        #expect(TerminalText.railBadge(for: "build watcher") == "bu")
    }

    @Test func badgeTrimsWhitespaceBeforeTaking() {
        #expect(TerminalText.railBadge(for: "  logs") == "lo")
    }

    @Test func badgeHandlesShortAndBlankNames() {
        #expect(TerminalText.railBadge(for: "x") == "x")
        #expect(TerminalText.railBadge(for: "   ") == "?")
        #expect(TerminalText.railBadge(for: "") == "?")
    }

    @Test func badgeCountsEmojiAsOneCharacter() {
        #expect(TerminalText.railBadge(for: "🚀 deploy") == "🚀 ")
    }

    // MARK: - Dropped-file insertion

    @Test func plainPathsInsertBareWithTrailingSpace() {
        #expect(TerminalText.droppedPathsInsertion(["/tmp/app.apk"]) == "/tmp/app.apk ")
    }

    @Test func pathsWithSpacesAreSingleQuoted() {
        #expect(TerminalText.droppedPathsInsertion(["/tmp/My App.apk"]) == "'/tmp/My App.apk' ")
    }

    @Test func metacharactersForceQuoting() {
        #expect(TerminalText.droppedPathsInsertion(["/tmp/a;rm -rf.txt"]) == "'/tmp/a;rm -rf.txt' ")
        #expect(TerminalText.droppedPathsInsertion(["/tmp/$(x).txt"]) == "'/tmp/$(x).txt' ")
    }

    @Test func singleQuotesInsideAPathSurviveQuoting() {
        #expect(TerminalText.droppedPathsInsertion(["/tmp/it's here"]) == #"'/tmp/it'\''s here' "#)
    }

    @Test func multiplePathsJoinWithSingleSpaces() {
        #expect(TerminalText.droppedPathsInsertion(["/a/b.txt", "/c d/e.txt"])
            == "/a/b.txt '/c d/e.txt' ")
    }

    @Test func noPathsInsertNothing() {
        #expect(TerminalText.droppedPathsInsertion([]) == "")
    }
}
