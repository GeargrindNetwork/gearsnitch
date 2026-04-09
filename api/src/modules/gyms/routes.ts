import { Router } from 'express';
import { isAuthenticated } from '../../middleware/auth.js';
import { successResponse } from '../../utils/response.js';

const router = Router();

// GET /gyms
router.get('/', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'List gyms — not yet implemented' }, 501);
});

// GET /gyms/nearby
router.get('/nearby', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Find nearby gyms — not yet implemented' }, 501);
});

// GET /gyms/:id
router.get('/:id', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Get gym details — not yet implemented' }, 501);
});

// POST /gyms/:id/check-in
router.post('/:id/check-in', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Gym check-in — not yet implemented' }, 501);
});

export default router;
