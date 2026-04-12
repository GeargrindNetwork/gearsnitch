import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react';
import { Card, CardContent } from '@/components/ui/card';
import ReleaseBlockedView from '@/components/release/ReleaseBlockedView';
import { api } from '@/lib/api';
import { APP_RELEASE } from '@/lib/release-meta';
import { useAuth } from '@/lib/auth';

interface ReleaseConfig {
  minimumVersion: string;
  currentVersion: string;
  forceUpdate: boolean;
  releaseNotes: string[];
  publishedAt: string;
}

interface CompatibilityConfig {
  status: 'supported' | 'blocked' | 'unknown';
  reason: string | null;
  clientVersion: string | null;
  minimumSupportedVersion: string;
  currentVersion: string;
  forceUpgrade: boolean;
  platform: string | null;
  build: string | null;
}

interface ServerConfig {
  version: string;
  buildId: string | null;
  gitSha: string | null;
  builtAt: string | null;
  environment: string;
}

interface ReleasePayload {
  release: ReleaseConfig;
  compatibility: CompatibilityConfig;
  server: ServerConfig;
}

type ReleaseStatus = 'checking' | 'supported' | 'blocked' | 'error';

interface ReleaseContextValue {
  status: ReleaseStatus;
  payload: ReleasePayload | null;
  errorMessage: string | null;
  refresh: () => Promise<void>;
}

const ReleaseContext = createContext<ReleaseContextValue | null>(null);

export function ReleaseProvider({ children }: { children: ReactNode }) {
  const [status, setStatus] = useState<ReleaseStatus>('checking');
  const [payload, setPayload] = useState<ReleasePayload | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    setStatus((current) => (payload ? current : 'checking'));
    setErrorMessage(null);

    try {
      const res = await api.get<ReleasePayload>('/config/app');
      if (!res.success || !res.data) {
        throw new Error(res.error?.message ?? 'Failed to fetch release configuration');
      }

      setPayload(res.data);
      setStatus(res.data.compatibility.status === 'supported' ? 'supported' : 'blocked');
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'Unable to verify release status');
      setStatus('error');
    }
  }, [payload]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  const value = useMemo<ReleaseContextValue>(
    () => ({
      status,
      payload,
      errorMessage,
      refresh,
    }),
    [errorMessage, payload, refresh, status],
  );

  return <ReleaseContext.Provider value={value}>{children}</ReleaseContext.Provider>;
}

export function useRelease() {
  const context = useContext(ReleaseContext);
  if (!context) {
    throw new Error('useRelease must be used within ReleaseProvider');
  }
  return context;
}

export function RequireSupportedRelease({ children }: { children: ReactNode }) {
  const { signOut } = useAuth();
  const { status, payload, errorMessage, refresh } = useRelease();

  if (status === 'checking') {
    return (
      <div className="min-h-screen bg-zinc-950 px-6 py-24 text-zinc-100 lg:px-8">
        <div className="mx-auto max-w-2xl">
          <Card className="border-zinc-800 bg-zinc-900/50">
            <CardContent className="py-12 text-center text-zinc-400">
              Checking your GearSnitch version...
            </CardContent>
          </Card>
        </div>
      </div>
    );
  }

  if (status === 'error') {
    return (
      <ReleaseBlockedView
        title="Unable to verify your app version"
        message={errorMessage ?? 'We could not confirm whether this web build is still supported.'}
        currentVersion={APP_RELEASE.version}
        requiredVersion={payload?.release.minimumVersion ?? null}
        releaseNotes={payload?.release.releaseNotes ?? []}
        primaryActionLabel="Retry Check"
        onPrimaryAction={() => { void refresh(); }}
        secondaryActionLabel="Sign Out"
        onSecondaryAction={() => { void signOut(); }}
      />
    );
  }

  if (status === 'blocked' && payload) {
    return (
      <ReleaseBlockedView
        title="Refresh required"
        message="This GearSnitch web build is no longer supported for the authenticated app experience."
        currentVersion={payload.compatibility.clientVersion ?? APP_RELEASE.version}
        requiredVersion={payload.release.minimumVersion}
        releaseNotes={payload.release.releaseNotes}
        primaryActionLabel="Refresh Now"
        onPrimaryAction={() => {
          window.location.reload();
        }}
        secondaryActionLabel="Sign Out"
        onSecondaryAction={() => { void signOut(); }}
      />
    );
  }

  return <>{children}</>;
}
