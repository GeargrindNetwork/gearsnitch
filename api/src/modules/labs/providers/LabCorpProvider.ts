/**
 * LabCorpProvider — contract-gated stub.
 *
 * Phase 0 research (see docs/) concluded LabCorp OnDemand has no public
 * developer API; integration requires a signed BAA + MSA + LOA and takes
 * 30–90 days to reach a sandbox. Until the contract lands, every method
 * throws the same signalling error so the factory can return this provider
 * and the audit/error handling layer shows a consistent message.
 *
 * Switching strategy:
 *   - Keep the class exported and wired into the factory.
 *   - Once the contract is active, replace method bodies with real HTTP
 *     calls (or layer a `LabCorpSandboxProvider` on top of the same
 *     `LabProvider` interface) and flip `LAB_PROVIDER=labcorp` in prod.
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

const CONTRACT_NOT_SIGNED_MESSAGE =
  'LabCorp API contract not yet signed — use RupaHealthProvider via LAB_PROVIDER=rupa';

export class LabCorpProvider implements LabProvider {
  readonly id: LabProviderId = 'labcorp';
  readonly displayName = 'LabCorp';

  async listTests(): Promise<LabTest[]> {
    throw new Error(CONTRACT_NOT_SIGNED_MESSAGE);
  }

  async listDrawSites(input: ListDrawSitesInput): Promise<DrawSite[]> {
    void input;
    throw new Error(CONTRACT_NOT_SIGNED_MESSAGE);
  }

  async createOrder(input: CreateOrderInput): Promise<CreateOrderResponse> {
    void input;
    throw new Error(CONTRACT_NOT_SIGNED_MESSAGE);
  }

  async getOrderStatus(orderId: string): Promise<LabOrderStatusResponse> {
    void orderId;
    throw new Error(CONTRACT_NOT_SIGNED_MESSAGE);
  }

  async getResults(orderId: string): Promise<FhirDiagnosticReport> {
    void orderId;
    throw new Error(CONTRACT_NOT_SIGNED_MESSAGE);
  }

  async cancelOrder(orderId: string): Promise<LabOrderStatusResponse> {
    void orderId;
    throw new Error(CONTRACT_NOT_SIGNED_MESSAGE);
  }
}

export const LABCORP_CONTRACT_NOT_SIGNED_MESSAGE = CONTRACT_NOT_SIGNED_MESSAGE;
