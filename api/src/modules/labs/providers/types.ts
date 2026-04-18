/**
 * LabProvider abstraction.
 *
 * This file intentionally isolates all lab-provider domain types so that
 * concrete implementations (Rupa, LabCorp, future vendors) stay swappable
 * behind `labProviderFactory()`.
 *
 * Types are aligned with FHIR R4 (DiagnosticReport + Observation) where
 * results/orders cross our boundary, but we keep internal request/response
 * shapes flat and TypeScript-friendly — FHIR compliance is applied at the
 * concrete-provider serialization boundary, not in the interface.
 *
 * @phi Every field that can carry patient identity or lab results is marked
 *       `@phi` so a future KMS/encryption pass can find the scope easily.
 */

// ─── Common ────────────────────────────────────────────────────────────────

/**
 * Thrown when a provider method is not yet wired up to a real vendor.
 * Callers should treat this as a 501 Not Implemented at the HTTP layer.
 */
export class NotImplementedError extends Error {
  constructor(method: string, provider: string) {
    super(`${provider}.${method} is not yet implemented — see LabProvider README`);
    this.name = 'NotImplementedError';
  }
}

export type LabProviderId = 'rupa' | 'labcorp';

// ─── Test catalog ──────────────────────────────────────────────────────────

/**
 * A single orderable lab test / panel.
 * Aligned with FHIR `ActivityDefinition` + `PlanDefinition` intent but flattened.
 */
export interface LabTest {
  /** Provider-scoped test id (stable per provider). */
  id: string;
  /** Human-readable test name, e.g. "Comprehensive Metabolic Panel". */
  name: string;
  /** Long-form description / what's measured. */
  description: string;
  /** Retail price shown to the member in cents, USD. */
  priceCents: number;
  currency: 'USD';
  /** Typical turnaround time once the specimen reaches the lab. */
  turnaroundHours: number;
  /** Which collection methods this test supports. */
  collectionMethods: LabCollectionMethod[];
  /** LOINC codes covered by the panel, if the provider exposes them. */
  loincCodes?: string[];
  /** True if fasting is required before collection. */
  fastingRequired: boolean;
}

export type LabCollectionMethod =
  | 'phlebotomy_site' // walk-in draw site (LabCorp, Quest, etc.)
  | 'mobile_phleb'    // provider dispatches a phlebotomist
  | 'self_collect';   // at-home finger-prick, saliva, etc.

// ─── Draw sites ────────────────────────────────────────────────────────────

/**
 * A physical location where a specimen can be collected.
 * Aligned with FHIR `Location`.
 */
export interface DrawSite {
  id: string;
  name: string;
  address: {
    line1: string;
    line2?: string;
    city: string;
    state: string;   // 2-letter US state
    postalCode: string;
  };
  /** [longitude, latitude] — GeoJSON order. */
  coordinates?: [number, number];
  hours?: string;
  phone?: string;
  /** Distance from the query zip centroid, in miles. */
  distanceMiles?: number;
}

// ─── Orders ────────────────────────────────────────────────────────────────

/**
 * @phi Patient identity — handle under HIPAA BAA scope only.
 *
 * Sent to the provider when creating an order. Mirrors FHIR `Patient`.
 */
export interface LabPatient {
  /** GearSnitch user id for correlation. */
  userId: string;
  /** @phi */ firstName: string;
  /** @phi */ lastName: string;
  /** @phi ISO-8601 date (YYYY-MM-DD). */
  dateOfBirth: string;
  /** FHIR-coded sex at birth. */
  sexAtBirth: 'male' | 'female' | 'unknown';
  /** @phi */ email: string;
  /** @phi */ phone: string;
  /** @phi Billing + shipping address. */
  address: DrawSite['address'];
}

/**
 * Request payload for `createOrder()`.
 * @phi — contains patient identity and test selection.
 */
export interface CreateOrderInput {
  patient: LabPatient;
  /** Provider-scoped test ids from `listTests()`. */
  testIds: string[];
  collectionMethod: LabCollectionMethod;
  /** Required when collectionMethod === 'phlebotomy_site'. */
  drawSiteId?: string;
  /** Optional scheduled appointment. ISO-8601. */
  preferredDateTime?: string;
  /** Opaque correlation id — usually our internal appointment id. */
  externalRef?: string;
}

export type LabOrderStatus =
  | 'created'       // order accepted by provider
  | 'scheduled'     // appointment confirmed
  | 'in_progress'   // specimen collected, at the lab
  | 'resulted'      // results available
  | 'cancelled'
  | 'failed';

/**
 * Status response. Deliberately does NOT include PHI by default — use
 * `getResults()` for the full FHIR DiagnosticReport.
 */
export interface LabOrderStatusResponse {
  orderId: string;
  status: LabOrderStatus;
  /** Unix ms timestamp when the status last changed. */
  updatedAt: number;
  /** Optional provider-side tracking reference. */
  providerRef?: string;
}

/**
 * Create-order response. The provider's orderId is what we persist locally
 * to later poll status / pull results.
 */
export interface CreateOrderResponse {
  orderId: string;
  status: LabOrderStatus;
  /** Echoed back so callers can correlate. */
  externalRef?: string;
  /** Pre-signed URL for any lab requisition PDF, if the provider emits one. */
  requisitionUrl?: string;
}

// ─── Results (FHIR R4) ──────────────────────────────────────────────────────

/**
 * Minimal FHIR R4 `Observation` shape — what the provider hands us per analyte.
 * @phi Results are PHI.
 */
export interface FhirObservation {
  resourceType: 'Observation';
  id: string;
  status: 'registered' | 'preliminary' | 'final' | 'amended' | 'cancelled';
  code: {
    coding: Array<{
      system: string; // usually http://loinc.org
      code: string;
      display?: string;
    }>;
    text?: string;
  };
  /** @phi */ valueQuantity?: {
    value: number;
    unit: string;
    system?: string;
    code?: string;
  };
  /** @phi */ valueString?: string;
  referenceRange?: Array<{
    low?: { value: number; unit: string };
    high?: { value: number; unit: string };
    text?: string;
  }>;
  interpretation?: Array<{
    coding: Array<{ system: string; code: string; display?: string }>;
  }>;
  effectiveDateTime?: string;
}

/**
 * Minimal FHIR R4 `DiagnosticReport` — the envelope returned by `getResults()`.
 * @phi PHI — treat the entire resource as PHI in logs and transport.
 */
export interface FhirDiagnosticReport {
  resourceType: 'DiagnosticReport';
  id: string;
  status: 'registered' | 'partial' | 'preliminary' | 'final' | 'amended' | 'cancelled';
  code: {
    coding: Array<{ system: string; code: string; display?: string }>;
    text?: string;
  };
  /** Patient reference — keep opaque; never log. */
  subject?: { reference: string };
  effectiveDateTime?: string;
  issued?: string;
  /** Inline observations. Larger result sets may link via `result[].reference`. */
  contained?: FhirObservation[];
  result?: Array<{ reference: string; display?: string }>;
  /** Provider-issued PDF URL, if any. */
  presentedForm?: Array<{ contentType: string; url?: string; title?: string }>;
}

// ─── Provider interface ────────────────────────────────────────────────────

export interface ListDrawSitesInput {
  zip: string;
  /** Search radius in miles. */
  radius?: number;
}

/**
 * The abstraction every lab vendor implementation must satisfy.
 *
 * Methods deliberately return plain (non-FHIR) types for catalog / sites /
 * status, and the FHIR resource only for results — results are where FHIR
 * compatibility is most valuable for downstream consumers (clinicians,
 * export-my-data tooling).
 */
export interface LabProvider {
  /** Stable identifier matching `LAB_PROVIDER=...`. */
  readonly id: LabProviderId;
  /** Human-friendly name for logs / admin surfaces. */
  readonly displayName: string;

  listTests(): Promise<LabTest[]>;
  listDrawSites(input: ListDrawSitesInput): Promise<DrawSite[]>;
  createOrder(input: CreateOrderInput): Promise<CreateOrderResponse>;
  getOrderStatus(orderId: string): Promise<LabOrderStatusResponse>;
  getResults(orderId: string): Promise<FhirDiagnosticReport>;
  cancelOrder(orderId: string): Promise<LabOrderStatusResponse>;
}
