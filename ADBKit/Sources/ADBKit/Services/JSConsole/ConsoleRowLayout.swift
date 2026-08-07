import Foundation

/// One measured piece of a console row — a run of scalars, an object's inline
/// disclosure, whatever the row is built from.
public struct ConsoleRowSegment: Sendable, Equatable {
    public let width: Double
    public let height: Double
    /// Distance from the segment's own top down to its first text baseline.
    public let baseline: Double

    public init(width: Double, height: Double, baseline: Double) {
        self.width = width
        self.height = height
        self.baseline = baseline
    }
}

/// Where a segment sits, relative to the row's top-left.
public struct ConsoleRowSlot: Sendable, Equatable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct ConsoleRowArrangement: Sendable, Equatable {
    public let slots: [ConsoleRowSlot]
    public let width: Double
    public let height: Double

    public init(slots: [ConsoleRowSlot], width: Double, height: Double) {
        self.slots = slots
        self.width = width
        self.height = height
    }
}

/// The geometry behind the JS console's wrapping row — Chrome puts a log's
/// whole argument list on one line and wraps only when it runs out of width.
///
/// Pure, because the arithmetic is where it went wrong: the height of a line
/// can only be known once every segment on it has been measured. Growing it as
/// segments arrive under-measures a tall one that a later, lower-baselined
/// segment pushes down — the row then draws past the height it reported, and a
/// feed of rows that each under-report leaves blank gaps that shift every time
/// the pane changes width.
public enum ConsoleRowLayout {
    public static func arrange(
        _ segments: [ConsoleRowSegment],
        maxWidth: Double,
        spacing: Double = 5,
        lineSpacing: Double = 3
    ) -> ConsoleRowArrangement {
        guard !segments.isEmpty else { return ConsoleRowArrangement(slots: [], width: 0, height: 0) }

        // Break into lines first, so a line's baseline is settled before
        // anything is positioned against it.
        var lines: [[Int]] = []
        var line: [Int] = []
        var cursor = 0.0
        for (index, segment) in segments.enumerated() {
            if !line.isEmpty, cursor + segment.width > maxWidth + 0.5 {
                lines.append(line)
                line = []
                cursor = 0
            }
            line.append(index)
            cursor += segment.width + spacing
        }
        if !line.isEmpty { lines.append(line) }

        var slots = [ConsoleRowSlot](repeating: ConsoleRowSlot(x: 0, y: 0), count: segments.count)
        var y = 0.0
        var widest = 0.0
        for line in lines {
            let baseline = line.map { segments[$0].baseline }.max() ?? 0
            var x = 0.0
            var height = 0.0
            for index in line {
                let segment = segments[index]
                slots[index] = ConsoleRowSlot(x: x, y: y + baseline - segment.baseline)
                x += segment.width + spacing
                height = max(height, baseline - segment.baseline + segment.height)
            }
            widest = max(widest, x - spacing)
            y += height + lineSpacing
        }
        // Never wider than it was offered: a row that advertises more than the
        // pane can give it makes the pane lay the row out off its own edge.
        return ConsoleRowArrangement(
            slots: slots, width: min(widest, maxWidth), height: max(0, y - lineSpacing)
        )
    }
}
