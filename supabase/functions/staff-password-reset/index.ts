// supabase/functions/staff-password-reset/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// Edge Function: Reset Password Staff via kode OTP WhatsApp (Fonnte)
//
// Dipanggil TANPA auth header (staff belum bisa login) — deploy dengan
// --no-verify-jwt. Keamanan diverifikasi lewat kode OTP, bukan JWT Supabase.
//
// step="request": cari staff by email, kirim kode 6-digit ke WhatsApp
//   (staff.phone) via Fonnte, simpan HASH kode-nya (bukan plaintext) di
//   staff_password_reset_otps dengan masa berlaku 5 menit.
// step="verify": cocokkan kode + email, kalau valid langsung update
//   password staff itu lewat Supabase Admin API (service role).
//
// Respons untuk step="request" SELALU generic message yang sama, baik
// email/staff ketemu atau tidak — supaya tidak bisa dipakai untuk
// menebak email staff mana yang valid (enumeration).
// ─────────────────────────────────────────────────────────────────────────────

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Origin diizinkan lewat env var ALLOWED_ORIGINS (comma-separated) di Supabase
// Edge Function secrets — sebelumnya "*" mengizinkan situs manapun memicu
// permintaan OTP (dan ikut kena rate limit staff itu sendiri) dari browser.
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
// Batas permintaan kode OTP per staff dalam 1 jam — sebelumnya tidak ada
// rate limit sama sekali di step "request", jadi bisa dipakai untuk (a) banjir
// WhatsApp korban dengan kode reset berulang, dan (b) terus-menerus
// meng-invalidate kode aktif sehingga user asli tidak pernah sempat pakai
// kodenya sendiri (DoS terhadap reset password akun sendiri).
const RATE_LIMIT_WINDOW_MINUTES = 60;
const RATE_LIMIT_MAX_REQUESTS = 3;
const GENERIC_REQUEST_MSG =
  "Kalau email terdaftar dan punya nomor WhatsApp, kode reset sudah dikirim.";
const GENERIC_VERIFY_ERROR = "Kode salah atau sudah kedaluwarsa.";

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

  // ── STEP 1: minta kode OTP ────────────────────────────────────────────────
  if (step === "request") {
    const email = String(body.email ?? "").trim().toLowerCase();
    if (!email) return json({ error: "Email wajib diisi" }, 400);

    const { data: staff } = await supabase
      .from("staff")
      .select("id, phone, full_name, is_active")
      .ilike("email", email)
      .maybeSingle();

    if (!staff || !staff.is_active || !staff.phone) {
      // Generic response — tidak bocorkan apakah email terdaftar/punya HP.
      return json({ message: GENERIC_REQUEST_MSG });
    }

    // Rate limit per staff — kalau sudah kena limit, diam-diam tolak (tetap
    // generic message, jangan bocorkan alasan) dan JANGAN invalidate kode
    // aktif yang mungkin sedang dipakai user asli.
    const since = new Date(Date.now() - RATE_LIMIT_WINDOW_MINUTES * 60_000).toISOString();
    const { count: recentCount } = await supabase
      .from("staff_password_reset_otps")
      .select("id", { count: "exact", head: true })
      .eq("staff_id", staff.id)
      .gte("created_at", since);

    if ((recentCount ?? 0) >= RATE_LIMIT_MAX_REQUESTS) {
      return json({ message: GENERIC_REQUEST_MSG });
    }

    // Invalidate kode lama yang belum kepakai, supaya cuma 1 kode aktif.
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
      `🔐 *Kode Reset Password*\n\n` +
      `Halo ${staff.full_name}, kode reset password kamu:\n\n` +
      `*${otp}*\n\n` +
      `Berlaku ${OTP_TTL_MINUTES} menit. Jangan bagikan kode ini ke siapa pun.`;

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

  // ── STEP 2: verifikasi kode + set password baru ───────────────────────────
  if (step === "verify") {
    const email = String(body.email ?? "").trim().toLowerCase();
    const otp = String(body.otp ?? "").trim();
    const newPassword = String(body.new_password ?? "");

    if (!email || !otp || !newPassword) {
      return json({ error: "Email, kode OTP, dan password baru wajib diisi" }, 400);
    }
    if (newPassword.length < 6) {
      return json({ error: "Password minimal 6 karakter" }, 400);
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

    // Kode benar → invalidate supaya tidak bisa dipakai ulang (replay).
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
      return json({ error: "Gagal update password. Coba lagi." }, 500);
    }

    return json({ message: "Password berhasil diubah" });
  }

  return json({ error: "step tidak dikenal" }, 400);
});
