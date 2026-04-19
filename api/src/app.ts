import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import cookieParser from 'cookie-parser';
import compression from 'compression';
import hpp from 'hpp';
import config from './config/index.js';
import { requestIdMiddleware } from './middleware/requestId.js';
import { createGlobalRateLimiter } from './middleware/rateLimiter.js';
import { errorHandler } from './middleware/errorHandler.js';
import logger from './utils/logger.js';
import routes from './routes/index.js';
import { universalLinkRouter } from './modules/referrals/routes.js';

export function createApp(): express.Application {
  const app = express();
  const globalRateLimiter = createGlobalRateLimiter();

  // 1. Request ID — attach correlation ID to every request
  app.use(requestIdMiddleware);

  // 2. Security headers
  app.use(helmet());

  // 3. Trust proxy (when behind load balancer / reverse proxy)
  app.set('trust proxy', 1);

  // 4. Request logging
  app.use((req, res, next) => {
    const startedAt = Date.now();

    logger.info('Incoming request', {
      correlationId: req.requestId,
      method: req.method,
      url: req.originalUrl,
      ip: req.ip,
      userAgent: req.get('user-agent'),
    });

    res.on('finish', () => {
      const durationMs = Date.now() - startedAt;
      const payload = {
        correlationId: req.requestId,
        method: req.method,
        url: req.originalUrl,
        statusCode: res.statusCode,
        durationMs,
      };

      if (res.statusCode >= 500) {
        logger.error('Request failed', payload);
      } else if (res.statusCode >= 400) {
        logger.warn('Request completed with client error', payload);
      } else {
        logger.info('Request completed', payload);
      }
    });

    res.on('close', () => {
      if (res.writableEnded) {
        return;
      }

      logger.warn('Request aborted before completion', {
        correlationId: req.requestId,
        method: req.method,
        url: req.originalUrl,
      });
    });

    next();
  });

  // 5. CORS
  app.use(
    cors({
      origin: config.corsOrigins,
      credentials: true,
      methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
      allowedHeaders: [
        'Content-Type',
        'Authorization',
        'X-Request-ID',
        'X-CSRF-Token',
        'X-Client-Platform',
        'X-Client-Version',
        'X-Client-Build',
      ],
    }),
  );

  // 6. Cookie parser
  app.use(cookieParser());

  // 7. Body parsers
  // Stripe webhooks require the raw body for signature verification.
  // Mount the raw parser first on the webhook path before JSON parsing.
  app.use(
    `/api/${config.apiVersion}/store/payments/webhook`,
    express.raw({ type: 'application/json' }),
  );
  app.use(express.json({ limit: '10mb' }));
  app.use(express.urlencoded({ extended: true, limit: '10mb' }));

  // 8. HTTP Parameter Pollution protection
  app.use(hpp());

  // 9. Compression
  app.use(compression());

  // 10. Rate limiting (global)
  app.use(globalRateLimiter);

  // 11. API routes
  app.use(`/api/${config.apiVersion}`, routes);

  // 11b. Universal Link landing — public, unauthenticated, lives at /r/:code
  // outside the /api/v1 namespace so it can answer the bare URL the QR codes
  // encode (https://gearsnitch.com/r/<code>). Apple's AASA file makes iOS
  // intercept this URL before it reaches HTTP when the app is installed; this
  // handler runs for browsers, Android, in-app webviews, and crawlers.
  app.use('/r', universalLinkRouter);

  // 12. 404 handler
  app.use((_req, res) => {
    res.status(404).json({
      success: false,
      data: null,
      error: {
        code: 404,
        message: 'Route not found',
      },
    });
  });

  // 13. Global error handler (must be last)
  app.use(errorHandler);

  return app;
}
