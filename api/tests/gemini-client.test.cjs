/**
 * Unit tests for api/src/services/geminiClient.ts.
 *
 * Pattern mirrors apns-client.test.cjs:
 *   - Source-level contract tests pin invariants a reviewer cares about.
 *   - Runtime tests spawn a child tsx/cjs process, hook Module._resolveFilename
 *     so `require('@google-cloud/vertexai')` returns an in-memory stub, then
 *     assert on the stringified result. This keeps env manipulation and
 *     SDK mocking fully isolated per-case.
 */

const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const apiRoot = path.join(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

// ---------------------------------------------------------------------------
// Source-level contract
// ---------------------------------------------------------------------------

describe('geminiClient — source contract', () => {
  const src = read('src/services/geminiClient.ts');

  test('uses @google-cloud/vertexai SDK', () => {
    expect(src).toContain("from '@google-cloud/vertexai'");
    expect(src).toContain("require('@google-cloud/vertexai')");
  });

  test('targets gemini-2.5-flash', () => {
    expect(src).toContain("MODEL_ID = 'gemini-2.5-flash'");
  });

  test('enforces the three guardrails requested in the spec', () => {
    expect(src).toContain('MAX_OUTPUT_TOKENS = 80');
    expect(src).toContain('TEMPERATURE = 0.7');
    expect(src).toContain('REQUEST_TIMEOUT_MS = 3_000');
  });

  test('applies BLOCK_MEDIUM_AND_ABOVE safety setting', () => {
    expect(src).toContain('BLOCK_MEDIUM_AND_ABOVE');
  });

  test('is feature-flagged via GEMINI_INSIGHTS_ENABLED', () => {
    expect(src).toContain('GEMINI_INSIGHTS_ENABLED');
    expect(src).toMatch(/flagEnabled\s*\(\)/);
  });

  test('uses lazy Proxy/init pattern (no module-load env dep)', () => {
    // _model starts null and is only constructed inside generativeModel()
    expect(src).toMatch(/let _model:\s*GenerativeModel \| null = null/);
    expect(src).toMatch(/if \(_model === null\)/);
  });

  test('defaults project to gearsnitch and location to us-central1', () => {
    expect(src).toContain("'gearsnitch'");
    expect(src).toContain("'us-central1'");
  });

  test('never logs full prompt or completion text', () => {
    // We should log metadata only — scan the logger.info / logger.warn calls.
    // Prompt/completion would require `userMessage` or `insight` in the meta.
    const insightLogBlock = src.match(/logger\.info\('gemini\.insight',[\s\S]*?\}\);/);
    expect(insightLogBlock).not.toBeNull();
    expect(insightLogBlock[0]).not.toMatch(/userMessage|input:|insight:|completion:|response:/);

    const errLogBlock = src.match(/logger\.warn\('gemini\.insight\.error',[\s\S]*?\}\);/);
    expect(errLogBlock).not.toBeNull();
    expect(errLogBlock[0]).not.toMatch(/userMessage|input:|insight:|completion:/);
  });

  test('exports generateWorkoutInsight and pingGemini', () => {
    expect(src).toContain('export async function generateWorkoutInsight');
    expect(src).toContain('export async function pingGemini');
  });

  test('returns null (not throws) on generateWorkoutInsight failure paths', () => {
    // The catch block in generateWorkoutInsight must `return null`
    expect(src).toMatch(/catch \(err\) \{[\s\S]*?return null;\s*\}/);
  });
});

// ---------------------------------------------------------------------------
// Runtime: child-process scenarios with a fake @google-cloud/vertexai
// ---------------------------------------------------------------------------

function runScenario({ env, vertexaiMock, body }) {
  const script = `
    const Module = require('module');
    const originalResolve = Module._resolveFilename;
    const VERTEX_MOCK_PATH = require('path').join(process.cwd(), '__vertexai_mock__.cjs');
    Module._resolveFilename = function (request, ...rest) {
      if (request === '@google-cloud/vertexai') {
        return VERTEX_MOCK_PATH;
      }
      return originalResolve.call(this, request, ...rest);
    };

    // Provide the mock via Module._cache so the require() hits memory, not disk.
    const mockModule = new Module(VERTEX_MOCK_PATH);
    mockModule.filename = VERTEX_MOCK_PATH;
    mockModule.loaded = true;
    mockModule.exports = (function () {
      ${vertexaiMock}
      return module.exports;
    })();
    Module._cache[VERTEX_MOCK_PATH] = mockModule;

    const { generateWorkoutInsight, pingGemini, __resetGeminiForTests } =
      require('./src/services/geminiClient');
    __resetGeminiForTests();

    (async () => {
      ${body}
    })().catch((err) => {
      process.stderr.write('REJECTED:' + err.message);
      process.exit(1);
    });
  `;

  const raw = execFileSync(process.execPath, ['-r', 'tsx/cjs', '-e', script], {
    cwd: apiRoot,
    encoding: 'utf8',
    env: {
      ...process.env,
      GEMINI_INSIGHTS_ENABLED: 'true',
      GCP_PROJECT_ID: 'gearsnitch',
      GCP_LOCATION: 'us-central1',
      ...env,
    },
  });
  // Child emits the winston logger lines on stdout alongside our marker.
  // Strip everything before __RESULT__: so the caller can JSON.parse cleanly.
  const idx = raw.indexOf('__RESULT__:');
  if (idx === -1) {
    throw new Error('child did not emit __RESULT__ marker: ' + raw);
  }
  return raw.slice(idx + '__RESULT__:'.length);
}

// Shared harness: a minimal VertexAI stub that records the last request
// and returns a caller-supplied response.
const BASE_MOCK = `
  const calls = { generateContent: [] };
  let nextResult = null;
  let nextError = null;
  function setNextResult(r) { nextResult = r; nextError = null; }
  function setNextError(e) { nextError = e; nextResult = null; }
  class FakeGenerativeModel {
    async generateContent(req) {
      calls.generateContent.push(req);
      if (nextError) throw nextError;
      return nextResult ?? { response: { candidates: [] } };
    }
  }
  class FakeVertexAI {
    constructor(opts) { this.opts = opts; }
    getGenerativeModel() { return new FakeGenerativeModel(); }
  }
  module.exports = {
    VertexAI: FakeVertexAI,
    HarmCategory: {
      HARM_CATEGORY_HATE_SPEECH: 'HARM_CATEGORY_HATE_SPEECH',
      HARM_CATEGORY_DANGEROUS_CONTENT: 'HARM_CATEGORY_DANGEROUS_CONTENT',
      HARM_CATEGORY_SEXUALLY_EXPLICIT: 'HARM_CATEGORY_SEXUALLY_EXPLICIT',
      HARM_CATEGORY_HARASSMENT: 'HARM_CATEGORY_HARASSMENT',
    },
    HarmBlockThreshold: {
      BLOCK_MEDIUM_AND_ABOVE: 'BLOCK_MEDIUM_AND_ABOVE',
    },
    __calls: calls,
    __setNextResult: setNextResult,
    __setNextError: setNextError,
  };
`;

describe('geminiClient — runtime behaviour (mocked SDK)', () => {
  test('returns trimmed string and caps at ~200 chars on canned response', () => {
    const body = `
      const vertex = require('@google-cloud/vertexai');
      vertex.__setNextResult({
        response: {
          candidates: [{
            finishReason: 'STOP',
            content: { parts: [{ text: '   Solid 45-minute ride — keep your cadence steady tomorrow.   ' }] },
          }],
          usageMetadata: { promptTokenCount: 80, candidatesTokenCount: 12, totalTokenCount: 92 },
        },
      });
      const out = await generateWorkoutInsight({
        activityType: 'cycling',
        durationMin: 45,
      });
      process.stdout.write('__RESULT__:' + JSON.stringify({ out }));
    `;

    const stdout = runScenario({ env: {}, vertexaiMock: BASE_MOCK, body });
    const parsed = JSON.parse(stdout);
    expect(parsed.out).toBe('Solid 45-minute ride — keep your cadence steady tomorrow.');
  });

  test('length-caps an overlong model response under ~200 chars', () => {
    const longText = 'a'.repeat(400);
    const body = `
      const vertex = require('@google-cloud/vertexai');
      vertex.__setNextResult({
        response: {
          candidates: [{
            finishReason: 'STOP',
            content: { parts: [{ text: ${JSON.stringify(longText)} }] },
          }],
        },
      });
      const out = await generateWorkoutInsight({ activityType: 'run', durationMin: 30 });
      process.stdout.write('__RESULT__:' + JSON.stringify({ out, len: (out || '').length }));
    `;

    const stdout = runScenario({ env: {}, vertexaiMock: BASE_MOCK, body });
    const parsed = JSON.parse(stdout);
    expect(typeof parsed.out).toBe('string');
    expect(parsed.len).toBeLessThanOrEqual(200);
    expect(parsed.len).toBeGreaterThan(150);
  });

  test('returns null when SDK throws a network error', () => {
    const body = `
      const vertex = require('@google-cloud/vertexai');
      vertex.__setNextError(new Error('ECONNRESET'));
      const out = await generateWorkoutInsight({ activityType: 'run', durationMin: 20 });
      process.stdout.write('__RESULT__:' + JSON.stringify({ out }));
    `;

    const stdout = runScenario({ env: {}, vertexaiMock: BASE_MOCK, body });
    expect(JSON.parse(stdout)).toEqual({ out: null });
  });

  test('returns null without calling SDK when GEMINI_INSIGHTS_ENABLED=false', () => {
    const body = `
      const vertex = require('@google-cloud/vertexai');
      vertex.__setNextResult({
        response: {
          candidates: [{
            finishReason: 'STOP',
            content: { parts: [{ text: 'should-not-be-returned' }] },
          }],
        },
      });
      const out = await generateWorkoutInsight({ activityType: 'run', durationMin: 20 });
      process.stdout.write('__RESULT__:' + JSON.stringify({ out, calls: vertex.__calls.generateContent.length }));
    `;

    const stdout = runScenario({
      env: { GEMINI_INSIGHTS_ENABLED: 'false' },
      vertexaiMock: BASE_MOCK,
      body,
    });
    const parsed = JSON.parse(stdout);
    expect(parsed.out).toBeNull();
    expect(parsed.calls).toBe(0);
  });

  test('returns null when the model emits only whitespace', () => {
    const body = `
      const vertex = require('@google-cloud/vertexai');
      vertex.__setNextResult({
        response: {
          candidates: [{
            finishReason: 'STOP',
            content: { parts: [{ text: '   \\n   \\t   ' }] },
          }],
        },
      });
      const out = await generateWorkoutInsight({ activityType: 'run', durationMin: 20 });
      process.stdout.write('__RESULT__:' + JSON.stringify({ out }));
    `;

    const stdout = runScenario({ env: {}, vertexaiMock: BASE_MOCK, body });
    expect(JSON.parse(stdout)).toEqual({ out: null });
  });

  test('returns null on safety-blocked response', () => {
    const body = `
      const vertex = require('@google-cloud/vertexai');
      vertex.__setNextResult({
        response: {
          candidates: [{
            finishReason: 'SAFETY',
            content: { parts: [] },
            safetyRatings: [{ blocked: true }],
          }],
          promptFeedback: { blockReason: 'SAFETY' },
        },
      });
      const out = await generateWorkoutInsight({ activityType: 'run', durationMin: 20 });
      process.stdout.write('__RESULT__:' + JSON.stringify({ out }));
    `;

    const stdout = runScenario({ env: {}, vertexaiMock: BASE_MOCK, body });
    expect(JSON.parse(stdout)).toEqual({ out: null });
  });

  test('pingGemini returns { model, response, latencyMs } on success', () => {
    const body = `
      const vertex = require('@google-cloud/vertexai');
      vertex.__setNextResult({
        response: {
          candidates: [{
            finishReason: 'STOP',
            content: { parts: [{ text: 'ok' }] },
          }],
        },
      });
      const result = await pingGemini();
      process.stdout.write('__RESULT__:' + JSON.stringify(result));
    `;

    const stdout = runScenario({ env: {}, vertexaiMock: BASE_MOCK, body });
    const parsed = JSON.parse(stdout);
    expect(parsed.model).toBe('gemini-2.5-flash');
    expect(parsed.response).toBe('ok');
    expect(typeof parsed.latencyMs).toBe('number');
  });
});

// ---------------------------------------------------------------------------
// /admin/ai/ping route contract (source-level)
// ---------------------------------------------------------------------------

describe('/admin/ai/ping route wiring', () => {
  const adminRoutes = read('src/modules/admin/routes.ts');

  test('route is registered and admin-only via router.use', () => {
    expect(adminRoutes).toContain("router.use(isAuthenticated, hasRole(['admin']))");
    expect(adminRoutes).toContain("router.get('/ai/ping'");
    expect(adminRoutes).toContain('pingGemini');
  });

  test('surfaces errors as 5xx (does not swallow)', () => {
    expect(adminRoutes).toMatch(/\/ai\/ping[\s\S]*?Gemini ping failed/);
  });
});
