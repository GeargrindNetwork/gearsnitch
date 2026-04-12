import winston from 'winston';
import DailyRotateFile from 'winston-daily-rotate-file';
import path from 'node:path';
import config from '../config/index.js';

const { combine, timestamp, json, errors, printf } = winston.format;
const fileLogDirectory = process.env.LOG_DIR?.trim() || '/tmp/gearsnitch-logs';

const correlationFormat = printf((info) => {
  const { timestamp: ts, level, message, correlationId, ...rest } = info;
  return JSON.stringify({
    timestamp: ts,
    level,
    message,
    ...(correlationId ? { correlationId } : {}),
    ...rest,
  });
});

const transports: winston.transport[] = [
  new winston.transports.Console({
    level: config.isDevelopment ? 'debug' : 'info',
  }),
  new DailyRotateFile({
    filename: path.join(fileLogDirectory, 'app-%DATE%.log'),
    datePattern: 'YYYY-MM-DD',
    maxSize: '20m',
    maxFiles: config.isProduction ? '14d' : '7d',
    level: config.isDevelopment ? 'debug' : 'info',
  }),
  new DailyRotateFile({
    filename: path.join(fileLogDirectory, 'error-%DATE%.log'),
    datePattern: 'YYYY-MM-DD',
    maxSize: '20m',
    maxFiles: config.isProduction ? '30d' : '14d',
    level: 'error',
  }),
];

const logger = winston.createLogger({
  level: config.isDevelopment ? 'debug' : 'info',
  format: combine(errors({ stack: true }), timestamp(), json(), correlationFormat),
  defaultMeta: { service: 'gearsnitch-api' },
  transports,
});

export function createChildLogger(correlationId: string): winston.Logger {
  return logger.child({ correlationId });
}

export default logger;
