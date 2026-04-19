/**
 * Exemplar test (item #24): SubscribePage renders all three subscription
 * tier cards and the "Subscribe" CTA triggers the checkout API with the
 * correct tier key.
 */
import { describe, it, expect, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import SubscribePage from '@/pages/SubscribePage';

vi.mock('@/lib/auth', () => ({
  useAuth: () => ({
    status: 'authenticated',
    user: { _id: 'u1', email: 'a@b.c', displayName: 'Test', role: 'user', status: 'active' },
    isAuthenticated: true,
    completeOAuthSignIn: vi.fn(),
    signOut: vi.fn(),
  }),
}));

vi.mock('@/lib/api', () => ({
  createSubscriptionCheckout: vi.fn(async () => ({
    checkoutUrl: 'https://checkout.stripe.test/session_hustle',
    sessionId: 'cs_test_hustle',
    tier: 'hustle',
    mode: 'subscription',
  })),
}));

import { createSubscriptionCheckout } from '@/lib/api';

describe('SubscribePage', () => {
  it('renders all three subscription tiers', () => {
    render(
      <MemoryRouter>
        <SubscribePage />
      </MemoryRouter>,
    );

    expect(screen.getByTestId('subscribe-tier-hustle')).toBeInTheDocument();
    expect(screen.getByTestId('subscribe-tier-hwmf')).toBeInTheDocument();
    expect(screen.getByTestId('subscribe-tier-babyMomma')).toBeInTheDocument();
  });

  it('starts a checkout session when the Subscribe CTA is clicked', async () => {
    const user = userEvent.setup();
    // jsdom does not implement navigation; stub assign so the redirect is a no-op.
    const assign = vi.fn();
    Object.defineProperty(window, 'location', {
      writable: true,
      value: { ...window.location, assign, origin: 'http://localhost' },
    });

    render(
      <MemoryRouter>
        <SubscribePage />
      </MemoryRouter>,
    );

    await user.click(screen.getByTestId('subscribe-cta-hustle'));

    await waitFor(() => {
      expect(createSubscriptionCheckout).toHaveBeenCalledWith(
        expect.objectContaining({ tier: 'hustle' }),
      );
    });
    expect(assign).toHaveBeenCalledWith('https://checkout.stripe.test/session_hustle');
  });
});
