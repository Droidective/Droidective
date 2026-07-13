import { StrictMode } from "react"
import { createRoot } from "react-dom/client"
import "./index.css"
import { BlogPostPage } from "@/components/site/BlogPostPage"

// Each post is served as a static /blog/<slug>/index.html; derive the slug
// from the path so every post page shares this one entry.
const segments = window.location.pathname.split("/").filter(Boolean)
const slug = segments[segments.length - 1] ?? ""

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <BlogPostPage slug={slug} />
  </StrictMode>,
)
