import { Router } from 'express';
import { successResponse } from '../utils/response.js';
import logger from '../utils/logger.js';

import authRoutes from '../modules/auth/routes.js';
import usersRoutes from '../modules/users/routes.js';
import referralsRoutes from '../modules/referrals/routes.js';
import subscriptionsRoutes from '../modules/subscriptions/routes.js';
import devicesRoutes from '../modules/devices/routes.js';
import gymsRoutes from '../modules/gyms/routes.js';
import alertsRoutes from '../modules/alerts/routes.js';
import notificationsRoutes from '../modules/notifications/routes.js';
import healthRoutes from '../modules/health/routes.js';
import caloriesRoutes from '../modules/calories/routes.js';
import workoutsRoutes from '../modules/workouts/routes.js';
import runsRoutes from '../modules/runs/routes.js';
import gearRoutes from '../modules/gear/routes.js';
import storeRoutes from '../modules/store/routes.js';
import contentRoutes from '../modules/content/routes.js';
import supportRoutes from '../modules/support/routes.js';
import adminRoutes from '../modules/admin/routes.js';
import configRoutes from '../modules/config/routes.js';
import sessionsRoutes from '../modules/sessions/routes.js';
import calendarRoutes from '../modules/calendar/routes.js';
import eventsRoutes from '../modules/events/routes.js';
import dosingRoutes from '../modules/dosing/routes.js';
import cyclesRoutes from '../modules/cycles/routes.js';
import medicationsRoutes from '../modules/medications/routes.js';
import labsRoutes from '../modules/labs/routes.js';
import emergencyContactsRoutes from '../modules/emergency-contacts/routes.js';
import metricsRoutes from '../modules/metrics/routes.js';
import ecgRoutes from '../modules/ecg/routes.js';

const router = Router();

// Health check (public, no auth)
router.get('/health', (_req, res) => {
  successResponse(res, {
    status: 'ok',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
  });
});

router.post('/client-logs', (req, res) => {
  const body = typeof req.body === 'object' && req.body !== null ? req.body as Record<string, unknown> : {};
  const level = body.level === 'warn' ? 'warn' : body.level === 'info' ? 'info' : body.level === 'debug' ? 'debug' : 'error';
  const message = typeof body.message === 'string' && body.message.trim() ? body.message.trim() : 'Client log';
  const context = typeof body.context === 'object' && body.context !== null ? body.context : {};

  const payload = {
    correlationId: req.requestId,
    source: 'web-client',
    clientTimestamp: typeof body.ts === 'string' ? body.ts : undefined,
    context,
    userAgent: req.get('user-agent'),
  };

  if (level === 'warn') {
    logger.warn(message, payload);
  } else if (level === 'info') {
    logger.info(message, payload);
  } else if (level === 'debug') {
    logger.debug(message, payload);
  } else {
    logger.error(message, payload);
  }

  successResponse(res, { accepted: true }, 202);
});

// Module routes
router.use('/auth', authRoutes);
router.use('/users', usersRoutes);
router.use('/referrals', referralsRoutes);
router.use('/subscriptions', subscriptionsRoutes);
router.use('/devices', devicesRoutes);
router.use('/gyms', gymsRoutes);
router.use('/alerts', alertsRoutes);
router.use('/notifications', notificationsRoutes);
router.use('/health', healthRoutes);
router.use('/health-data', healthRoutes);
router.use('/calories', caloriesRoutes);
router.use('/workouts', workoutsRoutes);
router.use('/runs', runsRoutes);
router.use('/gear', gearRoutes);
router.use('/store', storeRoutes);
router.use('/content', contentRoutes);
router.use('/support', supportRoutes);
router.use('/admin', adminRoutes);
router.use('/config', configRoutes);
router.use('/sessions', sessionsRoutes);
router.use('/calendar', calendarRoutes);
router.use('/events', eventsRoutes);
router.use('/dosing', dosingRoutes);
router.use('/cycles', cyclesRoutes);
router.use('/medications', medicationsRoutes);
router.use('/labs', labsRoutes);
router.use('/emergency-contacts', emergencyContactsRoutes);
router.use('/metrics', metricsRoutes);
router.use('/ecg', ecgRoutes);

export default router;
