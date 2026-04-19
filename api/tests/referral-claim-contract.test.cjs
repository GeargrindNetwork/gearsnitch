const fs = require('node:fs');
const path = require('node:path');

const repoRoot = path.join(__dirname, '..', '..');

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

describe('POST /referrals/claim — post-install attribution contract (item #2)', () => {
  const userModel = read('api/src/models/User.ts');
  const referralRoutes = read('api/src/modules/referrals/routes.ts');
  const referralService = read('api/src/modules/referrals/referralService.ts');
  const apiRoutes = read('api/src/routes/index.ts');

  // ---------------------------------------------------------------------------
  // User model surface
  // ---------------------------------------------------------------------------

  describe('User.referredBy schema', () => {
    test('IUser exposes referredBy as an optional ObjectId/null reference', () => {
      expect(userModel).toMatch(/referredBy\?:\s*Types\.ObjectId\s*\|\s*null;/);
    });

    test('schema declares referredBy as a User ref with default null', () => {
      expect(userModel).toMatch(
        /referredBy:\s*\{\s*type:\s*Schema\.Types\.ObjectId,\s*ref:\s*'User',\s*default:\s*null\s*\}/,
      );
    });

    test('referredBy is indexed sparsely (avoid bloating index with NULLs)', () => {
      expect(userModel).toMatch(
        /UserSchema\.index\(\{\s*referredBy:\s*1\s*\},\s*\{\s*sparse:\s*true\s*\}\)/,
      );
    });

    test('existing User indexes are preserved (no accidental removals)', () => {
      // Smoke-check that the indexes touched by adjacent migrations remain
      // declared. If we ever removed one of these unintentionally the test
      // catches the regression early.
      expect(userModel).toContain(
        "UserSchema.index({ emailHash: 1 }, { unique: true });",
      );
      expect(userModel).toContain(
        "UserSchema.index({ referralCode: 1 }, { unique: true, sparse: true });",
      );
      expect(userModel).toContain(
        "UserSchema.index({ stripeCustomerId: 1 }, { sparse: true });",
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Route mounting
  // ---------------------------------------------------------------------------

  describe('route mounting', () => {
    test('referrals module is still wired under /referrals on the v1 router', () => {
      expect(apiRoutes).toContain("router.use('/referrals', referralsRoutes);");
    });

    test('POST /claim is gated by isAuthenticated (no anonymous attribution)', () => {
      expect(referralRoutes).toMatch(
        /router\.post\(\s*'\/claim',\s*isAuthenticated,/,
      );
    });

    test('claim route uses the dedicated claim zod schema (not the redeem schema)', () => {
      expect(referralRoutes).toMatch(
        /const claimSchema\s*=\s*z\.object\(\{\s*code:\s*z\.string\(\)\.trim\(\)\.min\(4\)\.max\(32\),?\s*\}\);/,
      );
      expect(referralRoutes).toContain('claimSchema.safeParse(req.body)');
    });
  });

  // ---------------------------------------------------------------------------
  // POST /claim — branch coverage
  // ---------------------------------------------------------------------------

  describe('POST /claim — branch coverage', () => {
    test('idempotent: returns already_attributed when User.referredBy is set', () => {
      expect(referralRoutes).toContain('currentUser.referredBy');
      expect(referralRoutes).toMatch(
        /successResponse\(res,\s*\{\s*status:\s*'already_attributed'\s*\}\)/,
      );
    });

    test('404 when the code does not resolve to any user', () => {
      expect(referralRoutes).toMatch(
        /errorResponse\(\s*res,\s*StatusCodes\.NOT_FOUND,\s*'Referral code not found'\)/,
      );
    });

    test('400 when the code resolves to the calling user (self-referral)', () => {
      expect(referralRoutes).toMatch(
        /errorResponse\(\s*[\s\S]*?StatusCodes\.BAD_REQUEST,\s*'You cannot claim your own referral code'/,
      );
    });

    test('happy path: writes referredBy, calls recordAttribution, returns claimed + referrer name', () => {
      // Field write
      expect(referralRoutes).toMatch(/currentUser\.referredBy\s*=\s*referrer\._id;/);
      expect(referralRoutes).toContain('await currentUser.save();');
      // Service hand-off
      expect(referralRoutes).toContain('await recordAttribution(referrer, currentUser, normalizedCode);');
      // Response shape
      expect(referralRoutes).toMatch(/status:\s*'claimed'/);
      expect(referralRoutes).toMatch(/referrer:\s*referrer\.displayName/);
    });

    test('code is uppercased before the User lookup (matches DB invariant)', () => {
      expect(referralRoutes).toMatch(
        /const normalizedCode\s*=\s*parsed\.data\.code\.toUpperCase\(\);/,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // referralService.recordAttribution helper
  // ---------------------------------------------------------------------------

  describe('referralService.recordAttribution helper', () => {
    test('exists and is exported', () => {
      expect(referralService).toMatch(/export async function recordAttribution\(/);
    });

    test('rejects self-referral defensively (route already guards but service is reusable)', () => {
      expect(referralService).toContain("throw new Error('Self-referral is not allowed')");
    });

    test('is idempotent — returns the existing Referral row instead of creating a duplicate', () => {
      expect(referralService).toMatch(
        /Referral\.findOne\(\s*\{\s*referrerUserId:\s*referrer\._id,\s*referredUserId:\s*referee\._id,?\s*\}\s*\)/,
      );
      expect(referralService).toContain('return existing;');
    });

    test('triggers qualification when the referee already has an eligible subscription', () => {
      expect(referralService).toContain(
        'await processReferralQualificationForReferredUser(referee._id);',
      );
    });

    test('seeds the Referral row with the canonical 28-day reward window', () => {
      expect(referralService).toContain('rewardDays: REFERRAL_REWARD_DAYS,');
    });
  });

  // ---------------------------------------------------------------------------
  // GET /r/claim.html — post-install bridge
  // ---------------------------------------------------------------------------

  describe('GET /r/claim.html — post-install SFSafariViewController bridge', () => {
    test('handler is unauthenticated and registered on the universal link router', () => {
      expect(referralRoutes).toMatch(
        /universalLinkRouter\.get\(\s*'\/claim\.html',\s*\(req,\s*res\)\s*=>/,
      );
    });

    test('claim.html route is registered BEFORE /:code so it is not swallowed by the catch-all', () => {
      const claimIdx = referralRoutes.indexOf("universalLinkRouter.get('/claim.html'");
      const codeIdx = referralRoutes.indexOf("universalLinkRouter.get('/:code'");
      expect(claimIdx).toBeGreaterThan(-1);
      expect(codeIdx).toBeGreaterThan(-1);
      expect(claimIdx).toBeLessThan(codeIdx);
    });

    test('reads the gs_ref cookie and validates against the canonical code pattern', () => {
      expect(referralRoutes).toMatch(/req\.cookies\?\.\[REFERRAL_COOKIE_NAME\]/);
      expect(referralRoutes).toContain('REFERRAL_CODE_PATTERN.test(code)');
    });

    test('clears the cookie after read (single-shot consumption)', () => {
      expect(referralRoutes).toMatch(
        /res\.clearCookie\(\s*REFERRAL_COOKIE_NAME,\s*\{\s*path:\s*'\/'\s*\}\)/,
      );
    });

    test('renders the bridge HTML pointing at the canonical Universal Link with ?claim=1', () => {
      expect(referralRoutes).toContain('?claim=1');
      expect(referralRoutes).toContain('renderClaimBridgeHtml');
    });

    test('renders an empty-state page (not a 4xx) when no cookie is present', () => {
      // We deliberately return 200 + minimal HTML so the SFSafariViewController
      // doesn't show an error to the user.
      expect(referralRoutes).toContain('renderEmptyClaimHtml');
      // Make sure the empty-state path uses StatusCodes.OK, not an error.
      const claimHandlerSlice = referralRoutes
        .split("universalLinkRouter.get('/claim.html'")[1]
        .split("universalLinkRouter.get('/:code'")[0];
      expect(claimHandlerSlice).toContain('StatusCodes.OK');
      expect(claimHandlerSlice).not.toContain('StatusCodes.NOT_FOUND');
    });

    test('sets Cache-Control: no-store to prevent stale code reuse', () => {
      const claimHandlerSlice = referralRoutes
        .split("universalLinkRouter.get('/claim.html'")[1]
        .split("universalLinkRouter.get('/:code'")[0];
      expect(claimHandlerSlice).toMatch(/res\.setHeader\(\s*'Cache-Control',\s*'no-store'\s*\)/);
    });
  });
});
