#!/usr/bin/env bash
# scripts/tests/check-launch-readiness.test.sh
#
# Plain-shell test runner for check-launch-readiness.sh. We fall back to plain
# bash because bats is not installed everywhere; on CI this runs as a step.
#
# For each required Info.plist key, we construct a fixture with that key
# removed and assert exit code = 1. We also assert the happy-path fixture
# returns 0, and that missing-entitlement / wrong-bundle / wrong-team
# fixtures all fail.
#
# Usage:
#   bash scripts/tests/check-launch-readiness.test.sh
#
# Exit codes:
#   0  all cases behaved as expected
#   1  one or more cases failed

set -u
set -o pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/check-launch-readiness.sh"
FIXTURES="$TEST_DIR/fixtures"

if [[ ! -x "$SCRIPT" ]]; then
  echo "error: $SCRIPT not executable" >&2
  exit 2
fi

PASS=0
FAIL=0
FAILED_CASES=()

_run() {
  # Returns the script exit code without tripping `set -e`.
  "$SCRIPT" "$@" >/dev/null 2>&1
  echo $?
}

expect_exit() {
  local label="$1"
  local expected="$2"
  shift 2
  local actual
  actual=$(_run "$@")
  if [[ "$actual" == "$expected" ]]; then
    PASS=$((PASS + 1))
    printf '  [ok]   %s (exit=%s)\n' "$label" "$actual"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (expected $expected, got $actual)")
    printf '  [FAIL] %s (expected %s, got %s)\n' "$label" "$expected" "$actual"
  fi
}

make_plist_missing_key() {
  # Emits the good Info.plist with a given <key>...</key><...>...</...> pair
  # stripped. Works for both <string> and <array>-valued keys, and tolerates
  # arbitrary whitespace.
  local key="$1"
  local out="$2"

  awk -v key="$key" '
    BEGIN { skip = 0 }
    {
      if (skip > 0) {
        # Skip the value line(s) until we see the close tag that ends the value.
        if ($0 ~ /<\/string>/ || $0 ~ /<\/array>/ || $0 ~ /<true\/>/ || $0 ~ /<false\/>/) {
          skip = 0
        } else if ($0 ~ /<string>/ && $0 ~ /<\/string>/) {
          # single-line <string>value</string> — done after this line
          skip = 0
        }
        next
      }
      if ($0 ~ "<key>" key "</key>") {
        skip = 1
        next
      }
      print
    }
  ' "$FIXTURES/Info.good.plist" > "$out"
}

# -----------------------------------------------------------------------------
# cases
# -----------------------------------------------------------------------------

echo "==> check-launch-readiness.sh test suite"
echo

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# 1. happy path
expect_exit "happy path passes" 0 \
  --info-plist    "$FIXTURES/Info.good.plist" \
  --entitlements  "$FIXTURES/GearSnitch.good.entitlements" \
  --project-yml   "$FIXTURES/project.good.yml"

# 2. each required Info.plist key individually missing -> exit 1
REQUIRED_PLIST_KEYS=(
  "NSAccessorySetupKitSupports"
  "NSHealthShareUsageDescription"
  "NSHealthUpdateUsageDescription"
  "NSLocationWhenInUseUsageDescription"
  "NSBluetoothAlwaysUsageDescription"
)

for key in "${REQUIRED_PLIST_KEYS[@]}"; do
  fixture="$TMP/Info.missing-$key.plist"
  make_plist_missing_key "$key" "$fixture"

  # Sanity: the stripped fixture must actually lack the key.
  if grep -Fq "<key>$key</key>" "$fixture"; then
    echo "  [FAIL] fixture generator left <key>$key</key> in $fixture" >&2
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("fixture generator for $key")
    continue
  fi

  expect_exit "missing Info.plist key: $key -> exit 1" 1 \
    --info-plist    "$fixture" \
    --entitlements  "$FIXTURES/GearSnitch.good.entitlements" \
    --project-yml   "$FIXTURES/project.good.yml"
done

# 3. missing Apple Pay entitlement entirely -> exit 1
expect_exit "missing Apple Pay entitlement -> exit 1" 1 \
  --info-plist    "$FIXTURES/Info.good.plist" \
  --entitlements  "$FIXTURES/GearSnitch.no-applepay.entitlements" \
  --project-yml   "$FIXTURES/project.good.yml"

# 4. wrong merchant id in entitlement -> exit 1
expect_exit "wrong Apple Pay merchant id -> exit 1" 1 \
  --info-plist    "$FIXTURES/Info.good.plist" \
  --entitlements  "$FIXTURES/GearSnitch.no-merchant.entitlements" \
  --project-yml   "$FIXTURES/project.good.yml"

# 5. wrong bundle id -> exit 1
expect_exit "wrong bundle id -> exit 1" 1 \
  --info-plist    "$FIXTURES/Info.good.plist" \
  --entitlements  "$FIXTURES/GearSnitch.good.entitlements" \
  --project-yml   "$FIXTURES/project.bad-bundle.yml"

# 6. wrong team id -> exit 1
expect_exit "wrong team id -> exit 1" 1 \
  --info-plist    "$FIXTURES/Info.good.plist" \
  --entitlements  "$FIXTURES/GearSnitch.good.entitlements" \
  --project-yml   "$FIXTURES/project.bad-team.yml"

# 7. non-existent Info.plist -> exit 1
expect_exit "non-existent Info.plist -> exit 1" 1 \
  --info-plist    "$TMP/does-not-exist.plist" \
  --entitlements  "$FIXTURES/GearSnitch.good.entitlements" \
  --project-yml   "$FIXTURES/project.good.yml"

# 8. project.yml missing the Apple Pay capability -> exit 1 (item #13)
#    Even when the entitlements file currently has the merchant id, a
#    project.yml that omits it means the next `xcodegen generate` will strip
#    the entitlement on the next regen. We must fail closed.
expect_exit "project.yml missing Apple Pay capability -> exit 1 (item #13)" 1 \
  --info-plist    "$FIXTURES/Info.good.plist" \
  --entitlements  "$FIXTURES/GearSnitch.good.entitlements" \
  --project-yml   "$FIXTURES/project.no-applepay.yml"

# 9. project.yml has Apple Pay block but with a wrong merchant id -> exit 1
#    Catches the historical PR #25 / #29 typo class
#    (`merchant.com.gearsnitch.app` vs canonical `merchant.gearsnitch.app`).
expect_exit "project.yml with wrong Apple Pay merchant id -> exit 1 (item #13)" 1 \
  --info-plist    "$FIXTURES/Info.good.plist" \
  --entitlements  "$FIXTURES/GearSnitch.good.entitlements" \
  --project-yml   "$FIXTURES/project.wrong-merchant.yml"

# -----------------------------------------------------------------------------
# summary
# -----------------------------------------------------------------------------
echo
echo "==> SUMMARY"
echo "    passed: $PASS"
echo "    failed: $FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  echo
  echo "FAILED CASES:"
  for c in "${FAILED_CASES[@]}"; do
    echo "  - $c"
  done
  exit 1
fi
exit 0
