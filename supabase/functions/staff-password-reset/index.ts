// supabase/functions/staff-password-reset/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// Edge Function: Staff password reset via WhatsApp OTP code (Fonnte)
//
// Called WITHOUT an auth header (staff can't log in yet) — deployed with
// --no-verify-jwt. Security is verified via the OTP code, not a Supabase JWT.
//
// step="request": look up staff by email, send a 6-digit code to WhatsApp
//   (staff.phone) via Fonnte, store a HASH of the code (not plaintext) in
//   staff_password_reset_otps with a 5-minute validity window.
// step="verify": match the code + email; if valid, update that staff
//   member's password directly via the Supabase Admin API (service role).
//
// The response for step="request" is ALWAYS the same generic message,
// whether the email/staff is found or not — so it can't be used to
// guess which staff emails are valid (enumeration).
// ─────────────────────────────────────────────────────────────────────────────

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Origin allowed via the ALLOWED_ORIGINS env var (comma-separated) in Supabase
// Edge Function secrets — previously "*" allowed any site to trigger an OTP
// request (and consume that staff member's own rate limit) from a browser.
function resolveAllowedOrigin(req: Request): string {
  const allowed = (Deno.env.get("ALLOWED_ORIGINS") ?? "")
    .split(",").map((s) => s.trim()).filter(Boolean);
  const origin = req.headers.get("origin") ?? "";
  return allowed.includes(origin) ? origin : "";
}

function buildCorsHeaders(req: Request) {
  return {
    "Access-Control-Allow-Origin": resolveAllowedOrigin(req),
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
  };
}

const OTP_TTL_MINUTES = 5;
const MAX_ATTEMPTS = 5;
// Limit on OTP requests per staff member within 1 hour — previously there was
// no rate limit at all on the "request" step, so it could be used to (a) flood
// a victim's WhatsApp with repeated reset codes, and (b) continuously
// invalidate the active code so the real user never gets a chance to use
// their own code (DoS against resetting one's own account password).
const RATE_LIMIT_WINDOW_MINUTES = 60;
const RATE_LIMIT_MAX_REQUESTS = 3;
const GENERIC_REQUEST_MSG =
  "If the email is registered and has a WhatsApp number on file, a reset code has been sent.";
const GENERIC_VERIFY_ERROR = "Incorrect or expired code.";

async function sha256Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hashBuffer))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function generateOtp(): string {
  const arr = new Uint32Array(1);
  crypto.getRandomValues(arr);
  return String(100000 + (arr[0] % 900000));
}

Deno.serve(async (req) => {
  const corsHeaders = buildCorsHeaders(req);
  const json = (body: Record<string, unknown>, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
  const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const FONNTE_TOKEN = Deno.env.get("FONNTE_TOKEN")!;
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const step = body.step as string | undefined;

  // ── STEP 1: request OTP code ────────────────────────────────────────────────
  if (step === "request") {
    const email = String(body.email ?? "").trim().toLowerCase();
    if (!email) return json({ error: "Email is required" }, 400);

    const { data: staff } = await supabase
      .from("staff")
      .select("id, phone, full_name, is_active")
      .ilike("email", email)
      .maybeSingle();

    if (!staff || !staff.is_active || !staff.phone) {
      // Generic response — don't leak whether the email is registered/has a phone.
      return json({ message: GENERIC_REQUEST_MSG });
    }

    // Rate limit per staff member — if already over the limit, silently reject
    // (still the generic message, don't leak the reason) and do NOT invalidate
    // the active code that the real user might currently be using.
    const since = new Date(Date.now() - RATE_LIMIT_WINDOW_MINUTES * 60_000).toISOString();
    const { count: recentCount } = await supabase
      .from("staff_password_reset_otps")
      .select("id", { count: "exact", head: true })
      .eq("staff_id", staff.id)
      .gte("created_at", since);

    if ((recentCount ?? 0) >= RATE_LIMIT_MAX_REQUESTS) {
      return json({ message: GENERIC_REQUEST_MSG });
    }

    // Invalidate any old unused code, so only 1 code is active at a time.
    await supabase
      .from("staff_password_reset_otps")
      .update({ consumed: true })
      .eq("staff_id", staff.id)
      .eq("consumed", false);

    const otp = generateOtp();
    const otpHash = await sha256Hex(otp);
    const expiresAt = new Date(Date.now() + OTP_TTL_MINUTES * 60_000).toISOString();

    await supabase.from("staff_password_reset_otps").insert({
      staff_id: staff.id,
      otp_hash: otpHash,
      expires_at: expiresAt,
    });

    const message =
      `🔐 *Password Reset Code*\n\n` +
      `Hello ${staff.full_name}, your password reset code:\n\n` +
      `*${otp}*\n\n` +
      `Valid for ${OTP_TTL_MINUTES} minutes. Do not share this code with anyone.`;

    try {
      await fetch("https://api.fonnte.com/send", {
        method: "POST",
        headers: {
          "Authorization": FONNTE_TOKEN,
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: new URLSearchParams({
          target: staff.phone,
          message,
          countryCode: "62",
        }),
      });
    } catch (e) {
      console.error("Fonnte send error:", e);
    }

    return json({ message: GENERIC_REQUEST_MSG });
  }

  // ── STEP 2: verify code + set new password ───────────────────────────
  if (step === "verify") {
    const email = String(body.email ?? "").trim().toLowerCase();
    const otp = String(body.otp ?? "").trim();
    const newPassword = String(body.new_password ?? "");

    if (!email || !otp || !newPassword) {
      return json({ error: "Email, OTP code, and new password are required" }, 400);
    }
    if (newPassword.length < 6) {
      return json({ error: "Password must be at least 6 characters" }, 400);
    }

    const { data: staff } = await supabase
      .from("staff")
      .select("id, user_id, is_active")
      .ilike("email", email)
      .maybeSingle();

    if (!staff || !staff.is_active || !staff.user_id) {
      return json({ error: GENERIC_VERIFY_ERROR }, 400);
    }

    const { data: otpRow } = await supabase
      .from("staff_password_reset_otps")
      .select("id, otp_hash, expires_at, attempts, consumed")
      .eq("staff_id", staff.id)
      .eq("consumed", false)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (
      !otpRow ||
      new Date(otpRow.expires_at) < new Date() ||
      otpRow.attempts >= MAX_ATTEMPTS
    ) {
      return json({ error: GENERIC_VERIFY_ERROR }, 400);
    }

    const inputHash = await sha256Hex(otp);
    if (inputHash !== otpRow.otp_hash) {
      await supabase
        .from("staff_password_reset_otps")
        .update({ attempts: otpRow.attempts + 1 })
        .eq("id", otpRow.id);
      return json({ error: GENERIC_VERIFY_ERROR }, 400);
    }

    // Code is correct → invalidate it so it can't be reused (replay).
    await supabase
      .from("staff_password_reset_otps")
      .update({ consumed: true })
      .eq("id", otpRow.id);

    const { error: updateError } = await supabase.auth.admin.updateUserById(
      staff.user_id,
      { password: newPassword },
    );
    if (updateError) {
      console.error("updateUserById error:", updateError);
      return json({ error: "Failed to update password. Please try again." }, 500);
    }

    return json({ message: "Password changed successfully" });
  }

  return json({ error: "Unknown step" }, 400);
});
