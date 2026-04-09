import { Router } from 'express';
import { isAuthenticated } from '../../middleware/auth.js';
import { successResponse } from '../../utils/response.js';

const router = Router();

// POST /support/tickets
router.post('/tickets', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Create support ticket — not yet implemented' }, 501);
});

// GET /support/tickets
router.get('/tickets', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'List support tickets — not yet implemented' }, 501);
});

// GET /support/tickets/:id
router.get('/tickets/:id', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Get support ticket — not yet implemented' }, 501);
});

// GET /support/faq
router.get('/faq', (_req, res) => {
  successResponse(res, { message: 'Get FAQ — not yet implemented' }, 501);
});

export default router;
