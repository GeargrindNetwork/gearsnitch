import { randomBytes } from 'node:crypto';
import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { Types } from 'mongoose';
import { StatusCodes } from 'http-status-codes';
import { isAuthenticated, type JwtPayload } from '../../middleware/auth.js';
import { Referral } from '../../models/Referral.js';
import { Subscription } from '../../models/Subscription.js';
import { User } from '../../models/User.js';
import {
  REFERRAL_REWARD_DAYS,
  processReferralQualificationForReferredUser,
  recordAttribution,
} from './referralService.js';
import { errorResponse, successResponse } from '../../utils/response.js';

const router = Router();

const redeemSchema = z.object({
  referralCode: z.string().trim().min(4).max(32),
});

const claimSchema = z.object({
  code: z.string().trim().min(4).max(32),
});

const REFERRAL_BASE_URL = 'https://gearsnitch.com/ref';

// Universal Link landing constants. The iOS app intercepts
// https://gearsnitch.com/r/<code> via apple-app-site-association before any
// HTTP load. For everyone else (browsers, Android, in-app webviews) we
// resolve the code, drop a first-party `gs_ref` cookie, and bounce them to
// the App Store. The cookie is read on first launch by the iOS app via an
// SFSafariViewController flow (item #2 in the backlog).
const UNIVERSAL_LINK_BASE_URL = 'https://gearsnitch.com/r';
const APP_STORE_FALLBACK_URL =
  process.env.APP_STORE_URL ?? 'https://apps.apple.com/app/gearsnitch/id0000000000';
const REFERRAL_COOKIE_NAME = 'gs_ref';
const REFERRAL_COOKIE_MAX_AGE_SECONDS = 60 * 60 * 24 * 30; // 30 days
const REFERRAL_CODE_PATTERN = /^[A-Z0-9]{4,32}$/;

function getUserId(req: Request): string {
  return (req.user as JwtPayload).sub;
}

function buildReferralUrl(referralCode: string): string {
  return `${REFERRAL_BASE_URL}/${referralCode}`;
}

async function generateUniqueReferralCode(): Promise<string> {
  for (let attempt = 0; attempt < 10; attempt += 1) {
    const candidate = randomBytes(4).toString('hex').toUpperCase();
    const exists = await User.exists({ referralCode: candidate });
    if (!exists) {
      return candidate;
    }
  }

  throw new Error('Failed to generate a unique referral code');
}

async function ensureReferralCode(userId: string): Promise<string> {
  const user = await User.findById(userId);
  if (!user) {
    throw new Error('User not found');
  }

  if (user.referralCode) {
    return user.referralCode;
  }

  const referralCode = await generateUniqueReferralCode();
  user.referralCode = referralCode;
  await user.save();
  return referralCode;
}

function mapReferralHistoryStatus(status: string): 'pending' | 'completed' | 'expired' {
  if (status === 'rewarded' || status === 'qualified') {
    return 'completed';
  }

  if (status === 'rejected') {
    return 'expired';
  }

  return 'pending';
}

async function buildReferralPayload(userId: string) {
  const referralCode = await ensureReferralCode(userId);
  const userObjectId = new Types.ObjectId(userId);

  const [history, referrerSubscription] = await Promise.all([
    Referral.find({
      referrerUserId: userObjectId,
      referredUserId: { $ne: null },
    })
      .sort({ createdAt: -1 })
      .lean(),
    Subscription.findOne({ userId: userObjectId }).sort({ expiryDate: -1 }).lean(),
  ]);

  const referredIds = history
    .map((item) => item.referredUserId)
    .filter((value): value is Types.ObjectId => value instanceof Types.ObjectId);

  const referredUsers = referredIds.length
    ? await User.find({ _id: { $in: referredIds } }, { email: 1 }).lean()
    : [];
  const referredEmailById = new Map(
    referredUsers.map((user) => [String(user._id), user.email]),
  );

  const activeReferrals = history.filter((item) =>
    ['qualified', 'rewarded'].includes(item.status),
  ).length;
  const extensionDaysEarned = history
    .filter((item) => item.status === 'rewarded')
    .reduce((total, item) => total + (item.rewardDays || REFERRAL_REWARD_DAYS), 0);

  return {
    referralCode,
    referralURL: buildReferralUrl(referralCode),
    totalReferrals: history.length,
    activeReferrals,
    extensionDaysEarned:
      Math.max(extensionDaysEarned, referrerSubscription?.extensionDays ?? 0),
    history: history.map((item) => ({
      _id: String(item._id),
      referredEmail: item.referredUserId
        ? referredEmailById.get(String(item.referredUserId)) ?? null
        : null,
      status: mapReferralHistoryStatus(item.status),
      createdAt: item.createdAt,
    })),
  };
}

// GET /referrals/me
router.get('/me', isAuthenticated, async (req, res) => {
  try {
    const payload = await buildReferralPayload(getUserId(req));
    successResponse(res, payload);
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to load referral data',
      err instanceof Error ? err.message : String(err),
    );
  }
});

// GET /referrals/qr
router.get('/qr', isAuthenticated, async (req, res) => {
  try {
    const referralCode = await ensureReferralCode(getUserId(req));
    successResponse(res, {
      referralCode,
      referralURL: buildReferralUrl(referralCode),
      qrPayload: buildReferralUrl(referralCode),
    });
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to build referral QR payload',
      err instanceof Error ? err.message : String(err),
    );
  }
});

// GET /referrals
router.get('/', isAuthenticated, async (req, res) => {
  try {
    const payload = await buildReferralPayload(getUserId(req));
    successResponse(res, payload.history);
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to list referrals',
      err instanceof Error ? err.message : String(err),
    );
  }
});

// POST /referrals/generate
router.post('/generate', isAuthenticated, async (req, res) => {
  try {
    const referralCode = await ensureReferralCode(getUserId(req));
    successResponse(res, {
      referralCode,
      referralURL: buildReferralUrl(referralCode),
    });
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to generate referral code',
      err instanceof Error ? err.message : String(err),
    );
  }
});

// POST /referrals/redeem
router.post('/redeem', isAuthenticated, async (req, res) => {
  try {
    const parsed = redeemSchema.safeParse(req.body);
    if (!parsed.success) {
      errorResponse(
        res,
        StatusCodes.BAD_REQUEST,
        'Validation failed',
        parsed.error.flatten().fieldErrors,
      );
      return;
    }

    const userId = getUserId(req);
    const normalizedCode = parsed.data.referralCode.toUpperCase();
    const currentUser = await User.findById(userId);
    if (!currentUser) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'User not found');
      return;
    }

    const referrer = await User.findOne({ referralCode: normalizedCode });
    if (!referrer) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'Referral code not found');
      return;
    }

    if (String(referrer._id) === userId) {
      errorResponse(res, StatusCodes.CONFLICT, 'You cannot redeem your own referral code');
      return;
    }

    const existingReferral = await Referral.findOne({
      referredUserId: currentUser._id,
      referrerUserId: referrer._id,
    });

    if (existingReferral) {
      successResponse(res, {
        referralId: String(existingReferral._id),
        status: existingReferral.status,
      });
      return;
    }

    const referredSubscription = await Subscription.findOne({
      userId: currentUser._id,
      status: { $in: ['active', 'grace_period'] },
    }).sort({ expiryDate: -1 });

    const referral = await Referral.create({
      referrerUserId: referrer._id,
      referredUserId: currentUser._id,
      referralCode: normalizedCode,
      status: 'pending',
      rewardDays: REFERRAL_REWARD_DAYS,
      reason: referredSubscription ? undefined : 'Awaiting qualifying subscription',
    });

    if (referredSubscription) {
      await processReferralQualificationForReferredUser(currentUser._id);
    }

    const persistedReferral = await Referral.findById(referral._id).lean();

    successResponse(
      res,
      {
        referralId: String(referral._id),
        status: persistedReferral?.status ?? referral.status,
      },
      StatusCodes.CREATED,
    );
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to redeem referral code',
      err instanceof Error ? err.message : String(err),
    );
  }
});

// POST /referrals/claim
// ---------------------------------------------------------------------------
// Post-install referral attribution endpoint (item #2 in the referral
// backlog). Used in two paths:
//   1. The iOS app, on first launch after sign-in, sends the code that was
//      stashed in UserDefaults by the Universal Link handler.
//   2. The /r/claim.html bridge (below) hands off a `gs_ref` cookie that
//      survived a deferred install — the SFSafariViewController flow shows
//      the page, the page hands the code back via the Universal Link.
//
// Idempotent: once `User.referredBy` is set, repeat calls return
// `already_attributed` so the iOS retry loop is safe to fire on every cold
// start.
// ---------------------------------------------------------------------------
router.post('/claim', isAuthenticated, async (req, res) => {
  try {
    const parsed = claimSchema.safeParse(req.body);
    if (!parsed.success) {
      errorResponse(
        res,
        StatusCodes.BAD_REQUEST,
        'Validation failed',
        parsed.error.flatten().fieldErrors,
      );
      return;
    }

    const userId = getUserId(req);
    const normalizedCode = parsed.data.code.toUpperCase();

    const currentUser = await User.findById(userId);
    if (!currentUser) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'User not found');
      return;
    }

    if (currentUser.referredBy) {
      successResponse(res, { status: 'already_attributed' });
      return;
    }

    const referrer = await User.findOne({ referralCode: normalizedCode });
    if (!referrer) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'Referral code not found');
      return;
    }

    if (String(referrer._id) === String(currentUser._id)) {
      errorResponse(
        res,
        StatusCodes.BAD_REQUEST,
        'You cannot claim your own referral code',
      );
      return;
    }

    currentUser.referredBy = referrer._id;
    await currentUser.save();

    await recordAttribution(referrer, currentUser, normalizedCode);

    successResponse(res, {
      status: 'claimed',
      referrer: referrer.displayName,
    });
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to claim referral code',
      err instanceof Error ? err.message : String(err),
    );
  }
});

// ---------------------------------------------------------------------------
// Universal Link landing — GET /r/:code
// ---------------------------------------------------------------------------
//
// Mounted on the express app *outside* the /api/v1 namespace (see app.ts) so
// it can answer the bare https://gearsnitch.com/r/<code> URL that QR codes
// encode. Apple's apple-app-site-association makes iOS intercept the URL
// before it ever hits this handler when the app is installed; this code path
// runs for browsers, Android, in-app webviews, and crawlers.
//
// Behavior:
//   * Unknown / malformed code  → 404 HTML.
//   * Known code + iOS UA       → returns the Universal Link "bridge" HTML
//                                 (meta refresh + a fallback button) so the
//                                 system has a chance to hand off to the app
//                                 if AASA is freshly installed.
//   * Known code + everyone else → 302 to the App Store with a `gs_ref`
//                                 first-party cookie (SameSite=Lax; Secure).
//
// The route is INTENTIONALLY UNAUTHENTICATED — anyone scanning the QR can
// resolve a code (Apple Pay-style public landing).
// ---------------------------------------------------------------------------

const universalLinkRouter = Router();

function isIOSUserAgent(userAgent: string | undefined): boolean {
  if (!userAgent) return false;
  // iPhone / iPad / iPod, plus iPadOS desktop-class Safari that masquerades
  // as Macintosh but still includes "Mobile/" in the UA string.
  return (
    /iPhone|iPad|iPod/i.test(userAgent)
    || (/Macintosh/i.test(userAgent) && /Mobile\//.test(userAgent))
  );
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function setReferralCookie(res: Response, code: string): void {
  res.cookie(REFERRAL_COOKIE_NAME, code, {
    path: '/',
    maxAge: REFERRAL_COOKIE_MAX_AGE_SECONDS * 1000,
    sameSite: 'lax',
    secure: true,
    httpOnly: false, // readable by the SFSafariViewController-hosted JS bridge
  });
}

function renderNotFoundHtml(code: string): string {
  const safeCode = escapeHtml(code);
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Referral code not found · GearSnitch</title>
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
         background:#0b0f12; color:#e6e9ec; margin:0;
         display:flex; align-items:center; justify-content:center;
         min-height:100vh; padding:24px; box-sizing:border-box; }
  .card { max-width: 420px; text-align:center; }
  h1 { font-size: 22px; margin: 0 0 12px; }
  p { line-height: 1.5; color:#9aa4ad; margin: 0 0 20px; }
  a.button { display:inline-block; padding:12px 20px; border-radius:12px;
             background:#22c55e; color:#0b0f12; font-weight:600;
             text-decoration:none; }
</style>
</head>
<body>
  <div class="card">
    <h1>That referral code doesn't exist</h1>
    <p>We couldn't find a GearSnitch referral matching <code>${safeCode}</code>.
       Double-check the QR code or ask the person who sent it.</p>
    <a class="button" href="${escapeHtml(APP_STORE_FALLBACK_URL)}">Get GearSnitch</a>
  </div>
</body>
</html>`;
}

function renderUniversalLinkBridgeHtml(code: string): string {
  const safeCode = escapeHtml(code);
  const target = `${UNIVERSAL_LINK_BASE_URL}/${encodeURIComponent(code)}`;
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Opening GearSnitch…</title>
<meta http-equiv="refresh" content="0; url=${escapeHtml(target)}">
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
         background:#0b0f12; color:#e6e9ec; margin:0;
         display:flex; align-items:center; justify-content:center;
         min-height:100vh; padding:24px; box-sizing:border-box; }
  .card { max-width: 420px; text-align:center; }
  h1 { font-size: 22px; margin: 0 0 12px; }
  p { line-height: 1.5; color:#9aa4ad; margin: 0 0 20px; }
  a.button { display:inline-block; padding:12px 20px; border-radius:12px;
             background:#22c55e; color:#0b0f12; font-weight:600;
             text-decoration:none; }
  .muted { font-size: 12px; color:#6b7480; margin-top:24px; }
</style>
</head>
<body>
  <div class="card">
    <h1>Opening GearSnitch…</h1>
    <p>If the app doesn't open automatically, tap the button below.</p>
    <a class="button" href="${escapeHtml(target)}">Open GearSnitch</a>
    <p class="muted">Referral code: <strong>${safeCode}</strong></p>
    <p class="muted">Don't have the app? <a href="${escapeHtml(APP_STORE_FALLBACK_URL)}" style="color:#22c55e">Download from the App Store</a>.</p>
  </div>
</body>
</html>`;
}

function renderClaimBridgeHtml(code: string): string {
  const safeCode = escapeHtml(code);
  const target = `${UNIVERSAL_LINK_BASE_URL}/${encodeURIComponent(code)}?claim=1`;
  // Tiny page: meta-refresh hands control to the Universal Link, which iOS
  // intercepts and routes back into the installed app along with the code.
  // The page is rendered inside an SFSafariViewController on the iOS side, so
  // it carries the user's Safari cookie jar and can read `gs_ref` set during
  // /r/<code> landing.
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Restoring referral…</title>
<meta http-equiv="refresh" content="0; url=${escapeHtml(target)}">
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
         background:#0b0f12; color:#e6e9ec; margin:0;
         display:flex; align-items:center; justify-content:center;
         min-height:100vh; padding:24px; box-sizing:border-box; }
  .card { max-width: 420px; text-align:center; }
  p { line-height: 1.5; color:#9aa4ad; margin: 0; }
</style>
</head>
<body>
  <div class="card">
    <p>Restoring your referral (${safeCode})…</p>
  </div>
</body>
</html>`;
}

function renderEmptyClaimHtml(): string {
  // No referral cookie present; render a self-closing page so the iOS
  // SFSafariViewController is dismissed quickly and we waste no flow.
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>No referral</title>
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
         background:#0b0f12; color:#9aa4ad; margin:0;
         display:flex; align-items:center; justify-content:center;
         min-height:100vh; padding:24px; box-sizing:border-box; }
  .card { max-width: 420px; text-align:center; font-size: 14px; }
</style>
</head>
<body>
  <div class="card"><p>No referral to restore.</p></div>
</body>
</html>`;
}

// GET /r/claim.html — post-install fallback bridge. Mounted BEFORE /:code so
// the literal path doesn't get gobbled by the catch-all parameter route.
//
// The iOS app opens this URL inside an SFSafariViewController on first
// launch. Because that controller shares Safari's cookie jar, any `gs_ref`
// cookie dropped during the original https://gearsnitch.com/r/<code> landing
// is available here even though the App Store redirect happened in a fresh
// Safari tab earlier. We hand the code back to the app via the canonical
// Universal Link, which AASA reroutes back into the app with the ?claim=1
// query parameter so we can distinguish "post-install claim" from "user
// scanned a fresh QR".
universalLinkRouter.get('/claim.html', (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  res.type('html');

  const cookieValue = req.cookies?.[REFERRAL_COOKIE_NAME];
  const code = typeof cookieValue === 'string' ? cookieValue.trim().toUpperCase() : '';

  if (!code || !REFERRAL_CODE_PATTERN.test(code)) {
    res.status(StatusCodes.OK).send(renderEmptyClaimHtml());
    return;
  }

  // Clear the cookie now that we've consumed it — we hand the code off to
  // the app via the URL, so the cookie has done its job.
  res.clearCookie(REFERRAL_COOKIE_NAME, { path: '/' });
  res.status(StatusCodes.OK).send(renderClaimBridgeHtml(code));
});

universalLinkRouter.get('/:code', async (req, res) => {
  const rawCode = String(req.params.code ?? '').trim();
  const normalizedCode = rawCode.toUpperCase();

  res.setHeader('Cache-Control', 'no-store');

  if (!REFERRAL_CODE_PATTERN.test(normalizedCode)) {
    res
      .status(StatusCodes.NOT_FOUND)
      .type('html')
      .send(renderNotFoundHtml(rawCode));
    return;
  }

  try {
    // Look up either a User-owned referral code (the canonical surface that
    // the QR generator encodes) or any historical Referral row that used the
    // same code. Either match means the code is real and we can redirect.
    const [referrerUser, referralRecord] = await Promise.all([
      User.exists({ referralCode: normalizedCode }),
      Referral.exists({ referralCode: normalizedCode }),
    ]);

    if (!referrerUser && !referralRecord) {
      res
        .status(StatusCodes.NOT_FOUND)
        .type('html')
        .send(renderNotFoundHtml(rawCode));
      return;
    }

    // Always drop the cookie so the iOS app can pick it up post-install,
    // even if the user is bouncing through the bridge HTML.
    setReferralCookie(res, normalizedCode);

    if (isIOSUserAgent(req.get('user-agent'))) {
      res.status(StatusCodes.OK).type('html').send(renderUniversalLinkBridgeHtml(normalizedCode));
      return;
    }

    res.redirect(StatusCodes.MOVED_TEMPORARILY, APP_STORE_FALLBACK_URL);
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to resolve referral landing',
      err instanceof Error ? err.message : String(err),
    );
  }
});

export { universalLinkRouter };

export default router;
