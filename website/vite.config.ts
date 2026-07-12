import { readFileSync } from "node:fs"
import path from "node:path"
import tailwindcss from "@tailwindcss/vite"
import react from "@vitejs/plugin-react"
import { defineConfig, type Plugin } from "vite"

// Keeps index.html's JSON-LD "softwareVersion" in lockstep with the single
// version source, APP_VERSION in src/lib/content.ts — no manual bump needed.
function syncSoftwareVersion(): Plugin {
  const content = readFileSync(path.resolve(__dirname, "src/lib/content.ts"), "utf8")
  const match = content.match(/APP_VERSION = "v([^"]+)"/)
  if (!match) throw new Error("APP_VERSION not found in src/lib/content.ts")
  const version = match[1]
  return {
    name: "sync-software-version",
    transformIndexHtml(html) {
      return html.replace(/"softwareVersion": "[^"]*"/, `"softwareVersion": "${version}"`)
    },
  }
}

// publicDir points at ../site so the static passthrough files (CNAME,
// appcast.xml, sitemap, SEO subpages, screenshots) are served in dev and
// copied verbatim into dist — the build output is the complete deployable
// GitHub Pages site.
export default defineConfig({
  plugins: [react(), tailwindcss(), syncSoftwareVersion()],
  publicDir: path.resolve(__dirname, "../site"),
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
  build: {
    rollupOptions: {
      // Two HTML entries: the landing page and the full-changelog page —
      // GitHub Pages serves dist/changelog/index.html at /changelog/.
      input: {
        main: path.resolve(__dirname, "index.html"),
        changelog: path.resolve(__dirname, "changelog/index.html"),
      },
      output: {
        manualChunks: {
          react: ["react", "react-dom"],
          animation: ["gsap", "motion"],
        },
      },
    },
  },
})
