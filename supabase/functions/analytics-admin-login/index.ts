import { createClient } from "npm:@supabase/supabase-js@2.95.0";

const ADMIN_EMAIL = "mayankagarwal997@gmail.com";
const ADMIN_USER_ID = "5c16784f-2ab8-4b55-96fc-1740191a53d8";
const SESSION_TTL_MS = 12 * 60 * 60 * 1000;
const WINDOW_MS = 15 * 60 * 1000;
const MAX_FAILURES = 5;

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://m-scudder.github.io",
  "Access-Control-Allow-Headers": "content-type, apikey",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

function bytesToHex(bytes: Uint8Array) {
  return [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function hexToBytes(hex: string) {
  if (!/^[0-9a-f]+$/i.test(hex) || hex.length % 2) throw new Error("invalid_hex");
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  return out;
}

function constantTimeEqual(a: string, b: string) {
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return mismatch === 0;
}

async function sha256Hex(value: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return bytesToHex(new Uint8Array(digest));
}

async function derivePassword(password: string, saltHex: string, iterations: number) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(password),
    "PBKDF2",
    false,
    ["deriveBits"],
  );
  const bits = await crypto.subtle.deriveBits(
    {
      name: "PBKDF2",
      hash: "SHA-256",
      salt: hexToBytes(saltHex),
      iterations,
    },
    key,
    256,
  );
  return bytesToHex(new Uint8Array(bits));
}

function randomToken() {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return bytesToHex(bytes);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!url || !serviceRole) return json(500, { error: "server_not_configured" });

  let body: any;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const email = String(body?.email ?? "").trim().toLowerCase();
  const password = String(body?.password ?? "");
  if (!email || !password || password.length > 256) {
    return json(400, { error: "invalid_credentials" });
  }

  const admin = createClient(url, serviceRole, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const attemptKey = await sha256Hex(email);
  const now = new Date();
  const { data: attempt } = await admin
    .from("analytics_admin_login_attempts")
    .select("window_started_at,failures")
    .eq("attempt_key", attemptKey)
    .maybeSingle();

  if (attempt) {
    const started = new Date(attempt.window_started_at);
    if (now.getTime() - started.getTime() < WINDOW_MS && Number(attempt.failures) >= MAX_FAILURES) {
      return json(429, { error: "too_many_attempts" });
    }
  }

  let valid = false;
  if (email === ADMIN_EMAIL) {
    const { data: credential, error: credentialError } = await admin
      .from("analytics_admin_credentials")
      .select("password_salt,password_hash,password_iterations")
      .eq("user_id", ADMIN_USER_ID)
      .maybeSingle();

    if (!credentialError && credential) {
      const derived = await derivePassword(
        password,
        credential.password_salt,
        Number(credential.password_iterations),
      );
      valid = constantTimeEqual(derived, credential.password_hash);
    }
  }

  if (!valid) {
    const windowExpired = !attempt
      || now.getTime() - new Date(attempt.window_started_at).getTime() >= WINDOW_MS;

    await admin.from("analytics_admin_login_attempts").upsert({
      attempt_key: attemptKey,
      window_started_at: windowExpired ? now.toISOString() : attempt.window_started_at,
      failures: windowExpired ? 1 : Number(attempt.failures) + 1,
      updated_at: now.toISOString(),
    }, { onConflict: "attempt_key" });

    await new Promise((resolve) => setTimeout(resolve, 350));
    return json(401, { error: "invalid_credentials" });
  }

  await admin.from("analytics_admin_login_attempts").delete().eq("attempt_key", attemptKey);
  await admin.from("analytics_admin_sessions").delete().lte("expires_at", now.toISOString());

  const token = randomToken();
  const tokenHash = await sha256Hex(token);
  const expiresAt = new Date(now.getTime() + SESSION_TTL_MS);

  const { error: insertError } = await admin.from("analytics_admin_sessions").insert({
    token_hash: tokenHash,
    user_id: ADMIN_USER_ID,
    created_at: now.toISOString(),
    expires_at: expiresAt.toISOString(),
    last_used_at: now.toISOString(),
  });

  if (insertError) return json(500, { error: "session_create_failed" });

  return json(200, {
    token,
    expires_at: expiresAt.toISOString(),
    admin: { email: ADMIN_EMAIL },
  });
});
