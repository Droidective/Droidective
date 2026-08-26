/**
 * Metro's debugger target list, and which of them the console may talk to.
 *
 * A port of ADBKit's `MetroInspector`, rule for rule, because the two apps have
 * to pick the same target out of the same list — a console that attached to
 * Metro's placeholder entry would connect and then never receive anything.
 *
 * **The socket lives in the webview, not the daemon.** `URLSessionWebSocketTask`
 * compiles off-Darwin and then fails at runtime ("WebSockets not supported by
 * libcurl"), so the daemon cannot hold a CDP connection without a NIO client
 * written from scratch. Metro runs on this machine, so the webview can reach it
 * directly and both WebKitGTK and WebView2 ship a real WebSocket.
 */

export interface CdpTarget {
  id: string
  title: string
  appId: string | null
  detail: string
  deviceName: string
  vm: string | null
  webSocketDebuggerUrl: string
  logicalDeviceId: string | null
}

/** Metro's own placeholder entry, which answers nothing if you connect to it. */
const PLACEHOLDER_VM = "don't use"

export function isHermes(target: CdpTarget): boolean {
  return target.vm === "Hermes"
}

function text(value: unknown): string | null {
  return typeof value === "string" ? value : null
}

/**
 * The targets worth offering, Hermes first.
 *
 * Entries with no `webSocketDebuggerUrl` cannot be connected to, and Metro's
 * `"don't use"` entry is a placeholder it lists on purpose — both are dropped
 * rather than shown and then failing.
 */
export function parseTargets(payload: unknown): CdpTarget[] {
  if (!Array.isArray(payload)) return []
  const targets: CdpTarget[] = []
  for (const entry of payload) {
    if (typeof entry !== "object" || entry === null) continue
    const row = entry as Record<string, unknown>
    const ws = text(row["webSocketDebuggerUrl"])
    if (ws === null || ws === "") continue
    const vm = text(row["vm"])
    if (vm === PLACEHOLDER_VM) continue
    const appId = text(row["appId"])
    const reactNative = row["reactNative"]
    const logical =
      typeof reactNative === "object" && reactNative !== null
        ? text((reactNative as Record<string, unknown>)["logicalDeviceId"])
        : null
    targets.push({
      id: text(row["id"]) ?? ws,
      title: text(row["title"]) ?? "React Native",
      appId,
      detail: text(row["description"]) ?? appId ?? "",
      deviceName: text(row["deviceName"]) ?? "",
      vm,
      webSocketDebuggerUrl: ws,
      logicalDeviceId: logical,
    })
  }
  // Hermes first — a stable partition, not a full sort, so Metro's own order
  // survives within each group the way the Mac's does.
  return [...targets.filter((one) => isHermes(one)), ...targets.filter((one) => !isHermes(one))]
}

/**
 * Whether a target's socket URL is a local debugger socket.
 *
 * The proxy runs on this machine, so a real target is always `ws`/`wss` on
 * loopback. Refusing anything else stops a rogue process on the Metro port
 * from steering the console at an off-host WebSocket — the same check
 * `MetroInspector.isLocalDebuggerURL` makes, and it matters more here because
 * the webview, not a daemon, is what would open the connection.
 */
export function isLocalDebuggerUrl(raw: string): boolean {
  let url: URL
  try {
    url = new URL(raw)
  } catch {
    return false
  }
  const scheme = url.protocol.toLowerCase()
  if (scheme !== "ws:" && scheme !== "wss:") return false
  const host = url.hostname.toLowerCase()
  // `new URL` keeps IPv6 hosts in brackets.
  return host === "127.0.0.1" || host === "localhost" || host === "::1" || host === "[::1]"
}

/** Metro's target-list endpoint for a port. */
export function targetsUrl(port: number): string {
  return `http://localhost:${String(port)}/json/list`
}

/** Metro's status endpoint, which answers `packager-status:running` when up. */
export function statusUrl(port: number): string {
  return `http://localhost:${String(port)}/status`
}

export function isMetroStatus(body: string): boolean {
  return body.includes("packager-status:running")
}

/** A one-line label for a target, as the picker shows it. */
export function targetLabel(target: CdpTarget): string {
  const parts = [target.deviceName, target.title].filter((part) => part !== "")
  const label = parts.join(" · ")
  return label === "" ? target.id : label
}
