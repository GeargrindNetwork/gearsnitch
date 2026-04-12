declare const __APP_VERSION__: string;
declare const __APP_RELEASE_PUBLISHED_AT__: string;
declare const __APP_BUILD_ID__: string;
declare const __APP_BUILD_TIME__: string;
declare const __APP_GIT_SHA__: string;

export interface LocalReleaseMetadata {
  platform: 'web';
  version: string;
  publishedAt: string | null;
  buildId: string;
  builtAt: string | null;
  gitSha: string | null;
}

export const APP_RELEASE: LocalReleaseMetadata = {
  platform: 'web',
  version: __APP_VERSION__ || '0.0.0',
  publishedAt: __APP_RELEASE_PUBLISHED_AT__ || null,
  buildId: __APP_BUILD_ID__ || 'web-local',
  builtAt: __APP_BUILD_TIME__ || null,
  gitSha: __APP_GIT_SHA__ || null,
};
