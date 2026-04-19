#!/usr/bin/env node
/**
 * GearSnitch — App Store Connect metadata entry (Playwright driver).
 *
 * What this does:
 *   - Launches a headed Chromium window pointed at App Store Connect.
 *   - Waits for the operator to manually sign in + complete 2FA.
 *   - Locates the GearSnitch app listing (by bundle id `com.gearsnitch.app`
 *     or by fuzzy name match).
 *   - Fills metadata from /docs/app-store/*.md:
 *       * App name                   (app-name.md — picks GearSnitch)
 *       * Subtitle                   (derived: "BLE gym gear, HR, health log")
 *       * Promotional text           (short blurb, derived)
 *       * Description (long form)    (description.md §Long)
 *       * Keywords                   (keywords.md)
 *       * Support URL                (gearsnitch.com/support)
 *       * Marketing URL              (gearsnitch.com)
 *       * Privacy Policy URL         (gearsnitch.com/privacy)
 *       * Review notes               (review-notes.md §Guideline responses)
 *       * Review contact (email)     (placeholder: admin@geargrind.net)
 *   - Screenshots every filled page into scripts/asc-screenshots/ for audit.
 *   - PAUSES before any "Submit" / "Add for Review" button. Never submits.
 *
 * What this does NOT do:
 *   - Create the app listing (+ button flow — ASC tightly protects this).
 *   - Pricing / tax / banking.
 *   - Age rating questionnaire (walks operator through it manually).
 *   - IAP product creation.
 *   - Screenshot upload (device captures are operator work).
 *   - Privacy Nutrition Label questionnaire.
 *   - Final submission.
 *
 * Safety:
 *   - Session state lives in /tmp/asc-playwright-session (scoped user-data-dir).
 *   - `--cleanup` removes that dir.
 *   - Never prints cookies, tokens, or any credential.
 *   - Every action appends a timestamped line to scripts/asc-metadata-playwright.log.
 *
 * Usage:
 *   node scripts/asc-metadata-playwright.mjs
 *   node scripts/asc-metadata-playwright.mjs --cleanup   # wipe saved session
 *   node scripts/asc-metadata-playwright.mjs --dry-run   # fill nothing, just walk pages
 */

import { chromium } from 'playwright';
import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, '..');

const SESSION_DIR = '/tmp/asc-playwright-session';
const LOG_PATH = path.join(__dirname, 'asc-metadata-playwright.log');
const SHOT_DIR = path.join(__dirname, 'asc-screenshots');
const DOCS_DIR = path.join(repoRoot, 'docs', 'app-store');

const BUNDLE_ID = 'com.gearsnitch.app';
const TEAM_ID = 'TUZYDM227C';
const APP_NAME = 'GearSnitch';
const SUBTITLE = 'BLE gym gear, HR, health log';
const SUPPORT_URL = 'https://gearsnitch.com/support';
const MARKETING_URL = 'https://gearsnitch.com';
const PRIVACY_URL = 'https://gearsnitch.com/privacy';
const REVIEW_CONTACT_EMAIL = 'admin@geargrind.net';

const args = new Set(process.argv.slice(2));
const DRY_RUN = args.has('--dry-run');
const CLEANUP = args.has('--cleanup');

// ---------- logging ----------

function log(msg) {
  const line = `[${new Date().toISOString()}] ${msg}\n`;
  process.stdout.write(line);
  try {
    fs.appendFileSync(LOG_PATH, line);
  } catch {
    /* ignore */
  }
}

// ---------- cleanup mode ----------

if (CLEANUP) {
  try {
    fs.rmSync(SESSION_DIR, { recursive: true, force: true });
    log(`Removed session dir ${SESSION_DIR}`);
  } catch (e) {
    log(`Could not remove session dir: ${e.message}`);
  }
  process.exit(0);
}

// ---------- helpers ----------

function prompt(question) {
  return new Promise((resolve) => {
    const rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout,
    });
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer);
    });
  });
}

function readDoc(name) {
  return fs.readFileSync(path.join(DOCS_DIR, name), 'utf8');
}

// Extract the "Long (≈3500 chars)" section from description.md. Stops at the
// next H2 so the "Notes for founder" section is excluded.
function extractLongDescription() {
  const raw = readDoc('description.md');
  const marker = /## Long[^\n]*\n/;
  const m = raw.match(marker);
  if (!m) throw new Error('description.md: could not find ## Long section');
  const start = m.index + m[0].length;
  const rest = raw.slice(start);
  const next = rest.match(/\n---\n/);
  const body = next ? rest.slice(0, next.index) : rest;
  return body.trim();
}

// Extract the ```...``` keyword block from keywords.md (first fenced block).
function extractKeywords() {
  const raw = readDoc('keywords.md');
  const m = raw.match(/```[\s\S]*?\n([\s\S]*?)```/);
  if (!m) throw new Error('keywords.md: no fenced keywords block found');
  return m[1].trim();
}

// Build the condensed review notes string for the ASC "Notes" field.
function buildReviewNotes() {
  return [
    'GearSnitch — App Review notes',
    '',
    'Demo account: <OPERATOR: paste from 1Password "App Review Demo">',
    'Primary contact email (escalation): ' + REVIEW_CONTACT_EMAIL,
    '',
    '3.1.1 — All digital content (GearSnitch Pro subscription) is sold via',
    'StoreKit IAP. Physical goods (apparel, straps) are sold via Stripe',
    'Checkout on gearsnitch.com — Apple rules explicitly exempt physical',
    'goods. Referral rewards are store credit for physical goods only and',
    'never unlock digital content. Stripe Customer Portal is web-only and',
    'linked from Settings with External Link Entitlement.',
    '',
    '5.1.1 — HealthKit read: heart rate, active energy, workouts, body mass.',
    'Write: workouts we save. No third-party SDK receives health data. User',
    'can delete all data from Settings > Account > Delete Account.',
    '',
    '5.1.3 — The peptide/supplement log is a user-authored journal.',
    'GearSnitch does not diagnose, recommend doses, or claim therapeutic',
    'benefit. The dosing calculator is a unit converter (mg/IU/mL), not a',
    'recommender. In-app disclaimer appears before first use of the log.',
    '',
    'Export compliance — HTTPS/TLS only. Exempt under Annotation 5.',
    '',
    'Full notes: see docs/app-store/review-notes.md in the GearSnitch repo.',
  ].join('\n');
}

// Short derived promo text (<= 170 chars). Stays within Apple's field limit.
const PROMO_TEXT =
  'Pair BLE gear in seconds, see split live heart rate, log workouts and supplements privately. One app for every rep, every beat, every recovery.';

async function shot(page, name) {
  if (!fs.existsSync(SHOT_DIR)) fs.mkdirSync(SHOT_DIR, { recursive: true });
  const file = path.join(
    SHOT_DIR,
    `${String(Date.now())}-${name.replace(/[^a-z0-9]+/gi, '-')}.png`,
  );
  try {
    await page.screenshot({ path: file, fullPage: true });
    log(`Screenshot -> ${path.relative(repoRoot, file)}`);
  } catch (e) {
    log(`Screenshot failed (${name}): ${e.message}`);
  }
}

// Try to fill a field identified by a label / placeholder / name in the most
// robust order. Returns true on success, false otherwise. Never throws.
async function fillField(page, { labels = [], placeholders = [], names = [], value, fieldName }) {
  if (DRY_RUN) {
    log(`[dry-run] Would fill ${fieldName} (${value.length} chars)`);
    return true;
  }

  for (const label of labels) {
    try {
      const loc = page.getByLabel(label, { exact: false }).first();
      if (await loc.count()) {
        await loc.fill(value, { timeout: 5000 });
        log(`Filled ${fieldName} via label "${label}"`);
        return true;
      }
    } catch {
      /* try next strategy */
    }
  }
  for (const placeholder of placeholders) {
    try {
      const loc = page.getByPlaceholder(placeholder, { exact: false }).first();
      if (await loc.count()) {
        await loc.fill(value, { timeout: 5000 });
        log(`Filled ${fieldName} via placeholder "${placeholder}"`);
        return true;
      }
    } catch {
      /* try next */
    }
  }
  for (const name of names) {
    try {
      const loc = page.locator(`[name="${name}"], [id="${name}"]`).first();
      if (await loc.count()) {
        await loc.fill(value, { timeout: 5000 });
        log(`Filled ${fieldName} via selector [name|id=${name}]`);
        return true;
      }
    } catch {
      /* try next */
    }
  }
  log(`WARN: could not locate ${fieldName} field — leave blank, operator to verify`);
  return false;
}

// ---------- main ----------

async function main() {
  log(`Starting asc-metadata-playwright (bundle ${BUNDLE_ID}, team ${TEAM_ID})`);
  log(`Session dir: ${SESSION_DIR}`);
  if (DRY_RUN) log('DRY RUN — no fields will actually be filled');

  if (!fs.existsSync(SESSION_DIR)) fs.mkdirSync(SESSION_DIR, { recursive: true });

  const context = await chromium.launchPersistentContext(SESSION_DIR, {
    headless: false,
    viewport: { width: 1440, height: 900 },
    acceptDownloads: false,
  });

  const page = context.pages()[0] || (await context.newPage());

  // --- Step 1: sign in ---
  await page.goto('https://appstoreconnect.apple.com/', { waitUntil: 'domcontentloaded' });
  log('Opened App Store Connect.');

  console.log('\n--------------------------------------------------------');
  console.log('  Sign in with your Apple ID in the open browser window.');
  console.log('  Complete 2FA. Navigate to the My Apps dashboard.');
  console.log('  Then press ENTER in this terminal to continue.');
  console.log('--------------------------------------------------------\n');
  await prompt('[waiting] Press ENTER once you are on the My Apps dashboard: ');

  await shot(page, 'after-signin');

  // --- Step 2: locate GearSnitch app listing ---
  log('Attempting to locate GearSnitch app in the dashboard...');
  let appFound = false;

  // Strategy A: explicit navigation to apps list, then search.
  try {
    await page.goto('https://appstoreconnect.apple.com/apps', {
      waitUntil: 'domcontentloaded',
    });
    await page.waitForTimeout(2000);

    const searchBox = page
      .getByPlaceholder(/search/i)
      .or(page.locator('input[type="search"]'))
      .first();

    if (await searchBox.count()) {
      await searchBox.fill('GearSnitch');
      await page.waitForTimeout(1500);
    }

    const link = page.getByRole('link', { name: /GearSnitch/i }).first();
    if (await link.count()) {
      await link.click();
      log('Clicked GearSnitch link from apps list.');
      await page.waitForLoadState('domcontentloaded');
      appFound = true;
    }
  } catch (e) {
    log(`Search-by-name failed: ${e.message}`);
  }

  // Strategy B: fall back to bundle id text match.
  if (!appFound) {
    try {
      const bundleLink = page.getByText(BUNDLE_ID, { exact: false }).first();
      if (await bundleLink.count()) {
        await bundleLink.click();
        log(`Clicked result matching bundle id ${BUNDLE_ID}.`);
        await page.waitForLoadState('domcontentloaded');
        appFound = true;
      }
    } catch {
      /* fall through */
    }
  }

  if (!appFound) {
    console.log('\n--------------------------------------------------------');
    console.log('  Could not auto-locate the GearSnitch listing.');
    console.log('  If this is the FIRST submission, the app record does');
    console.log('  not exist yet. Click the "+" button in App Store Connect');
    console.log('  and create it manually with these values:');
    console.log(`    Platform:  iOS`);
    console.log(`    Name:      ${APP_NAME}`);
    console.log(`    Language:  English (U.S.)`);
    console.log(`    Bundle ID: ${BUNDLE_ID}`);
    console.log(`    SKU:       gearsnitch-ios-1`);
    console.log(`    Full Access`);
    console.log('  Once the record is created, navigate into it, then press');
    console.log('  ENTER to resume metadata filling.');
    console.log('--------------------------------------------------------\n');
    await prompt('[waiting] Press ENTER once you are on the GearSnitch app detail page: ');
    appFound = true;
  }

  await shot(page, 'app-detail-landing');

  // --- Step 3: open App Information / 1.0 Prepare For Submission ---
  console.log('\n--------------------------------------------------------');
  console.log('  In the left sidebar, click "1.0 Prepare for Submission"');
  console.log('  (or the current version draft). Wait for the page to');
  console.log('  load, then press ENTER.');
  console.log('--------------------------------------------------------\n');
  await prompt('[waiting] Press ENTER on the version page: ');

  await shot(page, 'version-page-before-fill');

  // --- Step 4: fill metadata fields ---
  const longDescription = extractLongDescription();
  const keywords = extractKeywords();
  const reviewNotes = buildReviewNotes();

  log(`Long description length: ${longDescription.length} chars`);
  log(`Keywords length: ${keywords.length} chars`);
  log(`Promo text length: ${PROMO_TEXT.length} chars`);

  const automated = [];
  const manual = [];

  async function tryFill(opts) {
    const ok = await fillField(page, opts);
    if (ok) automated.push(opts.fieldName);
    else manual.push(opts.fieldName);
    return ok;
  }

  await tryFill({
    fieldName: 'Promotional Text',
    labels: ['Promotional Text'],
    placeholders: ['Promotional Text'],
    names: ['promotionalText'],
    value: PROMO_TEXT,
  });

  await tryFill({
    fieldName: 'Description',
    labels: ['Description'],
    placeholders: ['Description'],
    names: ['description'],
    value: longDescription,
  });

  await tryFill({
    fieldName: 'Keywords',
    labels: ['Keywords'],
    placeholders: ['Keywords'],
    names: ['keywords'],
    value: keywords,
  });

  await tryFill({
    fieldName: 'Support URL',
    labels: ['Support URL'],
    placeholders: ['https://'],
    names: ['supportUrl', 'supportURL'],
    value: SUPPORT_URL,
  });

  await tryFill({
    fieldName: 'Marketing URL',
    labels: ['Marketing URL'],
    placeholders: ['https://'],
    names: ['marketingUrl', 'marketingURL'],
    value: MARKETING_URL,
  });

  await tryFill({
    fieldName: 'Privacy Policy URL',
    labels: ['Privacy Policy URL'],
    placeholders: ['https://'],
    names: ['privacyPolicyUrl', 'privacyPolicyURL'],
    value: PRIVACY_URL,
  });

  // App Information page holds Name + Subtitle. They live under a separate
  // left-nav "App Information" link. Prompt the operator to flip there.
  console.log('\n--------------------------------------------------------');
  console.log('  Next: in the left sidebar, click "App Information".');
  console.log('  This is where Name, Subtitle, Category, and Content');
  console.log('  Rights live. Wait for the page to load, then press ENTER.');
  console.log('--------------------------------------------------------\n');
  await prompt('[waiting] Press ENTER on the App Information page: ');

  await shot(page, 'app-info-before-fill');

  await tryFill({
    fieldName: 'App Name',
    labels: ['Name', 'App Name'],
    placeholders: ['App Name'],
    names: ['appName', 'name'],
    value: APP_NAME,
  });

  await tryFill({
    fieldName: 'Subtitle',
    labels: ['Subtitle'],
    placeholders: ['Subtitle'],
    names: ['subtitle'],
    value: SUBTITLE,
  });

  // --- Step 5: review information (notes + contact) ---
  console.log('\n--------------------------------------------------------');
  console.log('  Next: scroll back to the version page and find the');
  console.log('  "App Review Information" section (near the bottom).');
  console.log('  Press ENTER when that section is visible.');
  console.log('--------------------------------------------------------\n');
  await prompt('[waiting] Press ENTER on App Review Information: ');

  await shot(page, 'review-info-before-fill');

  await tryFill({
    fieldName: 'Review Contact Email',
    labels: ['Email'],
    placeholders: ['Email'],
    names: ['contactEmail', 'reviewEmail'],
    value: REVIEW_CONTACT_EMAIL,
  });

  await tryFill({
    fieldName: 'Review Notes',
    labels: ['Notes'],
    placeholders: ['Notes'],
    names: ['notes', 'reviewNotes'],
    value: reviewNotes,
  });

  // Demo account stays manual — we never type credentials.
  manual.push('Review Demo Account (username + password)');

  await shot(page, 'review-info-after-fill');

  // --- Step 6: hard stops + printed checklist of what's left ---
  console.log('\n========================================================');
  console.log('  DONE FILLING AUTOMATED FIELDS.');
  console.log('  The script has STOPPED before any Save / Submit button.');
  console.log('  Nothing has been submitted.');
  console.log('========================================================\n');

  console.log('Automated (you should verify):');
  for (const f of automated) console.log(`  [ok] ${f}`);

  console.log('\nStill manual (YOU DO THESE):');
  const staticManual = [
    'Age Rating questionnaire (17+; see docs/app-store/age-rating.md)',
    'Pricing & Availability (tier + territories)',
    'Tax and banking forms (App Store Connect > Agreements)',
    'IAP product creation (GearSnitch Pro subscription + group)',
    'Screenshots upload (6.9", 6.5", 6.1"; see docs/app-store/screenshots-needed.md)',
    'App preview video (optional)',
    'Privacy Nutrition Label questionnaire',
    'Demo account username + password in App Review Information',
    'App category (primary: Health & Fitness; secondary: Lifestyle)',
    'Content Rights (do you own or have licensed all content shown?)',
    'Age Rating submission',
    'Version "What\'s New" text (first submission: skip)',
    'Export compliance answer (Yes -> exempt under Annotation 5)',
    'Final "Submit for Review" click (do NOT let this script press it)',
  ];
  for (const f of [...manual, ...staticManual]) console.log(`  [todo] ${f}`);

  console.log('\nScreenshots saved to: scripts/asc-screenshots/');
  console.log(`Action log:           ${path.relative(repoRoot, LOG_PATH)}`);
  console.log('\nWhen you are done reviewing in the browser, close the window');
  console.log('or Ctrl-C this script. The session is preserved at');
  console.log(`  ${SESSION_DIR}`);
  console.log('Run with --cleanup to wipe it.');

  await prompt('\n[waiting] Press ENTER to close the browser and exit: ');

  await context.close();
  log('Browser closed. Exiting cleanly.');
}

main().catch((err) => {
  log(`FATAL: ${err.stack || err.message || String(err)}`);
  process.exit(1);
});
