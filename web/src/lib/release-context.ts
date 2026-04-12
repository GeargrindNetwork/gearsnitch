import { createContext, useContext } from 'react';

export interface ReleaseConfig {
  minimumVersion: string;
  currentVersion: string;
  forceUpdate: boolean;
  releaseNotes: string[];
  publishedAt: string;
}

export interface CompatibilityConfig {
  status: 'supported' | 'blocked' | 'unknown';
  reason: string | null;
  clientVersion: string | null;
  minimumSupportedVersion: string;
  currentVersion: string;
  forceUpgrade: boolean;
  platform: string | null;
  build: string | null;
}

export interface ServerConfig {
  version: string;
  buildId: string | null;
  gitSha: string | null;
  builtAt: string | null;
  environment: string;
}

export interface ReleasePayload {
  release: ReleaseConfig;
  compatibility: CompatibilityConfig;
  server: ServerConfig;
}

export type ReleaseStatus = 'checking' | 'supported' | 'blocked' | 'error';

export interface ReleaseContextValue {
  status: ReleaseStatus;
  payload: ReleasePayload | null;
  errorMessage: string | null;
  refresh: () => Promise<void>;
}

export const ReleaseContext = createContext<ReleaseContextValue | null>(null);

export function useRelease() {
  const context = useContext(ReleaseContext);
  if (!context) {
    throw new Error('useRelease must be used within ReleaseProvider');
  }
  return context;
}
