const fs = require('node:fs');
const path = require('node:path');

const apiRoot = path.join(__dirname, '..');
const repoRoot = path.join(apiRoot, '..');

function readFromApi(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

function readFromRepo(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

describe('medication dose backend contract', () => {
  const apiRoutes = readFromApi('src/routes/index.ts');
  const modelIndex = readFromApi('src/models/index.ts');
  const calendarRoutes = readFromApi('src/modules/calendar/routes.ts');
  const sharedSchemas = readFromRepo('shared/src/schemas/index.ts');
  const sharedTypes = readFromRepo('shared/src/types/index.ts');

  test('medication routes are mounted under the API surface', () => {
    expect(apiRoutes).toContain(
      "import medicationsRoutes from '../modules/medications/routes.js';",
    );
    expect(apiRoutes).toContain("router.use('/medications', medicationsRoutes);");
  });

  test('medication routes expose CRUD and reporting endpoints', () => {
    const medicationsRoutes = readFromApi('src/modules/medications/routes.ts');

    expect(medicationsRoutes).toContain("router.get('/doses', isAuthenticated");
    expect(medicationsRoutes).toContain("router.post(\n  '/doses',\n  isAuthenticated");
    expect(medicationsRoutes).toContain(
      "router.patch(\n  '/doses/:doseId',\n  isAuthenticated",
    );
    expect(medicationsRoutes).toContain(
      "router.delete('/doses/:doseId', isAuthenticated",
    );
    expect(medicationsRoutes).toContain("router.get('/day/:date', isAuthenticated");
    expect(medicationsRoutes).toContain("router.get('/month', isAuthenticated");
    expect(medicationsRoutes).toContain("router.get('/graph/year', isAuthenticated");
  });

  test('medication dose has a dedicated model and export', () => {
    const medicationDoseModel = readFromApi('src/models/MedicationDose.ts');

    expect(modelIndex).toContain("export { MedicationDose } from './MedicationDose';");
    expect(modelIndex).toContain('MedicationDoseCategory');
    expect(medicationDoseModel).toContain("mongoose.model<IMedicationDose>('MedicationDose'");
    expect(medicationDoseModel).toContain("category: { type: String");
    expect(medicationDoseModel).toContain("'oralMedication'");
  });

  test('shared schemas and types define medication graph and overlay contracts', () => {
    expect(sharedSchemas).toContain('export const medicationDoseCategorySchema');
    expect(sharedSchemas).toContain('export const medicationDoseSchema');
    expect(sharedSchemas).toContain('export const medicationYearGraphResponseSchema');
    expect(sharedSchemas).toContain('export const calendarMedicationOverlaySchema');

    expect(sharedTypes).toContain('export type MedicationDoseCategoryValue');
    expect(sharedTypes).toContain('export interface IMedicationDose');
    expect(sharedTypes).toContain('export interface MedicationYearGraphResponse');
    expect(sharedTypes).toContain('export interface CalendarMedicationOverlay');
  });

  test('calendar routes support additive medication overlays', () => {
    expect(calendarRoutes).toContain("import { MedicationDose } from '../../models/MedicationDose.js';");
    expect(calendarRoutes).toContain('const includeMedication');
    expect(calendarRoutes).toContain('medication: {');
    expect(calendarRoutes).toContain('categoryDoseMg');
    expect(calendarRoutes).toContain('medicationDoses');
    expect(calendarRoutes).toContain('medicationTotals');
  });
});
