import { Router } from 'express';
import { isAuthenticated } from '../../middleware/auth.js';
import { successResponse } from '../../utils/response.js';

const router = Router();

// GET /referrals
router.get('/', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'List referrals — not yet implemented' }, 501);
});

// POST /referrals/generate
router.post('/generate', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Generate referral code — not yet implemented' }, 501);
});

// POST /referrals/redeem
router.post('/redeem', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Redeem referral code — not yet implemented' }, 501);
});

export default router;
