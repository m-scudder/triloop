import { createClient } from "npm:@supabase/supabase-js@2.95.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

const SIMPLE_EVENTS = new Set([
  "app_opened",
  "$screen",
  "onboarding_step_viewed",
  "onboarding_completed",
  "onboarding_failed",
  "why_tapped",
  "info_tapped",
  "calendar_opened",
  "analytics_debug_test",
  "profile_updated",
  "plan_generated",
  "plan_regenerated",
  "workout_prescription_changed",
  "workout_viewed",
  "workout_completed",
  "workout_skipped",
  "workout_moved",
  "plan_update_explanation_viewed",
  "healthkit_import_started",
  "healthkit_import_completed",
  "healthkit_import_failed",
  "workout_matched",
]);

const ACTIONS = [
  "import_workouts",
  "move_workout",
  "skip_workout",
  "change_availability",
  "update_plan",
  "create_next_week",
  "send_to_watch",
  "start_workout",
];

const OUTCOMES = ["requested", "succeeded", "failed", "cancelled"];

const ACTION_EVENTS = new Set(
  ACTIONS.flatMap((action) => OUTCOMES.map((outcome) => `${action}_${outcome}`)),
);

const ALLOWED_EVENTS = new Set([...SIMPLE_EVENTS, ...ACTION_EVENTS]);
const ALLOWED_PROPERTY_KEYS = new Set([
  "$screen_name",
  "step",
  "sport",
  "basis",
  "phase",
  "reason",
  "outcome",
  "origin",
  "from",
  "to",
  "affected_workouts",
  "training_days",
]);

type InputRecord = {
  id?: unknown;
  session_id?: unknown;
  occurred_at?: unknown;
  name?: unknown;
  properties?: unknown;
  app_version?: unknown;
  app_build?: unknown;
  environment?: unknown;
};

function isUUID(value: unknown): value is string {
  return typeof value === "string"
    && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function cleanProperties(value: unknown): Record<string, string> | null {
  if (value == null) return {};
  if (typeof value !== "object" || Array.isArray(value)) return null;

  const entries = Object.entries(value as Record<string, unknown>);
  if (entries.length > 20) return null;

  const result: Record<string, string> = {};
  for (const [key, raw] of entries) {
    if (!ALLOWED_PROPERTY_KEYS.has(key)) return null;
    if (typeof raw !== "string" || raw.length > 120) return null;
    result[key] = raw;
  }
  return result;
}

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  const authHeader = req.headers.get("Authorization");
  const token = authHeader?.replace(/^Bearer\s+/i, "");
  if (!token) return json(401, { error: "unauthorized" });

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const publishable = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!url || !publishable || !serviceRole) {
    return json(500, { error: "server_not_configured" });
  }

  const authClient = createClient(url, publishable, {
    global: { headers: { Authorization: authHeader! } },
    auth: { persistSession: false },
  });
  const { data: authData, error: authError } = await authClient.auth.getUser(token);
  const user = authData.user;
  if (authError || !user) return json(401, { error: "unauthorized" });

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const batch = (body as { batch?: unknown })?.batch;
  if (!Array.isArray(batch) || batch.length < 1 || batch.length > 50) {
    return json(400, { error: "invalid_batch" });
  }

  const rows = [];
  for (const raw of batch as InputRecord[]) {
    if (!isUUID(raw.id) || !isUUID(raw.session_id)) {
      return json(400, { error: "invalid_identifier" });
    }
    if (typeof raw.name !== "string" || !ALLOWED_EVENTS.has(raw.name)) {
      return json(400, { error: "event_not_allowed" });
    }
    if (typeof raw.occurred_at !== "string" || Number.isNaN(Date.parse(raw.occurred_at))) {
      return json(400, { error: "invalid_timestamp" });
    }
    if (typeof raw.app_version !== "string" || raw.app_version.length > 32
      || typeof raw.app_build !== "string" || raw.app_build.length > 32) {
      return json(400, { error: "invalid_app_version" });
    }
    if (!["development", "testflight", "production"].includes(String(raw.environment))) {
      return json(400, { error: "invalid_environment" });
    }
    const properties = cleanProperties(raw.properties);
    if (!properties) return json(400, { error: "invalid_properties" });

    rows.push({
      id: raw.id,
      user_id: user.id,
      session_id: raw.session_id,
      occurred_at: new Date(raw.occurred_at).toISOString(),
      name: raw.name,
      properties,
      app_version: raw.app_version,
      app_build: raw.app_build,
      environment: raw.environment,
    });
  }

  const admin = createClient(url, serviceRole, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { error } = await admin
    .from("analytics_events")
    .upsert(rows, { onConflict: "id", ignoreDuplicates: true });

  if (error) {
    console.error("analytics-ingest insert failed", error.code);
    return json(500, { error: "storage_failed" });
  }

  return json(202, { accepted: rows.length });
});
