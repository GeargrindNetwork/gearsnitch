import type { NextFunction, Request, Response } from 'express';
import { StatusCodes } from 'http-status-codes';
import {
  getClientReleaseHeaders,
  resolveReleaseCompatibility,
} from '../modules/config/releasePolicy.js';
import { getRemoteConfigPayload } from '../modules/config/remoteConfig.js';

declare global {
  namespace Express {
    interface Request {
      clientRelease?: ReturnType<typeof getClientReleaseHeaders>;
    }
  }
}

export function enforceSupportedClientRelease(
  req: Request,
  res: Response,
  next: NextFunction,
): void {
  const clientRelease = getClientReleaseHeaders(req);
  const compatibility = resolveReleaseCompatibility(clientRelease);

  req.clientRelease = clientRelease;

  if (compatibility.status === 'supported') {
    next();
    return;
  }

  res.status(StatusCodes.UPGRADE_REQUIRED).json({
    success: false,
    data: getRemoteConfigPayload(clientRelease),
    error: {
      code: StatusCodes.UPGRADE_REQUIRED,
      message:
        compatibility.reason === 'missing_client_version'
          ? 'Client version header is required for this route'
          : 'Client update required',
    },
  });
}
