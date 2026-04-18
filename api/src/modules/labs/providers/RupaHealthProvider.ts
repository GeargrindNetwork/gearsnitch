/**
 * RupaHealthProvider — HTTP client skeleton against Rupa's sandbox.
 *
 * Rupa Health exposes a self-serve sandbox at:
 *   https://api-sandbox.rupahealth.com
 *
 * Auth: OAuth2 Bearer token. The scaffold reads the token from
 * `process.env.RUPA_API_KEY`. In GCP this is expected to be populated by
 * Secret Manager (see PR body).
 *
 * Deliverable note: until we have a real sandbox token and have confirmed
 * each endpoint shape, method bodies throw `NotImplementedError`. Request
 * shapes and target URLs are visible so a follow-up PR can plug in the
 * wire-level implementation without reshuffling the interface.
 *
 * @phi — request/response bodies that flow through here may contain PHI.
 *        Do NOT log bodies. Only metadata (orderId, status) is safe to log.
 */

import type {
  CreateOrderInput,
  CreateOrderResponse,
  DrawSite,
  FhirDiagnosticReport,
  LabOrderStatusResponse,
  LabProvider,
  LabProviderId,
  LabTest,
  ListDrawSitesInput,
} from './types.js';
import { NotImplementedError } from './types.js';

const RUPA_SANDBOX_BASE_URL = 'https://api-sandbox.rupahealth.com';

export interface RupaHealthProviderOptions {
  /** Override the base URL (e.g. for tests or staging). */
  baseUrl?: string;
  /** Explicit bearer token. Falls back to process.env.RUPA_API_KEY. */
  apiKey?: string;
  /** Optional injected fetch for testability. */
  fetchImpl?: typeof fetch;
}

export class RupaHealthProvider implements LabProvider {
  readonly id: LabProviderId = 'rupa';
  readonly displayName = 'Rupa Health';

  private readonly baseUrl: string;
  private readonly apiKey: string;
  /**
   * Injected fetch for a follow-up PR that wires real HTTP calls.
   * Retained so tests can stub the network without monkey-patching
   * `globalThis.fetch`.
   */
  protected readonly fetchImpl: typeof fetch;

  constructor(options: RupaHealthProviderOptions = {}) {
    this.baseUrl = options.baseUrl ?? RUPA_SANDBOX_BASE_URL;
    this.apiKey = options.apiKey ?? process.env.RUPA_API_KEY ?? '';
    this.fetchImpl = options.fetchImpl ?? globalThis.fetch;
  }

  // ─── Public ───────────────────────────────────────────────────────────────

  async listTests(): Promise<LabTest[]> {
    // Target: GET ${baseUrl}/v1/lab_tests
    // Response shape (expected): { results: [{ id, name, description, price, turnaround_hours, ... }] }
    this.assertAuth('listTests');
    throw new NotImplementedError('listTests', this.displayName);
  }

  async listDrawSites(input: ListDrawSitesInput): Promise<DrawSite[]> {
    // Target: GET ${baseUrl}/v1/phlebotomy/locations?zip=${zip}&radius=${radius ?? 25}
    this.assertAuth('listDrawSites');
    void input;
    throw new NotImplementedError('listDrawSites', this.displayName);
  }

  async createOrder(input: CreateOrderInput): Promise<CreateOrderResponse> {
    // Target: POST ${baseUrl}/v1/orders
    // Body: {
    //   patient: { first_name, last_name, dob, sex, email, phone, address },
    //   tests: [{ id }],
    //   collection_method: 'phlebotomy_site' | 'mobile_phleb' | 'self_collect',
    //   draw_site_id?: string,
    //   scheduled_for?: ISO-8601,
    //   external_ref?: string,
    // }
    this.assertAuth('createOrder');
    this.validateCreateOrderInput(input);
    throw new NotImplementedError('createOrder', this.displayName);
  }

  async getOrderStatus(orderId: string): Promise<LabOrderStatusResponse> {
    // Target: GET ${baseUrl}/v1/orders/${orderId}
    this.assertAuth('getOrderStatus');
    void orderId;
    throw new NotImplementedError('getOrderStatus', this.displayName);
  }

  async getResults(orderId: string): Promise<FhirDiagnosticReport> {
    // Target: GET ${baseUrl}/v1/orders/${orderId}/results?format=fhir
    // Expected: FHIR R4 DiagnosticReport resource.
    this.assertAuth('getResults');
    void orderId;
    throw new NotImplementedError('getResults', this.displayName);
  }

  async cancelOrder(orderId: string): Promise<LabOrderStatusResponse> {
    // Target: POST ${baseUrl}/v1/orders/${orderId}/cancel
    this.assertAuth('cancelOrder');
    void orderId;
    throw new NotImplementedError('cancelOrder', this.displayName);
  }

  // ─── Internal ─────────────────────────────────────────────────────────────

  /**
   * Builds the shared bearer-auth JSON headers used across Rupa calls.
   * Exported via `buildHeaders()` only for tests.
   */
  buildHeaders(correlationId?: string): Record<string, string> {
    const headers: Record<string, string> = {
      Authorization: `Bearer ${this.apiKey}`,
      'Content-Type': 'application/json',
      Accept: 'application/json',
    };
    if (correlationId) {
      headers['X-Request-ID'] = correlationId;
    }
    return headers;
  }

  /**
   * Centralized URL builder — exposed for tests.
   */
  buildUrl(pathname: string, query?: Record<string, string | number | undefined>): string {
    const url = new URL(pathname, this.baseUrl);
    if (query) {
      for (const [key, value] of Object.entries(query)) {
        if (value !== undefined && value !== null) {
          url.searchParams.set(key, String(value));
        }
      }
    }
    return url.toString();
  }

  private assertAuth(method: string): void {
    if (!this.apiKey) {
      throw new Error(
        `RupaHealthProvider.${method}: RUPA_API_KEY is not configured — ` +
          'populate it via GCP Secret Manager (secret: RUPA_API_KEY).',
      );
    }
  }

  /**
   * Cheap client-side guard so we fail fast before hitting the network.
   * Does NOT log PHI — only counts / flags.
   */
  private validateCreateOrderInput(input: CreateOrderInput): void {
    if (!input.patient) {
      throw new Error('createOrder: patient is required');
    }
    if (!input.testIds || input.testIds.length === 0) {
      throw new Error('createOrder: at least one testId is required');
    }
    if (
      input.collectionMethod === 'phlebotomy_site' &&
      !input.drawSiteId
    ) {
      throw new Error('createOrder: drawSiteId is required when collectionMethod=phlebotomy_site');
    }
  }

  // Convenience accessor for tests — avoids exposing the raw key.
  hasApiKey(): boolean {
    return this.apiKey.length > 0;
  }

  // For tests — exposes the configured sandbox base URL.
  getBaseUrl(): string {
    return this.baseUrl;
  }
}
