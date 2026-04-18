const fs = require('node:fs');
const path = require('node:path');

const apiRoot = path.join(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

describe('lab audit middleware', () => {
  const middleware = read('src/middleware/labAudit.ts');
  const model = read('src/models/LabAuditLog.ts');
  const routes = read('src/modules/labs/routes.ts');

  test('middleware is wired into every /labs/* route via router.use', () => {
    expect(routes).toContain("import { labAuditMiddleware }");
    expect(routes).toContain('router.use(labAuditMiddleware)');
  });

  test('middleware runs through the dedicated Pino/Winston child logger name', () => {
    expect(middleware).toContain("logger.child({ logger: 'lab-audit' })");
  });

  test('middleware logs metadata only (no request body, no response body)', () => {
    // If we ever leak `req.body` or `res.body` into a log call, this regex
    // fires. The middleware is allowed to *receive* bodies via Express;
    // it just must not log them.
    expect(middleware).not.toMatch(/logger[^\n]*body/i);
    expect(middleware).not.toMatch(/AUDIT_LOGGER[^\n]*body/i);
    expect(middleware).not.toMatch(/\bbody\b\s*:\s*req\.body/);
  });

  test('middleware persists LabAuditLog entries with safe fields only', () => {
    expect(middleware).toContain('LabAuditLog.create(');
    for (const field of ['userId', 'route', 'method', 'orderId', 'ip', 'userAgent', 'statusCode', 'requestId']) {
      expect(middleware).toContain(field);
    }
    // No PHI-adjacent fields should appear in the persisted record.
    expect(middleware).not.toMatch(/firstName|lastName|dateOfBirth|\bdob\b|patient:/);
  });

  test('audit log model uses its own collection and indexes userId + orderId', () => {
    expect(model).toContain("collection: 'lab_audit_logs'");
    expect(model).toContain('userId: 1');
    expect(model).toContain('orderId: 1');
  });

  test('audit log model does not declare any patient-identity fields', () => {
    for (const field of ['firstName', 'lastName', 'dateOfBirth', 'email', 'phone', 'address', 'testResults', 'results']) {
      expect(model).not.toMatch(new RegExp(`${field}\\s*:`));
    }
  });
});

describe('lab audit middleware runtime', () => {
  const distPath = path.join(apiRoot, 'dist', 'middleware', 'labAudit.js');
  if (!fs.existsSync(distPath)) {
    test.skip('runtime checks require dist/ — run npm run build first', () => {});
    return;
  }

  // Stub out the Mongoose model so we don't require a live DB.
  const modelPath = path.join(apiRoot, 'dist', 'models', 'LabAuditLog.js');
  const createSpy = jest.fn().mockResolvedValue({});
  jest.isolateModules(() => {
    jest.doMock(modelPath, () => ({
      LabAuditLog: { create: createSpy },
    }));
  });

  // Re-require the middleware under the mocked model.
  let labAuditMiddleware;
  jest.isolateModules(() => {
    jest.doMock(modelPath, () => ({
      LabAuditLog: { create: createSpy },
    }));
    ({ labAuditMiddleware } = require(distPath));
  });

  function buildReqRes(overrides = {}) {
    const listeners = {};
    const req = {
      method: 'GET',
      originalUrl: '/api/v1/labs/tests',
      params: {},
      ip: '10.0.0.1',
      get: (header) => (header === 'user-agent' ? 'jest-test' : undefined),
      requestId: 'req-abc',
      user: { sub: '507f1f77bcf86cd799439011' },
      ...overrides,
    };
    const res = {
      statusCode: 200,
      on: (event, handler) => {
        listeners[event] = handler;
      },
      emitFinish: () => listeners.finish?.(),
    };
    return { req, res };
  }

  afterEach(() => {
    createSpy.mockClear();
  });

  test('middleware calls next() synchronously', () => {
    const { req, res } = buildReqRes();
    const next = jest.fn();
    labAuditMiddleware(req, res, next);
    expect(next).toHaveBeenCalledTimes(1);
  });

  test('middleware persists a LabAuditLog entry on response finish', async () => {
    const { req, res } = buildReqRes({ params: { orderId: 'order-xyz' } });
    labAuditMiddleware(req, res, jest.fn());
    res.emitFinish();

    // persistAuditEntry is fire-and-forget; give the microtask queue a tick.
    await new Promise((resolve) => setImmediate(resolve));

    expect(createSpy).toHaveBeenCalledTimes(1);
    const entry = createSpy.mock.calls[0][0];
    expect(entry).toMatchObject({
      route: '/api/v1/labs/tests',
      method: 'GET',
      orderId: 'order-xyz',
      ip: '10.0.0.1',
      userAgent: 'jest-test',
      statusCode: 200,
      requestId: 'req-abc',
    });
    // userId must be the ObjectId-compatible string passed through.
    expect(entry.userId).toBe('507f1f77bcf86cd799439011');
    // Bodies must never reach the persistence layer.
    expect(entry).not.toHaveProperty('body');
    expect(entry).not.toHaveProperty('patient');
    expect(entry).not.toHaveProperty('results');
  });

  test('middleware drops non-ObjectId user ids instead of crashing Mongoose cast', async () => {
    const { req, res } = buildReqRes({ user: { sub: 'not-an-object-id' } });
    labAuditMiddleware(req, res, jest.fn());
    res.emitFinish();
    await new Promise((resolve) => setImmediate(resolve));

    const entry = createSpy.mock.calls[0][0];
    expect(entry.userId).toBeUndefined();
  });
});
