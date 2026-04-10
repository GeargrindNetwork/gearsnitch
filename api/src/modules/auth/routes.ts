import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { StatusCodes } from 'http-status-codes';
import { successResponse, errorResponse } from '../../utils/response.js';
import { validateBody } from '../../middleware/validate.js';
import { isAuthenticated, type JwtPayload } from '../../middleware/auth.js';
import { AuthService, AuthServiceError, type DeviceInfo } from '../../services/AuthService.js';

const router = Router();

// ---------------------------------------------------------------------------
// Validation Schemas
// ---------------------------------------------------------------------------

const googleOAuthSchema = z.object({
  idToken: z.string().min(1, 'idToken is required'),
});

const appleOAuthSchema = z.object({
  identityToken: z.string().min(1, 'identityToken is required'),
  authorizationCode: z.string().min(1, 'authorizationCode is required'),
  fullName: z.string().optional(),
});

const refreshSchema = z.object({
  refreshToken: z.string().min(1, 'refreshToken is required'),
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function extractDeviceInfo(req: Request): DeviceInfo {
  return {
    deviceName: (req.headers['x-device-name'] as string) || 'Unknown Device',
    platform: ((req.headers['x-client-platform'] as string) || 'ios') as DeviceInfo['platform'],
    userAgent: req.headers['user-agent'] || 'Unknown',
    ipAddress: (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim()
      || req.socket.remoteAddress
      || '0.0.0.0',
  };
}

function handleServiceError(res: Response, err: unknown): void {
  if (err instanceof AuthServiceError) {
    errorResponse(res, err.statusCode, err.message);
    return;
  }
  errorResponse(
    res,
    StatusCodes.INTERNAL_SERVER_ERROR,
    'An unexpected error occurred',
  );
}

// ---------------------------------------------------------------------------
// POST /auth/oauth/google
// ---------------------------------------------------------------------------

router.post(
  '/oauth/google',
  validateBody(googleOAuthSchema),
  async (req: Request, res: Response) => {
    try {
      const { idToken } = req.body as z.infer<typeof googleOAuthSchema>;
      const deviceInfo = extractDeviceInfo(req);

      const result = await AuthService.signInWithGoogle(idToken, deviceInfo);

      // Set refresh token as httpOnly cookie
      res.cookie('refreshToken', result.refreshToken, {
        httpOnly: true,
        secure: true,
        sameSite: 'strict',
        maxAge: 7 * 24 * 60 * 60 * 1000, // 7 days
        path: '/api/v1/auth',
      });

      successResponse(res, {
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        user: sanitizeUser(result.user),
      });
    } catch (err) {
      handleServiceError(res, err);
    }
  },
);

// ---------------------------------------------------------------------------
// POST /auth/oauth/apple
// ---------------------------------------------------------------------------

router.post(
  '/oauth/apple',
  validateBody(appleOAuthSchema),
  async (req: Request, res: Response) => {
    try {
      const { identityToken, authorizationCode, fullName } =
        req.body as z.infer<typeof appleOAuthSchema>;
      const deviceInfo = extractDeviceInfo(req);

      const result = await AuthService.signInWithApple(
        identityToken,
        authorizationCode,
        fullName,
        deviceInfo,
      );

      res.cookie('refreshToken', result.refreshToken, {
        httpOnly: true,
        secure: true,
        sameSite: 'strict',
        maxAge: 7 * 24 * 60 * 60 * 1000,
        path: '/api/v1/auth',
      });

      successResponse(res, {
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        user: sanitizeUser(result.user),
      });
    } catch (err) {
      handleServiceError(res, err);
    }
  },
);

// ---------------------------------------------------------------------------
// POST /auth/refresh
// ---------------------------------------------------------------------------

router.post(
  '/refresh',
  validateBody(refreshSchema.partial()),
  async (req: Request, res: Response) => {
    try {
      // Accept refresh token from body or cookie
      const refreshToken =
        (req.body as { refreshToken?: string }).refreshToken
        || req.cookies?.refreshToken;

      if (!refreshToken) {
        errorResponse(
          res,
          StatusCodes.BAD_REQUEST,
          'Refresh token is required (body or cookie)',
        );
        return;
      }

      const tokenPair = await AuthService.refreshToken(refreshToken);

      res.cookie('refreshToken', tokenPair.refreshToken, {
        httpOnly: true,
        secure: true,
        sameSite: 'strict',
        maxAge: 7 * 24 * 60 * 60 * 1000,
        path: '/api/v1/auth',
      });

      successResponse(res, {
        accessToken: tokenPair.accessToken,
        refreshToken: tokenPair.refreshToken,
      });
    } catch (err) {
      handleServiceError(res, err);
    }
  },
);

// ---------------------------------------------------------------------------
// POST /auth/logout
// ---------------------------------------------------------------------------

router.post('/logout', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const user = req.user as JwtPayload;
    await AuthService.logout(user.sub, user.jti);

    // Clear the refresh token cookie
    res.clearCookie('refreshToken', {
      httpOnly: true,
      secure: true,
      sameSite: 'strict',
      path: '/api/v1/auth',
    });

    successResponse(res, { message: 'Logged out successfully' });
  } catch (err) {
    handleServiceError(res, err);
  }
});

// ---------------------------------------------------------------------------
// GET /auth/me
// ---------------------------------------------------------------------------

router.get('/me', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const user = req.user as JwtPayload;
    const profile = await AuthService.getMe(user.sub);
    successResponse(res, sanitizeUser(profile));
  } catch (err) {
    handleServiceError(res, err);
  }
});

// ---------------------------------------------------------------------------
// Sanitize user for API response
// ---------------------------------------------------------------------------

function sanitizeUser(user: { _id?: unknown; email?: string; displayName?: string; photoUrl?: string; roles?: string[]; status?: string; defaultGymId?: unknown; onboardingCompletedAt?: Date | null; permissionsState?: unknown; preferences?: unknown }) {
  return {
    _id: String(user._id),
    email: user.email,
    displayName: user.displayName,
    avatarURL: user.photoUrl,
    role: user.roles?.[0] ?? 'user',
    status: user.status,
    defaultGymId: user.defaultGymId ? String(user.defaultGymId) : null,
    onboardingCompletedAt: user.onboardingCompletedAt,
    permissionsState: user.permissionsState,
    preferences: user.preferences,
  };
}

export default router;
