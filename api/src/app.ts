import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import cookieParser from 'cookie-parser';
import compression from 'compression';
import hpp from 'hpp';
import config from './config/index.js';
import { requestIdMiddleware } from './middleware/requestId.js';
import { globalRateLimiter } from './middleware/rateLimiter.js';
import { errorHandler } from './middleware/errorHandler.js';
import logger from './utils/logger.js';
import routes from './routes/index.js';

export function createApp(): express.Application {
  const app = express();

  // 1. Request ID — attach correlation ID to every request
  app.use(requestIdMiddleware);

  // 2. Security headers
  app.use(helmet());

  // 3. Trust proxy (when behind load balancer / reverse proxy)
  app.set('trust proxy', 1);

  // 4. Request logging
  app.use((req, _res, next) => {
    logger.info('Incoming request', {
      correlationId: req.requestId,
      method: req.method,
      url: req.originalUrl,
      ip: req.ip,
      userAgent: req.get('user-agent'),
    });
    next();
  });

  // 5. CORS
  app.use(
    cors({
      origin: config.corsOrigins,
      credentials: true,
      methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
      allowedHeaders: ['Content-Type', 'Authorization', 'X-Request-ID', 'X-CSRF-Token'],
    }),
  );

  // 6. Cookie parser
  app.use(cookieParser());

  // 7. Body parsers
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
