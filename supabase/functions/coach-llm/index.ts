import { createClient } from "npm:@supabase/supabase-js@2";
import { COACH_SYSTEM_PROMPT } from "../_shared/coach-system-prompt.ts";

type CoachKind = "analysis" | "workoutProposal" | "deterministicIntent";

const MAX_PAYLOAD_BYTES = 80 * 1024;
const MAX_REQUEST_CHARS = 1200;
const MAX_HISTORY_MESSAGES = 12;
const MAX_EVIDENCE_ITEMS = 4;

const recentCalls = new Map<string, number[]>();

function json(body: unknown, status = 200): Response {
  return Response.json(body, { status });
}

function boundedRateLimit(userID: string): boolean {
  const now = Date.now();
  const cutoff = now - 60_000;
  const calls = (recentCalls.get(userID) ?? []).filter((value) => value >= cutoff);
  if (calls.length >= 12) {
    recentCalls.set(userID, calls);
    return false;
  }
  calls.push(now);
  recentCalls.set(userID, calls);
  return true;
}

function parsePayload(value: unknown): Record<string, unknown> | null {
  if (typeof value !== "string" || new TextEncoder().encode(value).byteLength > MAX_PAYLOAD_BYTES) {
    return null;
  }
  try {
    const parsed = JSON.parse(value);
    return parsed && typeof parsed === "object" && !Array.isArray(parsed)
      ? parsed as Record<string, unknown>
      : null;
  } catch {
    return null;
  }
}

function cleanModelJSON(text: string): string {
  const trimmed = text.trim();
  if (!trimmed.startsWith("```")) return trimmed;
  return trimmed
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/\s*```$/, "")
    .trim();
}

function validateResponse(value: unknown): Record<string, unknown> | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const object = value as Record<string, unknown>;
  const kind = object.kind;
  const message = object.message;

  if (!["analysis", "workoutProposal", "deterministicIntent"].includes(String(kind))) {
    return null;
  }
  if (typeof message !== "string" || message.trim().length === 0 || message.length > 5000) {
    return null;
  }

  const evidence = Array.isArray(object.evidence)
    ? object.evidence.filter((item): item is string => typeof item === "string").slice(0, MAX_EVIDENCE_ITEMS)
    : [];
  object.evidence = evidence;

  if (kind === "workoutProposal") {
    const workout = object.workout;
    if (!workout || typeof workout !== "object" || Array.isArray(workout)) return null;
    const proposal = workout as Record<string, unknown>;
    if (!["running", "cycling", "swimming"].includes(String(proposal.sport))) return null;
    if (!["easy", "endurance", "technique", "intervals"].includes(String(proposal.focus))) return null;
    if (typeof proposal.dateISO !== "string") return null;
    if (typeof proposal.targetMinutes !== "number" || proposal.targetMinutes < 10 || proposal.targetMinutes > 180) {
      return null;
    }
    if (typeof proposal.goal !== "string" || proposal.goal.length === 0 || proposal.goal.length > 300) {
      return null;
    }
  }

  if (kind === "deterministicIntent") {
    const intent = object.intent;
    if (!intent || typeof intent !== "object" || Array.isArray(intent)) return null;
    const action = String((intent as Record<string, unknown>).kind ?? "");
    if (!["moveSession", "skipSession", "unavailable", "unavailableRange", "limitSession", "easeSession"].includes(action)) {
      return null;
    }
  }

  return object;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const publishableKeysJSON = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS");
  const legacyAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const openAIKey = Deno.env.get("OPENAI_API_KEY");
  const authorization = req.headers.get("Authorization");

  if (!supabaseUrl || !authorization) {
    return json({ error: "Server configuration is incomplete" }, 500);
  }

  let publishableKey = legacyAnonKey ?? "";
  if (publishableKeysJSON) {
    try {
      const keys = JSON.parse(publishableKeysJSON);
      publishableKey = keys.default ?? publishableKey;
    } catch {
      // Legacy key remains the fallback.
    }
  }
  if (!publishableKey) return json({ error: "Server configuration is incomplete" }, 500);

  const userClient = createClient(supabaseUrl, publishableKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user) return json({ error: "Authentication required" }, 401);
  if (!boundedRateLimit(user.id)) return json({ error: "Too many Coach requests. Try again shortly." }, 429);
  if (!openAIKey) return json({ error: "AI Coach is not configured on the server" }, 503);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  const payload = parsePayload(body.payload);
  if (!payload) return json({ error: "Invalid or oversized Coach payload" }, 400);

  const request = typeof payload.request === "string" ? payload.request.trim() : "";
  if (!request || request.length > MAX_REQUEST_CHARS) {
    return json({ error: "Coach request is empty or too long" }, 400);
  }

  if (Array.isArray(payload.recentMessages) && payload.recentMessages.length > MAX_HISTORY_MESSAGES) {
    payload.recentMessages = payload.recentMessages.slice(-MAX_HISTORY_MESSAGES);
  }

  const model = Deno.env.get("ATHEVIA_COACH_MODEL") ?? "gpt-6-luna";

  const openAIResponse = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${openAIKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model,
      instructions: COACH_SYSTEM_PROMPT,
      input: [{ role: "user", content: JSON.stringify(payload) }],
      max_output_tokens: 1200,
      store: false,
    }),
  });

  const raw = await openAIResponse.json().catch(() => null);
  if (!openAIResponse.ok) {
    console.error("OpenAI Coach request failed", {
      status: openAIResponse.status,
      userID: user.id,
      detail: raw?.error?.message ?? "unknown",
    });
    return json({ error: "AI Coach request failed" }, 502);
  }

  const outputText = Array.isArray(raw?.output)
    ? raw.output
        .flatMap((item: any) => Array.isArray(item?.content) ? item.content : [])
        .find((content: any) => content?.type === "output_text")?.text
    : null;

  if (typeof outputText !== "string") {
    return json({ error: "AI Coach returned no usable response" }, 502);
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(cleanModelJSON(outputText));
  } catch {
    console.error("AI Coach returned invalid JSON", { userID: user.id });
    return json({ error: "AI Coach returned an invalid response" }, 502);
  }

  const validated = validateResponse(parsed);
  if (!validated) {
    console.error("AI Coach response failed schema validation", { userID: user.id });
    return json({ error: "AI Coach response failed validation" }, 502);
  }

  return json(validated);
});
