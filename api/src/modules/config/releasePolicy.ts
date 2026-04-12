import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import type { Request } from 'express';
import { z } from 'zod';
import config from '../../config/index.js';

const releasePolicySchema = z.object({
  version: z.string().min(1),
  minimumSupportedVersion: z.string().min(1),
  forceUpgrade: z.boolean().default(false),
  publishedAt: z.string().min(1),
  releaseNotes: z.array(z.string()).default([]),
  environment: z.string().default('production'),
});

export type ReleasePolicy = z.infer<typeof releasePolicySchema>;

export interface ClientReleaseHeaders {
  platform: string | null;
  version: string | null;
  build: string | null;
}

export interface ReleaseCompatibility {
  status: 'supported' | 'blocked' | 'unknown';
  reason: string | null;
  clientVersion: string | null;
  minimumSupportedVersion: string;
  currentVersion: string;
  forceUpgrade: boolean;
  platform: string | null;
  build: string | null;
}

export interface ServerBuildInfo {
  version: string;
  buildId: string | null;
  gitSha: string | null;
  builtAt: string | null;
  environment: string;
}

function findReleasePolicyPath(): string {
  const candidates = [
    path.resolve(process.cwd(), 'config/release-policy.json'),
    path.resolve(process.cwd(), '../config/release-policy.json'),
  ];

  for (const candidate of candidates) {
    if (existsSync(candidate)) {
      return candidate;
    }
  }

  throw new Error(
    `Release policy file not found. Checked: ${candidates.join(', ')}`,
  );
}

function loadReleasePolicy(): ReleasePolicy {
  const filePath = findReleasePolicyPath();
  const raw = JSON.parse(readFileSync(filePath, 'utf8'));
  return releasePolicySchema.parse(raw);
}

const releasePolicy = loadReleasePolicy();

function parseSemanticVersion(value: string): [number, number, number] {
  const [coreVersion] = value.split('-');
  const parts = coreVersion.split('.').slice(0, 3).map((segment) => {
    const normalized = segment.replace(/[^0-9].*$/, '');
    const parsed = Number.parseInt(normalized, 10);
    return Number.isFinite(parsed) ? parsed : 0;
  });

  while (parts.length < 3) {
    parts.push(0);
  }

  return [parts[0] ?? 0, parts[1] ?? 0, parts[2] ?? 0];
}

export function compareSemanticVersions(left: string, right: string): number {
  const leftParts = parseSemanticVersion(left);
  const rightParts = parseSemanticVersion(right);

  for (let index = 0; index < 3; index += 1) {
    if (leftParts[index] > rightParts[index]) {
      return 1;
    }
    if (leftParts[index] < rightParts[index]) {
      return -1;
    }
  }

  return 0;
}

export function getReleasePolicy(): ReleasePolicy {
  return { ...releasePolicy, releaseNotes: [...releasePolicy.releaseNotes] };
}

export function getClientReleaseHeaders(req: Request): ClientReleaseHeaders {
  const getHeader = (name: string): string | null => {
    const value = req.get(name)?.trim();
    return value ? value : null;
  };

  return {
    platform: getHeader('X-Client-Platform'),
    version: getHeader('X-Client-Version'),
    build: getHeader('X-Client-Build'),
  };
}

export function resolveReleaseCompatibility(
  client: ClientReleaseHeaders,
  policy: ReleasePolicy = releasePolicy,
): ReleaseCompatibility {
  if (!client.version) {
    return {
      status: 'unknown',
      reason: 'missing_client_version',
      clientVersion: null,
      minimumSupportedVersion: policy.minimumSupportedVersion,
      currentVersion: policy.version,
      forceUpgrade: policy.forceUpgrade,
      platform: client.platform,
      build: client.build,
    };
  }

  const comparison = compareSemanticVersions(
    client.version,
    policy.minimumSupportedVersion,
  );

  return {
    status: comparison < 0 ? 'blocked' : 'supported',
    reason: comparison < 0 ? 'below_minimum_supported_version' : null,
    clientVersion: client.version,
    minimumSupportedVersion: policy.minimumSupportedVersion,
    currentVersion: policy.version,
    forceUpgrade: policy.forceUpgrade,
    platform: client.platform,
    build: client.build,
  };
}

export function getServerBuildInfo(
  policy: ReleasePolicy = releasePolicy,
): ServerBuildInfo {
  return {
    version: policy.version,
    buildId: config.releaseBuildId || null,
    gitSha: config.releaseGitSha || null,
    builtAt: config.releaseBuiltAt || null,
    environment: policy.environment,
  };
}
