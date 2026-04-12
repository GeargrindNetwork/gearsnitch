import { Router } from 'express';
import { isAuthenticated } from '../../middleware/auth.js';
import { successResponse } from '../../utils/response.js';
import { getRemoteConfigPayload, getRemoteFeatureFlags } from './remoteConfig.js';
import { getClientReleaseHeaders } from './releasePolicy.js';

const router = Router();

// GET /config and /config/app — public app config (feature flags, minimum version, etc.)
router.get(['/', '/app'], (req, res) => {
  successResponse(res, getRemoteConfigPayload(getClientReleaseHeaders(req)));
});

// GET /config/features — feature flag subset for lightweight refreshes
router.get('/features', (_req, res) => {
  successResponse(res, { featureFlags: getRemoteFeatureFlags() });
});

// GET /config/user — auth-scoped config that currently matches the app defaults
router.get('/user', isAuthenticated, (req, res) => {
  successResponse(res, getRemoteConfigPayload(getClientReleaseHeaders(req)));
});

export default router;
