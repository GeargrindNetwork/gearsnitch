import { Router, type Request, type Response } from 'express';
import { StatusCodes } from 'http-status-codes';
import { successResponse, errorResponse } from '../../utils/response.js';
import {
  getLastReconciliationRun,
  reconcileAllSubscriptions,
  type ReconciliationRunSummary,
  type ReconcilerClients,
} from '../subscriptions/reconciliation.js';
import { createDefaultReconcilerClients } from '../subscriptions/reconciliationClients.js';
import logger from '../../utils/logger.js';

/**
 * Admin-only reconciliation endpoints. Both require authentication +
 * admin role (enforced by the parent `admin/routes.ts` mount via
 * `router.use(isAuthenticated, hasRole(['admin']))`).
 *
 *   GET  /admin/reconciliation/last-run — last cron summary.
 *   POST /admin/reconciliation/run      — kick a run immediately (dev/testing).
 */

// Exposed as a factory so tests can inject mock provider clients without
// hitting the real SDKs.
export function createReconciliationRouter(
  clientsFactory: () => ReconcilerClients = createDefaultReconcilerClients,
): Router {
  const router = Router();

  router.get('/last-run', async (_req: Request, res: Response) => {
    try {
      const last = await getLastReconciliationRun();
      if (!last) {
        successResponse(res, { lastRun: null }, StatusCodes.OK);
        return;
      }
      successResponse(res, {
        lastRun: {
          startedAt: last.startedAt.toISOString(),
          completedAt: last.completedAt.toISOString(),
          durationMs: last.durationMs,
          counters: last.counters,
        },
      });
    } catch (err) {
      errorResponse(
        res,
        StatusCodes.INTERNAL_SERVER_ERROR,
        'Failed to load reconciliation summary',
        (err as Error).message,
      );
    }
  });

  router.post('/run', async (req: Request, res: Response) => {
    try {
      logger.info('Admin kicked manual reconciliation run', {
        adminUserId: req.user?.sub,
      });
      const summary: ReconciliationRunSummary = await reconcileAllSubscriptions(
        clientsFactory(),
      );
      successResponse(res, {
        run: {
          startedAt: summary.startedAt.toISOString(),
          completedAt: summary.completedAt.toISOString(),
          durationMs: summary.durationMs,
          counters: summary.counters,
        },
      });
    } catch (err) {
      errorResponse(
        res,
        StatusCodes.INTERNAL_SERVER_ERROR,
        'Reconciliation run failed',
        (err as Error).message,
      );
    }
  });

  return router;
}

const defaultRouter = createReconciliationRouter();
export default defaultRouter;
