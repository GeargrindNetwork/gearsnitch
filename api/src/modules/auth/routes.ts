import { Router } from 'express';
import { successResponse } from '../../utils/response.js';

const router = Router();

// POST /auth/register
router.post('/register', (_req, res) => {
  successResponse(res, { message: 'Registration endpoint — not yet implemented' }, 501);
});

// POST /auth/login
router.post('/login', (_req, res) => {
  successResponse(res, { message: 'Login endpoint — not yet implemented' }, 501);
});

// POST /auth/logout
router.post('/logout', (_req, res) => {
  successResponse(res, { message: 'Logout endpoint — not yet implemented' }, 501);
});

// POST /auth/refresh
router.post('/refresh', (_req, res) => {
  successResponse(res, { message: 'Token refresh endpoint — not yet implemented' }, 501);
});

// POST /auth/forgot-password
router.post('/forgot-password', (_req, res) => {
  successResponse(res, { message: 'Forgot password endpoint — not yet implemented' }, 501);
});

// POST /auth/reset-password
router.post('/reset-password', (_req, res) => {
  successResponse(res, { message: 'Reset password endpoint — not yet implemented' }, 501);
});

// POST /auth/oauth/google
router.post('/oauth/google', (_req, res) => {
  successResponse(res, { message: 'Google OAuth endpoint — not yet implemented' }, 501);
});

// POST /auth/oauth/apple
router.post('/oauth/apple', (_req, res) => {
  successResponse(res, { message: 'Apple OAuth endpoint — not yet implemented' }, 501);
});

// POST /auth/verify-email
router.post('/verify-email', (_req, res) => {
  successResponse(res, { message: 'Email verification endpoint — not yet implemented' }, 501);
});

export default router;
