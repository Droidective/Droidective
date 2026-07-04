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
      output: {
        manualChunks: {
          react: ["react", "react-dom"],
          animation: ["gsap", "motion"],
        },
      },
    },
  },
})
