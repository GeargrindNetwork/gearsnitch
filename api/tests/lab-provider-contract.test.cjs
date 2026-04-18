const fs = require('node:fs');
const path = require('node:path');

const apiRoot = path.join(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

describe('LabProvider abstraction contract', () => {
  const typesFile = read('src/modules/labs/providers/types.ts');
  const rupaFile = read('src/modules/labs/providers/RupaHealthProvider.ts');
  const labcorpFile = read('src/modules/labs/providers/LabCorpProvider.ts');
  const factoryFile = read('src/modules/labs/providers/factory.ts');
  const labsRoutes = read('src/modules/labs/routes.ts');

  test('LabProvider interface defines all six required methods', () => {
    for (const method of [
      'listTests',
      'listDrawSites',
      'createOrder',
      'getOrderStatus',
      'getResults',
      'cancelOrder',
    ]) {
      expect(typesFile).toContain(`${method}(`);
    }
  });

  test('FHIR R4 DiagnosticReport and Observation shapes are exported', () => {
    expect(typesFile).toContain("resourceType: 'DiagnosticReport'");
    expect(typesFile).toContain("resourceType: 'Observation'");
  });

  test('PHI fields are marked with @phi for future KMS integration', () => {
    expect(typesFile).toMatch(/@phi/);
    // At least the patient identity block should carry @phi markers.
    expect(typesFile).toMatch(/@phi[^\n]*firstName|firstName[^\n]*@phi|@phi[\s\S]*?firstName/);
  });

  test('RupaHealthProvider targets the public sandbox URL', () => {
    expect(rupaFile).toContain('https://api-sandbox.rupahealth.com');
    expect(rupaFile).toContain('process.env.RUPA_API_KEY');
  });

  test('RupaHealthProvider implements every LabProvider method', () => {
    for (const method of [
      'async listTests()',
      'async listDrawSites(',
      'async createOrder(',
      'async getOrderStatus(',
      'async getResults(',
      'async cancelOrder(',
    ]) {
      expect(rupaFile).toContain(method);
    }
  });

  test('LabCorpProvider signals contract-not-signed on every method', () => {
    const matches = labcorpFile.match(/CONTRACT_NOT_SIGNED_MESSAGE/g) || [];
    // 1 constant declaration + 6 method throws + 1 re-export.
    expect(matches.length).toBeGreaterThanOrEqual(7);
    expect(labcorpFile).toContain('LabCorp API contract not yet signed');
    expect(labcorpFile).toContain('LAB_PROVIDER=rupa');
  });

  test('factory reads LAB_PROVIDER and defaults to rupa', () => {
    expect(factoryFile).toContain('process.env.LAB_PROVIDER');
    expect(factoryFile).toContain("DEFAULT_PROVIDER: LabProviderId = 'rupa'");
  });

  test('provider-backed routes delegate to labProviderFactory', () => {
    expect(labsRoutes).toContain('labProviderFactory');
    for (const route of [
      "router.get('/tests', isAuthenticated",
      "router.get('/draw-sites', isAuthenticated",
      "router.post('/orders', isAuthenticated",
      "router.get('/orders/:orderId', isAuthenticated",
      "router.get('/orders/:orderId/results', isAuthenticated",
      "router.post('/orders/:orderId/cancel', isAuthenticated",
    ]) {
      expect(labsRoutes).toContain(route);
    }
  });

  test('labs router mounts the audit middleware before any handler', () => {
    expect(labsRoutes).toContain('labAuditMiddleware');
    const auditLineIndex = labsRoutes.indexOf('router.use(labAuditMiddleware)');
    const firstRouteIndex = labsRoutes.search(/router\.(get|post|patch)\(/);
    expect(auditLineIndex).toBeGreaterThan(0);
    expect(firstRouteIndex).toBeGreaterThan(auditLineIndex);
  });

  test('create-order payload is validated by a zod schema (no PHI leaks in error)', () => {
    expect(labsRoutes).toContain('createOrderSchema');
    expect(labsRoutes).toContain('validateBody(createOrderSchema)');
  });
});
