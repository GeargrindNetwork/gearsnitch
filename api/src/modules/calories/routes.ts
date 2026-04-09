import { Router } from 'express';
import { isAuthenticated } from '../../middleware/auth.js';
import { successResponse } from '../../utils/response.js';

const router = Router();

// GET /calories
router.get('/', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Get calorie data — not yet implemented' }, 501);
});

// POST /calories
router.post('/', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Log calories — not yet implemented' }, 501);
});

// GET /calories/summary
router.get('/summary', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Get calorie summary — not yet implemented' }, 501);
});

// DELETE /calories/:id
router.delete('/:id', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Delete calorie entry — not yet implemented' }, 501);
});

export default router;
