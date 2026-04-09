import mongoose from 'mongoose';
import logger from '../utils/logger.js';
import config from '../config/index.js';

const MAX_RETRIES = 5;
const RETRY_DELAY_MS = 3000;

export async function connectMongoDB(): Promise<typeof mongoose> {
  if (!config.mongodbUri) {
    throw new Error('MONGODB_URI is not configured');
  }

  let retries = 0;

  while (retries < MAX_RETRIES) {
    try {
      const conn = await mongoose.connect(config.mongodbUri, {
        maxPoolSize: 10,
        serverSelectionTimeoutMS: 5000,
        socketTimeoutMS: 45000,
      });

      logger.info('MongoDB connected', { host: conn.connection.host });

      mongoose.connection.on('error', (err) => {
        logger.error('MongoDB connection error', { error: err.message });
      });

      mongoose.connection.on('disconnected', () => {
        logger.warn('MongoDB disconnected');
      });

      return conn;
    } catch (err) {
      retries++;
      const message = err instanceof Error ? err.message : String(err);
      logger.error(`MongoDB connection attempt ${retries}/${MAX_RETRIES} failed`, {
        error: message,
      });

      if (retries >= MAX_RETRIES) {
        throw new Error(`MongoDB connection failed after ${MAX_RETRIES} attempts: ${message}`);
      }

      await new Promise((resolve) => setTimeout(resolve, RETRY_DELAY_MS));
    }
  }

  throw new Error('MongoDB connection failed — unreachable');
}

export async function disconnectMongoDB(): Promise<void> {
  await mongoose.disconnect();
  logger.info('MongoDB disconnected gracefully');
}
