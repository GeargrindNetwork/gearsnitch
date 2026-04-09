import { Router } from 'express';
import { isAuthenticated } from '../../middleware/auth.js';
import { successResponse } from '../../utils/response.js';

const router = Router();

// GET /workouts
router.get('/', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'List workouts — not yet implemented' }, 501);
});

// POST /workouts
router.post('/', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Create workout — not yet implemented' }, 501);
});

// GET /workouts/:id
router.get('/:id', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Get workout — not yet implemented' }, 501);
});

// PATCH /workouts/:id
router.patch('/:id', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Update workout — not yet implemented' }, 501);
});

// DELETE /workouts/:id
router.delete('/:id', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Delete workout — not yet implemented' }, 501);
});

// POST /workouts/:id/complete
router.post('/:id/complete', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Complete workout — not yet implemented' }, 501);
});

export default router;
