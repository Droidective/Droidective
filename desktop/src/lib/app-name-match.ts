/**
 * Which installed package an app *name* refers to.
 *
 * A port of ADBKit's `AppNameMatcher`. A Reactotron client introduces itself
 * with a display name ("StreamLab", "Food Hub") and a restart needs a package
 * id, so something has to bridge the two — and it has to refuse rather than
 * guess when the answer is ambiguous, because the cost of being wrong is
 * clearing the data of an app nobody asked about.
 */

/**
 * The single package matching `appName`, or null when none or several do.
 *
 * An exact match on the package's last segment wins ("My App" →
 * `com.acme.myapp`); failing that, a name appearing anywhere in the package id
 * is accepted only if exactly one package qualifies ("Food Hub" →
 * `com.foodhub.driver.dev`).
 */
export function matchAppName(appName: string, packages: readonly string[]): string | null {
  const name = normalize(appName)
  if (name === "") return null
  const lastSegment = packages.filter((id) => normalize(id.split(".").at(-1) ?? "") === name)
  if (lastSegment.length === 1) return lastSegment[0] ?? null
  // Two packages whose last segment is the same name is exactly the case where
  // guessing is worst — a dev and a prod build of the same app.
  if (lastSegment.length > 1) return null
  const containing = packages.filter((id) => normalize(id).includes(name))
  return containing.length === 1 ? (containing[0] ?? null) : null
}

/** Lowercased alphanumerics only, so "Food Hub" and `foodhub` compare equal. */
function normalize(text: string): string {
  return text.toLowerCase().replaceAll(/[^a-z0-9]/gu, "")
}
