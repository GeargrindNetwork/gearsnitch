# PRD — Labs Launch Decision (v1 critical path)

**Status:** DECIDED — founder selected **Option B: Rupa Health (v1)** on 2026-04-18
**Owner:** Founder (compliance + revenue model) / Eng (execution)
**Decided:** 2026-04-18
**Blocks:** v1 submission date, App Review category, HIPAA/BAA scope, Chemistry tab content
**Source:** existing labs abstraction in `api/src/modules/labs/*`; `ScheduleLabsView` in iOS; `docs/RALPH-BACKLOG.md` S6

## Decision summary (2026-04-18)

**Chosen: Rupa Health (Option B).** Blood-only launch scope, reuse Rupa
Services as physician-of-record. Integration work queued as a new Ralph
backlog item ("Labs v1 — Rupa Health integration"). Pricing model
(pass-through vs practitioner-pay) remains open and will be resolved in a
follow-up discussion before implementation kickoff.

## Context: current state

Labs are **scaffolded but non-functional**. Concretely:

- **API surface:** `api/src/modules/labs/routes.ts` registers a full router with Zod schemas for `scheduleLabSchema`, `createOrderSchema`, patient PHI, shipping addresses, state eligibility, and an audit middleware (`api/src/middleware/labAudit.ts`). Requests hit the router, but every provider call throws `NotImplementedError` → HTTP 501.
- **Provider abstraction:** `api/src/modules/labs/providers/factory.ts` selects `RupaHealthProvider` (default) or `LabCorpProvider` via `LAB_PROVIDER` env. Both files exist at `api/src/modules/labs/providers/RupaHealthProvider.ts` + `LabCorpProvider.ts`. Every endpoint method: `throw new NotImplementedError('listTests' | 'listDrawSites' | 'createOrder' | 'getOrderStatus' | 'getResults' | 'cancelOrder', this.displayName)`.
- **State eligibility:** `api/src/modules/labs/stateEligibility.ts` + `client-ios/GearSnitch/Features/Health/LabsStateEligibility.swift` already exist — the 50-state gating is implemented.
- **iOS:** `client-ios/GearSnitch/Features/Health/ScheduleLabsView.swift` exists and is wired from the floating menu (`MainTabView.swift:88–92` → `fullScreenCover` over `ScheduleLabsView()`).
- **Apple Pay:** wired (per backlog notes); payment tokens flow into `createOrderSchema.paymentToken`.
- **Compliance:** HIPAA BAA **not signed** with any lab provider. PHI audit middleware exists (`labAuditMiddleware`) but the downstream store (`LabAuditLog`) has not been pen-tested. KMS envelope encryption on PHI is S5 (separate blocker).
- **App Review:** labs surface an activity that Apple classifies under **5.1.3 (health & medical apps)** — stricter review, requires physician-of-record disclosure and accurate medical claims.

Net: everything is wired to the seam; nothing past the seam works.

## Options

### Option A — Ship v1 without labs

Remove the labs nav entry (or replace with a "Coming Soon" card). App reviews under standard health-app guidelines (no 5.1.3 lab-testing scrutiny). No BAA needed for v1.

- **Time to launch:** **0 weeks added** (we're done).
- **Engineering cost:** ~1 day to gate the UI + return `503 Service Unavailable` from `/api/v1/labs/*` with a clean "Coming soon" payload.
- **Compliance cost:** zero for v1. KMS + BAA deferred to fast-follow.
- **User value:** loses one of three "Chemistry" pillar features. Peptide + med log can still carry the Chemistry tab in v1. Communicates "labs are coming."
- **Revenue share:** zero from labs in v1. 100% from subscriptions + store in v1.

### Option B — Ship v1 with Rupa Health

Rupa gives us a physician-of-record (Rupa's "Rupa Services" network) + vendor API + patient-facing portal. We integrate, Rupa handles clinician oversight + results delivery.

- **Time to launch:** **4–8 weeks added** (BAA negotiation is the long pole; integration itself is 2–3 weeks once provider creds land).
- **Engineering cost:** implement every `NotImplementedError` in `RupaHealthProvider.ts` (6 endpoints). Pricing page. Order status polling worker. Results-ready push notification. iOS results view. Estimate ~3 eng-weeks.
- **Compliance cost:** BAA with Rupa (standard template, ~1–2 weeks back-and-forth). Our audit-log retention policy must be documented. App Review 5.1.3 prep: physician disclosure, sample order flow for reviewer account, state-eligibility UX copy.
- **User value:** full labs-at-home differentiator vs. Whoop's 2025 Advanced Labs. Strong signal to power users.
- **Revenue share:** Rupa has two models — **Pass-through** (patient pays us, we remit to Rupa's lab cost, keep margin) vs **Practitioner-Pay** (we pay Rupa's wholesale, mark up to patient). Practitioner-Pay gives margin control; Pass-through reduces our financial exposure.

### Option C — Ship v1 with LabCorp direct

LabCorp is a tier-1 lab network. We get direct wholesale pricing + national coverage. We must supply or contract our own physician of record (or use Rupa Services as a physician-only layer while using LabCorp for the lab itself).

- **Time to launch:** **8–16 weeks added.** LabCorp enterprise contracts + BAA are slow. Physician-of-record contract is a separate process.
- **Engineering cost:** LabCorp API is lower-level than Rupa — more custom code around orders, kit shipping, requisition forms. Estimate ~5–6 eng-weeks.
- **Compliance cost:** high. BAA with LabCorp + BAA with physician network + potentially state-by-state telemedicine registration for our physician. CLIA considerations. Audit-log retention + KMS likely required before go-live.
- **User value:** more tests available, lower unit economics at scale, stronger brand ("powered by LabCorp").
- **Revenue share:** best unit economics at scale (direct wholesale), worst cashflow early (upfront physician + compliance spend).

## Per-option summary

| Axis | A: No labs | B: Rupa | C: LabCorp direct |
|---|---|---|---|
| Weeks to launch | 0 | 4–8 | 8–16 |
| Eng cost (eng-weeks) | 0.2 | ~3 | ~5–6 |
| Compliance cost | low | medium | high |
| User value at launch | none | high | high |
| Unit economics | n/a | medium | best |
| App Review risk | standard | 5.1.3 | 5.1.3 + physician |
| Launch-date risk | zero | medium | high |

## Three sub-decisions (only if B or C)

1. **Pricing model:** Pass-through (patient pays list, fixed margin) vs Practitioner-Pay (we buy wholesale, set price). Recommend **Pass-through for v1**, move to Practitioner-Pay once we have volume data.
2. **Physician of record:** own our contract (cheaper at scale, slower) vs use Rupa Services (faster, per-order fee). Recommend **Rupa Services for v1**, revisit at 500 orders/mo.
3. **Launch scope:** **blood-only** (single panel, limited states) vs **full at-home suite** (blood + saliva + stool). Recommend **blood-only + one self-collect + one phlebotomy partner** for v1 — minimum viable loop.

## Recommendation

**Option A for v1; Option B as the immediate fast-follow (v1.1, ~6–8 weeks post-launch).**

Three sentences:

1. Labs adds 4–16 weeks to a launch window we've already deferred, and adds an App Review 5.1.3 surface — a single reviewer can bounce us and we lose weeks. For a founder-solo or small team shipping v1, that risk dominates.
2. The Chemistry pillar still ships meaningfully in v1 via peptide tracking + HealthKit Medications + (later) lab-PDF upload (backlog S6) — none of which require a BAA or a physician contract.
3. Keeping `/api/v1/labs/*` scaffolded behind a feature flag means we can ship B as a backend-only enable once the BAA lands, no app update required.

**The single highest-leverage v1 change:** remove the Labs entry from the floating menu (or swap for "Coming soon" teaser), return `503 + coming_soon` from all `/api/v1/labs/*` routes, and document the path to enabling Rupa in v1.1.

## Decision table

| Option | Founder choice | Decision date | Rationale (1–2 sentences) |
|---|---|---|---|
| A — Ship v1 without labs | | | |
| **B — Ship v1 with Rupa Health** | **Chosen: Rupa Health** | 2026-04-18 | Ships the labs differentiator in the v1 window while Rupa absorbs physician-of-record + BAA scope; LabCorp's 8–16 week timeline doesn't fit. |
| C — Ship v1 with LabCorp direct | | | |

**Sub-decisions (B selected):**

| Sub-decision | Choice | Rationale |
|---|---|---|
| Pricing model (pass-through vs practitioner-pay) | **OPEN — follow-up discussion required** | Founder deferred; revisit before Rupa integration agent is spawned. Default assumption while deferred is pass-through for v1. |
| Physician of record (own vs Rupa Services) | **Rupa Services** | Reuse Rupa's physician network for v1; revisit at 500 orders/month. |
| Launch scope (blood-only vs full at-home suite) | **Blood-only** | Minimum viable loop; one self-collect + one phlebotomy partner. Saliva + stool deferred. |

**Decided by:** Founder, 2026-04-18
**Next step:** Ralph backlog item "Labs v1 — Rupa Health integration" (pending) will be built in a future agent spawn once pricing-model sub-decision is resolved.
