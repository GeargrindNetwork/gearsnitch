const fs = require('node:fs');
const path = require('node:path');

const repoRoot = path.join(__dirname, '..', '..');

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

describe('referral reward policy regression sweep', () => {
  const referralModel = read('api/src/models/Referral.ts');
  const referralRoutes = read('api/src/modules/referrals/routes.ts');
  const referralService = read('api/src/modules/referrals/referralService.ts');
  const supportRoutes = read('api/src/modules/support/routes.ts');
  const supportPage = read('web/src/pages/SupportPage.tsx');
  const accountPage = read('web/src/pages/AccountPage.tsx');
  // Item #36 split `LandingPage.tsx` into a 2-variant dispatcher that
  // delegates to `LandingV1.tsx` (control) / `LandingV2.tsx` (variant).
  // The referral policy copy lives on the control; v2 is marketing-focused
  // and intentionally does not mention reward days.
  const landingV1 = read('web/src/pages/landing/LandingV1.tsx');

  test('reward policy is 28 bonus days and enforced from the live API path', () => {
    expect(referralModel).toContain('rewardDays: { type: Number, default: 28 },');
    expect(referralService).toContain('export const REFERRAL_REWARD_DAYS = 28;');
    expect(referralRoutes).toContain('await processReferralQualificationForReferredUser(currentUser._id);');
  });

  test('qualified referrals only extend active paid referrer subscriptions', () => {
    expect(referralService).toContain("status: { $in: REWARD_ELIGIBLE_SUBSCRIPTION_STATUSES }");
    expect(referralService).toContain('Referrer must have an active paid subscription to earn bonus days');
    expect(referralService).toContain("referral.status = 'rewarded';");
    expect(referralService).toContain('referrerSubscription.extensionDays =');
  });

  test('customer-facing referral copy matches the 28-day paid-plan policy', () => {
    expect(supportRoutes).toContain('28 bonus days');
    expect(supportPage).toContain('28 bonus days');
    expect(accountPage).toContain('28 bonus days');
    expect(landingV1).toContain('28 bonus days');
  });
});
