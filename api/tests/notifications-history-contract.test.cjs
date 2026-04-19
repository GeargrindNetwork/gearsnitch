const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const apiRoot = path.join(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

// -----------------------------------------------------------------------------
// Backlog item #23 — GET /notifications/history (web Notifications history).
//
// Static contract checks guard against future refactors silently stripping the
// route, removing auth, or dropping the 25-per-page pagination envelope.
// -----------------------------------------------------------------------------
describe('notifications history contract — static guards (item #23)', () => {
  const routes = read('src/modules/notifications/routes.ts');
  const routesIndex = read('src/routes/index.ts');

  test('notifications module is mounted on the v1 router', () => {
    expect(routesIndex).toContain(
      "import notificationsRoutes from '../modules/notifications/routes.js';",
    );
    expect(routesIndex).toContain("router.use('/notifications', notificationsRoutes);");
  });

  test('/history route is registered and authenticated', () => {
    expect(routes).toMatch(
      /router\.get\(\s*['"]\/history['"]\s*,\s*isAuthenticated\s*,/,
    );
  });

  test('/history pagination schema defaults to 25/page and caps at 100', () => {
    expect(routes).toContain('historySchema');
    // Default page size must be 25 per the item #23 spec.
    expect(routes).toMatch(/limit:\s*z\.coerce\.number\(\)\.int\(\)\.min\(1\)\.max\(100\)\.default\(25\)/);
  });

  test('/history filters by authenticated userId (never cross-user)', () => {
    expect(routes).toMatch(/NotificationLog\.find\(\{\s*userId\s*\}\)/);
    expect(routes).toMatch(/NotificationLog\.countDocuments\(\{\s*userId\s*\}\)/);
  });

  test('/history response envelope exposes items + page/limit/total/totalPages', () => {
    expect(routes).toMatch(/items,\s*page,\s*limit,\s*total,\s*totalPages/);
  });

  test('/history sorts by sentAt descending (newest first)', () => {
    expect(routes).toMatch(/\.sort\(\{\s*sentAt:\s*-1\s*\}\)/);
  });
});

// -----------------------------------------------------------------------------
// Runtime behavior against mongodb-memory-server.
//   1) happy path: 55 notifications paginated 25/page; user A cannot see user B
//   2) empty state: user with no notifications returns 200 + empty items list
//   3) status derivation: openedAt -> read, failureReason -> failed,
//      deliveredAt -> delivered, otherwise sent.
//   4) ?limit validation: non-numeric/negative returns 400
// -----------------------------------------------------------------------------
describe('notifications history contract — runtime behavior (item #23)', () => {
  test('paginates 25/page, scopes to user, derives status correctly', () => {
    const script = `
      const mongoose = require('mongoose');
      const { MongoMemoryServer } = require('mongodb-memory-server');

      process.env.LOG_DIR = process.env.LOG_DIR || '/tmp/gearsnitch-logs-test';
      process.env.NODE_ENV = 'test';

      const express = require('express');
      const { NotificationLog } = require('./src/models/NotificationLog.ts');
      const notificationsRouter = require('./src/modules/notifications/routes.ts').default;

      const app = express();
      app.use(express.json());
      app.use((req, _res, next) => {
        req.user = {
          sub: req.header('x-test-user-id'),
          jti: 't', email: 'e', role: 'r', scope: [], iat: 0, exp: 0,
        };
        next();
      });
      // Strip isAuthenticated so the handler runs against the shim above.
      for (const layer of notificationsRouter.stack) {
        if (!layer.route) continue;
        const stack = layer.route.stack;
        if (stack.length > 1 && stack[0].name === 'isAuthenticated') {
          stack.shift();
        }
      }
      app.use('/notifications', notificationsRouter);

      function request(method, url, { userId } = {}) {
        return new Promise((resolve, reject) => {
          const http = require('http');
          const server = app.listen(0, () => {
            const { port } = server.address();
            const req = http.request({
              hostname: '127.0.0.1', port, path: url, method,
              headers: {
                'content-type': 'application/json',
                'x-test-user-id': userId || '',
              },
            }, (res) => {
              let data = '';
              res.on('data', (c) => { data += c; });
              res.on('end', () => {
                server.close();
                try { resolve({ status: res.statusCode, body: JSON.parse(data) }); }
                catch (e) { resolve({ status: res.statusCode, body: data }); }
              });
            });
            req.on('error', (err) => { server.close(); reject(err); });
            req.end();
          });
        });
      }

      (async () => {
        const mongoServer = await MongoMemoryServer.create();
        await mongoose.connect(mongoServer.getUri(), { serverSelectionTimeoutMS: 15000 });

        try {
          const userA = new mongoose.Types.ObjectId();
          const userB = new mongoose.Types.ObjectId();
          const tokenId = new mongoose.Types.ObjectId();
          const now = Date.now();

          // 55 notifications for user A, newest first. Mix of delivered/failed/read/sent.
          const rows = [];
          // 4 states, deterministic via i % 4:
          //   0 -> delivered (deliveredAt set, no open, no failure)
          //   1 -> read (openedAt set)
          //   2 -> failed (failureReason set, no deliveredAt)
          //   3 -> sent (nothing set; purely queued)
          for (let i = 0; i < 55; i += 1) {
            const sentAt = new Date(now - (55 - i) * 60_000);
            const variant = i % 4;
            rows.push({
              userId: userA, tokenId,
              notificationType: variant === 0 ? 'panic_alarm' : variant === 1 ? 'workout_summary' : variant === 2 ? 'disconnect_warning' : 'referral',
              title: 'Test #' + i,
              body: 'Body for #' + i,
              sentAt,
              deliveredAt: variant === 0 || variant === 1 ? sentAt : null,
              openedAt: variant === 1 ? sentAt : null,
              failureReason: variant === 2 ? 'BadDeviceToken' : null,
            });
          }
          // And 3 rows for user B that must NEVER leak.
          for (let j = 0; j < 3; j += 1) {
            rows.push({
              userId: userB, tokenId,
              notificationType: 'panic_alarm',
              title: 'OTHER USER ' + j,
              body: 'SHOULD NOT APPEAR',
              sentAt: new Date(now - j * 60_000),
              deliveredAt: null, openedAt: null, failureReason: null,
            });
          }
          await NotificationLog.insertMany(rows);

          // ----- Scenario 1: page 1 returns newest 25 rows -----
          const r1 = await request('GET', '/notifications/history?page=1&limit=25', { userId: userA.toString() });
          if (r1.status !== 200) throw new Error('Expected 200, got ' + r1.status + ' body=' + JSON.stringify(r1.body));
          const p1 = r1.body.data;
          if (!p1 || p1.page !== 1 || p1.limit !== 25) throw new Error('Bad page meta: ' + JSON.stringify(p1));
          if (p1.total !== 55) throw new Error('Expected total=55, got ' + p1.total);
          if (p1.totalPages !== 3) throw new Error('Expected totalPages=3, got ' + p1.totalPages);
          if (p1.items.length !== 25) throw new Error('Expected 25 items on page 1, got ' + p1.items.length);
          // Newest first: #54 (idx 54) -> "Test #54"
          if (p1.items[0].title !== 'Test #54') throw new Error('Expected newest first, got ' + p1.items[0].title);
          // Ensure no userB rows leaked.
          if (p1.items.some(x => x.title && x.title.startsWith('OTHER USER'))) {
            throw new Error('User B rows leaked into user A history');
          }

          // ----- Scenario 2: page 3 returns remaining 5 -----
          const r3 = await request('GET', '/notifications/history?page=3&limit=25', { userId: userA.toString() });
          if (r3.status !== 200) throw new Error('Expected 200 for page 3');
          const p3 = r3.body.data;
          if (p3.items.length !== 5) throw new Error('Expected 5 items on page 3, got ' + p3.items.length);
          if (p3.page !== 3) throw new Error('Expected page=3, got ' + p3.page);

          // ----- Scenario 3: status derivation sanity -----
          const statuses = new Set(p1.items.map(x => x.status));
          // We created rows that are delivered, read (openedAt), failed, and sent.
          for (const expected of ['delivered', 'read', 'failed', 'sent']) {
            if (!statuses.has(expected)) {
              throw new Error('Expected status "' + expected + '" in page 1, got ' + JSON.stringify(Array.from(statuses)));
            }
          }

          // ----- Scenario 4: empty state for a user with no notifications -----
          const loner = new mongoose.Types.ObjectId();
          const rEmpty = await request('GET', '/notifications/history', { userId: loner.toString() });
          if (rEmpty.status !== 200) throw new Error('Expected 200 for empty user');
          const empty = rEmpty.body.data;
          if (empty.total !== 0) throw new Error('Expected total=0');
          if (empty.totalPages !== 0) throw new Error('Expected totalPages=0');
          if (empty.items.length !== 0) throw new Error('Expected empty items');

          // ----- Scenario 5: user B only sees own rows -----
          const rB = await request('GET', '/notifications/history', { userId: userB.toString() });
          if (rB.status !== 200) throw new Error('Expected 200 for userB');
          if (rB.body.data.total !== 3) throw new Error('Expected userB total=3, got ' + rB.body.data.total);
          if (rB.body.data.items.some(x => !x.title || !x.title.startsWith('OTHER USER'))) {
            throw new Error('User A rows leaked into user B history');
          }

          // ----- Scenario 6: invalid limit rejected -----
          const rBad = await request('GET', '/notifications/history?limit=-5', { userId: userA.toString() });
          if (rBad.status !== 400) throw new Error('Expected 400 for invalid limit, got ' + rBad.status);

          console.log('notifications-history-runtime-ok');
        } finally {
          await NotificationLog.deleteMany({});
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
      },
    );

    expect(output).toContain('notifications-history-runtime-ok');
  }, 60000);
});
