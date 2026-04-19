# PRD S2 — 3-Tab Nav Rebuild (Gear / Train / Chemistry + avatar)

**Status:** Draft — awaiting founder decision
**Owner:** Founder (IA) / iOS lead (execution)
**Target decision date:** within 1 week
**Blocks:** iOS screenshots for App Store, onboarding happy-path (S3), feature retirement (S4)
**Source:** `docs/RALPH-BACKLOG.md` → S2; ultrathink redesign

## Context

The current iOS app uses a custom floating menu with **5 primary tabs**, plus two full-screen surfaces (Hospitals, Labs) exposed via menu actions, plus several feature screens not surfaced in primary nav (Mesh Chat, Stopwatch, BMI calculator). Per the ultrathink redesign, the nav has drifted from "gear-tracking for athletes" to a grab-bag of tools.

## Current state

From `client-ios/GearSnitch/App/AppCoordinator.swift` (lines 7–11) and `client-ios/GearSnitch/App/MainTabView.swift`:

```
enum Tab {
    case dashboard
    case workouts
    case health
    case store
    case profile
}
```

Rendered surfaces (switch in `MainTabView.swift:13`):

- `.dashboard` → `DashboardView`
- `.workouts` → `WorkoutListView`
- `.health` → `HealthDashboardView`
- `.store` → `StoreHomeView`
- `.profile` → `ProfileView`

Plus a **floating menu** (`client-ios/GearSnitch/App/FloatingMenuView.swift`) with two additional action buttons: `onHospitals` → `NearestHospitalsView` and `onLabs` → `ScheduleLabsView` (`MainTabView.swift:68–92`). So users see 5 tab icons + "Hospitals" + "Labs" = **7 top-level destinations**.

Feature surfaces NOT in primary nav but shipping in the binary:

- `client-ios/GearSnitch/Features/MeshChat/MeshChatView.swift`
- `client-ios/GearSnitch/Features/Stopwatch/StopwatchView.swift`
- `client-ios/GearSnitch/Features/Health/BMICalculatorView.swift`

## Proposed 3-tab structure

Three primary tabs + an **avatar menu** in the top-right for account/settings/secondary actions.

### Tab 1 — Gear

Everything about the physical objects you track.

- Paired devices list (current `DashboardView` + `DeviceDetailView`)
- Inventory / component-mileage (future #4 in backlog)
- Alerts feed (disconnect, low battery, retirement thresholds)
- Store shortcut card ("Need a new chain?") — **not** a full store home
- Add-device sheet entry point

### Tab 2 — Train

The "doing fitness" surface.

- Workouts list (`WorkoutListView`)
- Active session / stopwatch (folded from standalone Stopwatch — see S4)
- Run tracker / GPS (future)
- External HR intake
- Recent sessions calendar

### Tab 3 — Chemistry

The longitudinal-health / differentiator surface.

- Peptides / dosing log (HealthKit Medications API — backlog #7)
- Labs (results + scheduling — folded from the floating-menu Labs entry; see Labs PRD)
- Biomarkers / trend charts
- Cycles (on/off peptide cycles)
- Hospitals nearby (folded from floating menu — demoted to a card inside Chemistry, not primary nav)

### Avatar menu (top-right popover)

- Profile edit
- Subscription / billing
- Referrals
- Notifications preferences
- Store (full-catalog browsing — the 5-minute-store user can still get here)
- Settings
- Sign out / delete account

## Migration plan

**Recommendation: phased, one tab at a time.** Big-bang risks destabilizing the whole app during the most visible 2 weeks before launch.

Proposed phase order:

1. **Phase 1 — Introduce 3-tab scaffold alongside old nav** behind a feature flag (or a debug toggle), no user-visible change. Wire the new `Tab` enum cases. 1–2 days.
2. **Phase 2 — Move `DashboardView` into "Gear" tab** with the alerts feed merged. Remove standalone alerts surface. 2–3 days.
3. **Phase 3 — Move `WorkoutListView` into "Train" tab**, fold `StopwatchView` as a child. 2–3 days.
4. **Phase 4 — Create "Chemistry" tab** wrapping `HealthDashboardView` + Labs entry + Hospitals card. 3–5 days.
5. **Phase 5 — Build avatar popover**, move `ProfileView`, `StoreHomeView`, subscription, settings into it. 3–4 days.
6. **Phase 6 — Remove the floating menu** and flip the feature flag to the new nav by default. 1 day.

Rough LOC: ~800–1500 net (mostly moves, not new views). Touch points: `AppCoordinator.swift`, `MainTabView.swift`, `FloatingMenuView.swift` (delete), new `AvatarMenuView.swift`, every deep-link destination, widget deep-links.

## Orphan features — what doesn't fit?

- **Mesh Chat** — does not fit gear/train/chemistry pillars. **Recommend retire** (see S4 PRD).
- **Stopwatch** — overlaps with "Train" active-session timer. **Recommend nest** inside Train (child screen, not primary nav).
- **BMI calculator** — does not fit. **Recommend retire or demote** to avatar > Tools submenu (see S4 PRD).
- **Hospitals** — "nearest hospital" is an emergency-adjacent feature. **Recommend demote** to a card inside Chemistry (safety-net visibility, not primary nav).

## Impact

- **LOC estimate:** ~800–1500 lines touched. Few new features; mostly re-wiring routes + deep-links.
- **User-visible risk:** deep-link breakage (universal links, widget taps, APNs payloads currently resolve against old `Tab` cases). Every `coordinator.selectedTab = .foo` call needs review.
- **Analytics continuity:** tab-enum changes break historical tab-view counts. Plan: emit both old and new tab name in analytics during Phase 1–5; cut over to new-only after Phase 6.
- **Screenshot impact:** App Store screenshots need re-shoots after Phase 6. If we ship the old nav, re-shooting post-launch is a v1.1 update with a new metadata review.

## Launch impact — do this BEFORE or AFTER launch?

**Argument for before launch (recommended):**

- First-impression review screenshots set expectations for years. Shipping with a crowded 7-destination floating menu reads "unfocused" to both Apple reviewers and new users.
- The nav rebuild is cleanup, not new surface area, so it doesn't extend scope much.
- Doing it post-launch means two sets of App Store screenshots in <60 days, two rounds of user re-orientation, and any "nav change" post-launch review bombs our rating.

**Argument for after launch:**

- 2 weeks of iOS refactor during pre-launch is risky — deep-links and analytics are the easiest things to break and the hardest to notice.
- We already have paying / TestFlight users mapping their mental model to the current nav.

**Recommendation: DO BEFORE LAUNCH, phased.** Phases 1–4 done pre-submission; Phase 5–6 flip feature flag the day of submission. If timeline slips, we ship with old nav and do the rebuild as a v1.1 followup, but our default should be "land it now."

## Decision table

| Option | Founder choice (X one) | Decision date | Rationale |
|---|---|---|---|
| Rebuild 3-tab nav BEFORE launch (phased) | | | |
| Rebuild 3-tab nav AFTER launch (v1.1) | | | |
| Keep current 5-tab + floating-menu nav (do nothing) | | | |

**Target decision date:** ____________________
**Decided by:** ____________________
**Sub-decisions once approved:** which tab owns Hospitals (Chemistry vs avatar), whether Store lives in Gear-tab card or only in avatar, whether "Chemistry" is the final consumer-facing label (alternatives: "Health," "Labs," "Bio").
