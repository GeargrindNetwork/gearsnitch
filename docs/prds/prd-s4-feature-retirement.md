# PRD S4 — Feature Retirement (Mesh Chat, Stopwatch, BMI Calculator)

**Status:** Draft — awaiting founder decision
**Owner:** Founder (scope) / iOS lead (execution)
**Target decision date:** within 1 week
**Blocks:** S2 nav rebuild (orphan features), App Store review (fewer half-finished surfaces), v1 focus
**Source:** `docs/RALPH-BACKLOG.md` → S4, ultrathink redesign

## Context

Three features exist in the iOS binary that do not align with the three-pillar product thesis (Gear / Train / Chemistry). Per the S2 nav rebuild, they have no obvious home. This PRD evaluates retire vs. demote vs. keep for each.

## Current usage data

**No in-app analytics instrumentation exists yet for feature-level usage** (grep of the repo finds no `analytics.track(...)` calls around these three views). The floating-menu + profile-settings routes to these screens are taken "some" number of times per day but we cannot quantify. This PRD uses **best-judgment reasoning**, not data.

Files:

- `client-ios/GearSnitch/Features/MeshChat/MeshChatView.swift`
- `client-ios/GearSnitch/Features/MeshChat/MeshChatViewModel.swift`
- `client-ios/GearSnitch/Features/Stopwatch/StopwatchView.swift`
- `client-ios/GearSnitch/Features/Stopwatch/StopwatchViewModel.swift`
- `client-ios/GearSnitch/Features/Health/BMICalculatorView.swift`

## Per-feature assessment

### 1. Mesh Chat

**What it is:** A peer-to-peer chat surface (MultipeerConnectivity / BLE mesh — not verified in this PRD). Nav title literally "Mesh Chat" (`MeshChatView.swift:23`).

**Value:** Near-zero for the core customer (someone tracking gear and body chemistry). Chat is not a pillar. Best case it's a novelty; worst case it's a moderation + privacy liability we don't want to own (user-to-user text in a health app invites PHI handling we haven't scoped).

**Cost to maintain:** Non-trivial. Any BLE/peer framework touches Bluetooth permission copy, background modes, and Info.plist entries. Every iOS update risks breaking it quietly.

**Competitors:** None of our peers (Whoop, Strava, Garmin Connect) ship a 1:1 in-app chat. Strava has comments on activities (social, not real-time chat). No competitive pressure.

**Pillar fit:** None. Does not serve Gear, Train, or Chemistry.

**Recommendation: RETIRE (remove code).** Zero user comms needed — there's no paying surface around Mesh Chat.

### 2. Stopwatch

**What it is:** Standalone stopwatch with lap tracking (`StopwatchView.swift`). Comment on line 5–7 explicitly notes "Can be embedded in ActiveWorkoutView or used standalone."

**Value:** Moderate — but only as a **component of an active workout**, not as a standalone tab/feature. iOS ships a system stopwatch; no one opens a fitness app to use its stopwatch.

**Cost to maintain:** Low. ~200 lines of SwiftUI, no external deps.

**Competitors:** Stopwatch is a within-workout feature in every tracker. Standalone stopwatch screens don't exist in competitors.

**Pillar fit:** Yes — **as a child of Train**, inside the active-workout surface. Not as a primary destination.

**Recommendation: DEMOTE (nest inside Train tab's active-workout view).** Delete the standalone navigation entry point. Keep the code; reuse the component. No user comms needed.

### 3. BMI Calculator

**What it is:** A form that computes BMI from weight + height (`BMICalculatorView.swift:1–25`). Pure function UI, no persistence.

**Value:** Very low. BMI is:
- Medically controversial (ignores lean mass, muscle-dense athletes always score "overweight").
- Trivially computable anywhere (Siri, Google, Apple Health).
- Slightly off-brand for a peptide/lab/biomarker-oriented product — we're trying to move USERS AWAY from BMI-as-health-proxy, toward actual biomarkers.

**Cost to maintain:** ~Zero; it's a stateless form.

**Competitors:** Present in basic calorie-counter apps, absent from serious fitness trackers.

**Pillar fit:** None. Actively conflicts with our Chemistry pillar's "real biomarkers > BMI" positioning.

**Recommendation: RETIRE (remove code).** If demanded later, add a better body-composition surface (DEXA import, impedance scale, InBody PDF upload).

## Summary recommendation table

| Feature | Action | Code status |
|---|---|---|
| Mesh Chat | Retire | Delete `Features/MeshChat/*` |
| Stopwatch | Demote | Keep the view; remove standalone entry; embed in Train active-workout |
| BMI Calculator | Retire | Delete `Features/Health/BMICalculatorView.swift` |

## Retirement mechanics

For each retired feature:

1. **Feature flag OFF** (one release) — hide the nav entry + route, keep the code. Ship v1 with it hidden.
2. **Monitor for support tickets / complaints** for one release cycle (2–4 weeks).
3. **Delete code** in the next release. Purge:
   - View files and view-models
   - Xcode project references (`client-ios/GearSnitch.xcodeproj/project.pbxproj`)
   - Any API routes exclusively serving these features (none anticipated for these three)
   - Any strings in `Info.plist` unique to these features (MeshChat may use `NSLocalNetworkUsageDescription` — audit before removing)

**Data migration:** Stopwatch stores no persistent data. BMI is stateless. MeshChat messages are ephemeral peer-to-peer. Nothing to migrate.

## User comms

For retired features:

- **Paid users:** These three features were never gated behind paid tier (verified via codebase pattern — no `subscription.isActive` checks around these views). No refund or grandfathering obligation.
- **Free users:** No proactive comms. If anyone asks in support, standard "we've streamlined the app to focus on gear tracking, training, and chemistry" response.
- **Release notes:** One line each in the v1.x release notes: "Streamlined navigation: [BMI calculator / Mesh Chat] has been removed to focus on our core tracking features."

## Launch impact

**Recommendation: RETIRE BEFORE LAUNCH.**

Reasoning:

- **App Store review:** Apple reviewers penalize apps with half-finished or low-value surfaces. Shipping with Mesh Chat + BMI looks like a grab-bag demo, not a focused product. Cleaner review = fewer back-and-forth rejections.
- **First-impression rating:** New users poke around every screen. Empty / confusing features hurt first-session review sentiment.
- **S2 nav rebuild depends on this** — if we try to build 3 tabs while also figuring out where MeshChat goes, we waste cycles.
- **Cost is low:** we're deleting ~500–800 lines total; no data migration; no user comms.

Ship v1 with these three features either deleted or flag-hidden. Delete the code in v1.1 once we're sure no support ticket appears.

## Decision table

| Feature | Founder choice (Retire / Demote / Keep) | Decision date | Rationale |
|---|---|---|---|
| Mesh Chat | | | |
| Stopwatch | | | |
| BMI Calculator | | | |

| Timing | Founder choice (X one) | Decision date |
|---|---|---|
| Retire/demote BEFORE launch (recommended) | | |
| Retire/demote AFTER launch (v1.1) | | |
| Keep all three, do nothing | | |

**Target decision date:** ____________________
**Decided by:** ____________________
**Sub-decisions once approved:** whether to ship with feature flag (default-off) vs. full code deletion in v1, and where exactly Stopwatch lives inside the Train tab (header pill vs. full-screen push).
