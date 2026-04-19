#!/usr/bin/env bash
# scripts/cloudrun-rollback-watcher.sh
#
# RALPH backlog item #30 — Cloud Run auto-rollback on deploy 5xx.
#
# After a Cloud Run deploy finishes, watch the newest revision's 5xx rate
# for a short window. If it exceeds a threshold, shift 100% of traffic back
# to the previous revision and exit non-zero so the deploy workflow fails
# loudly.
#
# Design goals:
#   * Idempotent: running against an already-healthy (or already-rolled-back)
#     service is a no-op. We only call `services update-traffic` when a
#     rollback is actually needed AND the current traffic is pointing at the
#     bad revision.
#   * Tolerant of empty metrics: Cloud Run revisions often have no requests
#     in the first 30-60s after deploy. "No data" is treated as healthy, not
#     as a failure. We only fire a rollback when we have observed real
#     traffic AND the 5xx rate is over the threshold.
#   * Hard-fails on gcloud errors: if we can't read metrics or list
#     revisions, we exit with a distinct non-zero code so the caller sees
#     a red CI step instead of a silent pass.
#   * Dependency-light: bash + gcloud + jq. No Python, no Node.
#
# Usage:
#   scripts/cloudrun-rollback-watcher.sh [--service NAME] [--region REGION]
#
# Env overrides (all optional):
#   CLOUDRUN_SERVICE                  — default: gearsnitch-api
#   CLOUDRUN_REGION                   — default: us-central1
#   ROLLBACK_5XX_THRESHOLD_PCT        — default: 5
#   ROLLBACK_WATCH_SECONDS            — default: 300
#   ROLLBACK_SAMPLE_INTERVAL_SECONDS  — default: 30
#   GCLOUD_BIN                        — default: gcloud  (tests override this)
#
# Exit codes:
#   0  — healthy; no rollback performed
#   1  — rollback was triggered (5xx above threshold)
#   2  — fatal error (gcloud failure, missing dependency, bad args)

set -u
set -o pipefail

# ---------------------------------------------------------------------------
# config
# ---------------------------------------------------------------------------

SERVICE="${CLOUDRUN_SERVICE:-gearsnitch-api}"
REGION="${CLOUDRUN_REGION:-us-central1}"
THRESHOLD_PCT="${ROLLBACK_5XX_THRESHOLD_PCT:-5}"
WATCH_SECONDS="${ROLLBACK_WATCH_SECONDS:-300}"
SAMPLE_INTERVAL="${ROLLBACK_SAMPLE_INTERVAL_SECONDS:-30}"
GCLOUD_BIN="${GCLOUD_BIN:-gcloud}"

# Parse CLI flags (override env). Kept minimal on purpose.
while [[ $# -gt 0 ]]; do
  case "$1" in
    --service)
      SERVICE="$2"; shift 2 ;;
    --region)
      REGION="$2"; shift 2 ;;
    --threshold-pct)
      THRESHOLD_PCT="$2"; shift 2 ;;
    --watch-seconds)
      WATCH_SECONDS="$2"; shift 2 ;;
    --sample-interval)
      SAMPLE_INTERVAL="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *)
      echo "unknown flag: $1" >&2
      exit 2 ;;
  esac
done

log()  { printf '[rollback-watcher] %s\n' "$*"; }
warn() { printf '[rollback-watcher] WARN: %s\n' "$*" >&2; }
die()  { printf '[rollback-watcher] FATAL: %s\n' "$*" >&2; exit 2; }

command -v "$GCLOUD_BIN" >/dev/null 2>&1 || die "gcloud not found (\$GCLOUD_BIN=$GCLOUD_BIN)"
command -v jq >/dev/null 2>&1            || die "jq not found"

# ---------------------------------------------------------------------------
# gcloud helpers
# ---------------------------------------------------------------------------

# Print the newest and previous revision names for $SERVICE, one per line:
#   line 1 = newest
#   line 2 = previous (empty if only one revision exists)
discover_revisions() {
  local json
  if ! json=$("$GCLOUD_BIN" run revisions list \
        --service="$SERVICE" \
        --region="$REGION" \
        --sort-by="~metadata.creationTimestamp" \
        --format=json 2>/dev/null); then
    return 1
  fi
  printf '%s' "$json" | jq -r '.[0].metadata.name // empty'
  printf '%s' "$json" | jq -r '.[1].metadata.name // empty'
}

# Print the revision name that currently has 100% traffic (or the highest
# share). Empty string if we can't determine it.
current_traffic_revision() {
  "$GCLOUD_BIN" run services describe "$SERVICE" \
    --region="$REGION" \
    --format=json 2>/dev/null \
    | jq -r '
        (.status.traffic // [])
        | sort_by(.percent // 0)
        | reverse
        | .[0].revisionName // empty
      '
}

# Print the 5xx rate (as an integer percent, 0-100) for $revision over the
# last 60s. Empty string if no request has been seen yet — the caller must
# treat empty as "tolerant: keep polling".
#
# We use `gcloud monitoring time-series list` against the Cloud Run
# request_count metric, filtered by revision_name and grouped by
# response_code_class. The math:
#
#   5xx_pct = 100 * sum(5xx) / sum(all)
#
# If sum(all) == 0, emit nothing.
sample_5xx_pct() {
  local revision="$1"
  local json
  # Metric interval = last 60s, ending now.
  local end_ts start_ts
  end_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  if date -u -v-60S +%Y-%m-%dT%H:%M:%SZ >/dev/null 2>&1; then
    start_ts=$(date -u -v-60S +%Y-%m-%dT%H:%M:%SZ)     # BSD/macOS
  else
    start_ts=$(date -u -d '60 seconds ago' +%Y-%m-%dT%H:%M:%SZ)  # GNU/Linux
  fi

  if ! json=$("$GCLOUD_BIN" monitoring time-series list \
        --filter="metric.type=\"run.googleapis.com/request_count\" AND resource.labels.service_name=\"$SERVICE\" AND resource.labels.revision_name=\"$revision\"" \
        --interval-start-time="$start_ts" \
        --interval-end-time="$end_ts" \
        --format=json 2>/dev/null); then
    return 1
  fi

  # Sum all points, and sum points whose response_code_class is "5xx".
  # Points come back as {metric:{labels:{response_code_class:"2xx"}}, points:[{value:{int64Value:"N"}}]}
  # across multiple series — one per class.
  printf '%s' "$json" | jq -r '
    def to_num(v):
      (v.int64Value // v.doubleValue // v.distributionValue.count // "0")
      | tonumber;
    def series_total:
      [ .points[]?.value | to_num(.) ] | add // 0;

    ([ .[]                                                  | series_total ] | add // 0) as $all
    | ([ .[] | select(.metric.labels.response_code_class == "5xx") | series_total ] | add // 0) as $five
    | if $all == 0 then ""
      else ( ($five * 100) / $all | floor )
      end
  '
}

# Shift 100% of traffic back to $prev on $SERVICE. Idempotent: if the
# service is already serving from $prev, gcloud is a no-op at the revision
# level but we still call it so the control loop converges.
perform_rollback() {
  local prev="$1"
  log "rolling back: shifting 100% traffic to $prev"
  if ! "$GCLOUD_BIN" run services update-traffic "$SERVICE" \
        --region="$REGION" \
        --to-revisions="${prev}=100" \
        --quiet >/dev/null; then
    die "gcloud services update-traffic failed"
  fi
}

# ---------------------------------------------------------------------------
# main control loop
# ---------------------------------------------------------------------------

log "service=$SERVICE region=$REGION threshold=${THRESHOLD_PCT}% watch=${WATCH_SECONDS}s sample=${SAMPLE_INTERVAL}s"

# Capture revisions up front. We only ever roll back to the revision that
# was serving when we started watching; if the service already rolled back
# manually (current != newest), we treat that as "nothing to do".
#
# We use a portable read loop instead of `mapfile` because some
# environments (notably macOS /bin/bash 3.2) don't support mapfile.
REV_OUTPUT=$(discover_revisions) || die "gcloud run revisions list failed"
NEWEST=""
PREVIOUS=""
_i=0
while IFS= read -r _line; do
  case "$_i" in
    0) NEWEST="$_line" ;;
    1) PREVIOUS="$_line" ;;
  esac
  _i=$((_i + 1))
done <<REV_EOF
$REV_OUTPUT
REV_EOF
unset _i _line

if [[ -z "$NEWEST" ]]; then
  die "could not determine newest revision for $SERVICE"
fi

if [[ -z "$PREVIOUS" ]]; then
  log "no previous revision exists (first deploy?) — nothing to roll back to, exiting healthy"
  exit 0
fi

CURRENT_TRAFFIC=$(current_traffic_revision || true)
log "newest=$NEWEST previous=$PREVIOUS current-traffic=${CURRENT_TRAFFIC:-unknown}"

# Idempotency guard: if the service is NOT currently serving the newest
# revision, there's nothing to watch (either the deploy didn't wire it up,
# or a prior invocation already rolled it back). Exit clean.
if [[ -n "$CURRENT_TRAFFIC" && "$CURRENT_TRAFFIC" != "$NEWEST" ]]; then
  log "current traffic is already on $CURRENT_TRAFFIC (not the newest $NEWEST); no-op"
  exit 0
fi

deadline=$(( $(date +%s) + WATCH_SECONDS ))
samples_seen=0
breaches=0

while :; do
  now=$(date +%s)
  if (( now >= deadline )); then
    break
  fi

  pct=$(sample_5xx_pct "$NEWEST") || die "gcloud monitoring time-series list failed"

  if [[ -z "$pct" ]]; then
    log "no request metrics yet for $NEWEST — tolerating, will re-sample"
  else
    samples_seen=$((samples_seen + 1))
    log "sample: 5xx=${pct}% (threshold=${THRESHOLD_PCT}%)"
    if (( pct > THRESHOLD_PCT )); then
      breaches=$((breaches + 1))
      warn "5xx rate ${pct}% exceeds threshold ${THRESHOLD_PCT}% on $NEWEST (breach #$breaches)"
      perform_rollback "$PREVIOUS"
      log "ROLLBACK TRIGGERED: $NEWEST -> $PREVIOUS (5xx=${pct}%)"
      exit 1
    fi
  fi

  # Sleep but never past the deadline.
  remaining=$(( deadline - $(date +%s) ))
  if (( remaining <= 0 )); then
    break
  fi
  if (( remaining < SAMPLE_INTERVAL )); then
    sleep "$remaining"
  else
    sleep "$SAMPLE_INTERVAL"
  fi
done

log "watch window complete: samples=${samples_seen} breaches=${breaches} — healthy"
exit 0
