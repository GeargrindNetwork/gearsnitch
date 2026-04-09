import { Router } from 'express';
import { isAuthenticated } from '../../middleware/auth.js';
import { successResponse } from '../../utils/response.js';

const router = Router();

// GET /devices
router.get('/', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'List devices — not yet implemented' }, 501);
});

// POST /devices
router.post('/', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Register device — not yet implemented' }, 501);
});

// GET /devices/:id
router.get('/:id', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Get device — not yet implemented' }, 501);
});

// PATCH /devices/:id
router.patch('/:id', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Update device — not yet implemented' }, 501);
});

// DELETE /devices/:id
router.delete('/:id', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Remove device — not yet implemented' }, 501);
});

export default router;
