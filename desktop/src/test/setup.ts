import { cleanup } from "@testing-library/react"
import { afterEach } from "vitest"

// Unmount between tests. Testing Library only auto-cleans when vitest runs with
// `globals: true`, and this project does not — without this, a component from
// one test stays mounted and the next `render` finds two of everything.
afterEach(cleanup)
