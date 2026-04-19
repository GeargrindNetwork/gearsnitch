# Privacy Policy URL

**App Store Connect field:** Privacy Policy URL (required)

**Value:** `https://gearsnitch.com/privacy`

## Pre-submit checks

- [ ] Web team confirms route is live and returns HTTP 200 (not a redirect chain).
- [ ] Page is reachable from a logged-out browser (no auth wall).
- [ ] Page covers: data collected, purpose, retention, deletion, third parties, contact.
- [ ] Page mentions HealthKit data handling explicitly (Apple requires HK-specific disclosure).
- [ ] Page matches the `NSPrivacyCollectedDataTypes` in `PrivacyInfo.xcprivacy`.
- [ ] Page has a "last updated" date within the last 90 days.
- [ ] Jurisdiction-specific sections (CCPA, GDPR) present — ** legal / founder to confirm wording**.

## In-app linkage

- [ ] Settings > Privacy Policy deep-links to the same URL.
- [ ] Onboarding consent screen references the URL.

## Risk notes

- If App Review can't load this URL, the submission is rejected under guideline 5.1.1.
- Any change to collected data types in this app MUST be reflected in the web page within 48 hours.
