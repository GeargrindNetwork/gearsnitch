export const PERMISSION_STATE_VALUES = [
  'granted',
  'denied',
  'not_determined',
] as const;

export type PermissionStateValue = (typeof PERMISSION_STATE_VALUES)[number];

export interface PermissionsStateShape {
  bluetooth: PermissionStateValue;
  location: PermissionStateValue;
  backgroundLocation: PermissionStateValue;
  notifications: PermissionStateValue;
  healthKit: PermissionStateValue;
}

export const DEFAULT_PERMISSIONS_STATE: PermissionsStateShape = {
  bluetooth: 'not_determined',
  location: 'not_determined',
  backgroundLocation: 'not_determined',
  notifications: 'not_determined',
  healthKit: 'not_determined',
};

export function normalizePermissionStateValue(value: unknown): PermissionStateValue {
  if (value === true) {
    return 'granted';
  }

  if (value === false) {
    return 'denied';
  }

  if (typeof value !== 'string') {
    return 'not_determined';
  }

  if (PERMISSION_STATE_VALUES.includes(value as PermissionStateValue)) {
    return value as PermissionStateValue;
  }

  return 'not_determined';
}

export function normalizePermissionsState(
  value: unknown,
): PermissionsStateShape {
  const source =
    value && typeof value === 'object'
      ? (value as Partial<Record<keyof PermissionsStateShape, unknown>>)
      : {};

  return {
    bluetooth: normalizePermissionStateValue(source.bluetooth),
    location: normalizePermissionStateValue(source.location),
    backgroundLocation: normalizePermissionStateValue(source.backgroundLocation),
    notifications: normalizePermissionStateValue(source.notifications),
    healthKit: normalizePermissionStateValue(source.healthKit),
  };
}
