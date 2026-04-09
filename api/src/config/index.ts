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
  googleOAuthClientId: process.env.GOOGLE_OAUTH_CLIENT_ID ?? '',
  googleOAuthClientSecret: process.env.GOOGLE_OAUTH_CLIENT_SECRET ?? '',

  // OAuth — Apple
  appleClientId: process.env.APPLE_CLIENT_ID ?? '',
  appleTeamId: process.env.APPLE_TEAM_ID ?? '',
  appleKeyId: process.env.APPLE_KEY_ID ?? '',

  // CORS
  corsOrigins: process.env.CORS_ORIGINS?.split(',').map((o) => o.trim()) ?? [
    'http://localhost:3000',
  ],

  // API
  apiVersion: process.env.API_VERSION ?? 'v1',
} as const;

export default config;
