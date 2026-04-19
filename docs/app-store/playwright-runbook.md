# App Store Connect metadata — Playwright runbook

This runbook is for the operator who is about to populate GearSnitch's App
Store Connect (ASC) listing. The script does the boring, repeatable fields.
You do the fields Apple gates behind agreements, identity checks, or
human-only questionnaires.

## TL;DR

```bash
# from repo root
npx playwright install chromium          # first time only
node scripts/asc-metadata-playwright.mjs
```

A headed Chromium window opens at https://appstoreconnect.apple.com. Sign in
with your Apple ID, complete 2FA, land on My Apps, then press ENTER in the
terminal each time the script prompts.

When all automated fields are filled the script stops before any Save /
Submit button and prints a checklist of what's still manual. **Nothing is
submitted automatically.**

## What the script fills

Reads these from `docs/app-store/` and pushes them into ASC:

| ASC field              | Source                                | Notes                             |
|------------------------|---------------------------------------|-----------------------------------|
| App Name               | `app-name.md` (Option A)              | `GearSnitch` (10 chars)           |
| Subtitle               | derived                               | `BLE gym gear, HR, health log`    |
| Promotional Text       | derived (<=170 chars)                 | editable post-submission          |
| Description            | `description.md` §Long                | ~2400 chars, under 4000 cap       |
| Keywords               | `keywords.md` (fenced block)          | 100 chars, at hard limit          |
| Support URL            | `support-url.md`                      | `https://gearsnitch.com/support`  |
| Marketing URL          | derived                               | `https://gearsnitch.com`          |
| Privacy Policy URL     | `privacy-policy-url.md`               | `https://gearsnitch.com/privacy`  |
| App Review Notes       | built from `review-notes.md` summary  | 3.1.1 / 5.1.1 / 5.1.3 responses   |
| App Review Contact     | placeholder                           | `admin@geargrind.net`             |

Bundle ID: `com.gearsnitch.app`  
Team ID:   `TUZYDM227C`

## What the script will NOT do

The script never clicks Save (on some forms ASC auto-saves on blur, which is
fine) and never clicks Submit. It also refuses to touch:

- **App creation** (the `+` button flow). ASC has strict CSRF on that
  endpoint and automating it is fragile. If the listing doesn't exist yet
  the script will detect that, print the required values, and wait for you
  to create it by hand.
- **Pricing & Availability.** Requires Paid Apps agreement + tier selection.
- **Banking / Tax / Agreements.** Legal.
- **In-App Purchase products.** Done separately — create the GearSnitch Pro
  subscription group and products through the ASC UI or App Store Connect
  API.
- **Screenshot upload.** You need real device captures at the iPhone 6.9",
  6.5", and 6.1" sizes. See `screenshots-needed.md`.
- **Age Rating questionnaire.** Walk it manually per `age-rating.md`
  (answer "Medical/Treatment Information = Infrequent/Mild" to land on 17+).
- **Privacy Nutrition Label.** The ASC questionnaire is long and specific
  to the `PrivacyInfo.xcprivacy` manifest; do it by hand so you can think.
- **Demo account credentials.** The script never types passwords. Paste the
  demo account from 1Password ("App Review Demo") into the Demo Account
  fields yourself.
- **Submit for Review.** Never. That's your call, not a script's call.

## Flags

| Flag         | Effect                                                    |
|--------------|-----------------------------------------------------------|
| _(none)_     | Normal run — headed Chromium, fills fields.               |
| `--dry-run`  | Walks every page and logs what it would fill; fills none. |
| `--cleanup`  | Deletes `/tmp/asc-playwright-session` and exits.          |

## Files the script writes

- `scripts/asc-metadata-playwright.log` — timestamped action log.
- `scripts/asc-screenshots/*.png` — full-page captures after each phase.
- `/tmp/asc-playwright-session/` — Playwright user-data-dir holding the
  signed-in Chromium profile between runs. Delete with `--cleanup`.

None of these are checked into git (see `.gitignore`).

## Recovery

If the script crashes or you Ctrl-C mid-fill:

1. **ASC keeps drafts.** Anything the script typed before the crash is
   auto-saved by ASC on blur. Log in through the normal browser and keep
   going from where it stopped.
2. Re-run `node scripts/asc-metadata-playwright.mjs`. Because the session
   directory is persisted at `/tmp/asc-playwright-session`, you usually
   will not need to re-do 2FA.
3. If Apple forces a new 2FA challenge, run with `--cleanup` first to wipe
   the session, then run normally.

## Safety notes

- The script never logs or prints session cookies, tokens, or any
  credential. Every action appended to the log is a plain English
  description (e.g. "Filled Keywords via label").
- The session is scoped to `/tmp/asc-playwright-session`. Nothing is
  written to `~/Library/Application Support` or the real Chromium profile.
- Apple ID credentials are typed only into the live ASC login page by the
  operator — they never pass through the script, Node, or the log.

## Sanity checks before you start

- [ ] `https://gearsnitch.com/privacy` returns 200.
- [ ] `https://gearsnitch.com/support` returns 200.
- [ ] You are signed into the Apple ID that has access to Team `TUZYDM227C`.
- [ ] The GearSnitch app record exists in ASC (or you are prepared to
      create it manually when the script prompts).
- [ ] 1Password entry "App Review Demo" has a working demo account.

## After the run

Work through the printed "Still manual" checklist. Then use
`docs/app-store/submission-checklist.md` as the final gate before pressing
Submit for Review.
