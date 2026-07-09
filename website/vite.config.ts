import path from "node:path"
import tailwindcss from "@tailwindcss/vite"
import react from "@vitejs/plugin-react"
import { defineConfig } from "vite"

// publicDir points at ../site so the static passthrough files (CNAME,
// appcast.xml, sitemap, SEO subpages, screenshots) are served in dev and
// copied verbatim into dist — the build output is the complete deployable
// GitHub Pages site.
export default defineConfig({
  plugins: [react(), tailwindcss()],
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
