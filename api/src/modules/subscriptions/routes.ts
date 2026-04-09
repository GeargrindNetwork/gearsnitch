import { Router } from 'express';
import { isAuthenticated } from '../../middleware/auth.js';
import { successResponse } from '../../utils/response.js';

const router = Router();

// GET /subscriptions
router.get('/', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Get subscription status — not yet implemented' }, 501);
});

// POST /subscriptions
router.post('/', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Create subscription — not yet implemented' }, 501);
});

// PATCH /subscriptions
router.patch('/', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Update subscription — not yet implemented' }, 501);
});

// DELETE /subscriptions
router.delete('/', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Cancel subscription — not yet implemented' }, 501);
});

export default router;
