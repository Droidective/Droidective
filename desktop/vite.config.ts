import path from "node:path"
import process from "node:process"
import tailwindcss from "@tailwindcss/vite"
import react from "@vitejs/plugin-react"
import { defineConfig } from "vitest/config"

// Set by `tauri dev` when serving to a device on the LAN; unset for a plain
// desktop run, where the dev server stays on localhost.
const host = process.env["TAURI_DEV_HOST"]

export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: { "@": path.resolve(import.meta.dirname, "./src") },
  },
  // Rust compiler errors scroll past if Vite clears the screen on rebuild.
  clearScreen: false,
  server: {
    // Tauri points its webview at a fixed URL, so a port fallback would load
    // a blank window instead of the app. Fail loudly instead.
    port: 1420,
    strictPort: true,
    host: host ?? false,
    // Spread rather than `hmr: undefined` — exactOptionalPropertyTypes makes
    // an explicit undefined a type error, and Vite's own default is "absent".
    ...(host ? { hmr: { protocol: "ws", host, port: 1421 } } : {}),
    watch: { ignored: ["**/src-tauri/**"] },
  },
  build: {
    // The webview, not the browser matrix: WebView2 on Windows, WebKit
    // elsewhere. Both are older than the default esnext target.
    target: process.env["TAURI_ENV_PLATFORM"] === "windows" ? "chrome105" : "safari13",
    // Boolean, not a named minifier: Vite 8 minifies with oxc and no longer
    // bundles esbuild, so naming one is a hard build failure.
    minify: !process.env["TAURI_ENV_DEBUG"],
    sourcemap: Boolean(process.env["TAURI_ENV_DEBUG"]),
  },
  test: {
    environment: "node",
    include: ["src/**/*.test.ts"],
  },
})
