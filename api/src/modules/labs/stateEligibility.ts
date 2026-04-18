/**
 * Lab state-eligibility source of truth.
 *
 * Rupa Health does not ship or fulfill at-home lab orders into the following
 * U.S. states due to state-level regulations on direct-to-consumer lab testing:
 *   - New York (NY)
 *   - New Jersey (NJ)
 *   - Rhode Island (RI)
 *
 * Reference: https://www.rupahealth.com/ (Rupa Health policy — restricted states).
 *
 * This module mirrors the iOS client-side gate introduced in PR #27 and provides
 * server-side enforcement so a compromised/modified client cannot bypass the gate.
 *
 * Treat unknown/empty state codes as NOT restricted here — validation of the
 * state field's presence and format is a separate concern handled by zod.
 */

/**
 * ISO 3166-2 state codes (uppercase) that Rupa Health cannot service.
 */
export const LAB_RESTRICTED_STATES: ReadonlySet<string> = new Set([
  'NY',
  'NJ',
  'RI',
]);

/**
 * Returns true if the provided U.S. state code is in the Rupa restricted list.
 *
 * Input is trimmed and upper-cased. Null, undefined, or empty strings return
 * false (we only block known-restricted states; validation of state presence
 * is the caller's responsibility).
 *
 * @param stateCode - 2-letter U.S. state code (e.g. "NY"), or null/undefined.
 */
export function isRestricted(stateCode: string | null | undefined): boolean {
  if (stateCode === null || stateCode === undefined) {
    return false;
  }
  const normalized = String(stateCode).trim().toUpperCase();
  if (normalized.length === 0) {
    return false;
  }
  return LAB_RESTRICTED_STATES.has(normalized);
}

/**
 * Canonical error code returned to clients when a lab request is rejected
 * due to state eligibility. iOS clients (PR #27) key off this code.
 */
export const LAB_STATE_RESTRICTED_ERROR_CODE = 'LAB_NOT_AVAILABLE_IN_STATE';

/**
 * Human-readable message template for the state-eligibility error.
 */
export function stateRestrictedMessage(stateCode: string): string {
  const normalized = String(stateCode).trim().toUpperCase();
  return `At-home lab testing is not available in ${normalized} due to state regulations.`;
}
