/**
 * Wraps a value for `sh`, the way ADBKit's `shellQuote` does: single quotes,
 * with any embedded quote closed, escaped and reopened.
 *
 * Its own module rather than a curl helper, because the two callers want it for
 * different reasons — a copied `curl` has to reproduce what was sent, and a
 * script path dropped into a command field has to survive `$`, backticks and
 * parentheses on the way through a login shell.
 */
export function shellQuote(value: string): string {
  return `'${value.replaceAll("'", String.raw`'\''`)}'`
}
