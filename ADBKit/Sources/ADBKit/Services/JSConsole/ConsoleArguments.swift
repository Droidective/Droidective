import Foundation

/// One chunk of a `console.*` call's argument list.
///
/// Chrome reads a log as a message with values in it: consecutive scalars run
/// together as text, and each object is a thing of its own — inline it gets a
/// disclosure triangle, and copied it gets its own JSON block instead of the
/// `{…}` placeholder that a paste can't use.
public enum ConsoleArgumentChunk: Sendable, Equatable {
    case scalars([JSToken])
    case object(RemoteObject)
}

public enum ConsoleArguments {
    /// Split a call's arguments into chunks, in argument order. Scalars carry
    /// their rendered tokens (with the separating spaces already in place), so
    /// the row and the clipboard can't drift apart.
    public static func chunks(_ args: [RemoteObject]) -> [ConsoleArgumentChunk] {
        var chunks: [ConsoleArgumentChunk] = []
        var run: [JSToken] = []
        func flushRun() {
            guard !run.isEmpty else { return }
            chunks.append(.scalars(run))
            run = []
        }
        for arg in args {
            if arg.isExpandable {
                flushRun()
                chunks.append(.object(arg))
            } else {
                if !run.isEmpty { run.append(JSToken(" ", .plain)) }
                run.append(contentsOf: arg.tokens(style: .consoleArgument))
            }
        }
        flushRun()
        return chunks
    }

    /// The clipboard form of a call whose objects have already been stringified:
    /// the message first, then each object's JSON on its own line. Copying a log
    /// has to carry the data it was logged with — a pasted `{…}` is the one part
    /// of the row nobody can act on.
    public static func copyText(_ chunks: [ConsoleArgumentChunk], json: [Int: String]) -> String {
        var parts: [String] = []
        for (index, chunk) in chunks.enumerated() {
            switch chunk {
            case let .scalars(tokens):
                parts.append(tokens.map(\.text).joined())
            case let .object(object):
                parts.append(json[index] ?? object.inlineSummary(style: .consoleArgument))
            }
        }
        return parts.joined(separator: "\n")
    }
}
