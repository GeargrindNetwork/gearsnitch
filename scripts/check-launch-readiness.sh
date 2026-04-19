#!/usr/bin/env bash
# scripts/check-launch-readiness.sh
#
# Launch-gate pre-flight check for the GearSnitch iOS app.
# Verifies required entitlements, Info.plist privacy strings, bundle id,
# team id, and optional provisioning-profile push capability.
#
# Exit codes:
#   0  everything required is present
#   1  one or more required checks failed
#   2  invocation / environment error (missing files, bad args)
#
# Usage:
#   scripts/check-launch-readiness.sh
#     Uses the repo's canonical paths under client-ios/.
#
#   scripts/check-launch-readiness.sh \
#     --info-plist path/to/Info.plist \
#     --entitlements path/to/GearSnitch.entitlements \
#     --project-yml path/to/project.yml
#     Explicit paths (used by unit tests / bats fixtures).
#
# This script ONLY reads. It never modifies any file.

set -u
set -o pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

INFO_PLIST_DEFAULT="$REPO_ROOT/client-ios/GearSnitch/Resources/Info.plist"
ENTITLEMENTS_DEFAULT="$REPO_ROOT/client-ios/GearSnitch/GearSnitch.entitlements"
PROJECT_YML_DEFAULT="$REPO_ROOT/client-ios/project.yml"
PROVISIONING_PROFILE_DEFAULT=""

INFO_PLIST="$INFO_PLIST_DEFAULT"
ENTITLEMENTS="$ENTITLEMENTS_DEFAULT"
PROJECT_YML="$PROJECT_YML_DEFAULT"
PROVISIONING_PROFILE="$PROVISIONING_PROFILE_DEFAULT"

EXPECTED_BUNDLE_ID="com.gearsnitch.app"
EXPECTED_TEAM_ID="TUZYDM227C"
EXPECTED_MERCHANT_ID="merchant.gearsnitch.app"

# -----------------------------------------------------------------------------
# arg parsing
# -----------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --info-plist)
      INFO_PLIST="$2"
      shift 2
      ;;
    --entitlements)
      ENTITLEMENTS="$2"
      shift 2
      ;;
    --project-yml)
      PROJECT_YML="$2"
      shift 2
      ;;
    --provisioning-profile)
      PROVISIONING_PROFILE="$2"
      shift 2
      ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

# -----------------------------------------------------------------------------
# output helpers
# -----------------------------------------------------------------------------
FAILURES=()
PASSES=()
WARNINGS=()

pass() {
  PASSES+=("$1")
  printf '  [PASS] %s\n' "$1"
}

fail() {
  local label="$1"
  local detail="${2:-}"
  FAILURES+=("$label${detail:+ — $detail}")
  if [[ -n "$detail" ]]; then
    printf '  [FAIL] %s — %s\n' "$label" "$detail"
  else
    printf '  [FAIL] %s\n' "$label"
  fi
}

warn() {
  WARNINGS+=("$1")
  printf '  [WARN] %s\n' "$1"
}

# -----------------------------------------------------------------------------
# plist helpers
#
# We prefer /usr/libexec/PlistBuddy on macOS (where CI runs) but fall back to a
# grep-based XML inspection for Linux / bats fixtures so this script stays
# testable off-device.
# -----------------------------------------------------------------------------
plistbuddy_available() {
  [[ -x /usr/libexec/PlistBuddy ]]
}

plist_has_key() {
  local file="$1"
  local key="$2"

  if plistbuddy_available; then
    /usr/libexec/PlistBuddy -c "Print :$key" "$file" >/dev/null 2>&1
    return $?
  fi

  # Fallback: look for <key>NAME</key> in the XML plist.
  grep -Fq "<key>$key</key>" "$file"
}

plist_string_value() {
  local file="$1"
  local key="$2"

  if plistbuddy_available; then
    /usr/libexec/PlistBuddy -c "Print :$key" "$file" 2>/dev/null
    return $?
  fi

  # Fallback: naive XML scrape. Finds the <string> immediately after <key>KEY</key>.
  awk -v key="$key" '
    $0 ~ "<key>" key "</key>" { found=1; next }
    found && /<string>/ {
      line = $0
      sub(/.*<string>/, "", line)
      sub(/<\/string>.*/, "", line)
      print line
      exit
    }
  ' "$file"
}

# -----------------------------------------------------------------------------
# checks
# -----------------------------------------------------------------------------
check_file_exists() {
  local label="$1"
  local path="$2"
  if [[ ! -f "$path" ]]; then
    fail "$label exists" "not found at $path"
    return 1
  fi
  pass "$label exists"
  return 0
}

check_entitlement_key() {
  local key="$1"
  local description="$2"
  if plist_has_key "$ENTITLEMENTS" "$key"; then
    pass "entitlement: $key ($description)"
  else
    fail "entitlement: $key ($description)" "missing from $ENTITLEMENTS"
  fi
}

check_entitlement_merchant() {
  local found=0

  if plistbuddy_available; then
    # The in-app-payments entitlement is an array of merchant IDs.
    local i=0
    while :; do
      local val
      val=$(/usr/libexec/PlistBuddy \
        -c "Print :com.apple.developer.in-app-payments:$i" \
        "$ENTITLEMENTS" 2>/dev/null) || break
      if [[ "$val" == "$EXPECTED_MERCHANT_ID" ]]; then
        found=1
        break
      fi
      i=$((i + 1))
    done
  else
    if grep -Fq "<string>$EXPECTED_MERCHANT_ID</string>" "$ENTITLEMENTS"; then
      found=1
    fi
  fi

  if [[ "$found" -eq 1 ]]; then
    pass "Apple Pay merchant id: $EXPECTED_MERCHANT_ID"
  else
    fail "Apple Pay merchant id: $EXPECTED_MERCHANT_ID" \
      "not present under com.apple.developer.in-app-payments"
  fi
}

check_info_plist_key() {
  local key="$1"
  local description="$2"
  if plist_has_key "$INFO_PLIST" "$key"; then
    # For string keys, also confirm the value is non-empty.
    local val
    val=$(plist_string_value "$INFO_PLIST" "$key" 2>/dev/null || true)
    if [[ -n "$val" ]]; then
      pass "Info.plist: $key ($description)"
    else
      # Non-string keys (e.g. boolean) — key-present is enough.
      pass "Info.plist: $key ($description)"
    fi
  else
    fail "Info.plist: $key ($description)" "missing from $INFO_PLIST"
  fi
}

check_bundle_id_and_team() {
  local bundle_id_match=0
  local team_id_match=0

  if [[ -f "$PROJECT_YML" ]]; then
    if grep -Eq "PRODUCT_BUNDLE_IDENTIFIER:[[:space:]]+$EXPECTED_BUNDLE_ID\b" "$PROJECT_YML"; then
      bundle_id_match=1
    fi
    if grep -Eq "DEVELOPMENT_TEAM:[[:space:]]+$EXPECTED_TEAM_ID\b" "$PROJECT_YML"; then
      team_id_match=1
    fi
  fi

  if [[ "$bundle_id_match" -eq 1 ]]; then
    pass "bundle id: $EXPECTED_BUNDLE_ID"
  else
    fail "bundle id: $EXPECTED_BUNDLE_ID" "not found in $PROJECT_YML"
  fi

  if [[ "$team_id_match" -eq 1 ]]; then
    pass "team id: $EXPECTED_TEAM_ID"
  else
    fail "team id: $EXPECTED_TEAM_ID" "not found in $PROJECT_YML"
  fi
}

# Asserts that project.yml itself declares the Apple Pay capability under the
# main GearSnitch target's `entitlements.properties` block. XcodeGen rebuilds
# GearSnitch.entitlements from this declaration on every regen — so if it
# vanishes from project.yml, the next `xcodegen generate` will silently strip
# the entitlement (history: PR #25 had to add it after a previous regen lost
# it). Backlog item #13.
check_project_yml_apple_pay_capability() {
  local in_app_payments_match=0
  local merchant_match=0

  # Match either same-line (`com.apple.developer.in-app-payments: [...]`) or
  # the YAML-block form we use in project.yml (key on its own line, merchant
  # on a subsequent `- merchant.gearsnitch.app` line).
  if grep -Eq "^[[:space:]]+com\.apple\.developer\.in-app-payments[[:space:]]*:" \
      "$PROJECT_YML"; then
    in_app_payments_match=1
  fi

  if grep -Eq "^[[:space:]]+-[[:space:]]+$EXPECTED_MERCHANT_ID([[:space:]]|$)" \
      "$PROJECT_YML"; then
    merchant_match=1
  fi

  if [[ "$in_app_payments_match" -eq 1 && "$merchant_match" -eq 1 ]]; then
    pass "project.yml declares Apple Pay (in-app-payments + $EXPECTED_MERCHANT_ID)"
  else
    fail "project.yml declares Apple Pay capability" \
      "missing com.apple.developer.in-app-payments entry with $EXPECTED_MERCHANT_ID — next xcodegen regen will silently strip the entitlement (item #13)"
  fi
}

check_provisioning_profile_push() {
  if [[ -z "$PROVISIONING_PROFILE" ]]; then
    warn "provisioning profile not supplied — skipping APNs push capability check"
    return 0
  fi

  if [[ ! -f "$PROVISIONING_PROFILE" ]]; then
    fail "provisioning profile readable" "$PROVISIONING_PROFILE not found"
    return 0
  fi

  # .mobileprovision is a CMS blob. `security cms -D` is macOS-only; fall back
  # to a raw grep for the aps-environment entitlement substring.
  local decoded=""
  if command -v security >/dev/null 2>&1; then
    decoded=$(security cms -D -i "$PROVISIONING_PROFILE" 2>/dev/null || true)
  fi
  if [[ -z "$decoded" ]]; then
    decoded=$(strings "$PROVISIONING_PROFILE" 2>/dev/null || true)
  fi

  if echo "$decoded" | grep -Fq "aps-environment"; then
    pass "provisioning profile has push (aps-environment) capability"
  else
    fail "provisioning profile has push (aps-environment) capability" \
      "aps-environment entitlement not found in $PROVISIONING_PROFILE"
  fi
}

# -----------------------------------------------------------------------------
# main
# -----------------------------------------------------------------------------
echo "==> GearSnitch launch-readiness check"
echo "    info plist:   $INFO_PLIST"
echo "    entitlements: $ENTITLEMENTS"
echo "    project.yml:  $PROJECT_YML"
if [[ -n "$PROVISIONING_PROFILE" ]]; then
  echo "    profile:      $PROVISIONING_PROFILE"
fi
echo

# File existence prerequisites. If these are missing we can't do anything else.
missing_prereqs=0
check_file_exists "Info.plist" "$INFO_PLIST" || missing_prereqs=1
check_file_exists "entitlements" "$ENTITLEMENTS" || missing_prereqs=1
if [[ "$missing_prereqs" -ne 0 ]]; then
  echo
  echo "==> SUMMARY: required input files missing — aborting."
  exit 1
fi

echo
echo "--> entitlements"
check_entitlement_key "com.apple.developer.in-app-payments" "Apple Pay"
check_entitlement_merchant

echo
echo "--> Info.plist privacy + capability strings"
check_info_plist_key "NSAccessorySetupKitSupports" "AccessorySetupKit (PR #56)"
check_info_plist_key "NSHealthShareUsageDescription" "HealthKit read (PR #57)"
check_info_plist_key "NSHealthUpdateUsageDescription" "HealthKit write (PR #57)"
check_info_plist_key "NSLocationWhenInUseUsageDescription" "Location (when-in-use)"
check_info_plist_key "NSBluetoothAlwaysUsageDescription" "Bluetooth"

echo
echo "--> identifiers"
if [[ -f "$PROJECT_YML" ]]; then
  check_bundle_id_and_team
  check_project_yml_apple_pay_capability
else
  warn "project.yml not found at $PROJECT_YML — skipping bundle/team id and Apple Pay capability checks"
fi

echo
echo "--> provisioning profile (optional)"
check_provisioning_profile_push

# -----------------------------------------------------------------------------
# summary
# -----------------------------------------------------------------------------
echo
echo "==> SUMMARY"
echo "    passed:   ${#PASSES[@]}"
echo "    warnings: ${#WARNINGS[@]}"
echo "    failed:   ${#FAILURES[@]}"

if [[ ${#FAILURES[@]} -gt 0 ]]; then
  echo
  echo "FAILED CHECKS:"
  for f in "${FAILURES[@]}"; do
    echo "  - $f"
  done
  exit 1
fi

echo
echo "OK: launch readiness gate passed."
exit 0
