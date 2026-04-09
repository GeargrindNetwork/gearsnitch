import { Router } from 'express';
import { isAuthenticated } from '../../middleware/auth.js';
import { successResponse } from '../../utils/response.js';

const router = Router();

// GET /config — public app config (feature flags, minimum version, etc.)
router.get('/', (_req, res) => {
  successResponse(res, { message: 'Get app config — not yet implemented' }, 501);
});

// GET /config/features
router.get('/features', (_req, res) => {
  successResponse(res, { message: 'Get feature flags — not yet implemented' }, 501);
});

// GET /config/user
router.get('/user', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Get user config — not yet implemented' }, 501);
});

export default router;
