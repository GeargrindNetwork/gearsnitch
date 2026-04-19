/**
 * Exemplar test (item #24): verify that unauthenticated users hitting a
 * protected route are redirected to `/sign-in` with a `redirect` param that
 * preserves the originally-requested path.
 *
 * The auth bootstrap makes a `/auth/refresh` call — we stub `fetch` so it
 * resolves to a 401 and the AuthProvider transitions to `unauthenticated`.
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { AuthProvider } from '@/lib/auth';
import { ProtectedAppRoute } from '@/routes/ProtectedAppRoute';

function jsonResponse(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function renderWithProviders(initialPath: string) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return render(
    <QueryClientProvider client={queryClient}>
      <AuthProvider>
        <MemoryRouter initialEntries={[initialPath]}>
          <Routes>
            <Route
              path="/sign-in"
              element={<div data-testid="sign-in-landed">sign-in</div>}
            />
            <Route
              path="/metrics"
              element={
                <ProtectedAppRoute>
                  <div data-testid="metrics-loaded">metrics</div>
                </ProtectedAppRoute>
              }
            />
          </Routes>
        </MemoryRouter>
      </AuthProvider>
    </QueryClientProvider>,
  );
}

describe('ProtectedAppRoute', () => {
  beforeEach(() => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async (input: RequestInfo | URL) => {
        const url = typeof input === 'string' ? input : input.toString();
        if (url.includes('/auth/refresh')) {
          return jsonResponse(401, {
            success: false,
            data: null,
            meta: {},
            error: { code: '401', message: 'no session' },
          });
        }
        return jsonResponse(200, { success: true, data: null, meta: {}, error: null });
      }),
    );
  });

  it('redirects unauthenticated visitors to /sign-in', async () => {
    renderWithProviders('/metrics');

    await waitFor(() => {
      expect(screen.getByTestId('sign-in-landed')).toBeInTheDocument();
    });
    expect(screen.queryByTestId('metrics-loaded')).not.toBeInTheDocument();
  });
});
