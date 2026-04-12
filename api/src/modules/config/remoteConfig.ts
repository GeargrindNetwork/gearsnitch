export interface RemoteFeatureFlags {
  workoutsEnabled: boolean;
  storeEnabled: boolean;
  watchCompanionEnabled: boolean;
  waterTrackingEnabled: boolean;
  emergencyContactsEnabled: boolean;
}

export interface RemoteAppVersionConfig {
  minimumVersion: string;
  currentVersion: string;
  forceUpdate: boolean;
}

export interface RemoteMaintenanceConfig {
  isActive: boolean;
  message: string | null;
}

export interface RemoteConfigPayload {
  featureFlags: RemoteFeatureFlags;
  appVersion: RemoteAppVersionConfig;
  maintenance: RemoteMaintenanceConfig;
}

const featureFlags: RemoteFeatureFlags = {
  workoutsEnabled: true,
  storeEnabled: true,
  watchCompanionEnabled: true,
  waterTrackingEnabled: true,
  emergencyContactsEnabled: true,
};

const appVersion: RemoteAppVersionConfig = {
  minimumVersion: '1.0.0',
  currentVersion: '1.0.0',
  forceUpdate: false,
};

const maintenance: RemoteMaintenanceConfig = {
  isActive: false,
  message: null,
};

export function getRemoteConfigPayload(): RemoteConfigPayload {
  return {
    featureFlags: { ...featureFlags },
    appVersion: { ...appVersion },
    maintenance: { ...maintenance },
  };
}

export function getRemoteFeatureFlags(): RemoteFeatureFlags {
  return { ...featureFlags };
}
