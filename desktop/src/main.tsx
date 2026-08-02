import React from "react"
import ReactDOM from "react-dom/client"
import { App } from "@/App"
// Vite takes the stylesheet through the bundler as a side effect.
// oxlint-disable-next-line import/no-unassigned-import
import "@/index.css"

const root = document.querySelector("#root")
if (!root) throw new Error("index.html is missing #root")

ReactDOM.createRoot(root).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
)
