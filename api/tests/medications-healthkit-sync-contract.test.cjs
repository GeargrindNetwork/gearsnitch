const fs = require('node:fs');
const path = require('node:path');

const apiRoot = path.join(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

describe('medication dose HealthKit sync contract (item #7)', () => {
  const model = read('src/models/MedicationDose.ts');
  const routes = read('src/modules/medications/routes.ts');

  test('MedicationDose model exposes appleHealthDoseId field', () => {
    expect(model).toContain('appleHealthDoseId: string | null');
    expect(model).toContain('appleHealthDoseId: { type: String');
    expect(model).toContain('sparse: true');
  });

  test('MedicationDose has a sparse unique compound index for {userId, appleHealthDoseId}', () => {
    // Required so a HealthKit dose can never be ingested twice for the same
    // user, even under concurrent foreground-sync race conditions.
    // Strip whitespace so a multi-line call still matches a single regex.
    const compact = model.replace(/\s+/g, ' ');
    expect(compact).toMatch(
      /MedicationDoseSchema\.index\( \{ userId: 1, appleHealthDoseId: 1 \}, \{ unique: true, sparse: true \}, \)/,
    );
  });

  test('create-dose schema accepts optional appleHealthDoseId', () => {
    expect(routes).toContain('appleHealthDoseId: appleHealthDoseIdSchema');
    expect(routes).toContain('appleHealthDoseIdSchema');
  });

  test('POST /doses dedupes on appleHealthDoseId before insert', () => {
    // The handler must look up by {userId, appleHealthDoseId} first and
    // return the existing row instead of inserting a duplicate.
    expect(routes).toContain(
      "appleHealthDoseId: body.appleHealthDoseId,",
    );
    expect(routes).toMatch(/findOne\(\{[\s\S]*?appleHealthDoseId:\s*body\.appleHealthDoseId/);
  });

  test('POST /doses handles E11000 race-window for HealthKit dedupe', () => {
    // If two concurrent foreground-syncs hit POST /doses with the same
    // appleHealthDoseId, the second insert will trip the unique index — the
    // handler must catch code 11000 and return the existing row instead of
    // surfacing a 500 to the client.
    expect(routes).toContain('code === 11000');
  });

  test('serializer exposes appleHealthDoseId on the response payload', () => {
    expect(routes).toContain('appleHealthDoseId: dose.appleHealthDoseId ?? null');
  });

  test('persisted-build helper threads appleHealthDoseId from request body', () => {
    expect(routes).toContain('appleHealthDoseId: body.appleHealthDoseId ?? null');
  });
});
