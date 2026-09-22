/**
 * What a drop in the terminal tab strip means.
 *
 * A table rather than branches at the call site, so a drop onto a group's
 * header and a drop onto its first tab cannot end up doing different things —
 * which is exactly what two implementations of this would drift into. The
 * same reason `FileDropRouter` and `TabDropRouter` are one table each.
 */

import {
  groupOfTab,
  moveGroupBefore,
  moveGroupToEnd,
  moveTabBefore,
  moveTabToEnd,
  moveTabToGroup,
  type Entry,
} from "@/lib/terminal-groups"

/** What is being dragged in the tab strip. */
export type Drag = { kind: "tab"; id: string } | { kind: "group"; id: string }

/** Where it was let go. */
export type Drop =
  | { kind: "tab"; id: string }
  | { kind: "group"; id: string }
  | { kind: "end" }

/** Apply one drop to the strip's entries. */
export function applyDrop(entries: Entry[], drag: Drag, target: Drop): Entry[] {
  if (drag.kind === "group") {
    // A group cannot go *into* another group, so a drop on a grouped tab is
    // read as a drop on that group — the nearest top-level row.
    if (target.kind === "end") return moveGroupToEnd(entries, drag.id)
    const anchor =
      target.kind === "group" ? target.id : (groupOfTab(entries, target.id)?.id ?? target.id)
    return moveGroupBefore(entries, drag.id, anchor)
  }
  switch (target.kind) {
    case "tab":
      return moveTabBefore(entries, drag.id, target.id)
    case "group":
      return moveTabToGroup(entries, drag.id, target.id)
    case "end":
      return moveTabToEnd(entries, drag.id)
  }
}
