import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';

function loadLocalEnv(): void {
  const candidates = [
    path.resolve(process.cwd(), '.env'),
    path.resolve(process.cwd(), 'api/.env'),
  ];

  for (const envPath of candidates) {
    if (!existsSync(envPath)) {
      continue;
    }

    const file = readFileSync(envPath, 'utf8');
    for (const rawLine of file.split(/\r?\n/)) {
      const line = rawLine.trim();
      if (!line || line.startsWith('#')) {
        continue;
      }

      const separator = line.indexOf('=');
      if (separator <= 0) {
        continue;
      }

      const key = line.slice(0, separator).trim();
      let value = line.slice(separator + 1).trim();

      if (
        (value.startsWith('"') && value.endsWith('"'))
        || (value.startsWith("'") && value.endsWith("'"))
      ) {
        value = value.slice(1, -1);
      }

      if (!(key in process.env)) {
        process.env[key] = value;
      }
    }

    return;
  }
}

loadLocalEnv();

function parseEnvList(...values: Array<string | undefined>): string[] {
  return Array.from(
    new Set(
      values
        .flatMap((value) => (value ?? '').split(','))
        .map((value) => value.trim())
        .filter(Boolean),
    ),
  );
}

const googleOAuthClientIds = parseEnvList(
  process.env.GOOGLE_OAUTH_CLIENT_IDS,
  process.env.GOOGLE_OAUTH_CLIENT_ID,
);

const appleClientIds = parseEnvList(
  process.env.APPLE_CLIENT_IDS,
  process.env.APPLE_CLIENT_ID,
);

const config = {
  port: parseInt(process.env.PORT ?? '4000', 10),
  nodeEnv: process.env.NODE_ENV ?? 'development',
  isProduction: process.env.NODE_ENV === 'production',
  isDevelopment: process.env.NODE_ENV !== 'production',

  // Database
  mongodbUri: process.env.MONGODB_URI ?? '',
  redisUrl: process.env.REDIS_URL ?? '',

  // JWT
  jwtPrivateKey: process.env.JWT_PRIVATE_KEY ?? '',
  jwtPublicKey: process.env.JWT_PUBLIC_KEY ?? '',

  // OAuth — Google
  googleOAuthClientId: googleOAuthClientIds[0] ?? '',
  googleOAuthClientIds,
  googleOAuthClientSecret: process.env.GOOGLE_OAUTH_CLIENT_SECRET ?? '',

  // OAuth — Apple
  appleClientId: appleClientIds[0] ?? '',
  appleClientIds,
  appleTeamId: process.env.APPLE_TEAM_ID ?? '',
  appleKeyId: process.env.APPLE_KEY_ID ?? '',
  applePrivateKey: process.env.APPLE_PRIVATE_KEY ?? '',

  // Stripe
  stripeSecretKey: process.env.STRIPE_SECRET_KEY ?? '',
  stripeWebhookSecret: process.env.STRIPE_WEBHOOK_SECRET ?? '',
  stripePublishableKey: process.env.STRIPE_PUBLISHABLE_KEY ?? '',

  // Stripe — web subscription Price IDs (created via scripts/setup-stripe-products.sh).
  // Each `price_xxx` corresponds to one tier surfaced on the public /subscribe page.
  // Env vars are the source of truth so live IDs never land in the repo.
  stripePriceHustle: process.env.STRIPE_PRICE_HUSTLE ?? '',
  stripePriceHwmf: process.env.STRIPE_PRICE_HWMF ?? '',
  stripePriceBabyMomma: process.env.STRIPE_PRICE_BABY_MOMMA ?? '',

  // CORS
  corsOrigins: process.env.CORS_ORIGINS?.split(',').map((o) => o.trim()) ?? [
    'http://localhost:3000',
  ],

  // API
  apiVersion: process.env.API_VERSION ?? 'v1',

  // Release metadata
  releaseBuildId: process.env.K_REVISION ?? process.env.RELEASE_BUILD_ID ?? '',
  releaseGitSha: process.env.GIT_SHA ?? '',
  releaseBuiltAt: process.env.BUILD_TIME ?? '',
} as const;

export default config;
