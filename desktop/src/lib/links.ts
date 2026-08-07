/**
 * Where the About screen points.
 *
 * The same URLs `ADBKit.SupportLinks` builds, so the two apps file issues in
 * the same place and star the same repo. Kept here rather than fetched from
 * the daemon because these are constants of the *project*, not of the device —
 * a round-trip to learn our own repo URL would be a round-trip for nothing.
 */

const REPO_OWNER = "Rohindh-R"
const REPO_NAME = "Droidective"

export const AUTHOR_NAME = "Rohindh R"

export const LINKS = {
  repo: `https://github.com/${REPO_OWNER}/${REPO_NAME}`,
  releases: `https://github.com/${REPO_OWNER}/${REPO_NAME}/releases`,
  author: `https://github.com/${REPO_OWNER}`,
} as const

/**
 * A bug report pre-filled with what someone would otherwise be asked for.
 *
 * The Mac fills in its version, macOS build and connected device. This fills in
 * what a webview can honestly know — the app version and the platform string —
 * rather than guessing at the rest.
 */
export function bugReportUrl(version: string | null): string {
  const body = [
    "### What happened",
    "",
    "",
    "### Steps to reproduce",
    "",
    "",
    "### Environment",
    `- Droidective: ${version ?? "unknown"} (desktop)`,
    `- Platform: ${platformLabel()}`,
  ].join("\n")
  return issueUrl({ title: "", labels: "bug", body })
}

export function featureRequestUrl(): string {
  return issueUrl({ title: "", labels: "enhancement", body: "" })
}

function issueUrl(fields: { title: string; labels: string; body: string }): string {
  const query = new URLSearchParams({
    labels: fields.labels,
    body: fields.body,
  })
  if (fields.title !== "") query.set("title", fields.title)
  return `${LINKS.repo}/issues/new?${query.toString()}`
}

/** "Windows", "Linux", "macOS" — whatever the webview will admit to. */
export function platformLabel(): string {
  const agent = globalThis.navigator.userAgent
  if (agent.includes("Windows")) return "Windows"
  if (agent.includes("Mac OS")) return "macOS"
  if (agent.includes("Linux")) return "Linux"
  return "unknown"
}
