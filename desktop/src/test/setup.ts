import { cleanup } from "@testing-library/react"
import { afterEach } from "vitest"

// Unmount between tests. Testing Library only auto-cleans when vitest runs with
// `globals: true`, and this project does not — without this, a component from
// one test stays mounted and the next `render` finds two of everything.
afterEach(cleanup)

// jsdom implements no scrolling at all: it lays nothing out, so these throw
// rather than doing nothing. Every feed here follows its tail, so without the
// stubs a test that merely *renders* one fails on the effect. Stubbed rather
// than guarded in the app code, because a guard would be dead weight in the
// only environment that matters — a real webview has both.
//
// Guarded on `Element` because this file is the setup for *every* suite, and
// the pure ones (`menuKeys`, `hints`, …) run in a node environment where there
// is no DOM to patch.
if (typeof Element !== "undefined") {
  Element.prototype.scrollTo = () => {
    // Nothing to scroll: jsdom has no layout.
  }
  Element.prototype.scrollIntoView = () => {
    // As above.
  }
}
