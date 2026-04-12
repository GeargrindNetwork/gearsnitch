import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { StatusCodes } from 'http-status-codes';
import { isAuthenticated } from '../../middleware/auth.js';
import { type JwtPayload } from '../../middleware/auth.js';
import { validateBody } from '../../middleware/validate.js';
import { errorResponse, successResponse } from '../../utils/response.js';
import paymentRoutes from './paymentRoutes.js';
import { StoreService, StoreServiceError } from './storeService.js';

const router = Router();
const storeService = new StoreService();

const addToCartSchema = z.object({
  productId: z.string().trim().min(1),
  quantity: z.coerce.number().int().min(1).max(99).default(1),
});

const updateCartItemSchema = z.object({
  quantity: z.coerce.number().int().min(0).max(99),
});

function getUserId(req: Request): string {
  return (req.user as JwtPayload).sub;
}

function getRouteParam(req: Request, key: string): string {
  const value = req.params[key];
  return Array.isArray(value) ? value[0] : value;
}

function handleStoreError(res: Response, err: unknown, fallbackMessage: string): void {
  if (err instanceof StoreServiceError) {
    errorResponse(res, err.statusCode, err.message);
    return;
  }

  errorResponse(
    res,
    StatusCodes.INTERNAL_SERVER_ERROR,
    fallbackMessage,
    err instanceof Error ? err.message : String(err),
  );
}

// Payment routes
router.use('/payments', paymentRoutes);

// GET /store/products
router.get('/products', async (_req, res) => {
  try {
    const products = await storeService.listProducts();
    successResponse(res, products);
  } catch (err) {
    handleStoreError(res, err, 'Failed to list store products');
  }
});

// GET /store/products/:id
router.get('/products/:id', async (req, res) => {
  try {
    const product = await storeService.getProductByReference(getRouteParam(req, 'id'));
    successResponse(res, product);
  } catch (err) {
    handleStoreError(res, err, 'Failed to load product details');
  }
});

// POST /store/cart
router.post(
  '/cart',
  isAuthenticated,
  validateBody(addToCartSchema),
  async (req, res) => {
    try {
      const cart = await storeService.addToCart(
        getUserId(req),
        req.body as z.infer<typeof addToCartSchema>,
      );
      successResponse(res, cart, StatusCodes.CREATED);
    } catch (err) {
      handleStoreError(res, err, 'Failed to add item to cart');
    }
  },
);

// GET /store/cart
router.get('/cart', isAuthenticated, async (req, res) => {
  try {
    const cart = await storeService.getCart(getUserId(req));
    successResponse(res, cart);
  } catch (err) {
    handleStoreError(res, err, 'Failed to load cart');
  }
});

// PATCH /store/cart/:productId
router.patch(
  '/cart/:productId',
  isAuthenticated,
  validateBody(updateCartItemSchema),
  async (req, res) => {
    try {
      const cart = await storeService.updateCartItem(getUserId(req), {
        productId: getRouteParam(req, 'productId'),
        quantity: (req.body as z.infer<typeof updateCartItemSchema>).quantity,
      });
      successResponse(res, cart);
    } catch (err) {
      handleStoreError(res, err, 'Failed to update cart item');
    }
  },
);

// DELETE /store/cart/:productId
router.delete('/cart/:productId', isAuthenticated, async (req, res) => {
  try {
    const cart = await storeService.removeCartItem(
      getUserId(req),
      getRouteParam(req, 'productId'),
    );
    successResponse(res, cart);
  } catch (err) {
    handleStoreError(res, err, 'Failed to remove cart item');
  }
});

// POST /store/checkout
router.post('/checkout', isAuthenticated, (_req, res) => {
  errorResponse(
    res,
    StatusCodes.NOT_IMPLEMENTED,
    'Checkout is not implemented on this route. Use /store/payments/* instead.',
  );
});

// GET /store/orders
router.get('/orders', isAuthenticated, async (req, res) => {
  try {
    const page = Number.parseInt(String(req.query.page ?? '1'), 10);
    const limit = Number.parseInt(String(req.query.limit ?? '20'), 10);
    const result = await storeService.listOrders(getUserId(req), page, limit);

    successResponse(res, result.orders, StatusCodes.OK, {
      page: result.page,
      limit: result.limit,
      total: result.total,
      hasMore: result.hasMore,
    });
  } catch (err) {
    handleStoreError(res, err, 'Failed to list store orders');
  }
});

export default router;
