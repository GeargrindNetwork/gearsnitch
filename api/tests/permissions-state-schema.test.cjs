const fs = require('node:fs');
const path = require('node:path');

const repoRoot = path.join(__dirname, '..', '..');

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

describe('permissionsState wire format is aligned with iOS enum contract', () => {
  const sharedTypes = read('shared/src/types/index.ts');
  const iosUser = read('client-ios/GearSnitch/Shared/Models/User.swift');
  const iosEndpoint = read('client-ios/GearSnitch/Core/Network/APIEndpoint.swift');
  const apiUserRoutes = read('api/src/modules/users/routes.ts');
  const permissionsUtil = read('api/src/utils/permissionsState.ts');
  const webAccountPage = read('web/src/pages/AccountPage.tsx');

  test('shared IPermissionsState is a string-enum-keyed object, not a boolean bag', () => {
    // Guard: the old boolean shape must be gone.
    expect(sharedTypes).not.toMatch(/notificationsEnabled:\s*boolean/);
    expect(sharedTypes).not.toMatch(/bluetoothEnabled:\s*boolean/);
    expect(sharedTypes).not.toMatch(/locationEnabled:\s*boolean/);
    expect(sharedTypes).not.toMatch(/healthKitEnabled:\s*boolean/);

    // New shape: string-literal union matching PermissionStatus on iOS.
    expect(sharedTypes).toContain(
      "export type PermissionStateValue = 'granted' | 'denied' | 'not_determined';",
    );
    expect(sharedTypes).toContain('export interface IPermissionsState {');
    expect(sharedTypes).toMatch(/bluetooth\?:\s*PermissionStateValue;/);
    expect(sharedTypes).toMatch(/location\?:\s*PermissionStateValue;/);
    expect(sharedTypes).toMatch(/backgroundLocation\?:\s*PermissionStateValue;/);
    expect(sharedTypes).toMatch(/notifications\?:\s*PermissionStateValue;/);
    expect(sharedTypes).toMatch(/healthKit\?:\s*PermissionStateValue;/);
  });

  test('iOS PermissionStateSyncBody field names match shared IPermissionsState keys', () => {
    // These are the five fields the Swift struct actually posts over the wire.
    expect(iosEndpoint).toContain('struct PermissionStateSyncBody: Encodable {');
    expect(iosEndpoint).toMatch(/let bluetooth: String\?/);
    expect(iosEndpoint).toMatch(/let location: String\?/);
    expect(iosEndpoint).toMatch(/let backgroundLocation: String\?/);
    expect(iosEndpoint).toMatch(/let notifications: String\?/);
    expect(iosEndpoint).toMatch(/let healthKit: String\?/);
  });

  test('iOS PermissionStatus enum emits exactly the three wire values', () => {
    expect(iosUser).toMatch(/case granted\b/);
    expect(iosUser).toMatch(/case denied\b/);
    expect(iosUser).toMatch(/case notDetermined = "not_determined"/);
  });

  test('API zod schema on PATCH /users/me accepts the iOS enum values', () => {
    expect(apiUserRoutes).toContain("z.enum(PERMISSION_STATE_VALUES)");
    // The five permission keys must be validated by the schema.
    expect(apiUserRoutes).toMatch(/bluetooth:\s*z\.enum\(PERMISSION_STATE_VALUES\)\.optional\(\)/);
    expect(apiUserRoutes).toMatch(/location:\s*z\.enum\(PERMISSION_STATE_VALUES\)\.optional\(\)/);
    expect(apiUserRoutes).toMatch(/backgroundLocation:\s*z\.enum\(PERMISSION_STATE_VALUES\)\.optional\(\)/);
    expect(apiUserRoutes).toMatch(/notifications:\s*z\.enum\(PERMISSION_STATE_VALUES\)\.optional\(\)/);
    expect(apiUserRoutes).toMatch(/healthKit:\s*z\.enum\(PERMISSION_STATE_VALUES\)\.optional\(\)/);
  });

  test('API PERMISSION_STATE_VALUES is the literal iOS wire enum', () => {
    expect(permissionsUtil).toContain("'granted'");
    expect(permissionsUtil).toContain("'denied'");
    expect(permissionsUtil).toContain("'not_determined'");
  });

  test('web Account page types permissionsState with the iOS enum (no booleans)', () => {
    expect(webAccountPage).toContain("'granted' | 'denied' | 'not_determined'");
    expect(webAccountPage).not.toMatch(/notificationsEnabled:\s*boolean/);
  });
});

describe('normalizePermissionsState round-trips iOS-shaped payloads', () => {
  // Use the compiled build output so this .cjs test can consume the TS util
  // without needing ts-jest (matches the convention of the rest of tests/).
  const {
    normalizePermissionsState,
    normalizePermissionStateValue,
    PERMISSION_STATE_VALUES,
    DEFAULT_PERMISSIONS_STATE,
  } = require('../dist/utils/permissionsState.js');

  test('PERMISSION_STATE_VALUES exposes exactly the iOS enum', () => {
    expect(PERMISSION_STATE_VALUES).toEqual(['granted', 'denied', 'not_determined']);
  });

  test('iOS-shaped payload passes through unchanged', () => {
    const iosPayload = {
      bluetooth: 'granted',
      location: 'granted',
      backgroundLocation: 'denied',
      notifications: 'granted',
      healthKit: 'not_determined',
    };

    expect(normalizePermissionsState(iosPayload)).toEqual(iosPayload);
  });

  test('partial iOS payload fills gaps with not_determined', () => {
    const partial = { bluetooth: 'granted', notifications: 'denied' };

    expect(normalizePermissionsState(partial)).toEqual({
      bluetooth: 'granted',
      location: 'not_determined',
      backgroundLocation: 'not_determined',
      notifications: 'denied',
      healthKit: 'not_determined',
    });
  });

  test('legacy boolean values are coerced to enum values', () => {
    expect(normalizePermissionStateValue(true)).toBe('granted');
    expect(normalizePermissionStateValue(false)).toBe('denied');
    expect(normalizePermissionStateValue(undefined)).toBe('not_determined');
    expect(normalizePermissionStateValue('garbage')).toBe('not_determined');
  });

  test('non-object input returns the all-not_determined default', () => {
    expect(normalizePermissionsState(null)).toEqual(DEFAULT_PERMISSIONS_STATE);
    expect(normalizePermissionsState(undefined)).toEqual(DEFAULT_PERMISSIONS_STATE);
    expect(normalizePermissionsState('nope')).toEqual(DEFAULT_PERMISSIONS_STATE);
  });
});
