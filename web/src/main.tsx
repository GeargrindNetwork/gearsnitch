import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App'
import { ThemeProvider } from './lib/theme'
import { installGlobalWebErrorLogging, webLogger } from './lib/logger'

installGlobalWebErrorLogging()

try {
  createRoot(document.getElementById('root')!).render(
    <StrictMode>
      <ThemeProvider>
        <App />
      </ThemeProvider>
    </StrictMode>,
  )
} catch (error) {
  webLogger.error('React root render failed', {
    error: error instanceof Error
      ? { name: error.name, message: error.message, stack: error.stack }
      : String(error),
  })
  throw error
}
