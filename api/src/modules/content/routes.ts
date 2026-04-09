import { Router } from 'express';
import { isAuthenticated } from '../../middleware/auth.js';
import { successResponse } from '../../utils/response.js';

const router = Router();

// GET /content/articles
router.get('/articles', (_req, res) => {
  successResponse(res, { message: 'List articles — not yet implemented' }, 501);
});

// GET /content/articles/:id
router.get('/articles/:id', (_req, res) => {
  successResponse(res, { message: 'Get article — not yet implemented' }, 501);
});

// GET /content/tips
router.get('/tips', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Get tips — not yet implemented' }, 501);
});

// GET /content/featured
router.get('/featured', (_req, res) => {
  successResponse(res, { message: 'Get featured content — not yet implemented' }, 501);
});

export default router;
