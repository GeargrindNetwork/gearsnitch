import { Router } from 'express';
import { isAuthenticated, hasRole } from '../../middleware/auth.js';
import { successResponse } from '../../utils/response.js';

const router = Router();

// All admin routes require authentication + admin role
router.use(isAuthenticated, hasRole(['admin']));

// GET /admin/users
router.get('/users', (_req, res) => {
  successResponse(res, { message: 'Admin list users — not yet implemented' }, 501);
});

// GET /admin/stats
router.get('/stats', (_req, res) => {
  successResponse(res, { message: 'Admin stats — not yet implemented' }, 501);
});

// PATCH /admin/users/:id
router.patch('/users/:id', (_req, res) => {
  successResponse(res, { message: 'Admin update user — not yet implemented' }, 501);
});

// DELETE /admin/users/:id
router.delete('/users/:id', (_req, res) => {
  successResponse(res, { message: 'Admin delete user — not yet implemented' }, 501);
});

export default router;
