import type { FeatureSummary, FieldOption } from "@/lib/wire"

/**
 * The locale list, read out of the registry the daemon served.
 *
 * The Mac's Simulate hub does the same
 * (`FeatureRegistry.byID["locale"]?.fields.first?.options`) rather than keeping
 * a second list: these are the values the runner accepts, so a copy here would
 * be a menu offering locales the action would reject — and it would drift the
 * first time upstream adds one.
 *
 * Empty when the feature is absent, which is a real answer: a daemon too old to
 * serve `locale` should leave the picker empty rather than offer a value it has
 * never heard of.
 */
export function localeOptions(features: readonly FeatureSummary[]): FieldOption[] {
  const locale = features.find((feature) => feature.id === "locale")
  return locale?.fields.find((field) => field.name === "locale")?.options ?? []
}
