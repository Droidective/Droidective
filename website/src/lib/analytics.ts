// Thin wrapper over the PostHog snippet loaded by /analytics.js. Calls are
// queued by the snippet stub and flushed once PostHog initializes; when no key
// is configured (local checkouts, forks) they simply never send. Pageviews and
// clicks are already handled by capture_pageview + autocapture — these are the
// structured blog events on top of that.
interface PostHogLite {
  capture: (event: string, properties?: Record<string, unknown>) => void
}

declare global {
  interface Window {
    posthog?: PostHogLite
  }
}

export function track(event: string, properties?: Record<string, unknown>): void {
  if (typeof window === "undefined") return
  window.posthog?.capture(event, properties)
}
