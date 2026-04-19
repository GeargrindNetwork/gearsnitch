const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const apiRoot = path.join(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

// -----------------------------------------------------------------------------
// Static guards — the four previously-501 endpoints are now live, wired to the
// service layer, and continue to demand authentication.
// -----------------------------------------------------------------------------
describe('gyms geofence + users profile read — static guards', () => {
  const gymRoutes = read('src/modules/gyms/routes.ts');
  const gymService = read('src/modules/gyms/gymService.ts');
  const userRoutes = read('src/modules/users/routes.ts');
  const gymModel = read('src/models/Gym.ts');

  test('gym routes no longer return StatusCodes.NOT_IMPLEMENTED for the four deferred flows', () => {
    // All four previously-501 routes now call the service.
    expect(gymRoutes).toContain('gymService.evaluateLocation(');
    expect(gymRoutes).toContain('gymService.findNearby(');
    expect(gymRoutes).toContain('gymService.checkIn(');
    expect((gymRoutes.match(/StatusCodes\.NOT_IMPLEMENTED/g) || []).length).toBe(0);
  });

  test('gym routes mount the spec-mandated paths under isAuthenticated', () => {
    expect(gymRoutes).toContain("'/:id/evaluate-location',");
    expect(gymRoutes).toContain("'/:id/checkin',");
    // Legacy aliases remain for the iOS client.
    expect(gymRoutes).toContain("router.post(\n  '/evaluate',\n  isAuthenticated");
    expect(gymRoutes).toContain("router.get('/nearby', isAuthenticated");
    expect(gymRoutes).toContain("'/:id/check-in',");
    // Each of the new writes is gated by the auth middleware.
    expect(
      (gymRoutes.match(/isAuthenticated,\s*validateBody\(evaluateLocationSchema\)/g)
        || []).length,
    ).toBeGreaterThanOrEqual(2);
    expect(
      (gymRoutes.match(/isAuthenticated,\s*validateBody\(checkinSchema\)/g) || [])
        .length,
    ).toBeGreaterThanOrEqual(2);
  });

  test('gym service exposes a haversine helper and the three new methods', () => {
    expect(gymService).toContain('export function haversineDistanceMeters');
    expect(gymService).toMatch(/async\s+evaluateLocation\s*\(/);
    expect(gymService).toMatch(/async\s+findNearby\s*\(/);
    expect(gymService).toMatch(/async\s+checkIn\s*\(/);
  });

  test('gym model preserves its 2dsphere index on location', () => {
    expect(gymModel).toContain("GymSchema.index({ location: '2dsphere' })");
  });

  test('users GET /:id is no longer a 501 stub and is scoped by caller identity', () => {
    expect(userRoutes).not.toContain('Get user by ID — not yet implemented');
    expect(userRoutes).toContain("router.get('/:id', isAuthenticated");
    // Non-self branch selects only the public trio.
    expect(userRoutes).toMatch(
      /\.select\(\s*\{\s*_id:\s*1,\s*displayName:\s*1,\s*photoUrl:\s*1\s*\}\s*\)/,
    );
    // The public branch must not serialize private fields.
    expect(userRoutes).toMatch(/if\s*\(callerId\s*===\s*targetId\)/);
  });
});

// -----------------------------------------------------------------------------
// Unit: the haversine helper computes sensible great-circle distances.
// -----------------------------------------------------------------------------
describe('haversineDistanceMeters — unit', () => {
  test('returns 0 for identical points, and SF -> LA in the correct ballpark', () => {
    const output = execFileSync(
      process.execPath,
      [
        '-r',
        'tsx/cjs',
        '-e',
        `
        const { haversineDistanceMeters } = require('./src/modules/gyms/gymService.ts');
        const same = haversineDistanceMeters(
          { lat: 37.7749, lng: -122.4194 },
          { lat: 37.7749, lng: -122.4194 },
        );
        if (same !== 0) {
          throw new Error('expected 0 for identical points, got ' + same);
        }

        // San Francisco to Los Angeles City Hall — ~559 km great-circle.
        const sfToLa = haversineDistanceMeters(
          { lat: 37.7749, lng: -122.4194 },
          { lat: 34.0537, lng: -118.2428 },
        );
        if (sfToLa < 540_000 || sfToLa > 580_000) {
          throw new Error('SF->LA out of band: ' + sfToLa);
        }

        // 100 m north at SF — should be close to 100 m (within 1 m).
        const near = haversineDistanceMeters(
          { lat: 37.7749, lng: -122.4194 },
          { lat: 37.7749 + 100 / 111_320, lng: -122.4194 },
        );
        if (Math.abs(near - 100) > 1) {
          throw new Error('~100m north out of band: ' + near);
        }

        console.log('haversine-unit-ok');
      `,
      ],
      { cwd: path.join(__dirname, '..'), encoding: 'utf8', stdio: 'pipe' },
    );
    expect(output).toContain('haversine-unit-ok');
  }, 30000);
});

// -----------------------------------------------------------------------------
// Runtime integration — mounts the real routers against mongodb-memory-server,
// strips the auth middleware in favor of a tiny header-based shim, and
// exercises every code path the spec requires.
// -----------------------------------------------------------------------------
describe('gyms geofence + users profile read — runtime integration', () => {
  test('evaluate-location, nearby, checkin, and users/:id privacy rules', () => {
    const script = `
      process.env.LOG_DIR = process.env.LOG_DIR || '/tmp/gearsnitch-logs-test';
      process.env.NODE_ENV = 'test';
      process.env.STRIPE_SECRET_KEY = process.env.STRIPE_SECRET_KEY || 'sk_test_stub';

      // Stripe stub — users router imports subscriptionService which constructs Stripe.
      const StripeModule = require('stripe');
      function StripeStub() {
        return {
          subscriptions: { update: async () => ({}), retrieve: async () => ({}) },
          paymentIntents: { create: async () => ({}), retrieve: async () => ({}) },
          paymentMethods: { create: async () => ({}), list: async () => ({ data: [] }) },
          customers: { list: async () => ({ data: [] }), create: async () => ({ id: 'cus_stub' }) },
          webhooks: { constructEvent: () => ({}) },
        };
      }
      StripeStub.default = StripeStub;
      require.cache[require.resolve('stripe')].exports = StripeStub;

      const mongoose = require('mongoose');
      const { MongoMemoryServer } = require('mongodb-memory-server');
      const express = require('express');

      const { User } = require('./src/models/User.ts');
      const { Gym } = require('./src/models/Gym.ts');
      const { GymSession } = require('./src/models/GymSession.ts');
      const gymsRouter = require('./src/modules/gyms/routes.ts').default;
      const usersRouter = require('./src/modules/users/routes.ts').default;

      // Strip isAuthenticated from every route in both routers — we inject the
      // caller via the x-test-user-id header instead. This is the same technique
      // the subscription-cancel contract test uses.
      function stripAuth(router) {
        for (const layer of router.stack) {
          if (!layer.route) continue;
          const stack = layer.route.stack;
          while (stack.length > 1 && stack[0].name === 'isAuthenticated') {
            stack.shift();
          }
        }
      }
      stripAuth(gymsRouter);
      stripAuth(usersRouter);

      const app = express();
      app.use(express.json());
      app.use((req, _res, next) => {
        const sub = req.header('x-test-user-id');
        if (sub) {
          req.user = { sub, jti: 't', email: 'e@example.com', role: 'user', scope: [], iat: 0, exp: 0 };
        }
        next();
      });
      app.use('/gyms', gymsRouter);
      app.use('/users', usersRouter);

      const http = require('http');
      function request(method, url, { userId, body } = {}) {
        return new Promise((resolve, reject) => {
          const server = app.listen(0, () => {
            const { port } = server.address();
            const payload = body !== undefined ? JSON.stringify(body) : null;
            const headers = { 'content-type': 'application/json' };
            if (userId) headers['x-test-user-id'] = userId;
            if (payload) headers['content-length'] = Buffer.byteLength(payload);
            const req = http.request({
              hostname: '127.0.0.1', port, path: url, method, headers,
            }, (res) => {
              let data = '';
              res.on('data', (c) => { data += c; });
              res.on('end', () => {
                server.close();
                try { resolve({ status: res.statusCode, body: JSON.parse(data || '{}') }); }
                catch { resolve({ status: res.statusCode, body: data }); }
              });
            });
            req.on('error', (err) => { server.close(); reject(err); });
            if (payload) req.write(payload);
            req.end();
          });
        });
      }

      (async () => {
        const mongoServer = await MongoMemoryServer.create();
        await mongoose.connect(mongoServer.getUri(), { serverSelectionTimeoutMS: 15000 });

        try {
          // --- Seed two users, one owning five gyms near SF, one unrelated.
          const owner = await User.create({
            email: 'owner@example.com',
            emailHash: 'hash-owner',
            displayName: 'Gym Owner',
            photoUrl: 'https://cdn.example.com/owner.png',
            authProviders: ['password'],
          });
          const other = await User.create({
            email: 'other@example.com',
            emailHash: 'hash-other',
            displayName: 'Other User',
            authProviders: ['password'],
          });

          // SF anchor.
          const anchor = { lat: 37.7749, lng: -122.4194 };
          // Offset helper — approximate meters -> degree for quick seeding.
          const metersNorth = (m) => anchor.lat + m / 111_320;

          const seedSpecs = [
            { name: 'Gym A (on top)',   lat: anchor.lat,            lng: anchor.lng,           radius: 100, isDefault: true },
            { name: 'Gym B (~300 m)',    lat: metersNorth(300),      lng: anchor.lng,           radius: 100 },
            { name: 'Gym C (~1 km)',     lat: metersNorth(1000),     lng: anchor.lng,           radius: 150 },
            { name: 'Gym D (~3 km)',     lat: metersNorth(3000),     lng: anchor.lng,           radius: 150 },
            { name: 'Gym E (far away)',  lat: 40.7128,               lng: -74.0060,             radius: 200 },
          ];
          const gyms = [];
          for (const spec of seedSpecs) {
            const g = await Gym.create({
              userId: owner._id,
              name: spec.name,
              location: { type: 'Point', coordinates: [spec.lng, spec.lat] },
              radiusMeters: spec.radius,
              isDefault: !!spec.isDefault,
            });
            gyms.push(g);
          }

          // -----------------------------------------------------------------
          // 1. POST /gyms/:id/evaluate-location
          // -----------------------------------------------------------------
          // Inside the geofence (same point as gym A).
          const insideRes = await request('POST', '/gyms/' + gyms[0]._id + '/evaluate-location', {
            userId: owner._id.toString(),
            body: { lat: anchor.lat, lng: anchor.lng },
          });
          if (insideRes.status !== 200) {
            throw new Error('evaluate inside expected 200, got ' + insideRes.status + ' ' + JSON.stringify(insideRes.body));
          }
          if (insideRes.body.data.inside !== true) {
            throw new Error('expected inside=true, got ' + JSON.stringify(insideRes.body));
          }
          if (insideRes.body.data.distanceMeters > 1) {
            throw new Error('expected distance ~0 on same point, got ' + insideRes.body.data.distanceMeters);
          }
          if (!insideRes.body.data.evaluatedAt) {
            throw new Error('missing evaluatedAt');
          }

          // Outside the 100m radius (point ~300m away on gym A's fence).
          const outsideRes = await request('POST', '/gyms/' + gyms[0]._id + '/evaluate-location', {
            userId: owner._id.toString(),
            body: { lat: metersNorth(300), lng: anchor.lng },
          });
          if (outsideRes.status !== 200) {
            throw new Error('evaluate outside expected 200, got ' + outsideRes.status);
          }
          if (outsideRes.body.data.inside !== false) {
            throw new Error('expected inside=false for 300m away, got ' + JSON.stringify(outsideRes.body));
          }
          // Expected ~300m — tolerate 10% deviation.
          const d = outsideRes.body.data.distanceMeters;
          if (d < 270 || d > 330) {
            throw new Error('expected ~300m, got ' + d);
          }

          // Cross-tenant should 404 (gym belongs to owner, not other).
          const crossRes = await request('POST', '/gyms/' + gyms[0]._id + '/evaluate-location', {
            userId: other._id.toString(),
            body: { lat: anchor.lat, lng: anchor.lng },
          });
          if (crossRes.status !== 404) {
            throw new Error('cross-tenant evaluate expected 404, got ' + crossRes.status);
          }

          // -----------------------------------------------------------------
          // 2. GET /gyms/nearby
          // -----------------------------------------------------------------
          const nearby2kRes = await request(
            'GET',
            '/gyms/nearby?lat=' + anchor.lat + '&lng=' + anchor.lng + '&radiusMeters=2000',
            { userId: owner._id.toString() },
          );
          if (nearby2kRes.status !== 200) {
            throw new Error('nearby expected 200, got ' + nearby2kRes.status + ' ' + JSON.stringify(nearby2kRes.body));
          }
          const list = nearby2kRes.body.data.gyms;
          // A, B, C should be within 2km — D (3km) and E (NYC) should not.
          if (list.length !== 3) {
            throw new Error('expected 3 gyms within 2km, got ' + list.length + ' — ' + JSON.stringify(list.map(g => g.name)));
          }
          // Ordering: nearest first.
          for (let i = 1; i < list.length; i += 1) {
            if (list[i - 1].distanceMeters > list[i].distanceMeters) {
              throw new Error('nearby not sorted by distance ascending');
            }
          }
          if (list[0].name !== 'Gym A (on top)') {
            throw new Error('expected Gym A nearest, got ' + list[0].name);
          }

          // Big radius picks up D but still excludes the NYC gym.
          const nearby10kRes = await request(
            'GET',
            '/gyms/nearby?lat=' + anchor.lat + '&lng=' + anchor.lng + '&radiusMeters=10000',
            { userId: owner._id.toString() },
          );
          if (nearby10kRes.body.data.gyms.length !== 4) {
            throw new Error('expected 4 gyms within 10km, got ' + nearby10kRes.body.data.gyms.length);
          }

          // Missing lat → 400.
          const badNearby = await request('GET', '/gyms/nearby?lng=' + anchor.lng, {
            userId: owner._id.toString(),
          });
          if (badNearby.status !== 400) {
            throw new Error('expected 400 for missing lat, got ' + badNearby.status);
          }

          // -----------------------------------------------------------------
          // 3. POST /gyms/:id/checkin
          // -----------------------------------------------------------------
          // Outside → 400 with distanceMeters in error details.
          const farCheckin = await request('POST', '/gyms/' + gyms[0]._id + '/checkin', {
            userId: owner._id.toString(),
            body: { lat: metersNorth(500), lng: anchor.lng },
          });
          if (farCheckin.status !== 400) {
            throw new Error('expected 400 for outside check-in, got ' + farCheckin.status);
          }
          if (farCheckin.body.error.message !== 'Not inside gym geofence') {
            throw new Error('unexpected error message: ' + JSON.stringify(farCheckin.body));
          }

          // Inside → 201 + session created.
          const inCheckin = await request('POST', '/gyms/' + gyms[0]._id + '/checkin', {
            userId: owner._id.toString(),
            body: { lat: anchor.lat, lng: anchor.lng },
          });
          if (inCheckin.status !== 201) {
            throw new Error('expected 201 for inside check-in, got ' + inCheckin.status + ' ' + JSON.stringify(inCheckin.body));
          }
          const session1 = inCheckin.body.data.session;
          if (!session1._id) throw new Error('expected session._id');
          if (session1.resumed !== false) throw new Error('first check-in should not be resumed');

          // Idempotent: repeat inside → same session id, resumed=true.
          const repeatCheckin = await request('POST', '/gyms/' + gyms[0]._id + '/checkin', {
            userId: owner._id.toString(),
            body: { lat: anchor.lat, lng: anchor.lng },
          });
          if (repeatCheckin.status !== 201) {
            throw new Error('repeat check-in expected 201, got ' + repeatCheckin.status);
          }
          const session2 = repeatCheckin.body.data.session;
          if (session2._id !== session1._id) {
            throw new Error('expected same session id on idempotent check-in, got ' + session2._id);
          }
          if (session2.resumed !== true) {
            throw new Error('repeat check-in must be resumed=true');
          }

          // Confirm only one session in Mongo.
          const sessionCount = await GymSession.countDocuments({
            userId: owner._id, gymId: gyms[0]._id,
          });
          if (sessionCount !== 1) {
            throw new Error('expected exactly 1 gym session, got ' + sessionCount);
          }

          // -----------------------------------------------------------------
          // 4. GET /users/:id privacy
          // -----------------------------------------------------------------
          // Self → full profile (includes email).
          const selfRes = await request('GET', '/users/' + owner._id, {
            userId: owner._id.toString(),
          });
          if (selfRes.status !== 200) {
            throw new Error('self GET expected 200, got ' + selfRes.status);
          }
          if (selfRes.body.data.email !== 'owner@example.com') {
            throw new Error('self GET should include email');
          }

          // Other → only public trio.
          const otherRes = await request('GET', '/users/' + owner._id, {
            userId: other._id.toString(),
          });
          if (otherRes.status !== 200) {
            throw new Error('other GET expected 200, got ' + otherRes.status);
          }
          const publicFields = otherRes.body.data;
          if (publicFields.email !== undefined) {
            throw new Error('cross-user GET must NOT expose email');
          }
          if (publicFields.referralCode !== undefined) {
            throw new Error('cross-user GET must NOT expose referralCode');
          }
          if (publicFields.permissionsState !== undefined) {
            throw new Error('cross-user GET must NOT expose permissionsState');
          }
          if (publicFields.linkedAccounts !== undefined) {
            throw new Error('cross-user GET must NOT expose linkedAccounts');
          }
          if (publicFields.displayName !== 'Gym Owner') {
            throw new Error('cross-user GET must include displayName');
          }
          if (publicFields.photoUrl !== 'https://cdn.example.com/owner.png') {
            throw new Error('cross-user GET must include photoUrl');
          }
          if (Object.keys(publicFields).sort().join(',') !== '_id,displayName,photoUrl') {
            throw new Error('cross-user GET leaked fields: ' + Object.keys(publicFields).join(','));
          }

          // Unknown user → 404.
          const ghostId = new mongoose.Types.ObjectId().toString();
          const missing = await request('GET', '/users/' + ghostId, {
            userId: owner._id.toString(),
          });
          if (missing.status !== 404) {
            throw new Error('unknown user expected 404, got ' + missing.status);
          }

          // Malformed id → 404.
          const malformed = await request('GET', '/users/not-an-objectid', {
            userId: owner._id.toString(),
          });
          if (malformed.status !== 404) {
            throw new Error('malformed id expected 404, got ' + malformed.status);
          }

          console.log('gyms-geofence-users-runtime-ok');
        } finally {
          await GymSession.deleteMany({});
          await Gym.deleteMany({});
          await User.deleteMany({});
          await mongoose.disconnect();
          await mongoServer.stop();
        }
      })().catch((err) => {
        console.error('RUNTIME_FAIL:', err.message || err);
        if (err.stack) console.error(err.stack);
        process.exit(1);
      });
    `;

    const output = execFileSync(
      process.execPath,
      ['-r', 'tsx/cjs', '-e', script],
      {
        cwd: apiRoot,
        encoding: 'utf8',
        stdio: 'pipe',
        env: {
          ...process.env,
          STRIPE_SECRET_KEY:
            process.env.STRIPE_SECRET_KEY || 'sk_test_' + 'a'.repeat(99),
          STRIPE_WEBHOOK_SECRET:
            process.env.STRIPE_WEBHOOK_SECRET || 'whsec_test_' + 'a'.repeat(32),
        },
      },
    );

    expect(output).toContain('gyms-geofence-users-runtime-ok');
  }, 60000);

  // ---------------------------------------------------------------------------
  // Unauthenticated caller → 401. We exercise this against the real
  // isAuthenticated middleware (no auth stripping) to prove the guard is live.
  // ---------------------------------------------------------------------------
  test('unauthenticated requests to /gyms/:id/evaluate-location and /users/:id → 401', () => {
    const script = `
      process.env.LOG_DIR = process.env.LOG_DIR || '/tmp/gearsnitch-logs-test';
      process.env.NODE_ENV = 'test';
      process.env.STRIPE_SECRET_KEY = process.env.STRIPE_SECRET_KEY || 'sk_test_stub';

      const StripeModule = require('stripe');
      function StripeStub() {
        return {
          subscriptions: { update: async () => ({}), retrieve: async () => ({}) },
          paymentIntents: { create: async () => ({}), retrieve: async () => ({}) },
          paymentMethods: { create: async () => ({}), list: async () => ({ data: [] }) },
          customers: { list: async () => ({ data: [] }), create: async () => ({ id: 'cus_stub' }) },
          webhooks: { constructEvent: () => ({}) },
        };
      }
      StripeStub.default = StripeStub;
      require.cache[require.resolve('stripe')].exports = StripeStub;

      const express = require('express');
      const gymsRouter = require('./src/modules/gyms/routes.ts').default;
      const usersRouter = require('./src/modules/users/routes.ts').default;

      const app = express();
      app.use(express.json());
      app.use('/gyms', gymsRouter);
      app.use('/users', usersRouter);

      const http = require('http');
      function request(method, url, body) {
        return new Promise((resolve, reject) => {
          const server = app.listen(0, () => {
            const { port } = server.address();
            const payload = body !== undefined ? JSON.stringify(body) : null;
            const headers = { 'content-type': 'application/json' };
            if (payload) headers['content-length'] = Buffer.byteLength(payload);
            const req = http.request({
              hostname: '127.0.0.1', port, path: url, method, headers,
            }, (res) => {
              let data = '';
              res.on('data', (c) => { data += c; });
              res.on('end', () => {
                server.close();
                try { resolve({ status: res.statusCode, body: JSON.parse(data || '{}') }); }
                catch { resolve({ status: res.statusCode, body: data }); }
              });
            });
            req.on('error', (err) => { server.close(); reject(err); });
            if (payload) req.write(payload);
            req.end();
          });
        });
      }

      (async () => {
        const ev = await request('POST', '/gyms/507f1f77bcf86cd799439011/evaluate-location', { lat: 0, lng: 0 });
        if (ev.status !== 401) throw new Error('evaluate-location no-auth expected 401, got ' + ev.status);

        const nb = await request('GET', '/gyms/nearby?lat=0&lng=0');
        if (nb.status !== 401) throw new Error('nearby no-auth expected 401, got ' + nb.status);

        const ci = await request('POST', '/gyms/507f1f77bcf86cd799439011/checkin', { lat: 0, lng: 0 });
        if (ci.status !== 401) throw new Error('checkin no-auth expected 401, got ' + ci.status);

        const usr = await request('GET', '/users/507f1f77bcf86cd799439011');
        if (usr.status !== 401) throw new Error('users/:id no-auth expected 401, got ' + usr.status);

        console.log('gyms-users-unauth-ok');
      })().catch((err) => {
        console.error('UNAUTH_FAIL:', err.message || err);
        if (err.stack) console.error(err.stack);
        process.exit(1);
      });
    `;

    const output = execFileSync(
      process.execPath,
      ['-r', 'tsx/cjs', '-e', script],
      {
        cwd: apiRoot,
        encoding: 'utf8',
        stdio: 'pipe',
        env: {
          ...process.env,
          STRIPE_SECRET_KEY:
            process.env.STRIPE_SECRET_KEY || 'sk_test_' + 'a'.repeat(99),
          STRIPE_WEBHOOK_SECRET:
            process.env.STRIPE_WEBHOOK_SECRET || 'whsec_test_' + 'a'.repeat(32),
        },
      },
    );

    expect(output).toContain('gyms-users-unauth-ok');
  }, 30000);
});
