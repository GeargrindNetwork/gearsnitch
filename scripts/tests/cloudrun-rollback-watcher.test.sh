#!/usr/bin/env bash
# scripts/tests/cloudrun-rollback-watcher.test.sh
#
# Plain-shell unit tests for scripts/cloudrun-rollback-watcher.sh.
#
# We don't have a real Cloud Run project in CI, so we stub `gcloud` with a
# shell script on PATH and drive it via env-var scenarios. The stub writes
# its argv to a log file so we can assert on what the watcher tried to do.
#
# Cases covered (at minimum, per item #30 requirements):
#   1. threshold-just-below   — 5% exactly, threshold 5 -> no rollback, exit 0
#   2. threshold-just-above   — 6%, threshold 5 -> rollback invoked, exit 1
#   3. no-metrics-yet         — empty time-series -> tolerated, exit 0
#   4. gcloud-failure-fatal   — `gcloud run revisions list` returns rc=1 -> exit 2
#   5. idempotent-noop        — current traffic already on previous rev -> exit 0, no update-traffic
#   6. single-revision        — no previous rev exists -> exit 0, no update-traffic
#
# Usage: bash scripts/tests/cloudrun-rollback-watcher.test.sh
# Exit : 0 if all cases pass, 1 otherwise.

set -u
set -o pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/cloudrun-rollback-watcher.sh"

if [[ ! -x "$SCRIPT" ]]; then
  echo "error: $SCRIPT not executable" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required to run these tests" >&2
  exit 2
fi

PASS=0
FAIL=0
FAILED_CASES=()

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# mock gcloud
# ---------------------------------------------------------------------------
#
# The stub's behavior is entirely driven by env vars set per-case:
#
#   MOCK_REVISIONS_JSON   — JSON body for `gcloud run revisions list`
#                           (newest first). If unset, defaults to two revs.
#   MOCK_REVISIONS_FAIL   — if "1", `revisions list` exits 1.
#   MOCK_SERVICE_JSON     — JSON body for `gcloud run services describe`.
#                           Used to determine current-traffic revision.
#   MOCK_TS_JSON          — JSON body for `gcloud monitoring time-series list`.
#                           Set to "[]" to simulate "no metrics yet".
#   MOCK_TS_FAIL          — if "1", `monitoring time-series list` exits 1.
#   MOCK_UPDATE_FAIL      — if "1", `services update-traffic` exits 1.
#   MOCK_LOG              — path to a log file the stub appends its argv to.
#
# Keeping this in a single stub script means all code paths in the watcher
# hit the same shape of fake CLI — the closest we can get to a real gcloud
# without spending cloud money.

MOCK_BIN="$TMP/bin"
mkdir -p "$MOCK_BIN"

cat > "$MOCK_BIN/gcloud" <<'STUB'
#!/usr/bin/env bash
# Mock gcloud for cloudrun-rollback-watcher tests.
set -u

LOG="${MOCK_LOG:-/dev/null}"
printf 'gcloud' >> "$LOG"
for a in "$@"; do printf ' %q' "$a" >> "$LOG"; done
printf '\n' >> "$LOG"

DEFAULT_REVISIONS='[{"metadata":{"name":"svc-00002-abc"}},{"metadata":{"name":"svc-00001-xyz"}}]'
DEFAULT_SERVICE='{"status":{"traffic":[{"revisionName":"svc-00002-abc","percent":100}]}}'
DEFAULT_TS='[]'

# Dispatch on the subcommand path.
sub="$1 ${2:-} ${3:-}"

case "$sub" in
  "run revisions list"*)
    if [ "${MOCK_REVISIONS_FAIL:-0}" = "1" ]; then
      echo "mock: revisions list failed" >&2
      exit 1
    fi
    printf '%s' "${MOCK_REVISIONS_JSON:-$DEFAULT_REVISIONS}"
    exit 0
    ;;
  "run services describe"*)
    printf '%s' "${MOCK_SERVICE_JSON:-$DEFAULT_SERVICE}"
    exit 0
    ;;
  "monitoring time-series list"*)
    if [ "${MOCK_TS_FAIL:-0}" = "1" ]; then
      echo "mock: time-series failed" >&2
      exit 1
    fi
    printf '%s' "${MOCK_TS_JSON:-$DEFAULT_TS}"
    exit 0
    ;;
  "run services update-traffic"*)
    if [ "${MOCK_UPDATE_FAIL:-0}" = "1" ]; then
      echo "mock: update-traffic failed" >&2
      exit 1
    fi
    exit 0
    ;;
  *)
    echo "mock gcloud: unhandled subcommand: $*" >&2
    exit 127
    ;;
esac
STUB
chmod +x "$MOCK_BIN/gcloud"

# ---------------------------------------------------------------------------
# case runner
# ---------------------------------------------------------------------------

run_case() {
  local label="$1"; shift
  local expected_exit="$1"; shift
  local expected_grep_in_log="${1:-}"; shift || true
  local unexpected_grep_in_log="${1:-}"; shift || true

  local case_log="$TMP/log.${RANDOM}-${RANDOM}.txt"
  : > "$case_log"

  # Run the watcher with a mocked gcloud on PATH. We also force tiny timing
  # so the tests take under a couple of seconds in aggregate.
  set +e
  (
    export PATH="$MOCK_BIN:$PATH"
    export MOCK_LOG="$case_log"
    export ROLLBACK_WATCH_SECONDS="2"
    export ROLLBACK_SAMPLE_INTERVAL_SECONDS="1"
    export ROLLBACK_5XX_THRESHOLD_PCT="${CASE_THRESHOLD:-5}"
    export CLOUDRUN_SERVICE="gearsnitch-api"
    export CLOUDRUN_REGION="us-central1"
    export GCLOUD_BIN="gcloud"
    # Per-case mock env is exported by the caller BEFORE run_case.
    "$SCRIPT" >"$case_log.stdout" 2>"$case_log.stderr"
  )
  local actual_exit=$?
  set -e

  local ok=1
  if [[ "$actual_exit" != "$expected_exit" ]]; then
    ok=0
  fi
  # "expected" strings are checked in the watcher's own stdout+stderr so we
  # can assert on log lines like "no-op" or "nothing to roll back".
  # "unexpected" strings are checked against the gcloud argv log so we can
  # assert that e.g. `update-traffic` was NOT invoked on the idempotent path.
  if [[ -n "$expected_grep_in_log" ]] \
      && ! grep -Fq "$expected_grep_in_log" "$case_log.stdout" "$case_log.stderr"; then
    ok=0
  fi
  if [[ -n "$unexpected_grep_in_log" ]] && grep -Fq "$unexpected_grep_in_log" "$case_log"; then
    ok=0
  fi

  if [[ "$ok" == "1" ]]; then
    PASS=$((PASS + 1))
    printf '  [ok]   %s (exit=%s)\n' "$label" "$actual_exit"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (expected exit=$expected_exit, got $actual_exit)")
    printf '  [FAIL] %s (expected %s, got %s)\n' "$label" "$expected_exit" "$actual_exit"
    printf '         gcloud log:\n'
    sed 's/^/           /' "$case_log" || true
    printf '         stdout:\n'
    sed 's/^/           /' "$case_log.stdout" || true
    printf '         stderr:\n'
    sed 's/^/           /' "$case_log.stderr" || true
  fi
}

# Helper: build a time-series JSON with given 2xx and 5xx counts.
make_ts_json() {
  local two="$1" five="$2"
  printf '[
    {"metric":{"labels":{"response_code_class":"2xx"}},"points":[{"value":{"int64Value":"%s"}}]},
    {"metric":{"labels":{"response_code_class":"5xx"}},"points":[{"value":{"int64Value":"%s"}}]}
  ]' "$two" "$five"
}

echo "==> cloudrun-rollback-watcher.sh test suite"
echo

# Helper: clear all MOCK_* env so each case starts from a known default.
reset_mocks() {
  unset MOCK_REVISIONS_JSON MOCK_REVISIONS_FAIL \
        MOCK_SERVICE_JSON \
        MOCK_TS_JSON MOCK_TS_FAIL \
        MOCK_UPDATE_FAIL \
        CASE_THRESHOLD
}

# ---------------------------------------------------------------------------
# case 1: threshold-just-below — 5/100 = 5% = threshold, should NOT rollback
# ---------------------------------------------------------------------------
reset_mocks
export MOCK_TS_JSON="$(make_ts_json 95 5)"
export CASE_THRESHOLD=5
run_case "threshold just below (5% == 5%)" 0 "sample: 5xx=5%" "update-traffic"

# ---------------------------------------------------------------------------
# case 2: threshold-just-above — 6/100 = 6%, threshold 5, SHOULD rollback
# ---------------------------------------------------------------------------
reset_mocks
export MOCK_TS_JSON="$(make_ts_json 94 6)"
export CASE_THRESHOLD=5
run_case "threshold just above (6% > 5%)" 1 "ROLLBACK TRIGGERED" ""

# ---------------------------------------------------------------------------
# case 3: no-metrics-yet — empty time-series list is tolerated
# ---------------------------------------------------------------------------
reset_mocks
export MOCK_TS_JSON="[]"
run_case "no metrics yet (empty time-series)" 0 "no request metrics yet" "update-traffic"

# ---------------------------------------------------------------------------
# case 4: gcloud-failure-fatal — revisions list fails, exit 2
# ---------------------------------------------------------------------------
reset_mocks
export MOCK_REVISIONS_FAIL=1
run_case "gcloud revisions list failure is fatal" 2 "" "update-traffic"

# ---------------------------------------------------------------------------
# case 5: idempotent-noop — current traffic is already on previous rev
# ---------------------------------------------------------------------------
reset_mocks
# services describe says traffic is on svc-00001-xyz (the "previous" one),
# not the newest. Watcher should short-circuit without watching metrics
# and without calling update-traffic.
export MOCK_SERVICE_JSON='{"status":{"traffic":[{"revisionName":"svc-00001-xyz","percent":100}]}}'
run_case "idempotent: current traffic already on previous rev" 0 "no-op" "update-traffic"

# ---------------------------------------------------------------------------
# case 6: single-revision — only one revision exists (first deploy), exit 0
# ---------------------------------------------------------------------------
reset_mocks
export MOCK_REVISIONS_JSON='[{"metadata":{"name":"svc-00001-only"}}]'
run_case "single revision (first deploy) is a no-op" 0 "nothing to roll back" "update-traffic"

reset_mocks

# ---------------------------------------------------------------------------
# summary
# ---------------------------------------------------------------------------
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
