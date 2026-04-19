const fs = require('node:fs');
const path = require('node:path');

const apiRoot = path.join(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

describe('gear retirement + mileage alerts contract (item #4)', () => {
  const routes = read('src/modules/gear/routes.ts');
  const model = read('src/models/GearComponent.ts');
  const modelIndex = read('src/models/index.ts');
  const eventLog = read('src/models/EventLog.ts');
  const apiRoutes = read('src/routes/index.ts');
  const queueService = read('src/services/pushNotificationQueue.ts');

  test('GearComponent model is exported from the model index', () => {
    expect(modelIndex).toContain("export { GearComponent } from './GearComponent';");
    expect(model).toMatch(/mongoose\.model<IGearComponent>\(\s*'GearComponent'/);
  });

  test('GearComponent schema declares the contract fields and enums', () => {
    expect(model).toContain("userId");
    expect(model).toContain("deviceId");
    expect(model).toContain("name");
    expect(model).toContain("kind");
    expect(model).toContain("unit");
    expect(model).toContain("lifeLimit");
    expect(model).toContain("warningThreshold");
    expect(model).toContain("currentValue");
    expect(model).toContain("status");
    expect(model).toContain("retiredAt");

    // Enum values from the spec
    for (const kind of ['shoe', 'chain', 'tire', 'cassette', 'helmet', 'battery', 'other']) {
      expect(model).toContain(`'${kind}'`);
    }
    for (const unit of ['miles', 'km', 'hours', 'sessions']) {
      expect(model).toContain(`'${unit}'`);
    }
    for (const status of ['active', 'retired', 'archived']) {
      expect(model).toContain(`'${status}'`);
    }
  });

  test('GearComponent indexes the user+status compound key', () => {
    expect(model).toContain('GearComponentSchema.index({ userId: 1, status: 1 })');
  });

  test('warningThreshold defaults to 0.85', () => {
    expect(model).toMatch(/warningThreshold:\s*\{[^}]*default:\s*0\.85/);
  });

  test('gear routes are mounted at /gear under the API surface', () => {
    expect(apiRoutes).toContain("import gearRoutes from '../modules/gear/routes.js';");
    expect(apiRoutes).toContain("router.use('/gear', gearRoutes);");
  });

  test('all 5 CRUD endpoints exist and require authentication', () => {
    expect(routes).toContain("router.post(\n  '/',\n  isAuthenticated");
    expect(routes).toContain("router.get('/', isAuthenticated");
    expect(routes).toContain("router.patch(\n  '/:id',\n  isAuthenticated");
    expect(routes).toContain("router.post(\n  '/:id/log-usage',\n  isAuthenticated");
    expect(routes).toContain("router.post('/:id/retire', isAuthenticated");
  });

  test('log-usage atomically increments via $inc and detects crossings', () => {
    expect(routes).toContain("$inc: { currentValue: amount }");
    expect(routes).toContain("evaluateThresholdCrossings");
    expect(routes).toContain("crossedWarning");
    expect(routes).toContain("crossedRetirement");
  });

  test('log-usage enqueues APNs push for both warning and retirement', () => {
    expect(routes).toContain("enqueuePushNotification");
    expect(routes).toContain("'Gear approaching retirement'");
    expect(routes).toContain("'Gear ready to retire'");
    expect(routes).toContain("type: 'gear_warning'");
    expect(routes).toContain("type: 'gear_retirement'");
  });

  test('log-usage deduplicates pushes per component', () => {
    expect(routes).toContain('dedupeKey: `gear-warning:');
    expect(routes).toContain('dedupeKey: `gear-retirement:');
  });

  test('retirement crossing auto-flips status to retired', () => {
    expect(routes).toContain("status: 'retired'");
    expect(routes).toContain("retiredAt: new Date()");
  });

  test('explicit retire endpoint sets retired status and emits event', () => {
    expect(routes).toContain("eventType: 'GearRetired'");
  });

  test('EventLog gained the three gear event types', () => {
    expect(eventLog).toContain("'GearWarningCrossed'");
    expect(eventLog).toContain("'GearRetirementCrossed'");
    expect(eventLog).toContain("'GearRetired'");
  });

  test('push notification queue helper is API-side and exposes a test override', () => {
    expect(queueService).toContain("export async function enqueuePushNotification");
    expect(queueService).toContain("__setPushNotificationEnqueueOverrideForTests");
    expect(queueService).toContain("'push-notifications'");
  });

  test('routes do not touch payment/auth/subscription surface', () => {
    expect(routes).not.toMatch(/PaymentService|appleServerNotifications|referralService/);
  });
});

// ---------------------------------------------------------------------------
// Threshold crossing logic — pure-function unit tests. We import the helper
// via tsx so we can exercise the real implementation rather than a copy.
// ---------------------------------------------------------------------------

describe('gear threshold crossing detection', () => {
  const { execFileSync } = require('node:child_process');

  function runCase(prev, next, limit, threshold) {
    const script = `
      const { evaluateThresholdCrossings } = require('./src/modules/gear/routes.ts');
      const out = evaluateThresholdCrossings(${prev}, ${next}, ${limit}, ${threshold});
      process.stdout.write(JSON.stringify(out));
    `;
    const out = execFileSync(process.execPath, ['-r', 'tsx/cjs', '-e', script], {
      cwd: apiRoot,
      encoding: 'utf8',
      timeout: 30000,
    });
    return JSON.parse(out);
  }

  test('does not fire when usage stays below warning band', () => {
    const result = runCase(0, 100, 400, 0.85);
    expect(result).toEqual({ crossedWarning: false, crossedRetirement: false });
  }, 30000);

  test('fires warning exactly once on the crossing edge', () => {
    const result = runCase(330, 350, 400, 0.85); // 85% of 400 == 340
    expect(result).toEqual({ crossedWarning: true, crossedRetirement: false });
  }, 30000);

  test('does not refire warning once already past it', () => {
    const result = runCase(360, 380, 400, 0.85);
    expect(result).toEqual({ crossedWarning: false, crossedRetirement: false });
  }, 30000);

  test('fires both warning and retirement when a single big log skips both bands', () => {
    const result = runCase(0, 400, 400, 0.85);
    expect(result).toEqual({ crossedWarning: true, crossedRetirement: true });
  }, 30000);

  test('fires retirement on hitting exactly the limit', () => {
    const result = runCase(395, 400, 400, 0.85);
    expect(result).toEqual({ crossedWarning: false, crossedRetirement: true });
  }, 30000);

  test('does not refire retirement once past it', () => {
    const result = runCase(400, 410, 400, 0.85);
    expect(result).toEqual({ crossedWarning: false, crossedRetirement: false });
  }, 30000);
});
