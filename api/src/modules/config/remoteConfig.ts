import {
  getReleasePolicy,
  getServerBuildInfo,
  resolveReleaseCompatibility,
  type ClientReleaseHeaders,
} from './releasePolicy.js';

export interface RemoteFeatureFlags {
  workoutsEnabled: boolean;
  storeEnabled: boolean;
  watchCompanionEnabled: boolean;
  waterTrackingEnabled: boolean;
  emergencyContactsEnabled: boolean;
}

export interface RemoteReleaseConfig {
  minimumVersion: string;
  currentVersion: string;
  forceUpdate: boolean;
  releaseNotes: string[];
  publishedAt: string;
}

export interface RemoteCompatibilityConfig {
  status: 'supported' | 'blocked' | 'unknown';
  reason: string | null;
  clientVersion: string | null;
  minimumSupportedVersion: string;
  currentVersion: string;
  forceUpgrade: boolean;
  platform: string | null;
  build: string | null;
}

export interface RemoteMaintenanceConfig {
  isActive: boolean;
  message: string | null;
}

export interface RemoteServerConfig {
  version: string;
  buildId: string | null;
  gitSha: string | null;
  builtAt: string | null;
  environment: string;
}

export interface RemoteConfigPayload {
  featureFlags: RemoteFeatureFlags;
  release: RemoteReleaseConfig;
  compatibility: RemoteCompatibilityConfig;
  maintenance: RemoteMaintenanceConfig;
  server: RemoteServerConfig;
}

const featureFlags: RemoteFeatureFlags = {
  workoutsEnabled: true,
  storeEnabled: true,
  watchCompanionEnabled: true,
  waterTrackingEnabled: true,
  emergencyContactsEnabled: true,
};

const maintenance: RemoteMaintenanceConfig = {
  isActive: false,
  message: null,
};

export function getRemoteConfigPayload(
  client: ClientReleaseHeaders = {
    platform: null,
    version: null,
    build: null,
  },
): RemoteConfigPayload {
  const policy = getReleasePolicy();
  const compatibility = resolveReleaseCompatibility(client, policy);

  return {
    featureFlags: { ...featureFlags },
    release: {
      minimumVersion: policy.minimumSupportedVersion,
      currentVersion: policy.version,
      forceUpdate: policy.forceUpgrade,
      releaseNotes: [...policy.releaseNotes],
      publishedAt: policy.publishedAt,
    },
    compatibility,
    maintenance: { ...maintenance },
    server: getServerBuildInfo(policy),
  };
}

export function getRemoteFeatureFlags(): RemoteFeatureFlags {
  return { ...featureFlags };
}
