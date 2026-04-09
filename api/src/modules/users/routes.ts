import { Router } from 'express';
import { isAuthenticated } from '../../middleware/auth.js';
import { successResponse } from '../../utils/response.js';

const router = Router();

// GET /users/me
router.get('/me', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Get current user — not yet implemented' }, 501);
});

// PATCH /users/me
router.patch('/me', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Update current user — not yet implemented' }, 501);
});

// DELETE /users/me
router.delete('/me', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Delete current user — not yet implemented' }, 501);
});

// GET /users/:id
router.get('/:id', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Get user by ID — not yet implemented' }, 501);
});

export default router;
