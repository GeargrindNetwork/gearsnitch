import { Router, type Request, type Response } from 'express';
import { StatusCodes } from 'http-status-codes';
import { isAuthenticated } from '../../middleware/auth.js';
import { Content } from '../../models/Content.js';
import { successResponse, errorResponse } from '../../utils/response.js';

const router = Router();

function serialize(doc: Record<string, any>) {
  return {
    _id: String(doc._id),
    slug: doc.slug,
    type: doc.type,
    title: doc.title,
    body: doc.body,
    summary: doc.summary || null,
    imageUrl: doc.imageUrl || null,
    tags: doc.tags || [],
    publishedAt: doc.publishedAt?.toISOString?.() ?? null,
  };
}

// GET /content/terms — public
router.get('/terms', async (_req: Request, res: Response) => {
  try {
    const doc = await Content.findOne({ slug: 'terms-of-service', type: 'legal' }).lean();
    successResponse(res, {
      content: doc?.body ?? 'Terms of Service for GearSnitch. By using this application you agree to these terms. Full terms will be published soon.',
      title: doc?.title ?? 'Terms of Service',
    });
  } catch (err) {
    errorResponse(res, StatusCodes.INTERNAL_SERVER_ERROR, 'Failed to load terms', (err as Error).message);
  }
});

// GET /content/privacy — public
router.get('/privacy', async (_req: Request, res: Response) => {
  try {
    const doc = await Content.findOne({ slug: 'privacy-policy', type: 'legal' }).lean();
    successResponse(res, {
      content: doc?.body ?? 'Privacy Policy for GearSnitch. We respect your privacy. Full policy will be published soon.',
      title: doc?.title ?? 'Privacy Policy',
    });
  } catch (err) {
    errorResponse(res, StatusCodes.INTERNAL_SERVER_ERROR, 'Failed to load privacy policy', (err as Error).message);
  }
});

// GET /content/articles — public, paginated
router.get('/articles', async (req: Request, res: Response) => {
  try {
    const page = Math.max(1, parseInt(req.query.page as string, 10) || 1);
    const limit = Math.min(50, Math.max(1, parseInt(req.query.limit as string, 10) || 20));
    const skip = (page - 1) * limit;
    const filter = { type: 'article' as const, published: true };

    const [articles, total] = await Promise.all([
      Content.find(filter).sort({ sortOrder: 1, publishedAt: -1 }).skip(skip).limit(limit).lean(),
      Content.countDocuments(filter),
    ]);

    successResponse(res, articles.map(serialize), StatusCodes.OK, { page, limit, total, totalPages: Math.ceil(total / limit) });
  } catch (err) {
    errorResponse(res, StatusCodes.INTERNAL_SERVER_ERROR, 'Failed to load articles', (err as Error).message);
  }
});

// GET /content/articles/:slug — public
router.get('/articles/:id', async (req: Request, res: Response) => {
  try {
    const doc = await Content.findOne({ slug: req.params.id, type: 'article', published: true }).lean();
    if (!doc) { errorResponse(res, StatusCodes.NOT_FOUND, 'Article not found'); return; }
    successResponse(res, serialize(doc));
  } catch (err) {
    errorResponse(res, StatusCodes.INTERNAL_SERVER_ERROR, 'Failed to load article', (err as Error).message);
  }
});

// GET /content/tips — authenticated
router.get('/tips', isAuthenticated, async (_req: Request, res: Response) => {
  try {
    const tips = await Content.find({ type: 'tip', published: true }).sort({ sortOrder: 1 }).limit(10).lean();
    successResponse(res, tips.map(serialize));
  } catch (err) {
    errorResponse(res, StatusCodes.INTERNAL_SERVER_ERROR, 'Failed to load tips', (err as Error).message);
  }
});

// GET /content/featured — public
router.get('/featured', async (_req: Request, res: Response) => {
  try {
    const featured = await Content.find({ type: 'featured', published: true }).sort({ sortOrder: 1 }).limit(5).lean();
    successResponse(res, featured.map(serialize));
  } catch (err) {
    errorResponse(res, StatusCodes.INTERNAL_SERVER_ERROR, 'Failed to load featured content', (err as Error).message);
  }
});

export default router;
