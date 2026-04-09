import { Router } from 'express';
import { successResponse } from '../utils/response.js';

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
import storeRoutes from '../modules/store/routes.js';
import contentRoutes from '../modules/content/routes.js';
import supportRoutes from '../modules/support/routes.js';
import adminRoutes from '../modules/admin/routes.js';
import configRoutes from '../modules/config/routes.js';

const router = Router();

// Health check (public, no auth)
router.get('/health', (_req, res) => {
  successResponse(res, {
    status: 'ok',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
  });
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
router.use('/health-data', healthRoutes);
router.use('/calories', caloriesRoutes);
router.use('/workouts', workoutsRoutes);
router.use('/store', storeRoutes);
router.use('/content', contentRoutes);
router.use('/support', supportRoutes);
router.use('/admin', adminRoutes);
router.use('/config', configRoutes);

export default router;
