import type { ReactNode } from 'react';
import { RequireAuth } from '@/lib/auth';
import { RequireSupportedRelease } from '@/lib/release';

/**
 * Wrap a route element so the browser user must be authenticated AND on a
 * supported GearSnitch release before the child is rendered. Extracted from
 * `App.tsx` so that it can be unit-tested in isolation (item #24).
 */
export function ProtectedAppRoute({ children }: { children: ReactNode }) {
  return (
    <RequireAuth>
      <RequireSupportedRelease>{children}</RequireSupportedRelease>
    </RequireAuth>
  );
}

export default ProtectedAppRoute;
