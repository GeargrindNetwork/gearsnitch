/* eslint-disable react-refresh/only-export-components */

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { Navigate, useLocation } from 'react-router-dom';
import { Card, CardContent } from '@/components/ui/card';
import { api } from '@/lib/api';

export interface AuthUser {
  _id: string;
  email: string;
  displayName: string;
  avatarURL?: string | null;
  role: string;
  status: string;
  defaultGymId?: string | null;
  onboardingCompletedAt?: string | null;
}

interface OAuthSession {
  accessToken: string;
  user?: AuthUser | null;
}

type AuthStatus = 'bootstrapping' | 'authenticated' | 'unauthenticated';

interface AuthContextValue {
  status: AuthStatus;
  user: AuthUser | null;
  isAuthenticated: boolean;
  completeOAuthSignIn: (session: OAuthSession) => Promise<boolean>;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue | null>(null);

function clearLegacyAuthArtifacts() {
  localStorage.removeItem('token');
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const queryClient = useQueryClient();
  const [status, setStatus] = useState<AuthStatus>('bootstrapping');
  const [user, setUser] = useState<AuthUser | null>(null);

  const clearSession = useCallback((nextStatus: AuthStatus = 'unauthenticated') => {
    api.setToken(null);
    setUser(null);
    setStatus(nextStatus);
    clearLegacyAuthArtifacts();
  }, []);

  const fetchCurrentUser = useCallback(async (): Promise<AuthUser | null> => {
    const res = await api.get<AuthUser>('/auth/me');
    if (!res.success || !res.data) {
      return null;
    }
    return res.data;
  }, []);

  const refreshAccessToken = useCallback(async (): Promise<string | null> => {
    const res = await api.post<{ accessToken: string }>('/auth/refresh', {});
    if (!res.success || !res.data?.accessToken) {
      clearSession();
      return null;
    }

    api.setToken(res.data.accessToken);
    return res.data.accessToken;
  }, [clearSession]);

  const completeOAuthSignIn = useCallback(
    async ({ accessToken, user: sessionUser }: OAuthSession): Promise<boolean> => {
      api.setToken(accessToken);

      const currentUser = sessionUser ?? (await fetchCurrentUser());
      if (!currentUser) {
        clearSession();
        return false;
      }

      queryClient.clear();
      clearLegacyAuthArtifacts();
      setUser(currentUser);
      setStatus('authenticated');
      return true;
    },
    [clearSession, fetchCurrentUser, queryClient],
  );

  const signOut = useCallback(async () => {
    try {
      await api.post('/auth/logout', {});
    } catch {
      // Clearing local state is sufficient when the server session is already gone.
    }

    clearSession();
    queryClient.clear();
  }, [clearSession, queryClient]);

  useEffect(() => {
    api.setRefreshHandler(refreshAccessToken);
    return () => {
      api.setRefreshHandler(null);
    };
  }, [refreshAccessToken]);

  useEffect(() => {
    let active = true;

    const restoreSession = async () => {
      const accessToken = await refreshAccessToken();
      if (!active) {
        return;
      }

      if (!accessToken) {
        setStatus('unauthenticated');
        return;
      }

      const currentUser = await fetchCurrentUser();
      if (!active) {
        return;
      }

      if (!currentUser) {
        clearSession();
        return;
      }

      setUser(currentUser);
      setStatus('authenticated');
      clearLegacyAuthArtifacts();
    };

    void restoreSession();

    return () => {
      active = false;
    };
  }, [clearSession, fetchCurrentUser, refreshAccessToken]);

  const value = useMemo<AuthContextValue>(
    () => ({
      status,
      user,
      isAuthenticated: status === 'authenticated' && !!user,
      completeOAuthSignIn,
      signOut,
    }),
    [completeOAuthSignIn, signOut, status, user],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used within AuthProvider');
  }
  return context;
}

export function RequireAuth({ children }: { children: ReactNode }) {
  const location = useLocation();
  const { status, isAuthenticated } = useAuth();

  if (status === 'bootstrapping') {
    return (
      <div className="min-h-screen bg-zinc-950 px-6 py-24 text-zinc-100 lg:px-8">
        <div className="mx-auto max-w-2xl">
          <Card className="border-zinc-800 bg-zinc-900/50">
            <CardContent className="py-12 text-center text-zinc-400">
              Restoring your GearSnitch session...
            </CardContent>
          </Card>
        </div>
      </div>
    );
  }

  if (!isAuthenticated) {
    const redirectTo = `${location.pathname}${location.search}${location.hash}`;
    return <Navigate to={`/sign-in?redirect=${encodeURIComponent(redirectTo)}`} replace />;
  }

  return <>{children}</>;
}

export function RequireAdmin({ children }: { children: ReactNode }) {
  const { user, status, isAuthenticated } = useAuth();

  if (status === 'bootstrapping') {
    return (
      <div className="min-h-screen bg-zinc-950 px-6 py-24 text-zinc-100">
        <div className="mx-auto max-w-2xl text-center text-zinc-400">Loading...</div>
      </div>
    );
  }

  if (!isAuthenticated || !user || user.role !== 'admin') {
    return <Navigate to="/" replace />;
  }

  return <>{children}</>;
}
