import React from "react"
import ReactDOM from "react-dom/client"
import { App } from "@/App"
import { QuickPanel } from "@/components/quick/QuickPanel"
// Vite takes the stylesheet through the bundler as a side effect.
// oxlint-disable-next-line import/no-unassigned-import
import "@/index.css"

const root = document.querySelector("#root")
if (!root) throw new Error("index.html is missing #root")

/**
 * One bundle, two entry points.
 *
 * The Quick Actions panel is a second window of the same app, so it loads the
 * same page and the URL says which of the two to render. A query string rather
 * than the window's label: the label is reachable, but only through the Tauri
 * API, which would make this choice asynchronous and paint the wrong app for a
 * frame first.
 */
const isPanel = new URLSearchParams(globalThis.location.search).get("window") === "quick"

ReactDOM.createRoot(root).render(
  <React.StrictMode>{isPanel ? <QuickPanel /> : <App />}</React.StrictMode>,
)
