import { Router } from 'express';
import { isAuthenticated } from '../../middleware/auth.js';
import { successResponse } from '../../utils/response.js';

const router = Router();

// GET /health
router.get('/', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Get health data — not yet implemented' }, 501);
});

// POST /health/sync
router.post('/sync', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Sync health data — not yet implemented' }, 501);
});

// GET /health/metrics
router.get('/metrics', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Get health metrics — not yet implemented' }, 501);
});

// GET /health/history
router.get('/history', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Get health history — not yet implemented' }, 501);
});

export default router;
