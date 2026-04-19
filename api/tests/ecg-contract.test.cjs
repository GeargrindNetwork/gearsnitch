const fs = require('node:fs');
const path = require('node:path');

const apiRoot = path.join(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

describe('ecg module contract', () => {
  const routes = read('src/modules/ecg/routes.ts');
  const model = read('src/modules/ecg/model.ts');
  const routeIndex = read('src/routes/index.ts');

  test('ecg routes are registered in route index', () => {
    expect(routeIndex).toContain("import ecgRoutes from '../modules/ecg/routes.js'");
    expect(routeIndex).toContain("router.use('/ecg', ecgRoutes)");
  });

  test('records CRUD endpoints require authentication', () => {
    expect(routes).toContain("router.post(\n  '/records',\n  isAuthenticated");
    expect(routes).toContain("router.get('/records', isAuthenticated");
    expect(routes).toContain("router.get('/records/:id', isAuthenticated");
    expect(routes).toContain("router.delete('/records/:id', isAuthenticated");
  });

  test('create schema validates required classification fields', () => {
    expect(routes).toContain('recordedAt: z.string().datetime()');
    expect(routes).toContain('durationSec: z.number().min(0).max(600)');
    expect(routes).toContain('sampleCount: z.number().int().min(0).max(1_000_000)');
    expect(routes).toContain('classification: classificationSchema');
  });

  test('classification schema covers every supported rhythm', () => {
    const rhythms = [
      'sinusRhythm',
      'sinusBradycardia',
      'sinusTachycardia',
      'atrialFibrillation',
      'atrialFlutter',
      'firstDegreeAVBlock',
      'mobitzI',
      'mobitzII',
      'completeHeartBlock',
      'pvc',
      'pac',
      'ventricularTachycardia',
      'supraventricularTachycardia',
      'indeterminate',
    ];
    for (const r of rhythms) {
      expect(routes).toContain(`'${r}'`);
      expect(model).toContain(`'${r}'`);
    }
  });

  test('confidence is clamped to 0..1 in route schema', () => {
    expect(routes).toContain('confidence: z.number().min(0).max(1)');
    expect(model).toContain('confidence: { type: Number, required: true, min: 0, max: 1 }');
  });

  test('model is user-scoped and indexed on (userId, recordedAt)', () => {
    expect(model).toContain("userId: { type: Schema.Types.ObjectId, ref: 'User', required: true }");
    expect(model).toContain('ECGRecordSchema.index({ userId: 1, recordedAt: -1 })');
  });

  test('anomaly schema supports the required anomaly kinds', () => {
    const kinds = ['pvc', 'pac', 'pause', 'droppedBeat', 'wideQRS'];
    for (const k of kinds) {
      expect(routes).toContain(`'${k}'`);
      expect(model).toContain(`'${k}'`);
    }
  });

  test('delete endpoint enforces ownership via userId match', () => {
    expect(routes).toContain('userId: new Types.ObjectId(user.sub)');
    expect(routes).toContain('findOneAndDelete');
  });

  test('list endpoint paginates with page/limit query params', () => {
    expect(routes).toContain("req.query.page");
    expect(routes).toContain("req.query.limit");
    expect(routes).toContain('totalPages');
  });
});
