const fs = require('node:fs');
const path = require('node:path');

const apiRoot = path.join(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

describe('cycles domain backend contract', () => {
  const cyclesRoutes = read('src/modules/cycles/routes.ts');
  const apiRoutes = read('src/routes/index.ts');
  const modelIndex = read('src/models/index.ts');
  const cycleModel = read('src/models/Cycle.ts');
  const cycleEntryModel = read('src/models/CycleEntry.ts');

  test('cycles routes are mounted under the authenticated API surface', () => {
    expect(apiRoutes).toContain("import cyclesRoutes from '../modules/cycles/routes.js';");
    expect(apiRoutes).toContain("router.use('/cycles', cyclesRoutes);");
  });

  test('cycle CRUD, entry management, and reporting endpoints are present', () => {
    expect(cyclesRoutes).toContain("router.get('/', isAuthenticated");
    expect(cyclesRoutes).toContain("router.post(\n  '/',\n  isAuthenticated");
    expect(cyclesRoutes).toContain("router.get('/day/:date', isAuthenticated");
    expect(cyclesRoutes).toContain("router.get('/month', isAuthenticated");
    expect(cyclesRoutes).toContain("router.get('/year', isAuthenticated");
    expect(cyclesRoutes).toContain("router.get('/:id', isAuthenticated");
    expect(cyclesRoutes).toContain("router.patch(\n  '/:id',\n  isAuthenticated");
    expect(cyclesRoutes).toContain("router.delete('/:id', isAuthenticated");
    expect(cyclesRoutes).toContain("router.get('/:id/entries', isAuthenticated");
    expect(cyclesRoutes).toContain("router.post(\n  '/:id/entries',\n  isAuthenticated");
    expect(cyclesRoutes).toContain("router.patch(\n  '/entries/:entryId',\n  isAuthenticated");
    expect(cyclesRoutes).toContain("router.delete('/entries/:entryId', isAuthenticated");
  });

  test('cycle and cycle-entry are dedicated models with exports', () => {
    expect(modelIndex).toContain("export { Cycle } from './Cycle';");
    expect(modelIndex).toContain("export { CycleEntry } from './CycleEntry';");
    expect(cycleModel).toContain("mongoose.model<ICycle>('Cycle'");
    expect(cycleEntryModel).toContain("mongoose.model<ICycleEntry>('CycleEntry'");
    expect(cycleModel).not.toContain('DosingHistory');
    expect(cycleEntryModel).not.toContain('DosingHistory');
  });
});
