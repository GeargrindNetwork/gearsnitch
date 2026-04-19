# Gemini Integration (via Vertex AI)

## What it does

GearSnitch's backend calls Google's `gemini-2.5-flash` model through Vertex AI
to produce a single-sentence coaching insight after a workout is completed.
The insight is appended to the workout summary push notification body when
available; when unavailable, the push is sent without it.

The implementation lives in `api/src/services/geminiClient.ts`. Its public
surface is intentionally narrow:

- `generateWorkoutInsight(input)` — returns `string | null`. Non-null is a
  trimmed, length-capped (~200 chars) single-sentence observation. Any
  failure path (timeout, network error, safety block, empty model output,
  feature flag off) collapses to `null` so upstream callers never fail
  because Gemini is down.
- `pingGemini()` — small diagnostic; sends "Say 'ok' in one word" and
  returns `{ model, response, latencyMs }`. Wired into
  `GET /api/v1/admin/ai/ping` for post-deploy IAM + network verification.

## Cost

`gemini-2.5-flash` pricing (as of 2026-04):

- Input: ~$0.0000375 per 1k tokens
- Output: ~$0.00015 per 1k tokens

A typical workout insight uses roughly **100 input tokens + 30 output
tokens**, which lands at **~$0.0000079 per workout**. At 10k workouts per
month that's **~$0.08/month**. Guardrails `maxOutputTokens: 80` and the
3-second request timeout keep per-request cost and latency bounded even on
pathological model behaviour.

## Environment variables (Cloud Run)

| Variable                   | Default         | Purpose                                      |
| -------------------------- | --------------- | -------------------------------------------- |
| `GEMINI_INSIGHTS_ENABLED`  | `false`         | Must be `'true'` to engage Gemini at all.    |
| `GCP_PROJECT_ID`           | `gearsnitch`    | GCP project hosting the Vertex AI endpoint.  |
| `GCP_LOCATION`             | `us-central1`   | Vertex AI region.                            |

Setting `GEMINI_INSIGHTS_ENABLED=false` (or leaving it unset) causes
`generateWorkoutInsight` to return `null` without ever loading the SDK.
This is the kill-switch.

## Authentication

The client uses **Application Default Credentials (ADC)**. On Cloud Run
this is picked up automatically from the metadata server — no secret file
needs to be mounted. Locally, `gcloud auth application-default login` is
sufficient.

## IAM

The Cloud Run runtime service account must have the **`roles/aiplatform.user`**
role on the project. Grant it with:

```bash
# Find the SA Cloud Run uses:
gcloud run services describe gearsnitch-api --region=us-central1 \
  --format='value(spec.template.spec.serviceAccountName)'

# Bind the role (replace SA_EMAIL with the output above):
gcloud projects add-iam-policy-binding gearsnitch \
  --member='serviceAccount:SA_EMAIL' \
  --role='roles/aiplatform.user'
```

The Vertex AI API itself must be enabled on the project:

```bash
gcloud services enable aiplatform.googleapis.com --project=gearsnitch
```

## Fallback behaviour

Every failure path in `generateWorkoutInsight` returns `null`:

- Feature flag off (`GEMINI_INSIGHTS_ENABLED !== 'true'`)
- SDK not installed / lazy-init throws
- Network / transport error from Vertex AI
- 3-second timeout (`REQUEST_TIMEOUT_MS`) elapses
- Safety filter blocks the response (`finishReason === 'SAFETY'` or
  `promptFeedback.blockReason` set)
- Empty / whitespace-only model output

The caller is expected to pattern-match on `null` and continue without
the insight. The workout summary push must never fail because of Gemini.

## Observability

The client logs exactly three fields on every successful call, and no
user content:

- `model` — always `gemini-2.5-flash`
- `latencyMs` — wall-clock from `generateContent` start to resolve
- `promptTokens`, `completionTokens`, `totalTokens` (from `usageMetadata`)
- `success` — boolean

Errors log `model`, `latencyMs`, and `error.message`. The prompt body and
the completion text are deliberately **not** logged — this is the PII +
cost-monitoring boundary.

Search logs for `gemini.insight` (info) and `gemini.insight.error` (warn).

## How to disable

Set the Cloud Run env var and redeploy:

```bash
gcloud run services update gearsnitch-api --region=us-central1 \
  --update-env-vars=GEMINI_INSIGHTS_ENABLED=false
```

Alternatively, revoke `roles/aiplatform.user` from the runtime SA — every
Gemini call will then fail ADC/IAM and the client's error path will swallow
it into `null`. This is slower to take effect than the env-var toggle but
is a hard kill if the service account is ever compromised.

## Diagnostics

After each deploy, an admin user can hit:

```
GET /api/v1/admin/ai/ping
```

to confirm IAM + network end-to-end. A 200 with
`{ model, response, latencyMs }` means Vertex AI is reachable. A 500 with
a descriptive `error.message` (quota exhausted, permission denied, etc.)
is the expected failure shape.
