# PRD S1 — Brand Identity Collapse

**Status:** Draft — awaiting founder decision
**Owner:** Founder (brand) / Eng (rollout)
**Target decision date:** within 48 hours of this doc being opened
**Blocks:** App Store submission, Stripe onboarding copy, web launch, email sender reputation
**Source:** `docs/RALPH-BACKLOG.md` → "Needs user signoff" row S1

## Context

Four names currently coexist across product, legal, and marketing surfaces:

1. **GearSnitch** — the product name. Dominant in iOS, API, infra, web.
2. **GearGrind.Net** — a domain / web brand. Appears in footer links and docs.
3. **GearGrind Network** — corporate-sounding parent name. Referenced in the backlog; GitHub org is `GeargrindNetwork`.
4. **Shawn Frazier Inc** — the legal entity (presumed; no repo occurrences found).

### Where each name currently appears in the repo

- **GearSnitch** (product, dominant):
  - iOS bundle display name: `client-ios/GearSnitch/Resources/Info.plist` → `CFBundleDisplayName = "GearSnitch"`.
  - iOS watch / widget bundles: `client-ios/GearSnitchWatch/Info.plist`, `client-ios/GearSnitchWidgetExtension/Resources/Info.plist`, `client-ios/GearSnitchWatchWidgets/Info.plist`.
  - Xcode project root: `client-ios/GearSnitch.xcodeproj/project.pbxproj`.
  - URL scheme: `gearsnitch` (Info.plist `CFBundleURLSchemes`).
  - Bundle ID prefix: `com.gearsnitch.*` (BGTask identifiers, etc.).
  - Splash copy: `client-ios/GearSnitch/App/RootView.swift:368` — `Text("GearSnitch")`.
  - Usage-description strings throughout Info.plist (Bluetooth, Health, Location, Camera, Photos).
  - Web HTML, landing page, account pages — dozens of `web/src/**` references.
  - API/worker/realtime — appears in package names, logs, release files (`web/src/lib/release.tsx`, `worker/src/index.ts`, etc.).
- **GearGrind.Net / GeargrindNetwork**:
  - GitHub org slug: `GeargrindNetwork/gearsnitch` (git remote `origin`).
  - Footer link: `web/src/components/layout/Footer.tsx:70` → `href="https://github.com/GeargrindNetwork/gearsnitch"`.
  - Backlog PRs: `docs/RALPH-BACKLOG.md` links to `github.com/GeargrindNetwork/...`.
- **GearGrind Network / Shawn Frazier Inc**:
  - Not found in code. Assumed used for Stripe/App Store Connect/LLC filings; no in-repo strings.

Net: **GearSnitch is already the de facto product canonical name.** GearGrind is the vestigial parent-org identifier.

## Options

### A) GearSnitch canonical (product + parent collapse)

Everything becomes "GearSnitch." The LLC keeps its legal name (Shawn Frazier Inc or rename later), but every user-visible surface says GearSnitch. `geargrind.net` redirects to `gearsnitch.com` (or equivalent).

### B) GearGrind canonical (rebrand the product)

Rename the iOS app, repo, bundle IDs, URL schemes, and marketing to "GearGrind." Retain `geargrind.net`. Nuke "GearSnitch" from the codebase.

### C) Hybrid parent-child

"GearGrind Network" = parent company / holding brand (legal, Stripe entity, careers, corp blog). "GearSnitch" = the app / product. Two domains, two App Store names, clear hierarchy.

## Tradeoffs

| Dimension | A: GearSnitch only | B: GearGrind only | C: Hybrid parent-child |
|---|---|---|---|
| App Store name availability | Need to confirm "GearSnitch" is free; likely fine (uncommon compound) | Need to confirm "GearGrind" is free; **higher risk** — common word combo | Same as A for the app |
| Trademark (open Q — no legal claim here) | One mark to file/defend | One mark to file/defend; more crowded class | Two marks; higher legal spend |
| SEO | Starts from zero but "GearSnitch" is high-uniqueness, easy to rank | "GearGrind" competes with a broader term cluster | Dilutes — two brands split domain authority |
| User confusion cost | Low — matches current in-app brand | **High** — every existing screenshot, doc, and URL breaks | Medium — users must remember both names |
| Rebrand effort (touch points) | Low. ~5–10 touch points (domain redirect, GitHub org, email) | **Very high.** 100+ touch points: `Info.plist`, bundle IDs (`com.gearsnitch.*`), URL scheme, Xcode targets, all Swift Text strings, every web page, release strings, push notification sender name, etc. | Medium. Same as A plus parent-brand marketing surface. |
| Stripe statement descriptor | `GEARSNITCH` (22-char limit fine) | `GEARGRIND` | Product charges = `GEARSNITCH`; corporate items = `GEARGRIND NET` |
| Email from-name | `GearSnitch <hello@gearsnitch.com>` | `GearGrind <hello@geargrind.net>` | Product = GearSnitch; corporate = GearGrind |

## Touch points to update once decided

All of the following must be reconciled before App Store submission:

- **Stripe:** statement descriptor, business name, support email, public-facing dashboard name.
- **App Store Connect:** App Name (the single most visible string), subtitle, seller (legal entity), copyright.
- **App Store listing copy:** description, promo text, keywords, support URL.
- **iOS:** `client-ios/GearSnitch/Resources/Info.plist` → `CFBundleDisplayName`, bundle id (only if renaming), URL scheme, all Usage-Description strings that mention the name. Watch + widget Info.plist files.
- **Web:** `web/index.html` title/meta, `web/src/components/layout/Footer.tsx`, landing hero copy, legal pages (`PrivacyPolicyPage.tsx`, `TermsOfServicePage.tsx`, `DeleteAccountPage.tsx`), account pages, email templates.
- **Email:** transactional sender display name, reply-to, DKIM / SPF record owner.
- **DNS:** decide who owns `gearsnitch.com`, `geargrind.net`, `geargrind.com`. Set up canonical redirects.
- **Referral copy:** "Refer a friend to GearSnitch" — audit `web/src/pages/ReferralsPage.tsx` and iOS referral strings.
- **API / codebase:** search for any leftover `GearGrind` strings (currently only `docs/RALPH-BACKLOG.md`). The GitHub org slug `GeargrindNetwork` is a larger question — rename the org or leave it?
- **Push notification sender name** (APNs `alert.title` defaults or copy that prepends brand).
- **Legal entity on the Apple Developer account** (this is brand-adjacent; note the disconnect between DBA and legal entity).

## Recommendation

**Option A — GearSnitch canonical.** Rationale in three sentences:

1. The product codebase is already 95% GearSnitch; switching to GearGrind would cost weeks of rename work and break every existing screenshot, App Store screenshot, support thread, and external link — all before we've shipped v1.
2. "GearSnitch" is distinctive and brandable (uncommon compound word, available as a .com, easy trademark class fit), whereas "GearGrind" collides with a broader fitness-jargon cluster.
3. We can keep "Shawn Frazier Inc" (or rename the LLC later) as the quiet legal entity and let `geargrind.net` 301-redirect to `gearsnitch.com` — zero user-facing brand hierarchy to memorize.

The only work required: rename the GitHub org (optional; cosmetic), point `geargrind.net` DNS at `gearsnitch.com`, and make sure Stripe / App Store Connect / email sender all display "GearSnitch."

## Decision table

| Option | Founder choice (X one) | Decision date | Rationale (1–2 sentences) |
|---|---|---|---|
| A — GearSnitch canonical | | | |
| B — GearGrind canonical | | | |
| C — Hybrid parent-child | | | |

**Target decision date:** ____________________
**Decided by:** ____________________
**Follow-up tickets to file once decided:** DNS redirect, App Store Connect name lock, Stripe descriptor update, footer link cleanup, email sender config.
