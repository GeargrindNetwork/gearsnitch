import winston from 'winston';
import DailyRotateFile from 'winston-daily-rotate-file';
import config from '../config/index.js';

const { combine, timestamp, json, errors, printf } = winston.format;

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
];

if (config.isProduction) {
  transports.push(
    new DailyRotateFile({
      filename: 'logs/app-%DATE%.log',
      datePattern: 'YYYY-MM-DD',
      maxSize: '20m',
      maxFiles: '14d',
      level: 'info',
    }),
    new DailyRotateFile({
      filename: 'logs/error-%DATE%.log',
      datePattern: 'YYYY-MM-DD',
      maxSize: '20m',
      maxFiles: '30d',
      level: 'error',
    }),
  );
}

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
