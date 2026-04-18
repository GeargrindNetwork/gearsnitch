const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const apiRoot = path.join(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

describe('labs state-eligibility contract (NY/NJ/RI) — mirrors iOS PR #27', () => {
  const stateEligibility = read('src/modules/labs/stateEligibility.ts');
  const labsRoutes = read('src/modules/labs/routes.ts');

  test('stateEligibility module defines the restricted set with NY, NJ, RI', () => {
    expect(stateEligibility).toContain('LAB_RESTRICTED_STATES');
    expect(stateEligibility).toMatch(/new Set\(\[[^\]]*'NY'[^\]]*'NJ'[^\]]*'RI'[^\]]*\]\)/);
  });

  test('stateEligibility exports isRestricted and the canonical error code', () => {
    expect(stateEligibility).toContain('export function isRestricted');
    expect(stateEligibility).toContain("LAB_STATE_RESTRICTED_ERROR_CODE = 'LAB_NOT_AVAILABLE_IN_STATE'");
  });

  test('stateEligibility JSDoc cites Rupa Health policy as source of truth', () => {
    expect(stateEligibility.toLowerCase()).toContain('rupa');
  });

  test('stateEligibility tolerates null/undefined and normalizes case/whitespace', () => {
    // null/undefined/empty short-circuit
    expect(stateEligibility).toMatch(/stateCode === null \|\| stateCode === undefined/);
    // trim + uppercase normalization
    expect(stateEligibility).toContain('.trim().toUpperCase()');
  });

  test('labs routes import isRestricted from the state-eligibility module', () => {
    expect(labsRoutes).toContain("from './stateEligibility.js'");
    expect(labsRoutes).toContain('isRestricted');
  });

  test('labs routes gate POST /labs/orders with the state check before any side-effect', () => {
    expect(labsRoutes).toContain("router.post('/orders', isAuthenticated");
    // Guard must appear before any Mongo/Stripe/provider work in the orders handler.
    const ordersFn = labsRoutes.slice(
      labsRoutes.indexOf('async function handlePlaceLabOrder'),
      labsRoutes.indexOf('async function handleListAppointments'),
    );
    expect(ordersFn).toContain('isRestricted(shippingAddress.state)');
    expect(ordersFn).toContain('sendStateRestrictedResponse');
    // No LabAppointment.create, no Stripe charge in the orders handler before the gate.
    const guardIdx = ordersFn.indexOf('isRestricted(shippingAddress.state)');
    const createIdx = ordersFn.indexOf('LabAppointment.create');
    const stripeIdx = ordersFn.indexOf('stripe');
    expect(guardIdx).toBeGreaterThan(-1);
    // Either absent entirely (preferred) or strictly after the guard.
    if (createIdx !== -1) expect(createIdx).toBeGreaterThan(guardIdx);
    if (stripeIdx !== -1) expect(stripeIdx).toBeGreaterThan(guardIdx);
  });

  test('labs routes also gate POST /labs/schedule for consistency (legacy path)', () => {
    const scheduleFn = labsRoutes.slice(
      labsRoutes.indexOf('async function handleScheduleLab'),
      labsRoutes.indexOf('async function handlePlaceLabOrder'),
    );
    expect(scheduleFn).toContain('isRestricted(shippingState)');
    const guardIdx = scheduleFn.indexOf('isRestricted(shippingState)');
    const createIdx = scheduleFn.indexOf('LabAppointment.create');
    expect(guardIdx).toBeGreaterThan(-1);
    expect(createIdx).toBeGreaterThan(guardIdx);
  });

  test('rejection response uses the exact payload shape iOS PR #27 expects', () => {
    // { error: 'LAB_NOT_AVAILABLE_IN_STATE', state: '<XX>', message: '...' }
    expect(labsRoutes).toContain("error: LAB_STATE_RESTRICTED_ERROR_CODE");
    expect(labsRoutes).toContain('state: normalized');
    expect(labsRoutes).toContain('stateRestrictedMessage(normalized)');
    expect(labsRoutes).toContain('StatusCodes.BAD_REQUEST');
  });
});

describe('labs state-eligibility runtime — isRestricted() behavior', () => {
  test('isRestricted correctly classifies restricted and permitted states', () => {
    const script = `
      const mod = require('./src/modules/labs/stateEligibility.ts');
      const { isRestricted, LAB_RESTRICTED_STATES, LAB_STATE_RESTRICTED_ERROR_CODE } = mod;

      const assertions = [];
      function check(label, actual, expected) {
        if (actual !== expected) {
          assertions.push(label + ' expected=' + expected + ' actual=' + actual);
        }
      }

      // Restricted — all three states, various casings + whitespace
      check('NY upper', isRestricted('NY'), true);
      check('NJ upper', isRestricted('NJ'), true);
      check('RI upper', isRestricted('RI'), true);
      check('ny lower', isRestricted('ny'), true);
      check('nj lower', isRestricted('nj'), true);
      check('ri lower', isRestricted('ri'), true);
      check('Ny mixed', isRestricted('Ny'), true);
      check('NY whitespace', isRestricted('  NY  '), true);
      check('nj whitespace', isRestricted(' nj\\t'), true);

      // Not restricted
      check('CA', isRestricted('CA'), false);
      check('TX', isRestricted('TX'), false);
      check('NV', isRestricted('NV'), false);
      check('FL', isRestricted('FL'), false);

      // Tolerant of null/undefined/empty
      check('null', isRestricted(null), false);
      check('undefined', isRestricted(undefined), false);
      check('empty', isRestricted(''), false);
      check('whitespace only', isRestricted('   '), false);

      // Canonical error code is stable
      check('error code', LAB_STATE_RESTRICTED_ERROR_CODE, 'LAB_NOT_AVAILABLE_IN_STATE');

      // Set contents
      check('set size', LAB_RESTRICTED_STATES.size, 3);
      check('set has NY', LAB_RESTRICTED_STATES.has('NY'), true);
      check('set has NJ', LAB_RESTRICTED_STATES.has('NJ'), true);
      check('set has RI', LAB_RESTRICTED_STATES.has('RI'), true);
      check('set no CA', LAB_RESTRICTED_STATES.has('CA'), false);

      if (assertions.length > 0) {
        console.error('FAIL:\\n' + assertions.join('\\n'));
        process.exit(1);
      }
      console.log('state-eligibility-runtime-ok');
    `;

    const output = execFileSync(process.execPath, ['-r', 'tsx/cjs', '-e', script], {
      cwd: apiRoot,
      encoding: 'utf8',
      stdio: 'pipe',
    });

    expect(output).toContain('state-eligibility-runtime-ok');
  }, 30000);

  test('stateRestrictedMessage formats the canonical user-facing copy', () => {
    const script = `
      const { stateRestrictedMessage } = require('./src/modules/labs/stateEligibility.ts');
      const msg = stateRestrictedMessage('ny');
      if (msg !== 'At-home lab testing is not available in NY due to state regulations.') {
        console.error('FAIL: ' + msg);
        process.exit(1);
      }
      console.log('message-ok');
    `;

    const output = execFileSync(process.execPath, ['-r', 'tsx/cjs', '-e', script], {
      cwd: apiRoot,
      encoding: 'utf8',
      stdio: 'pipe',
    });

    expect(output).toContain('message-ok');
  }, 30000);
});

describe('labs state-eligibility runtime — POST /labs/orders Express integration', () => {
  test('NY shipping state is rejected with 400 and canonical payload; no provider/Mongo side-effect', () => {
    const script = `
      const express = require('express');
      // Stub out auth middleware so the handler runs without a real JWT.
      const authPath = require.resolve('./src/middleware/auth.ts');
      require.cache[authPath] = {
        id: authPath,
        filename: authPath,
        loaded: true,
        exports: {
          isAuthenticated: (req, _res, next) => {
            req.user = { sub: '507f1f77bcf86cd799439011' };
            next();
          },
        },
      };

      // Stub LabAppointment so we can assert it is NOT called.
      let mongoCreateCalls = 0;
      const labApptPath = require.resolve('./src/models/LabAppointment.ts');
      require.cache[labApptPath] = {
        id: labApptPath,
        filename: labApptPath,
        loaded: true,
        exports: {
          LabAppointment: {
            create: async () => { mongoCreateCalls += 1; return { _id: 'never' }; },
            find: () => ({ sort: () => ({ limit: () => ({ lean: async () => [] }) }) }),
            findOneAndUpdate: () => ({ lean: async () => null }),
          },
        },
      };

      const labsRoutes = require('./src/modules/labs/routes.ts').default;
      const app = express();
      app.use(express.json());
      app.use('/labs', labsRoutes);

      const http = require('node:http');
      const server = app.listen(0, async () => {
        const port = server.address().port;
        const assertions = [];

        function postJson(path, body) {
          return new Promise((resolve, reject) => {
            const data = Buffer.from(JSON.stringify(body));
            const req = http.request({
              hostname: '127.0.0.1',
              port,
              path,
              method: 'POST',
              headers: {
                'Content-Type': 'application/json',
                'Content-Length': data.length,
              },
            }, (res) => {
              const chunks = [];
              res.on('data', (c) => chunks.push(c));
              res.on('end', () => {
                const raw = Buffer.concat(chunks).toString('utf8');
                let json;
                try { json = JSON.parse(raw); } catch (_e) { json = null; }
                resolve({ status: res.statusCode, body: json, raw });
              });
            });
            req.on('error', reject);
            req.write(data);
            req.end();
          });
        }

        try {
          // Case 1: NY — must 400 with canonical shape
          const nyRes = await postJson('/labs/orders', {
            productId: 'com.gearsnitch.app.bloodwork',
            paymentToken: 'tok_test',
            shippingAddress: {
              name: 'Test User',
              line1: '1 Test St',
              city: 'New York',
              state: 'NY',
              postalCode: '10001',
              country: 'US',
            },
          });
          if (nyRes.status !== 400) assertions.push('NY status=' + nyRes.status);
          if (!nyRes.body || nyRes.body.error !== 'LAB_NOT_AVAILABLE_IN_STATE') {
            assertions.push('NY error code=' + (nyRes.body && nyRes.body.error));
          }
          if (!nyRes.body || nyRes.body.state !== 'NY') {
            assertions.push('NY state=' + (nyRes.body && nyRes.body.state));
          }
          if (!nyRes.body || !nyRes.body.message || !nyRes.body.message.includes('NY')) {
            assertions.push('NY message=' + (nyRes.body && nyRes.body.message));
          }

          // Case 2: lowercase nj — must still 400
          const njRes = await postJson('/labs/orders', {
            productId: 'com.gearsnitch.app.bloodwork',
            paymentToken: 'tok_test',
            shippingAddress: {
              state: 'nj',
            },
          });
          if (njRes.status !== 400) assertions.push('nj status=' + njRes.status);
          if (!njRes.body || njRes.body.state !== 'NJ') assertions.push('nj normalize=' + (njRes.body && njRes.body.state));

          // Case 3: RI with whitespace — must still 400
          const riRes = await postJson('/labs/orders', {
            productId: 'com.gearsnitch.app.bloodwork',
            paymentToken: 'tok_test',
            shippingAddress: { state: ' RI ' },
          });
          if (riRes.status !== 400) assertions.push('RI status=' + riRes.status);

          // Case 4: CA — should pass the gate (and then get 501 because orders flow is scaffold-only)
          const caRes = await postJson('/labs/orders', {
            productId: 'com.gearsnitch.app.bloodwork',
            paymentToken: 'tok_test',
            shippingAddress: { state: 'CA' },
          });
          if (caRes.status !== 501) assertions.push('CA status=' + caRes.status + ' body=' + caRes.raw);
          // Most importantly: CA must NOT produce the state-restricted error code.
          if (caRes.body && caRes.body.error === 'LAB_NOT_AVAILABLE_IN_STATE') {
            assertions.push('CA incorrectly gated');
          }

          // Case 5: schedule endpoint also gated on NY
          const schedRes = await postJson('/labs/schedule', {
            date: new Date().toISOString(),
            paymentToken: 'tok_test',
            productId: 'com.gearsnitch.app.bloodwork',
            shippingAddress: { state: 'NY' },
          });
          if (schedRes.status !== 400) assertions.push('schedule NY status=' + schedRes.status);
          if (!schedRes.body || schedRes.body.error !== 'LAB_NOT_AVAILABLE_IN_STATE') {
            assertions.push('schedule NY code=' + (schedRes.body && schedRes.body.error));
          }

          // No Mongo writes for any restricted-state request.
          if (mongoCreateCalls !== 0) assertions.push('mongo creates=' + mongoCreateCalls);

          if (assertions.length > 0) {
            console.error('FAIL:\\n' + assertions.join('\\n'));
            process.exit(1);
          }
          console.log('labs-orders-integration-ok');
        } finally {
          server.close();
        }
      });
    `;

    const output = execFileSync(process.execPath, ['-r', 'tsx/cjs', '-e', script], {
      cwd: apiRoot,
      encoding: 'utf8',
      stdio: 'pipe',
    });

    expect(output).toContain('labs-orders-integration-ok');
  }, 30000);
});
