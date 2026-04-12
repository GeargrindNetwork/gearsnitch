import { Router } from 'express';
import { isAuthenticated } from '../../middleware/auth.js';
import { successResponse } from '../../utils/response.js';
import { getRemoteConfigPayload, getRemoteFeatureFlags } from './remoteConfig.js';

const router = Router();

// GET /config and /config/app — public app config (feature flags, minimum version, etc.)
router.get(['/', '/app'], (_req, res) => {
  successResponse(res, getRemoteConfigPayload());
});

// GET /config/features — feature flag subset for lightweight refreshes
router.get('/features', (_req, res) => {
  successResponse(res, { featureFlags: getRemoteFeatureFlags() });
});

// GET /config/user — auth-scoped config that currently matches the app defaults
router.get('/user', isAuthenticated, (_req, res) => {
  successResponse(res, getRemoteConfigPayload());
});

export default router;
