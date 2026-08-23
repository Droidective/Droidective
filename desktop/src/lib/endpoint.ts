/**
 * Whether an endpoint field is worth submitting yet.
 *
 * **Deliberately permissive.** `ConnectionService.parseEndpoint` is the
 * authority on what adb accepts — bracketed and bare IPv6, a truncated IPv4
 * like "1.1.1", a port out of range — and it lives daemon-side so the two apps
 * cannot disagree. This only decides whether a *button* is enabled, so it errs
 * towards enabling: anything it lets through that adb will not take comes back
 * as the daemon's own refusal, which says more than a greyed-out button ever
 * could. A stricter check here would be the drift this split exists to avoid.
 */

/** Something has been typed, and it is one token. */
export function looksLikeEndpoint(text: string): boolean {
  const trimmed = text.trim()
  return trimmed !== "" && !/\s/u.test(trimmed)
}

/**
 * The same, plus an explicit port.
 *
 * Pairing needs one: the Android 11+ pairing port is random per session, so
 * there is nothing sensible to default to and the daemon refuses a bare host.
 * A bracketed IPv6 puts colons inside the brackets, so the port is what follows
 * the closing one.
 */
export function looksLikePairEndpoint(text: string): boolean {
  const trimmed = text.trim()
  if (!looksLikeEndpoint(trimmed)) return false
  const afterHost = trimmed.startsWith("[")
    ? trimmed.slice(trimmed.indexOf("]") + 1)
    : lastColonPart(trimmed)
  return /^:?\d+$/u.test(afterHost) && afterHost.replace(":", "") !== ""
}

/**
 * Everything from the last colon on — the port half of "host:port".
 *
 * A bare IPv6 has several colons and no port, so returning the last segment is
 * right: "fe80::1" ends in ":1", which reads as a port here and is refused
 * daemon-side rather than pretending to be one. Pairing against a bare IPv6 is
 * not a flow the phone's pairing dialog ever shows.
 */
function lastColonPart(text: string): string {
  const index = text.lastIndexOf(":")
  return index === -1 ? "" : text.slice(index)
}

/**
 * The host half, for prefilling the connect field after a pair.
 *
 * The Mac writes "ip:" into it so only the port is left to type when discovery
 * comes up empty.
 */
export function hostPrefix(text: string): string {
  const trimmed = text.trim()
  if (trimmed.startsWith("[")) {
    const close = trimmed.indexOf("]")
    return close === -1 ? trimmed : trimmed.slice(0, close + 1)
  }
  const index = trimmed.lastIndexOf(":")
  return index === -1 ? trimmed : trimmed.slice(0, index)
}
