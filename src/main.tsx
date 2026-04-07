import { createRoot } from 'react-dom/client'
import { ErrorBoundary, FallbackProps } from "react-error-boundary";

import App from './App.tsx'

import "./main.css"
import "./styles/theme.css"
import "./index.css"

function ErrorFallbackWrapper(props: FallbackProps) {
  const error = props.error instanceof Error ? props.error : new Error(String(props.error))
  if (import.meta.env.DEV) throw error;
  return (
    <div className="min-h-screen bg-background flex items-center justify-center p-4">
      <div className="w-full max-w-md text-center">
        <h2 className="text-xl font-bold text-destructive mb-4">Runtime Error</h2>
        <pre className="text-xs text-destructive bg-muted/50 p-3 rounded border overflow-auto max-h-32 mb-4">
          {error.message}
        </pre>
        <button onClick={props.resetErrorBoundary} className="px-4 py-2 rounded border hover:bg-muted">
          Try Again
        </button>
      </div>
    </div>
  )
}

createRoot(document.getElementById('root')!).render(
  <ErrorBoundary FallbackComponent={ErrorFallbackWrapper}>
    <App />
  </ErrorBoundary>
)
