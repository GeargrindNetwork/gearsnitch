import { Component, type ErrorInfo, type ReactNode } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { webLogger } from '@/lib/logger';

interface Props {
  children: ReactNode;
  fallback?: ReactNode;
}

interface State {
  hasError: boolean;
  error: Error | null;
}

export class ErrorBoundary extends Component<Props, State> {
  state: State = { hasError: false, error: null };

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    webLogger.error('React error boundary caught error', {
      error: { name: error.name, message: error.message, stack: error.stack },
      componentStack: errorInfo.componentStack,
    });
  }

  handleReset = () => {
    this.setState({ hasError: false, error: null });
  };

  handleReload = () => {
    window.location.reload();
  };

  render() {
    if (this.state.hasError) {
      if (this.props.fallback) {
        return this.props.fallback;
      }

      return (
        <div className="min-h-screen bg-zinc-950 px-6 py-24 text-zinc-100">
          <div className="mx-auto max-w-2xl">
            <Card className="border-red-500/20 bg-zinc-900/70">
              <CardContent className="space-y-4 p-8 text-center">
                <h1 className="text-2xl font-bold text-red-400">Something went wrong</h1>
                <p className="text-sm text-zinc-400">
                  An unexpected error occurred. The error has been logged. You can try again or reload the page.
                </p>
                {this.state.error && import.meta.env.DEV && (
                  <pre className="mt-4 overflow-x-auto rounded-lg bg-zinc-950 p-4 text-left text-xs text-red-300">
                    {this.state.error.message}
                  </pre>
                )}
                <div className="flex justify-center gap-3 pt-2">
                  <Button variant="outline" onClick={this.handleReset}>
                    Try Again
                  </Button>
                  <Button className="bg-emerald-600 text-white hover:bg-emerald-700" onClick={this.handleReload}>
                    Reload Page
                  </Button>
                </div>
              </CardContent>
            </Card>
          </div>
        </div>
      );
    }

    return this.props.children;
  }
}
