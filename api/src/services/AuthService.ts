import { OAuth2Client } from 'google-auth-library';
import jwt from 'jsonwebtoken';
import jwksRsa from 'jwks-rsa';
import { createHash } from 'crypto';
import { v4 as uuidv4 } from 'uuid';
import { StatusCodes } from 'http-status-codes';
import { SignJWT, importPKCS8 } from 'jose';
import { User, type IUser } from '../models/User.js';
import { Session } from '../models/Session.js';
import { getRedisClient } from '../loaders/redis.js';
import config from '../config/index.js';
import logger from '../utils/logger.js';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface DeviceInfo {
  deviceName: string;
  platform: 'ios' | 'watchos' | 'web';
  userAgent: string;
  ipAddress: string;
}

export interface GoogleProfile {
  email: string;
  name: string;
  picture?: string;
  googleId: string;
}

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
}

export interface AuthResult {
  accessToken: string;
  refreshToken: string;
  user: IUser;
}

interface AppleTokenExchangeResponse {
  access_token?: string;
  expires_in?: number;
  id_token?: string;
  refresh_token?: string;
  token_type?: string;
  error?: string;
  error_description?: string;
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const ACCESS_TOKEN_TTL = '15m';
const REFRESH_TOKEN_TTL = '7d';
const REFRESH_TOKEN_TTL_SECONDS = 7 * 24 * 60 * 60; // 7 days
const ACCESS_TOKEN_TTL_SECONDS = 15 * 60; // 15 minutes

// ---------------------------------------------------------------------------
// Google OAuth2 Client (singleton)
// ---------------------------------------------------------------------------

let googleClient: OAuth2Client | null = null;

function requireConfiguredValue(value: string, message: string): string {
  if (!value) {
    logger.error(message);
    throw new AuthServiceError(message, StatusCodes.INTERNAL_SERVER_ERROR);
  }

  return value;
}

function getGoogleClient(): OAuth2Client {
  if (!googleClient) {
    googleClient = new OAuth2Client(
      requireConfiguredValue(
        config.googleOAuthClientId,
        'Google OAuth client ID is not configured',
      ),
    );
  }
  return googleClient;
}

// ---------------------------------------------------------------------------
// Apple JWKS Client (singleton, caches keys automatically)
// ---------------------------------------------------------------------------

let appleJwksClient: jwksRsa.JwksClient | null = null;

function getAppleJwksClient(): jwksRsa.JwksClient {
  if (!appleJwksClient) {
    appleJwksClient = jwksRsa({
      jwksUri: 'https://appleid.apple.com/auth/keys',
      cache: true,
      cacheMaxAge: 86_400_000, // 24 hours
      rateLimit: true,
      jwksRequestsPerMinute: 10,
    });
  }
  return appleJwksClient;
}

// ---------------------------------------------------------------------------
// AuthService
// ---------------------------------------------------------------------------

export class AuthService {
  // -----------------------------------------------------------------------
  // Sign In with Google
  // -----------------------------------------------------------------------

  static async signInWithGoogle(
    idToken: string,
    deviceInfo: DeviceInfo,
  ): Promise<AuthResult> {
    const profile = await AuthService.verifyGoogleToken(idToken);

    // Find by googleId first, then by email
    let user = await User.findOne({ googleId: profile.googleId });

    if (!user) {
      // Check if user exists with the same email but different provider
      const emailHash = AuthService.hashEmail(profile.email);
      user = await User.findOne({ emailHash });

      if (user) {
        // Link Google to existing account
        user.googleId = profile.googleId;
        if (!user.authProviders.includes('google')) {
          user.authProviders.push('google');
        }
        if (profile.picture && !user.photoUrl) {
          user.photoUrl = profile.picture;
        }
        await user.save();
      } else {
        // Create new user
        user = await User.create({
          email: profile.email,
          emailHash: emailHash,
          displayName: profile.name || profile.email.split('@')[0],
          photoUrl: profile.picture,
          googleId: profile.googleId,
          authProviders: ['google'],
          roles: ['user'],
          status: 'active',
        });
      }
    } else {
      // Update profile picture if changed
      if (profile.picture && profile.picture !== user.photoUrl) {
        user.photoUrl = profile.picture;
        await user.save();
      }
    }

    await AuthService.reactivateIfNeeded(user);

    const tokenPair = await AuthService.issueTokenPair(
      user._id.toString(),
      user.roles,
      user.email,
    );

    // Create DB session record
    const jti = AuthService.extractJti(tokenPair.accessToken);
    await AuthService.createSession(user._id.toString(), jti, deviceInfo);

    return {
      ...tokenPair,
      user,
    };
  }

  // -----------------------------------------------------------------------
  // Sign In with Apple
  // -----------------------------------------------------------------------

  static async signInWithApple(
    identityToken: string,
    authorizationCode: string,
    fullName: string | undefined,
    deviceInfo: DeviceInfo,
  ): Promise<AuthResult> {
    const decoded = await AuthService.verifyAppleToken(identityToken);
    const exchanged = await AuthService.exchangeAppleAuthorizationCode(
      authorizationCode,
    );

    if (decoded.sub !== exchanged.sub) {
      throw new AuthServiceError(
        'Apple authorization code did not match the identity token',
        StatusCodes.UNAUTHORIZED,
      );
    }

    const appleId = decoded.sub;
    const email = decoded.email ?? exchanged.email;
    const normalizedFullName = fullName?.trim() || undefined;

    let user = await User.findOne({ appleId });

    if (user) {
      let shouldSave = false;

      if (!user.authProviders.includes('apple')) {
        user.authProviders.push('apple');
        shouldSave = true;
      }

      if (normalizedFullName && !user.displayName) {
        user.displayName = normalizedFullName;
        shouldSave = true;
      }

      if (shouldSave) {
        await user.save();
      }
    } else {
      if (!email) {
        throw new AuthServiceError(
          'Apple account email unavailable for first-time sign in',
          StatusCodes.UNAUTHORIZED,
        );
      }

      const emailHash = AuthService.hashEmail(email);
      user = await User.findOne({ emailHash });

      if (user) {
        user.appleId = appleId;
        if (!user.authProviders.includes('apple')) {
          user.authProviders.push('apple');
        }
        if (normalizedFullName && !user.displayName) {
          user.displayName = normalizedFullName;
        }
        await user.save();
      } else {
        user = await User.create({
          email,
          emailHash: emailHash,
          displayName: normalizedFullName || email.split('@')[0],
          appleId,
          authProviders: ['apple'],
          roles: ['user'],
          status: 'active',
        });
      }
    }

    await AuthService.reactivateIfNeeded(user);

    const tokenPair = await AuthService.issueTokenPair(
      user._id.toString(),
      user.roles,
      user.email,
    );

    const jti = AuthService.extractJti(tokenPair.accessToken);
    await AuthService.createSession(user._id.toString(), jti, deviceInfo);

    return {
      ...tokenPair,
      user,
    };
  }

  // -----------------------------------------------------------------------
  // Refresh Token
  // -----------------------------------------------------------------------

  static async refreshToken(refreshTokenValue: string): Promise<TokenPair> {
    const redis = getRedisClient();

    // Verify the refresh token
    let decoded: { sub: string; jti: string; type: string };
    try {
      const signingKey = config.isProduction
        ? config.jwtPublicKey
        : config.jwtPrivateKey;
      const algorithm = config.isProduction ? 'RS256' : 'HS256';

      decoded = jwt.verify(refreshTokenValue, signingKey, {
        algorithms: [algorithm],
      }) as typeof decoded;
    } catch {
      throw new AuthServiceError(
        'Invalid or expired refresh token',
        StatusCodes.UNAUTHORIZED,
      );
    }

    if (decoded.type !== 'refresh') {
      throw new AuthServiceError(
        'Invalid token type',
        StatusCodes.UNAUTHORIZED,
      );
    }

    // Check that the refresh token is still whitelisted
    const refreshKey = `refresh:${decoded.sub}:${decoded.jti}`;
    const exists = await redis.exists(refreshKey);
    if (!exists) {
      throw new AuthServiceError(
        'Refresh token revoked or expired',
        StatusCodes.UNAUTHORIZED,
      );
    }

    // Revoke the old refresh token (rotation)
    await redis.del(refreshKey);

    // Look up user to get current roles
    const user = await User.findById(decoded.sub).lean();
    if (!user) {
      throw new AuthServiceError('User not found', StatusCodes.UNAUTHORIZED);
    }

    // Issue new pair
    const newPair = await AuthService.issueTokenPair(
      decoded.sub,
      user.roles,
      user.email,
    );

    // Update session in DB with new jti
    const newJti = AuthService.extractJti(newPair.accessToken);
    await Session.findOneAndUpdate(
      { userId: decoded.sub, jti: decoded.jti, revokedAt: null },
      { jti: newJti, expiresAt: new Date(Date.now() + REFRESH_TOKEN_TTL_SECONDS * 1000) },
    );

    return newPair;
  }

  // -----------------------------------------------------------------------
  // Logout (single session)
  // -----------------------------------------------------------------------

  static async logout(userId: string, jti: string): Promise<void> {
    const redis = getRedisClient();

    // Remove session from Redis whitelist
    const sessionKey = `session:${userId}:${jti}`;
    const refreshKey = `refresh:${userId}:${jti}`;
    await redis.del(sessionKey, refreshKey);

    // Revoke session in DB
    await Session.findOneAndUpdate(
      { userId, jti, revokedAt: null },
      { revokedAt: new Date() },
    );

    logger.info('User session revoked', { userId, jti });
  }

  // -----------------------------------------------------------------------
  // Logout All
  // -----------------------------------------------------------------------

  static async logoutAll(userId: string): Promise<void> {
    const redis = getRedisClient();

    // Find all active sessions for user
    const sessions = await Session.find({
      userId,
      revokedAt: null,
    }).lean();

    // Remove all from Redis
    const keys: string[] = [];
    for (const session of sessions) {
      keys.push(`session:${userId}:${session.jti}`);
      keys.push(`refresh:${userId}:${session.jti}`);
    }
    if (keys.length > 0) {
      await redis.del(...keys);
    }

    // Revoke all sessions in DB
    await Session.updateMany(
      { userId, revokedAt: null },
      { revokedAt: new Date() },
    );

    logger.info('All sessions revoked for user', { userId });
  }

  // -----------------------------------------------------------------------
  // Get Me
  // -----------------------------------------------------------------------

  static async getMe(userId: string): Promise<IUser> {
    const user = await User.findById(userId);
    if (!user) {
      throw new AuthServiceError('User not found', StatusCodes.NOT_FOUND);
    }
    return user;
  }

  // -----------------------------------------------------------------------
  // Private Helpers
  // -----------------------------------------------------------------------

  private static async verifyGoogleToken(
    idToken: string,
  ): Promise<GoogleProfile> {
    const client = getGoogleClient();
    try {
      const ticket = await client.verifyIdToken({
        idToken,
        audience: config.googleOAuthClientId,
      });

      const payload = ticket.getPayload();
      if (!payload || !payload.email) {
        throw new Error('Missing email in Google token payload');
      }

      return {
        email: payload.email,
        name: payload.name ?? payload.email.split('@')[0],
        picture: payload.picture,
        googleId: payload.sub,
      };
    } catch (err) {
      logger.error('Google token verification failed', {
        error: err instanceof Error ? err.message : String(err),
      });
      throw new AuthServiceError(
        'Invalid Google ID token',
        StatusCodes.UNAUTHORIZED,
      );
    }
  }

  private static async verifyAppleToken(
    identityToken: string,
  ): Promise<{ sub: string; email?: string }> {
    try {
      const appleClientId = requireConfiguredValue(
        config.appleClientId,
        'Apple OAuth client ID is not configured',
      );

      // Decode the header to get the key ID (kid)
      const header = jwt.decode(identityToken, { complete: true })?.header;
      if (!header?.kid) {
        throw new Error('Missing kid in token header');
      }

      // Fetch the matching signing key from Apple's JWKS endpoint
      const client = getAppleJwksClient();
      const signingKey = await client.getSigningKey(header.kid);
      const publicKey = signingKey.getPublicKey();

      // Verify the token signature and claims
      const payload = jwt.verify(identityToken, publicKey, {
        algorithms: ['RS256'],
        issuer: 'https://appleid.apple.com',
        audience: appleClientId,
      }) as {
        sub?: string;
        email?: string;
        email_verified?: string | boolean;
        iss?: string;
        aud?: string;
      };

      if (!payload.sub) {
        throw new Error('Missing sub in Apple token payload');
      }

      return { sub: payload.sub, email: payload.email };
    } catch (err) {
      logger.error('Apple token verification failed', {
        error: err instanceof Error ? err.message : String(err),
      });
      throw new AuthServiceError(
        'Invalid Apple identity token',
        StatusCodes.UNAUTHORIZED,
      );
    }
  }

  private static async exchangeAppleAuthorizationCode(
    authorizationCode: string,
  ): Promise<{ sub: string; email?: string }> {
    try {
      const appleClientId = requireConfiguredValue(
        config.appleClientId,
        'Apple OAuth client ID is not configured',
      );
      const appleTeamId = requireConfiguredValue(
        config.appleTeamId,
        'Apple OAuth team ID is not configured',
      );
      const appleKeyId = requireConfiguredValue(
        config.appleKeyId,
        'Apple OAuth key ID is not configured',
      );
      const applePrivateKey = AuthService.normalizePemKey(
        requireConfiguredValue(
          config.applePrivateKey,
          'Apple OAuth private key is not configured',
        ),
      );

      const clientSecret = await AuthService.createAppleClientSecret({
        appleClientId,
        appleTeamId,
        appleKeyId,
        applePrivateKey,
      });

      const response = await fetch('https://appleid.apple.com/auth/token', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: new URLSearchParams({
          grant_type: 'authorization_code',
          code: authorizationCode,
          client_id: appleClientId,
          client_secret: clientSecret,
        }),
      });

      const payload = await response.json() as AppleTokenExchangeResponse;
      if (!response.ok || !payload.id_token) {
        logger.error('Apple authorization code exchange failed', {
          status: response.status,
          error: payload.error ?? payload.error_description ?? 'unknown',
        });
        throw new AuthServiceError(
          payload.error_description
            ?? payload.error
            ?? 'Apple authorization code exchange failed',
          StatusCodes.UNAUTHORIZED,
        );
      }

      return AuthService.verifyAppleToken(payload.id_token);
    } catch (err) {
      if (err instanceof AuthServiceError) {
        throw err;
      }

      logger.error('Apple authorization code exchange failed', {
        error: err instanceof Error ? err.message : String(err),
      });
      throw new AuthServiceError(
        'Apple authorization code exchange failed',
        StatusCodes.UNAUTHORIZED,
      );
    }
  }

  private static async createAppleClientSecret({
    appleClientId,
    appleTeamId,
    appleKeyId,
    applePrivateKey,
  }: {
    appleClientId: string;
    appleTeamId: string;
    appleKeyId: string;
    applePrivateKey: string;
  }): Promise<string> {
    const signingKey = await importPKCS8(applePrivateKey, 'ES256');

    return new SignJWT({})
      .setProtectedHeader({ alg: 'ES256', kid: appleKeyId })
      .setIssuer(appleTeamId)
      .setSubject(appleClientId)
      .setAudience('https://appleid.apple.com')
      .setIssuedAt()
      .setExpirationTime('5m')
      .sign(signingKey);
  }

  private static normalizePemKey(value: string): string {
    return value.replace(/\\n/g, '\n');
  }

  private static async issueTokenPair(
    userId: string,
    roles: string[],
    email: string,
  ): Promise<TokenPair> {
    const jti = uuidv4();
    const signingKey = config.isProduction
      ? config.jwtPrivateKey
      : config.jwtPrivateKey;
    const algorithm = config.isProduction ? 'RS256' : 'HS256';

    if (!signingKey) {
      throw new AuthServiceError(
        'JWT signing key not configured',
        StatusCodes.INTERNAL_SERVER_ERROR,
      );
    }

    const accessToken = jwt.sign(
      {
        sub: userId,
        email,
        role: roles[0] ?? 'user',
        scope: AuthService.scopesForRole(roles[0] ?? 'user'),
        jti,
      },
      signingKey,
      {
        algorithm,
        expiresIn: ACCESS_TOKEN_TTL,
      },
    );

    const refreshToken = jwt.sign(
      {
        sub: userId,
        jti,
        type: 'refresh',
      },
      signingKey,
      {
        algorithm,
        expiresIn: REFRESH_TOKEN_TTL,
      },
    );

    // Whitelist session in Redis
    await AuthService.whitelistSession(userId, jti, ACCESS_TOKEN_TTL_SECONDS);

    // Whitelist refresh token in Redis
    const redis = getRedisClient();
    const refreshKey = `refresh:${userId}:${jti}`;
    await redis.set(refreshKey, '1', 'EX', REFRESH_TOKEN_TTL_SECONDS);

    return { accessToken, refreshToken };
  }

  private static async reactivateIfNeeded(user: IUser): Promise<void> {
    if (user.status !== 'deletion_requested') {
      return;
    }

    user.status = 'active';
    user.deletionRequestedAt = null;
    user.deletionScheduledFor = null;
    user.deletedAt = null;
    await user.save();
  }

  private static async whitelistSession(
    userId: string,
    jti: string,
    expiresIn: number,
  ): Promise<void> {
    const redis = getRedisClient();
    // Use the last 8 chars of the access token as the session key suffix
    // to match the auth middleware lookup pattern
    const sessionKey = `session:${userId}:${jti}`;
    await redis.set(sessionKey, '1', 'EX', expiresIn);
  }

  private static async createSession(
    userId: string,
    jti: string,
    deviceInfo: DeviceInfo,
  ): Promise<void> {
    await Session.create({
      userId,
      jti,
      deviceName: deviceInfo.deviceName,
      platform: deviceInfo.platform,
      ipAddress: deviceInfo.ipAddress,
      userAgent: deviceInfo.userAgent,
      expiresAt: new Date(Date.now() + REFRESH_TOKEN_TTL_SECONDS * 1000),
    });
  }

  private static extractJti(token: string): string {
    const decoded = jwt.decode(token) as { jti: string };
    return decoded.jti;
  }

  private static hashEmail(email: string): string {
    return createHash('sha256')
      .update(email.toLowerCase().trim())
      .digest('hex');
  }

  private static scopesForRole(role: string): string[] {
    switch (role) {
      case 'admin':
        return ['read', 'write', 'admin'];
      case 'support':
        return ['read', 'write'];
      case 'auditor':
        return ['read'];
      default:
        return ['read', 'write'];
    }
  }
}

// ---------------------------------------------------------------------------
// Error class
// ---------------------------------------------------------------------------

export class AuthServiceError extends Error {
  public statusCode: number;

  constructor(message: string, statusCode: number) {
    super(message);
    this.name = 'AuthServiceError';
    this.statusCode = statusCode;
  }
}
