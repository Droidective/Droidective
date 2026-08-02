import type { FeatureField, FeatureSummary, FieldValue } from "@/lib/wire"
import { PACKAGE_PARAM, TOGGLE_PARAM } from "@/lib/wire"

/**
 * Turning a rendered form into the parameters a runner expects.
 *
 * Pure, because the interesting parts — which control produces which JSON
 * type, and what counts as "filled in" — are exactly what breaks silently
 * when they live inside a component.
 */

export type FormValues = Record<string, FieldValue>

export function initialValues(feature: FeatureSummary): FormValues {
  const values: FormValues = {}
  for (const field of feature.fields) {
    values[field.name] = field.defaultValue ?? blankFor(field)
  }
  return values
}

function blankFor(field: FeatureField): FieldValue {
  switch (field.control) {
    case "switch":
      return false
    case "slider":
      // The low end of the range, not zero: a slider whose range starts at 10
      // has no zero to sit at.
      return field.min ?? 0
    case "number":
      return ""
    case "select":
      return field.options[0]?.value ?? ""
    default:
      return ""
  }
}

/**
 * Coerces one control's raw input to the JSON type its runner reads.
 *
 * A number field stays a string while it is empty or half-typed ("-", "1e"):
 * sending `NaN` would reach the device as garbage, and sending 0 would be a
 * value the user never chose.
 */
export function coerce(field: FeatureField, raw: string | boolean): FieldValue {
  if (typeof raw === "boolean") return raw
  switch (field.control) {
    case "switch":
      return raw === "true"
    case "number":
    case "slider": {
      if (raw.trim() === "") return ""
      const parsed = Number(raw)
      return Number.isFinite(parsed) ? parsed : raw
    }
    default:
      return raw
  }
}

/** The names of required fields the form has not filled in. */
export function missingRequired(feature: FeatureSummary, values: FormValues): string[] {
  return feature.fields
    .filter((field) => !field.optional && isBlank(values[field.name]))
    .map((field) => field.name)
}

function isBlank(value: FieldValue | undefined): boolean {
  if (value === undefined) return true
  // `false` is a deliberate answer for a switch, and 0 for a number.
  if (typeof value === "boolean" || typeof value === "number") return false
  return value.trim() === ""
}

/**
 * The `fields` map for a run request.
 *
 * A toggle contributes its implicit `on` and nothing else; an optional field
 * left blank is omitted rather than sent as `""`, so the runner sees "not
 * given" instead of "given as empty".
 */
export function runFields(
  feature: FeatureSummary,
  values: FormValues,
  toggleOn?: boolean,
  packageId?: string | null,
): FormValues | undefined {
  const fields: FormValues = {}
  if (feature.kind === "toggleAction") {
    fields[TOGGLE_PARAM] = toggleOn ?? false
  } else {
    for (const field of feature.fields) {
      const value = values[field.name]
      if (isBlank(value) || value === undefined) continue
      fields[field.name] = value
    }
  }
  // Required for a `needsBundle` feature and harmless context for the rest —
  // the same rule `AppState.run` applies on the Mac.
  if (packageId !== undefined && packageId !== null && packageId !== "") {
    fields[PACKAGE_PARAM] = packageId
  }
  return Object.keys(fields).length > 0 ? fields : undefined
}
