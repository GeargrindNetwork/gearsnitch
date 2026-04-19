# PRD S3 — Onboarding "First Win" Restructure (JIT auth + permissions)

**Status:** Draft — awaiting founder decision
**Owner:** Founder (activation strategy) / iOS lead (execution)
**Target decision date:** within 2 weeks
**Blocks:** Post-launch activation optimization. Does NOT block v1 submission (see launch impact).
**Source:** `docs/RALPH-BACKLOG.md` → S3

## Context

Current onboarding front-loads the entire permission gauntlet (Bluetooth, Location, Notifications, HealthKit) and forces sign-in before the user has seen a single useful screen. Industry standard for the last ~4 years — and Apple's own HIG guidance — is **just-in-time** permissions and **deferred auth** until after a "first win" (the moment the product demonstrates concrete value).

## Current flow

From `client-ios/GearSnitch/Features/Onboarding/OnboardingViewModel.swift:11–41` the steps are hard-coded in an ordinal enum:

```
.welcome → .signIn → .subscription → .handPreference →
.bluetoothPrePrompt → .locationWhenInUse → .locationAlways →
.notifications → .healthKit → .addGym → .pairDevice → .complete
```

That's **12 screens** (11 visible — `welcome` is excluded from progress — see `OnboardingStep.visibleStepCount`). `.signIn`, `.bluetoothPrePrompt`, `.locationWhenInUse`, `.addGym`, `.pairDevice` are marked `isGated` (user cannot skip past). So a new user must:

1. See welcome
2. **Sign in** (gated)
3. See subscription pitch
4. Pick hand preference
5. **Accept Bluetooth** (gated)
6. **Accept Location when-in-use** (gated)
7. Accept Location always
8. Accept notifications
9. Accept HealthKit
10. **Add a gym** (gated — a network call)
11. **Pair a device** (gated — BLE scan + pair)
12. Complete

The user has to hand over identity + 4 permission scopes + pair a physical device BEFORE seeing the app's main surface. If any step fails (e.g. BLE permission denied), they're kicked into `fixPermissionsView` (`RootView.swift:163`).

## Proposed flow (guest-first + JIT auth)

Let the user see the app, pair a device, or log a gym **before** they sign in, and ask for each permission only when the next step literally cannot proceed without it.

Revised sequence:

1. **Welcome** (value prop in one sentence)
2. **Hand preference** (cosmetic, no permissions)
3. **Choose your first path** — three cards: "Pair a gear item" / "Log a gym" / "Just browse" → each is a guest-mode surface
4. **If user picked Pair:** BLE pre-prompt + request → add device (guest account, data stored locally)
5. **If user picked Log gym:** Location pre-prompt + request → add gym (guest)
6. **If user picked Browse:** drop them in the store, no permission prompts at all
7. **First value moment** achieved (device paired / gym added / product viewed)
8. **JIT sign-up prompt** — "Save your work across devices? Sign in" — only when triggered by cloud-sync, subscription, or lab-scheduling
9. **HealthKit, notifications, always-on location** requested at the moment a feature that needs them is tapped (e.g. "Enable alerts?" when the user opens an empty Alerts feed)

**Screen count: 3–5 screens before first value moment**, down from 11.

## Metrics to measure the change

We need analytics on both flows to judge the swap. Instrument:

- **Activation rate** — % of new installs who reach a "first win" event (device paired, gym logged, product viewed) within 5 minutes of install.
- **TTV (time to value)** — median seconds from `AppDidLaunch` to first-win event.
- **Permission grant rate per scope** — current baseline vs. JIT. (Bluetooth, Location, Notifications, HealthKit.) Expect higher grants at a lower volume of prompts; JIT conversion often 2–3× front-loaded.
- **Sign-up rate** — % of installs that create an account. Expect a drop in raw %, but higher **qualified** sign-ups (users who already have data to save).
- **D1 / D7 retention** — standard funnel. Biggest signal.
- **Onboarding abandonment by step** — currently every drop-off is inside one big gated flow; after JIT, we should see a smoother distribution.

## JIT auth boundaries — what can a guest do?

Proposed guest-mode matrix (writes to local SQLite; shadow-account on first sign-in syncs up):

| Action | Guest allowed? | Forces sign-up? |
|---|---|---|
| Pair 1st BLE device | yes | no |
| Pair 2nd+ device | yes | no |
| Log a gym location | yes | no |
| Start a workout session | yes | no |
| View store product | yes | no |
| **Check out / pay** | — | **yes** |
| **Subscribe** | — | **yes** |
| **Schedule a lab** | — | **yes** (PHI collection) |
| **Enable cloud sync / multi-device** | — | **yes** |
| **Receive push notifications** | — | **yes** (APNs token tied to user) |
| **Use referrals** (both sides) | — | **yes** |

## Risks

- **Local-only data loss.** Guest data in SQLite is wiped on app uninstall. Mitigation: show a "save your X device pairings" upsell at 2× guest sessions.
- **Orphaned gear records.** A device paired in guest mode is a row with no user_id. Needs a cleanup job (worker cron) or a backfill on first sign-in.
- **Account-recovery friction.** Users sign up 3 days later with a different email; their guest data is stranded. Mitigation: a one-time "merge my previous guest session" prompt using a device-id hash.
- **Fraud / abuse.** Guest mode rate-limited by device id, not auth. Need IP + device-fingerprint throttles on pair/gym endpoints.
- **Analytics continuity.** Emit `anonymous_id` (UUID in Keychain) alongside `user_id` after sign-in to preserve the funnel.
- **Apple review.** Reviewers will test "just browse" — ensure no hard gates or broken surfaces in guest mode.

## Scope estimate

**M–L.** Touching auth, onboarding, every list view that assumes a `user_id`, the local-to-cloud merge flow, and analytics. Realistic: 2–3 weeks of focused iOS + API work.

Breakdown: iOS onboarding rewrite (1 wk) + guest-mode local store + merge-on-signin (1 wk) + API guest-scoped endpoints + merge (3–4d) + analytics rewiring (2–3d) + QA / Apple review prep (3–4d).

## Launch impact

**Recommendation: AFTER launch, phased.**

Reasoning:

- Onboarding is the single most load-bearing flow in the app. Rewriting it <4 weeks before a submission we've never done before is the textbook "too many in-flight variables" mistake.
- The current onboarding works — it's inefficient, not broken.
- We can measure the baseline activation funnel on v1, then ship S3 as v1.2 (four weeks post-launch) with hard A/B data to defend the redesign.
- S3 touches auth, which transitively touches Stripe / subscription state / referral — pre-launch is the worst time to rewire those.

Phased post-launch rollout:

- **Week 0–2 post-launch:** instrument current funnel; ship no changes.
- **Week 3–5:** ship guest-mode scaffold (read-only; sign-up still forced). Behind feature flag.
- **Week 6–8:** enable guest writes (device + gym) for 50% of installs. A/B measure.
- **Week 9+:** flip default if activation ↑ and permission-grant ↑.

## Decision table

| Option | Founder choice (X one) | Decision date | Rationale |
|---|---|---|---|
| Ship S3 rewrite BEFORE v1 launch | | | |
| Ship S3 rewrite AFTER launch, phased (recommended) | | | |
| Don't ship S3 — keep current onboarding indefinitely | | | |

**Target decision date:** ____________________
**Decided by:** ____________________
**Sub-decisions once approved:** guest-device cap (1 device or unlimited?), whether subscription pitch moves pre-signup or post-first-win, whether HealthKit ever gets a proactive prompt or only JIT.
