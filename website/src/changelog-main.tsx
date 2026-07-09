import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import { ChangelogPage } from '@/components/site/ChangelogPage'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <ChangelogPage />
  </StrictMode>,
)
