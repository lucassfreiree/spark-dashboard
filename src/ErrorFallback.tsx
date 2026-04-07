import { Button } from "./components/ui/button";
import { WarningCircle, ArrowClockwise } from "@phosphor-icons/react";

interface ErrorFallbackProps {
  error: Error;
  resetErrorBoundary: () => void;
}

export const ErrorFallback = ({ error, resetErrorBoundary }: ErrorFallbackProps) => {
  if (import.meta.env.DEV) throw error;

  return (
    <div className="min-h-screen bg-background flex items-center justify-center p-4">
      <div className="w-full max-w-md">
        <div className="border border-destructive/40 bg-destructive/10 rounded-lg p-4 mb-6">
          <div className="flex items-center gap-2 mb-2">
            <WarningCircle className="w-5 h-5 text-destructive" weight="fill" />
            <h2 className="font-semibold text-destructive">Runtime Error</h2>
          </div>
          <p className="text-sm text-muted-foreground">
            Something unexpected happened. Contact the dashboard maintainer.
          </p>
        </div>

        <div className="bg-card border rounded-lg p-4 mb-6">
          <h3 className="font-semibold text-sm text-muted-foreground mb-2">Error Details:</h3>
          <pre className="text-xs text-destructive bg-muted/50 p-3 rounded border overflow-auto max-h-32">
            {error.message}
          </pre>
        </div>

        <Button onClick={resetErrorBoundary} className="w-full" variant="outline">
          <ArrowClockwise className="w-4 h-4 mr-2" />
          Try Again
        </Button>
      </div>
    </div>
  );
}
