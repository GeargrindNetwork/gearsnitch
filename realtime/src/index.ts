import http from 'http';
import { Server } from 'socket.io';
import { createAdapter } from '@socket.io/redis-adapter';
import IORedis from 'ioredis';
import jwt from 'jsonwebtoken';
import mongoose from 'mongoose';
import { logger } from './utils/logger';

const PORT = parseInt(process.env.PORT || '3002', 10);
const MONGODB_URI = process.env.MONGODB_URI || '';
const REDIS_URL = process.env.REDIS_URL || 'redis://localhost:6379';
const JWT_PUBLIC_KEY = process.env.JWT_PUBLIC_KEY || '';
const CORS_ORIGINS = (process.env.CORS_ORIGINS || 'http://localhost:5173').split(',');

const httpServer = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200);
    res.end('OK');
    return;
  }
  res.writeHead(404);
  res.end();
});

const io = new Server(httpServer, {
  cors: {
    origin: CORS_ORIGINS,
    credentials: true,
  },
  pingTimeout: 60000,
  pingInterval: 25000,
});

// Redis adapter for multi-instance support
const pubClient = new IORedis(REDIS_URL);
const subClient = pubClient.duplicate();

io.adapter(createAdapter(pubClient, subClient));

// JWT authentication middleware
io.use(async (socket, next) => {
  const token = socket.handshake.auth.token || socket.handshake.headers.authorization?.replace('Bearer ', '');

  if (!token) {
    return next(new Error('Authentication required'));
  }

  try {
    const decoded = jwt.verify(token, JWT_PUBLIC_KEY, { algorithms: ['RS256'] }) as {
      sub: string;
      jti: string;
    };

    // Verify token is in Redis whitelist
    const whitelistKey = `whitelist:auth:${decoded.sub}:${decoded.jti}`;
    const exists = await pubClient.exists(whitelistKey);
    if (!exists) {
      return next(new Error('Session revoked'));
    }

    socket.data.userId = decoded.sub;
    socket.data.jti = decoded.jti;
    next();
  } catch {
    next(new Error('Invalid token'));
  }
});

// Namespaces
const userNs = io.of('/user');
const deviceNs = io.of('/devices');

// Apply same auth to namespaces
[userNs, deviceNs].forEach((ns) => {
  ns.use(async (socket, next) => {
    const token = socket.handshake.auth.token;
    if (!token) return next(new Error('Authentication required'));

    try {
      const decoded = jwt.verify(token, JWT_PUBLIC_KEY, { algorithms: ['RS256'] }) as {
        sub: string;
        jti: string;
      };
      socket.data.userId = decoded.sub;
      next();
    } catch {
      next(new Error('Invalid token'));
    }
  });
});

// User namespace — personal room for alerts, subscription, referral events
userNs.on('connection', (socket) => {
  const userId = socket.data.userId;
  socket.join(`user:${userId}`);
  logger.info(`User connected: ${userId}`);

  socket.on('user:presence', () => {
    pubClient.setex(`presence:user:${userId}`, 120, 'online');
  });

  socket.on('alerts:ack', (data: { alertId: string }) => {
    logger.info(`Alert acknowledged: ${data.alertId} by ${userId}`);
    // TODO: Update alert status in DB
  });

  socket.on('disconnect', () => {
    logger.info(`User disconnected: ${userId}`);
  });
});

// Devices namespace — device status streaming
deviceNs.on('connection', (socket) => {
  const userId = socket.data.userId;
  socket.join(`devices:${userId}`);

  socket.on('device:status:update', (data: { deviceId: string; status: string }) => {
    logger.info(`Device status update from ${userId}`, data);
    // TODO: Update device in DB, broadcast to shared users
  });

  socket.on('device:sync', () => {
    // TODO: Send current device states to client
  });

  socket.on('disconnect', () => {
    logger.info(`Device socket disconnected: ${userId}`);
  });
});

// Subscribe to Redis pub/sub for cross-service events
const eventSubscriber = pubClient.duplicate();
const EVENT_CHANNELS = [
  'events:device-status',
  'events:alert',
  'events:subscription',
  'events:referral',
  'events:store-order',
];

eventSubscriber.subscribe(...EVENT_CHANNELS);
eventSubscriber.on('message', (channel, message) => {
  try {
    const event = JSON.parse(message);
    const { userId, type, payload } = event;

    switch (channel) {
      case 'events:device-status':
        deviceNs.to(`devices:${userId}`).emit(`device:${type}`, payload);
        break;
      case 'events:alert':
        userNs.to(`user:${userId}`).emit(`alert:${type}`, payload);
        break;
      case 'events:subscription':
        userNs.to(`user:${userId}`).emit('subscription:updated', payload);
        break;
      case 'events:referral':
        userNs.to(`user:${userId}`).emit('referral:rewarded', payload);
        break;
      case 'events:store-order':
        userNs.to(`user:${userId}`).emit('store:order:updated', payload);
        break;
    }
  } catch (err) {
    logger.error('Failed to process pub/sub event', { channel, error: err });
  }
});

async function start() {
  await mongoose.connect(MONGODB_URI);
  logger.info('Connected to MongoDB');

  httpServer.listen(PORT, () => {
    logger.info(`GearSnitch Realtime service running on port ${PORT}`);
  });
}

async function shutdown() {
  logger.info('Realtime service shutting down...');
  io.close();
  await eventSubscriber.quit();
  await pubClient.quit();
  await subClient.quit();
  await mongoose.disconnect();
  httpServer.close();
  process.exit(0);
}

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

start().catch((err) => {
  logger.error('Realtime service failed to start', { error: err });
  process.exit(1);
});
