import { Router } from 'express';
import { isAuthenticated } from '../../middleware/auth.js';
import { successResponse } from '../../utils/response.js';

const router = Router();

// GET /alerts
router.get('/', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'List alerts — not yet implemented' }, 501);
});

// POST /alerts
router.post('/', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Create alert — not yet implemented' }, 501);
});

// PATCH /alerts/:id
router.patch('/:id', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Update alert — not yet implemented' }, 501);
});

// DELETE /alerts/:id
router.delete('/:id', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Delete alert — not yet implemented' }, 501);
});

export default router;
