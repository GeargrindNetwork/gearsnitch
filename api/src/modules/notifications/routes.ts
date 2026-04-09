import { Router } from 'express';
import { isAuthenticated } from '../../middleware/auth.js';
import { successResponse } from '../../utils/response.js';

const router = Router();

// GET /notifications
router.get('/', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'List notifications — not yet implemented' }, 501);
});

// PATCH /notifications/:id/read
router.patch('/:id/read', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Mark notification as read — not yet implemented' }, 501);
});

// POST /notifications/read-all
router.post('/read-all', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Mark all notifications as read — not yet implemented' }, 501);
});

// GET /notifications/preferences
router.get('/preferences', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Get notification preferences — not yet implemented' }, 501);
});

// PATCH /notifications/preferences
router.patch('/preferences', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Update notification preferences — not yet implemented' }, 501);
});

export default router;
