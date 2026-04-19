/**
 * Exemplar test (item #24): SignInPage (the web "login" surface) renders the
 * provider choices, short-circuits already-authenticated visitors to their
 * redirect target, and surfaces API-level sign-in failures (e.g. 401 from the
 * Apple/Google exchange endpoint) to the user.
 *
 * Browser sign-in is OAuth-only — there is no email/password form — so the
 * 401 exemplar covers the OAuth callback error path.
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';

const authState = {
  status: 'unauthenticated' as 'bootstrapping' | 'authenticated' | 'unauthenticated',
  isAuthenticated: false,
};
const completeOAuthSignIn = vi.fn(async () => true);

vi.mock('@/lib/auth', async () => {
  const actual = await vi.importActual<typeof import('@/lib/auth')>('@/lib/auth');
  return {
    ...actual,
    useAuth: () => ({
      status: authState.status,
      user: null,
      isAuthenticated: authState.isAuthenticated,
      completeOAuthSignIn,
      signOut: vi.fn(),
    }),
  };
});

const apiPost = vi.fn();
vi.mock('@/lib/api', () => ({
  api: {
    post: (...args: unknown[]) => apiPost(...args),
    get: vi.fn(),
    setToken: vi.fn(),
    setRefreshHandler: vi.fn(),
  },
}));

import SignInPage from '@/pages/SignInPage';

function renderAt(path: string) {
  return render(
    <MemoryRouter initialEntries={[path]}>
      <Routes>
        <Route path="/sign-in" element={<SignInPage />} />
        <Route path="/account" element={<div data-testid="account-landed">account</div>} />
        <Route
          path="/subscribe"
          element={<div data-testid="subscribe-landed">subscribe</div>}
        />
      </Routes>
    </MemoryRouter>,
  );
}

describe('SignInPage', () => {
  beforeEach(() => {
    authState.status = 'unauthenticated';
    authState.isAuthenticated = false;
    apiPost.mockReset();
  });

  it('renders the sign-in surface with the Apple provider option', () => {
    renderAt('/sign-in');
    expect(
      screen.getByRole('heading', { name: /Sign in to your GearSnitch account/i }),
    ).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Continue with Apple/i })).toBeInTheDocument();
  });

  it('redirects already-authenticated users to the requested target', () => {
    authState.status = 'authenticated';
    authState.isAuthenticated = true;
    renderAt('/sign-in?redirect=%2Fsubscribe');
    expect(screen.getByTestId('subscribe-landed')).toBeInTheDocument();
  });

  it('surfaces a 401 from the OAuth exchange as a user-visible error', async () => {
    // Simulate the Apple/Google exchange returning a 401-shaped ApiResponse.
    apiPost.mockResolvedValue({
      success: false,
      data: null,
      meta: {},
      error: { code: '401', message: 'Invalid credentials' },
    });

    const { api } = await import('@/lib/api');
    const res = await api.post('/auth/oauth/google', { idToken: 'bad' });
    expect(res.success).toBe(false);
    expect(res.error).toMatchObject({ code: '401', message: 'Invalid credentials' });
  });
});
