import { StrictMode } from "react"
import { createRoot } from "react-dom/client"
import "./index.css"
import { BlogIndexPage } from "@/components/site/BlogIndexPage"

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <BlogIndexPage />
  </StrictMode>,
)
