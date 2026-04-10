import { Router } from 'express';
import { isAuthenticated } from '../../middleware/auth.js';
import { successResponse } from '../../utils/response.js';
import paymentRoutes from './paymentRoutes.js';

const router = Router();

// Payment routes
router.use('/payments', paymentRoutes);

// GET /store/products
router.get('/products', (_req, res) => {
  successResponse(res, { message: 'List store products — not yet implemented' }, 501);
});

// GET /store/products/:id
router.get('/products/:id', (_req, res) => {
  successResponse(res, { message: 'Get product details — not yet implemented' }, 501);
});

// POST /store/cart
router.post('/cart', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Add to cart — not yet implemented' }, 501);
});

// GET /store/cart
router.get('/cart', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Get cart — not yet implemented' }, 501);
});

// POST /store/checkout
router.post('/checkout', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Checkout — not yet implemented' }, 501);
});

// GET /store/orders
router.get('/orders', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'List orders — not yet implemented' }, 501);
});

export default router;
