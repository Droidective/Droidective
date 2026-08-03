/**
 * Making sense of a `getprop` dump.
 *
 * A device answers with well over a thousand properties in no useful order.
 * The daemon passes them through untouched — which property matters is the
 * reader's question — so the arranging happens here, where it can be tested
 * against a real dump rather than eyeballed in a list.
 */

export interface PropertyRow {
  key: string
  value: string
}

export interface PropertyGroup {
  /** The `ro.build` in `ro.build.version.sdk` — how getprop already groups. */
  prefix: string
  rows: PropertyRow[]
}

/**
 * The handful worth reading first, in the order the Mac's Device Info header
 * shows them. Anything missing is simply skipped: an emulator and a phone do
 * not answer the same set, and a row reading "unknown" is worse than no row.
 */
const SUMMARY_KEYS: readonly { readonly key: string; readonly label: string }[] = [
  { key: "ro.product.model", label: "Model" },
  { key: "ro.product.manufacturer", label: "Manufacturer" },
  { key: "ro.build.version.release", label: "Android" },
  { key: "ro.build.version.sdk", label: "API level" },
  { key: "ro.build.id", label: "Build" },
  { key: "ro.product.cpu.abi", label: "ABI" },
  { key: "ro.serialno", label: "Serial" },
  { key: "ro.build.type", label: "Build type" },
]

export interface SummaryRow {
  label: string
  value: string
}

export function summary(properties: Readonly<Record<string, string>>): SummaryRow[] {
  return SUMMARY_KEYS.flatMap(({ key, label }) => {
    const value = properties[key]
    return value === undefined || value === "" ? [] : [{ label, value }]
  })
}

/** Case-insensitive match over the key and the value, both of which get read. */
export function matchesProperty(row: PropertyRow, query: string): boolean {
  const needle = query.toLowerCase().trim()
  if (needle === "") return true
  return `${row.key} ${row.value}`.toLowerCase().includes(needle)
}

/**
 * Every property a query matches, grouped by its first two dotted segments and
 * sorted within each group.
 *
 * Two segments rather than one: `ro` alone would be most of the dump in a
 * single heap, and `ro.build` against `ro.product` is the split someone reading
 * it already has in mind.
 */
export function propertyGroups(
  properties: Readonly<Record<string, string>>,
  query: string,
): PropertyGroup[] {
  const groups = new Map<string, PropertyRow[]>()
  for (const [key, value] of Object.entries(properties)) {
    const row = { key, value }
    if (!matchesProperty(row, query)) continue
    const prefix = key.split(".").slice(0, 2).join(".")
    const existing = groups.get(prefix)
    if (existing) existing.push(row)
    else groups.set(prefix, [row])
  }
  return [...groups.entries()]
    .toSorted(([left], [right]) => left.localeCompare(right))
    .map(([prefix, rows]) => ({
      prefix,
      rows: rows.toSorted((left, right) => left.key.localeCompare(right.key)),
    }))
}

/** How many rows survived the query — what the count in the search field says. */
export function countRows(groups: readonly PropertyGroup[]): number {
  return groups.reduce((total, group) => total + group.rows.length, 0)
}

/** The whole dump as `key=value` lines, for export or the clipboard. */
export function propertiesText(properties: Readonly<Record<string, string>>): string {
  return Object.keys(properties)
    .toSorted((left, right) => left.localeCompare(right))
    .map((key) => `${key}=${properties[key] ?? ""}`)
    .join("\n")
}
