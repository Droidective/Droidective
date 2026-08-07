/**
 * How the Developer Options panel is laid out.
 *
 * What each toggle *is* comes from the daemon — `DeveloperSettingsService`
 * holds that table and the definitions travel with the values. What does not
 * travel is which section a row belongs to and in what order, because on the
 * Mac that lives in `DeveloperSettingsView`, not in the service: it is display,
 * and display is the client's question. This is the same split `lib/sidebar.ts`
 * makes for feature categories, and it comes with the same guard — a test fails
 * if the daemon serves a toggle no section lists, or a section names one the
 * daemon does not serve.
 *
 * The section titles, their order, and the ids in each are copied from
 * `DeveloperSettingsView.form`. Changing them here changes what the two apps
 * look like relative to each other, which is the thing the port exists to
 * avoid.
 */

import type { DevScale, DevToggle } from "@/lib/wire"

/**
 * A section is either a list of switches or the animation-scale pickers.
 *
 * One ordered list rather than "the toggle sections, plus the scales": on the
 * Mac, Animations sits *between* Drawing and Apps, and a shape that could not
 * express that would quietly reorder the screen.
 */
export type DevSection =
  | { kind: "toggles"; title: string; toggles: string[] }
  | { kind: "scales"; title: string }

/** The Mac's four sections, in its order. */
export const DEV_SECTIONS: readonly DevSection[] = [
  { kind: "toggles", title: "Input", toggles: ["show-touches", "pointer-location"] },
  {
    kind: "toggles",
    title: "Drawing",
    toggles: ["layout-bounds", "gpu-overdraw", "gpu-profile"],
  },
  { kind: "scales", title: "Animations" },
  { kind: "toggles", title: "Apps", toggles: ["keep-activities", "strict-mode"] },
]

/** Every toggle id the sections place, for the invariant test. */
export function placedToggleIDs(): string[] {
  return DEV_SECTIONS.flatMap((section) => (section.kind === "toggles" ? section.toggles : []))
}

/**
 * The served toggles for one section, in the section's order.
 *
 * Missing ids are dropped rather than rendered blank: the guard test is what
 * catches a table that has drifted, and a half-drawn row at runtime would only
 * be a worse way to find out.
 */
export function togglesFor(
  section: DevSection,
  served: readonly DevToggle[],
): DevToggle[] {
  if (section.kind !== "toggles") return []
  const byID = new Map(served.map((toggle) => [toggle.id, toggle]))
  const rows: DevToggle[] = []
  for (const id of section.toggles) {
    const toggle = byID.get(id)
    if (toggle !== undefined) rows.push(toggle)
  }
  return rows
}

/**
 * What a scale picker shows for one step.
 *
 * `0` is "Off" rather than "0×" — Developer Options' own wording, and the one
 * value that means something different in kind from the rest. Whole numbers
 * print bare, so 2 reads "2×" and not "2.0×", matching how the platform stores
 * them and how `scaleArgument` writes them back.
 */
export function scaleLabel(choice: number): string {
  if (choice === 0) return "Off"
  return `${String(choice)}×`
}

/**
 * The choice a picker should show as selected.
 *
 * A device can report a scale that is not one of the offered steps — anything
 * can write that key. Showing no selection would make the picker look broken
 * and, worse, invite a click that silently changes the value; the nearest step
 * is at least true to what the device says.
 */
export function nearestChoice(value: number, choices: readonly number[]): number {
  let best = value
  let bestDistance = Number.POSITIVE_INFINITY
  for (const choice of choices) {
    const distance = Math.abs(choice - value)
    if (distance < bestDistance) {
      bestDistance = distance
      best = choice
    }
  }
  return best
}

/** A scale row's current step, resolved against the offered choices. */
export function scaleSelection(scale: DevScale, choices: readonly number[]): number {
  return nearestChoice(scale.value, choices)
}
