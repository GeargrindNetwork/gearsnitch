#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();

const checks = [];
let hasFailure = false;

function readFile(relativePath) {
  return fs.readFileSync(path.join(root, relativePath), 'utf8');
}

function record(ok, label, detail = '') {
  checks.push({ ok, label, detail });
  if (!ok) {
    hasFailure = true;
  }
}

function parseEnvKeys(relativePath) {
  const keys = new Set();
  const content = readFile(relativePath);

  for (const line of content.split(/\r?\n/u)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) {
      continue;
    }

    const separatorIndex = trimmed.indexOf('=');
    if (separatorIndex === -1) {
      continue;
    }

    keys.add(trimmed.slice(0, separatorIndex).trim());
  }

  return keys;
}

function requireEnvKeys(relativePath, expectedKeys) {
  const keys = parseEnvKeys(relativePath);
  for (const key of expectedKeys) {
    record(
      keys.has(key),
      `${relativePath} declares ${key}`,
      keys.has(key) ? '' : 'missing expected launch configuration key',
    );
  }
}

function requireContent(relativePath, needle, label) {
  const content = readFile(relativePath);
  record(
    content.includes(needle),
    `${relativePath} ${label}`,
    content.includes(needle) ? '' : `missing ${label}`,
  );
}

requireEnvKeys('web/.env.example', [
  'VITE_GOOGLE_CLIENT_ID',
  'VITE_APPLE_SERVICE_ID',
  'VITE_APPLE_REDIRECT_URI',
  'VITE_STRIPE_PUBLISHABLE_KEY',
]);

requireEnvKeys('api/.env.example', [
  'GOOGLE_OAUTH_CLIENT_ID',
  'GOOGLE_OAUTH_CLIENT_SECRET',
  'APPLE_CLIENT_ID',
  'APPLE_TEAM_ID',
  'APPLE_KEY_ID',
  'APPLE_PRIVATE_KEY',
  'STRIPE_SECRET_KEY',
  'STRIPE_WEBHOOK_SECRET',
  'STRIPE_PUBLISHABLE_KEY',
  'APNS_KEY',
  'APNS_KEY_ID',
  'APNS_TEAM_ID',
]);

requireContent(
  'client-ios/GearSnitch/Resources/Info.plist',
  '<key>GS_GOOGLE_CLIENT_ID</key>',
  'declares GS_GOOGLE_CLIENT_ID',
);
requireContent(
  'client-ios/GearSnitch/Resources/Info.plist',
  '<string>gearsnitch</string>',
  'keeps the gearsnitch URL scheme',
);
requireContent(
  'client-ios/GearSnitch/Resources/Info.plist',
  '<string>remote-notification</string>',
  'includes remote-notification background mode',
);

requireContent(
  'client-ios/GearSnitch/GearSnitch.entitlements',
  '<key>aps-environment</key>',
  'includes aps-environment entitlement',
);
requireContent(
  'client-ios/GearSnitch/GearSnitch.entitlements',
  '<key>com.apple.developer.applesignin</key>',
  'includes Sign in with Apple entitlement',
);

const total = checks.length;
const passed = checks.filter((check) => check.ok).length;

console.log('Launch Config Preflight');
console.log('');

for (const check of checks) {
  const marker = check.ok ? 'PASS' : 'FAIL';
  const suffix = check.detail ? ` — ${check.detail}` : '';
  console.log(`${marker} ${check.label}${suffix}`);
}

console.log('');
console.log(`Summary: ${passed}/${total} checks passed.`);

if (hasFailure) {
  process.exitCode = 1;
} else {
  console.log('Repo launch wiring is in place. Live provider setup still needs separate verification.');
}
