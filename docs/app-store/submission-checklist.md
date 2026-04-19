# GearSnitch — App Store Submission Checklist

**The night before submit. Founder reviews.** Every box ticked, or we don't push.

---

## Brand + metadata

- [ ] App name decided (see `app-name.md` — S1 brand decision)
- [ ] Subtitle decided (≤30 chars)
- [ ] Promotional text drafted (≤170 chars)
- [ ] Keywords finalized (see `keywords.md`, ≤100 chars)
- [ ] Description finalized (see `description.md`, ≤4000 chars)
- [ ] "What's New" text for version 1.0 drafted

## Visual assets

- [ ] App icon — 1024×1024 PNG, no alpha, no rounded corners
- [ ] Screenshots captured for iPhone 6.9" (required)
- [ ] Screenshots captured for iPhone 6.5"
- [ ] Screenshots captured for iPhone 6.1"
- [ ] Screenshots captured for iPad Pro 13" (if iPad supported)
- [ ] Screenshots captured for iPad Pro 11"
- [ ] Preview video (30s, 1080×1920) — optional, recommended
- [ ] All screenshots reviewed for leaked real-user data

## Age rating

- [ ] Age rating set (17+ recommended — see `age-rating.md`)
- [ ] Content questionnaire answered

## URLs live

- [ ] Privacy Policy URL: `https://gearsnitch.com/privacy` returns 200 (see `privacy-policy-url.md`)
- [ ] Support URL: `https://gearsnitch.com/support` returns 200 (see `support-url.md`)
- [ ] Marketing URL (optional): `https://gearsnitch.com` returns 200

## App Review Information

- [ ] Demo account created, tested, and populated (see `review-notes.md`)
- [ ] Contact name, phone, email filled in
- [ ] Notes field populated with review-notes.md highlights
- [ ] Sign-in required toggle set correctly

## TestFlight

- [ ] Internal tested end-to-end (see `tester-briefing.md`)
- [ ] At least 3 testers completed full flow
- [ ] All critical bugs fixed
- [ ] Build number incremented

## Entitlements + provisioning

- [ ] APNs **production** entitlement in provisioning profile
- [ ] HealthKit entitlement enabled
- [ ] Background Modes: BLE, Location, Remote Notifications
- [ ] Sign in with Apple capability (if used)
- [ ] Associated Domains for universal links
- [ ] App Groups for Widget/Watch
- [ ] Keychain sharing group (if used)

## Payments

- [ ] Apple Pay merchant live in web checkout (for physical goods)
- [ ] All IAP products **created and approved** in App Store Connect
- [ ] Subscription group set up with localized display names
- [ ] Subscription terms and renewal disclosure in-app
- [ ] Restore Purchases button reachable from Settings
- [ ] StoreKit sandbox tested end-to-end
- [ ] Tax and banking info complete in App Store Connect

## Privacy manifest

- [ ] `client-ios/GearSnitch/PrivacyInfo.xcprivacy` matches actual code behavior
- [ ] Data types in manifest match Privacy Policy
- [ ] Third-party SDK privacy manifests reviewed (check Pods/SPM packages)
- [ ] App Privacy section in App Store Connect answered (auto-validated against manifest)

## Export compliance

- [ ] Crypto question answered: **Yes** (uses HTTPS/TLS)
- [ ] Exemption: **Annotation 5** (standard HTTPS only)

## Content rating

- [ ] Questionnaire completed
- [ ] Rating displayed matches intent (17+)

## Release settings

- [ ] Release type chosen: manual / auto after approval / phased (**phased recommended**)
- [ ] Pricing tier chosen
- [ ] Available territories selected
- [ ] Pre-order enabled or disabled

## Final gate

- [ ] Archive built from `main` at tagged commit
- [ ] Build uploaded successfully and processed
- [ ] No missing compliance or metadata warnings in App Store Connect
- [ ] Submit to Review pressed

## Optional but nice

- [ ] Launch press release drafted
- [ ] Launch tweet/post queued
- [ ] Email blast to waitlist scheduled for "available" moment
- [ ] Hockey stick analytics dashboard ready for launch-day monitoring

---

**If any checkbox is unchecked at submit-time, stop. Fix it first.**
