const fs = require('node:fs');
const path = require('node:path');

const repoRoot = path.join(__dirname, '..', '..');

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

describe('GET /referrals/me history contract — dashboard polish (backlog #25)', () => {
  const referralRoutes = read('api/src/modules/referrals/routes.ts');

  test('history entries include rewardDays so iOS can render the "+28d" badge', () => {
    // Rewarded rows surface the actual bonus days, unrewarded rows
    // surface `null` so the iOS client can distinguish "not yet
    // earned" from "zero-day reward".
    expect(referralRoutes).toMatch(
      /rewardDays:\s*item\.status\s*===\s*'rewarded'[\s\S]{0,120}:\s*null,/,
    );
  });

  test('history entries include rewardedAt so the dashboard can show the earn date', () => {
    expect(referralRoutes).toMatch(/rewardedAt:\s*item\.rewardedAt\s*\?\?\s*null,/);
  });

  test('history entries include reason so pending rows can render a hint', () => {
    // e.g. "Awaiting qualifying subscription" — the iOS client shows
    // the reason as a secondary label on pending rows.
    expect(referralRoutes).toMatch(/reason:\s*item\.reason\s*\?\?\s*null,/);
  });

  test('history entries still include the originally-shipped fields', () => {
    // Regression guard — the polish must stay additive. If the fields
    // below disappear, the iOS `ReferralView` stops rendering rows
    // altogether.
    expect(referralRoutes).toContain('_id: String(item._id),');
    expect(referralRoutes).toContain('status: mapReferralHistoryStatus(item.status),');
    expect(referralRoutes).toContain('createdAt: item.createdAt,');
  });

  test('status mapper still normalises qualified/rewarded → completed', () => {
    // The iOS badge colour legend assumes only "pending", "completed",
    // "expired" reach the client. A regression here would leak
    // internal enum values and break the badge styling.
    expect(referralRoutes).toMatch(
      /status === 'rewarded'[^;]*status === 'qualified'[\s\S]{0,80}return 'completed';/,
    );
    expect(referralRoutes).toMatch(
      /status === 'rejected'[\s\S]{0,40}return 'expired';/,
    );
  });
});
