/**
 * Gemini (via Vertex AI) insight client.
 *
 * Used to generate a single-sentence coaching observation for a
 * just-completed workout, surfaced in the workout summary push.
 *
 * Design notes
 * ------------
 * - Lazy Proxy init mirroring `PaymentService.ts` so importing this module
 *   at type-check / test / CI time never requires GCP env or ADC to be
 *   present. The SDK is only constructed on first real use.
 * - Authentication uses Application Default Credentials. On Cloud Run this
 *   comes free from the metadata server; locally `gcloud auth
 *   application-default login` works. No secret file needed.
 * - Feature flag: `GEMINI_INSIGHTS_ENABLED` must be the string `'true'`
 *   (case-insensitive) to engage. Anything else -> return `null`.
 * - Guardrails:
 *     * safety: BLOCK_MEDIUM_AND_ABOVE on all four harm categories.
 *     * maxOutputTokens: 80  (keeps push body + insight under 230 chars).
 *     * temperature: 0.7    (modest variety, no essay mode).
 *     * 3s hard timeout wrapped around `generateContent`.
 * - Graceful degradation: timeout / network error / safety block / empty
 *   model output / env flag false all collapse to `null`. The upstream
 *   push send MUST NOT fail because Gemini is down.
 * - Logging: we log *only* model + token counts + latency + outcome. We
 *   do NOT log the prompt, the user input, or the completion text. PII +
 *   cost monitoring boundary.
 *
 * Env vars
 * --------
 * GEMINI_INSIGHTS_ENABLED   'true' to enable (default false)
 * GCP_PROJECT_ID            GCP project id (default 'gearsnitch')
 * GCP_LOCATION              Vertex AI region (default 'us-central1')
 *
 * IAM
 * ---
 * The Cloud Run runtime service account must hold `roles/aiplatform.user`
 * on the project. See docs/ai/gemini-integration.md.
 */

import type {
  VertexAI as VertexAIType,
  GenerativeModel,
  SafetySetting,
} from '@google-cloud/vertexai';
import logger from '../utils/logger.js';

// ---------------------------------------------------------------------------
// Tunables
// ---------------------------------------------------------------------------

const MODEL_ID = 'gemini-2.5-flash';
const MAX_OUTPUT_TOKENS = 80;
const TEMPERATURE = 0.7;
const REQUEST_TIMEOUT_MS = 3_000;
const MAX_INSIGHT_CHARS = 200;

const SYSTEM_PROMPT =
  "You are a concise fitness coach. Given the user's just-completed workout and their prior-week averages (if supplied), return a single sentence of 8-25 words with a specific observation or encouragement. No disclaimers, no medical claims, no emojis. If nothing notable, return an empty string.";

// ---------------------------------------------------------------------------
// Env helpers
// ---------------------------------------------------------------------------

function flagEnabled(): boolean {
  return (process.env.GEMINI_INSIGHTS_ENABLED ?? '').trim().toLowerCase() === 'true';
}

function projectId(): string {
  return (process.env.GCP_PROJECT_ID ?? '').trim() || 'gearsnitch';
}

function location(): string {
  return (process.env.GCP_LOCATION ?? '').trim() || 'us-central1';
}

// ---------------------------------------------------------------------------
// Lazy-init VertexAI client (Proxy pattern, mirrors PaymentService.ts)
//
// We hold the SDK module itself in a lazy ref too because requiring
// @google-cloud/vertexai at module load pulls in gRPC / gaxios which we
// don't want in tests that don't touch Gemini at all.
// ---------------------------------------------------------------------------

type VertexAICtor = new (opts: { project: string; location: string }) => VertexAIType;

let _sdk: { VertexAI: VertexAICtor; HarmCategory: Record<string, string>; HarmBlockThreshold: Record<string, string> } | null = null;
function loadSdk() {
  if (_sdk === null) {
    // Dynamic require so tests can intercept via module mocking before the
    // first call without touching the real package.

    const mod = require('@google-cloud/vertexai') as typeof import('@google-cloud/vertexai');
    _sdk = {
      VertexAI: mod.VertexAI as unknown as VertexAICtor,
      HarmCategory: mod.HarmCategory as unknown as Record<string, string>,
      HarmBlockThreshold: mod.HarmBlockThreshold as unknown as Record<string, string>,
    };
  }
  return _sdk;
}

let _vertex: VertexAIType | null = null;
function vertexClient(): VertexAIType {
  if (_vertex === null) {
    const { VertexAI } = loadSdk();
    _vertex = new VertexAI({ project: projectId(), location: location() });
  }
  return _vertex;
}

let _model: GenerativeModel | null = null;
function generativeModel(): GenerativeModel {
  if (_model === null) {
    const { HarmCategory, HarmBlockThreshold } = loadSdk();
    const safetySettings: SafetySetting[] = [
      'HARM_CATEGORY_HATE_SPEECH',
      'HARM_CATEGORY_DANGEROUS_CONTENT',
      'HARM_CATEGORY_SEXUALLY_EXPLICIT',
      'HARM_CATEGORY_HARASSMENT',
    ].map((cat) => ({
      category: (HarmCategory[cat] ?? cat) as unknown as SafetySetting['category'],
      threshold: (HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE ??
        'BLOCK_MEDIUM_AND_ABOVE') as unknown as SafetySetting['threshold'],
    }));

    _model = vertexClient().getGenerativeModel({
      model: MODEL_ID,
      safetySettings,
      generationConfig: {
        maxOutputTokens: MAX_OUTPUT_TOKENS,
        temperature: TEMPERATURE,
      },
      systemInstruction: {
        role: 'system',
        parts: [{ text: SYSTEM_PROMPT }],
      },
    });
  }
  return _model;
}

// Test hook: reset cached SDK + client between scenarios.
export function __resetGeminiForTests(): void {
  _sdk = null;
  _vertex = null;
  _model = null;
}

// Test hook: inject a stub model (bypasses SDK load entirely).
export function __setGeminiModelForTests(model: GenerativeModel | null): void {
  _model = model;
  // Also make sdk+vertex non-null so generativeModel() short-circuits; we
  // still want real loadSdk() to never fire inside unit tests.
  if (model !== null) {
    _sdk = _sdk ?? {
      VertexAI: class {} as unknown as VertexAICtor,
      HarmCategory: {},
      HarmBlockThreshold: {},
    };
    _vertex = _vertex ?? ({} as VertexAIType);
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

export interface WorkoutInsightInput {
  activityType: string;
  durationMin: number;
  distanceMeters?: number | null;
  calories?: number | null;
  avgHeartRate?: number | null;
  previousWeekAverage?: {
    durationMin?: number;
    distance?: number;
    avgHR?: number;
  } | null;
}

export interface GeminiPingResult {
  model: string;
  response: string;
  latencyMs: number;
}

/**
 * Generate a single-sentence workout insight.
 * Returns `null` on any failure path (timeout, safety block, empty
 * output, env flag off, SDK error). Callers should treat `null` as
 * "no insight available" and continue without it.
 */
export async function generateWorkoutInsight(
  input: WorkoutInsightInput,
): Promise<string | null> {
  if (!flagEnabled()) {
    return null;
  }

  const started = Date.now();
  try {
    const model = generativeModel();
    const userMessage = JSON.stringify(input);

    const result = await withTimeout(
      model.generateContent({
        contents: [{ role: 'user', parts: [{ text: userMessage }] }],
      }),
      REQUEST_TIMEOUT_MS,
    );

    const insight = extractInsight(result);
    const latencyMs = Date.now() - started;
    const usage = (result?.response as { usageMetadata?: Record<string, number> } | undefined)
      ?.usageMetadata;

    logger.info('gemini.insight', {
      model: MODEL_ID,
      latencyMs,
      success: insight !== null,
      promptTokens: usage?.promptTokenCount,
      completionTokens: usage?.candidatesTokenCount,
      totalTokens: usage?.totalTokenCount,
    });

    return insight;
  } catch (err) {
    const latencyMs = Date.now() - started;
    logger.warn('gemini.insight.error', {
      model: MODEL_ID,
      latencyMs,
      error: err instanceof Error ? err.message : String(err),
    });
    return null;
  }
}

/**
 * Admin health-check: sends a canned "say 'ok'" prompt so we can verify
 * IAM + network + model wiring from the running pod.
 * Throws on misconfiguration or SDK error — the caller (admin route)
 * turns that into a 5xx. We intentionally DON'T swallow errors here
 * because the whole point of the ping is to surface them.
 */
export async function pingGemini(): Promise<GeminiPingResult> {
  const started = Date.now();
  const model = generativeModel();
  const result = await withTimeout(
    model.generateContent({
      contents: [{ role: 'user', parts: [{ text: "Say 'ok' in one word" }] }],
    }),
    REQUEST_TIMEOUT_MS,
  );
  const latencyMs = Date.now() - started;
  const text = extractRawText(result) ?? '';
  return {
    model: MODEL_ID,
    response: text.trim(),
    latencyMs,
  };
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

function withTimeout<T>(p: Promise<T>, ms: number): Promise<T> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`Gemini request timed out after ${ms}ms`)), ms);
    p.then(
      (v) => {
        clearTimeout(timer);
        resolve(v);
      },
      (e) => {
        clearTimeout(timer);
        reject(e);
      },
    );
  });
}

interface VertexResultLike {
  response?: {
    candidates?: Array<{
      finishReason?: string;
      content?: { parts?: Array<{ text?: string }> };
      safetyRatings?: Array<{ blocked?: boolean }>;
    }>;
    promptFeedback?: { blockReason?: string };
  };
}

function extractRawText(result: unknown): string | null {
  const r = result as VertexResultLike;
  const candidate = r?.response?.candidates?.[0];
  if (!candidate) {
    return null;
  }
  const finish = candidate.finishReason;
  if (finish && finish !== 'STOP' && finish !== 'MAX_TOKENS') {
    // SAFETY / RECITATION / OTHER -> treat as blocked.
    return null;
  }
  if (r?.response?.promptFeedback?.blockReason) {
    return null;
  }
  const parts = candidate.content?.parts ?? [];
  const joined = parts.map((p) => p?.text ?? '').join('');
  return joined;
}

function extractInsight(result: unknown): string | null {
  const raw = extractRawText(result);
  if (raw === null) {
    return null;
  }
  const trimmed = raw.trim();
  if (trimmed.length === 0) {
    return null;
  }
  if (trimmed.length <= MAX_INSIGHT_CHARS) {
    return trimmed;
  }
  // Cap aggressively; trim on whitespace boundary if one exists within
  // the cap window to avoid mid-word chopping.
  const slice = trimmed.slice(0, MAX_INSIGHT_CHARS);
  const lastSpace = slice.lastIndexOf(' ');
  return lastSpace > MAX_INSIGHT_CHARS - 40 ? slice.slice(0, lastSpace) : slice;
}
