import { createApp } from './app.js';
import config from './config/index.js';
import { connectMongoDB, disconnectMongoDB } from './loaders/mongoose.js';
import { connectRedis, disconnectRedis } from './loaders/redis.js';
import logger from './utils/logger.js';

async function bootstrap(): Promise<void> {
  try {
    // Connect to infrastructure
    await connectMongoDB();
    logger.info('MongoDB ready');

    await connectRedis();
    logger.info('Redis ready');

    // Create and start Express app
    const app = createApp();

    const server = app.listen(config.port, () => {
      logger.info(`GearSnitch API listening on port ${config.port}`, {
        env: config.nodeEnv,
        apiVersion: config.apiVersion,
      });
    });

    // Graceful shutdown
    const shutdown = async (signal: string): Promise<void> => {
      logger.info(`${signal} received — shutting down gracefully`);

      server.close(async () => {
        logger.info('HTTP server closed');

        try {
          await disconnectMongoDB();
          await disconnectRedis();
          logger.info('All connections closed — exiting');
          process.exit(0);
        } catch (err) {
          logger.error('Error during shutdown', {
            error: err instanceof Error ? err.message : String(err),
          });
          process.exit(1);
        }
      });

      // Force exit after 10s if graceful shutdown stalls
      setTimeout(() => {
        logger.error('Forced shutdown — graceful shutdown timed out');
        process.exit(1);
      }, 10_000);
    };

    process.on('SIGTERM', () => void shutdown('SIGTERM'));
    process.on('SIGINT', () => void shutdown('SIGINT'));

    // Unhandled rejection / exception safety net
    process.on('unhandledRejection', (reason) => {
      logger.error('Unhandled rejection', {
        error: reason instanceof Error ? reason.message : String(reason),
        stack: reason instanceof Error ? reason.stack : undefined,
      });
    });

    process.on('uncaughtException', (err) => {
      logger.error('Uncaught exception — shutting down', {
        error: err.message,
        stack: err.stack,
      });
      process.exit(1);
    });
  } catch (err) {
    logger.error('Failed to start server', {
      error: err instanceof Error ? err.message : String(err),
    });
    process.exit(1);
  }
}

void bootstrap();
