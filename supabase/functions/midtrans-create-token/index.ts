// supabase/functions/midtrans-create-token/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// Edge Function: Buat Midtrans Snap Token
// Dipanggil Flutter saat user akan bayar → return snap_token ke Flutter
// Flutter pakai token itu untuk buka halaman pembayaran Midtrans
//
// PERUBAHAN PENTING (fix "order_id has already been taken"):
//   Midtrans MEWAJIBKAN order_id unik selamanya per akun, tidak boleh
//   dipakai dua kali walau transaksi sebelumnya gagal/pending/expired.
//   Karena itu, Flutter sekarang mengirim DUA id berbeda:
//     - `order_id`          → id UNIK per percobaan bayar, dikirim ke
//                             Midtrans sebagai transaction_details.order_id
//     - `internal_order_id` → UUID asli row di tabel `orders`, dipakai
//                             untuk lookup & update ke database
//
//   `order_id` (yang unik) juga disimpan ke kolom `midtrans_order_id` di
//   tabel `orders`, supaya webhook/notification handler nanti bisa
//   mencocokkan balik ke row yang benar saat Midtrans mengirim notifikasi
//   pembayaran (notifikasi itu hanya berisi `order_id` versi unik, BUKAN
//   internal_order_id).
//
//   WAJIB: tambahkan kolom baru di tabel `orders` kalau belum ada:
//     ALTER TABLE orders ADD COLUMN IF NOT EXISTS midtrans_order_id text;
//     CREATE INDEX IF NOT EXISTS idx_orders_midtrans_order_id
//       ON orders (midtrans_order_id);
//
//   Dan webhook handler kamu (function lain yang terima notifikasi dari
//   Midtrans) juga WAJIB diupdate untuk lookup pakai:
//     .eq("midtrans_order_id", notification.order_id)
//   BUKAN lagi:
//     .eq("id", notification.order_id)
// ─────────────────────────────────────────────────────────────────────────────

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Origin diizinkan lewat env var ALLOWED_ORIGINS (comma-separated) — sebelumnya
// "*" mengizinkan situs manapun memicu pembuatan Snap token dari browser.
function resolveAllowedOrigin(req: Request): string {
  const allowed = (Deno.env.get("ALLOWED_ORIGINS") ?? "")
    .split(",").map((s) => s.trim()).filter(Boolean);
  const origin = req.headers.get("origin") ?? "";
  return allowed.includes(origin) ? origin : "";
}

serve(async (req: Request) => {
  const corsHeaders = {
    "Access-Control-Allow-Origin": resolveAllowedOrigin(req),
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
  };

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // ── 1. Ambil secrets dari environment ──────────────────────────────────
    const MIDTRANS_SERVER_KEY = Deno.env.get("MIDTRANS_SERVER_KEY");
    const MIDTRANS_IS_PRODUCTION = Deno.env.get("MIDTRANS_IS_PRODUCTION") === "true";
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    if (!MIDTRANS_SERVER_KEY) {
      return new Response(
        JSON.stringify({ error: "MIDTRANS_SERVER_KEY not configured" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── 2. Verifikasi JWT user (pastikan request dari app sendiri) ──────────
    const authHeader = req.headers.get("authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing authorization header" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // ── 3. Parse request body ───────────────────────────────────────────────
    const body = await req.json();
    const {
      order_id,          // string: id UNIK per percobaan bayar (dikirim ke Midtrans)
      internal_order_id, // string: UUID asli row di tabel `orders`
      gross_amount,      // number: total dalam Rupiah (integer, tanpa desimal)
      customer_name,     // string: nama pelanggan
      customer_email,    // string: email (opsional, Midtrans tetap bisa jalan)
      customer_phone,    // string: nomor HP (opsional)
      items,             // array: [{id, name, price, quantity}]
      enabled_payments,  // array opsional: filter metode bayar
    } = body;

    // Fallback untuk kompatibilitas kalau ada caller lama yang belum kirim
    // internal_order_id (mis. versi app lama) — anggap order_id == internal id.
    const internalOrderId = internal_order_id || order_id;

    // Validasi input minimal
    if (!order_id || !internalOrderId || !gross_amount) {
      return new Response(
        JSON.stringify({
          error: "order_id, internal_order_id, and gross_amount are required",
        }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Pastikan gross_amount integer (Midtrans tidak terima desimal)
    const amount = Math.round(Number(gross_amount));
    if (amount <= 0) {
      return new Response(
        JSON.stringify({ error: "gross_amount must be > 0" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── 4. Cek order ada di DB dan statusnya valid ──────────────────────────
    // PENTING: lookup pakai internalOrderId (UUID asli), BUKAN order_id
    // (yang sekarang sudah unik per percobaan dan tidak match kolom `id`).
    const { data: order, error: orderError } = await supabase
      .from("orders")
      .select("id, status, payment_status, total_amount, branch_id")
      .eq("id", internalOrderId)
      .single();

    if (orderError || !order) {
      return new Response(
        JSON.stringify({ error: "Order not found" }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (order.payment_status === "paid") {
      return new Response(
        JSON.stringify({ error: "Order already paid" }),
        { status: 409, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── 4b. Validasi gross_amount vs total_amount asli di DB ────────────────
    // SEBELUM fix ini, `amount` (dari body request, dikirim client) dipakai
    // langsung sebagai gross_amount ke Midtrans tanpa pernah dicocokkan ke
    // `order.total_amount` yang sudah di-fetch di atas — client bisa minta
    // Snap token untuk nominal berapa pun terlepas dari harga order
    // sebenarnya. Toleransi Rp1 untuk pembulatan.
    const expectedAmount = Math.round(Number(order.total_amount));
    if (Math.abs(expectedAmount - amount) > 1) {
      console.error(
        `gross_amount mismatch: order=${internalOrderId} expected=${expectedAmount} received=${amount}`
      );
      return new Response(
        JSON.stringify({ error: "gross_amount does not match order total" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── 5. Build Snap request payload ──────────────────────────────────────
    //
    // Midtrans Snap endpoint:
    //   Sandbox:    https://app.sandbox.midtrans.com/snap/v1/transactions
    //   Production: https://app.midtrans.com/snap/v1/transactions
    //
    const snapBaseUrl = MIDTRANS_IS_PRODUCTION
      ? "https://app.midtrans.com/snap/v1/transactions"
      : "https://app.sandbox.midtrans.com/snap/v1/transactions";

    // Encode server key ke Base64 untuk Basic Auth
    // Format: Base64("SERVER_KEY:")  ← ada titik dua setelah server key
    const encodedKey = btoa(`${MIDTRANS_SERVER_KEY}:`);
    const snapPayload: Record<string, unknown> = {
      transaction_details: {
        // order_id yang dikirim ke MIDTRANS harus yang versi UNIK ini,
        // bukan internalOrderId — supaya tidak collision saat retry bayar.
        order_id: order_id,
        gross_amount: amount,
      },
      customer_details: {
        first_name: customer_name || "Pelanggan",
        email: customer_email || `order-${internalOrderId}@rms.local`,
        phone: customer_phone || "",
      },
    };

    // Tampilkan nama toko di halaman Snap — HANYA dikirim kalau memang di-set.
    // Midtrans sudah otomatis tahu merchant dari Server Key di Basic Auth,
    // jadi field ini opsional. Mengirim string kosong "" berisiko ditolak
    // sebagai merchant_id yang tidak valid oleh Midtrans.
    const MIDTRANS_MERCHANT_ID = Deno.env.get("MIDTRANS_MERCHANT_ID");
    if (MIDTRANS_MERCHANT_ID) {
      snapPayload.merchant_id = MIDTRANS_MERCHANT_ID;
    }

    // Tambah item detail jika ada
    if (items && Array.isArray(items) && items.length > 0) {
      snapPayload.item_details = items.map((item: Record<string, unknown>) => ({
        id: item.id || "ITEM",
        name: String(item.name || "Menu").substring(0, 50), // max 50 char
        price: Math.round(Number(item.price)),
        quantity: Number(item.quantity) || 1,
      }));
    }

    // ── 6. Request Snap token ke Midtrans ──────────────────────────────────
    const midtransRes = await fetch(snapBaseUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Basic ${encodedKey}`,
      },
      body: JSON.stringify(snapPayload),
    });

    const midtransData = await midtransRes.json();

    if (!midtransRes.ok) {
      console.error("Midtrans error:", JSON.stringify(midtransData));
      return new Response(
        JSON.stringify({
          error: "Failed to create Midtrans token",
          detail: midtransData,
        }),
        {
          status: midtransRes.status,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // ── 7. Simpan snap_token + order_id (unik) ke DB ───────────────────────
    // PENTING: simpan order_id (versi unik) ke kolom `midtrans_order_id`.
    // Ini dipakai webhook handler nanti untuk mencocokkan balik notifikasi
    // dari Midtrans ke row order yang benar — karena notifikasi Midtrans
    // hanya berisi order_id versi unik ini, bukan internalOrderId.
    const { error: updateError } = await supabase
      .from("orders")
      .update({
        midtrans_order_id: order_id,
        midtrans_snap_token: midtransData.token,
        midtrans_redirect_url: midtransData.redirect_url,
        payment_status: "pending",
        updated_at: new Date().toISOString(),
      })
      .eq("id", internalOrderId);

    // Jangan gagalkan response ke Flutter kalau update DB gagal — token Snap
    // tetap valid dan bisa dipakai user untuk bayar. Tapi catat di log supaya
    // ketahuan kalau ada masalah skema/RLS, karena kalau silent, retry/polling
    // status pembayaran bisa jadi tidak akurat nantinya.
    if (updateError) {
      console.error(
        `Failed to save snap_token for order ${internalOrderId}:`,
        JSON.stringify(updateError)
      );
    }

    // ── 8. Return token ke Flutter ─────────────────────────────────────────
    return new Response(
      JSON.stringify({
        snap_token: midtransData.token,
        redirect_url: midtransData.redirect_url,
        order_id: order_id,
        internal_order_id: internalOrderId,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (err) {
    console.error("Unexpected error:", err);
    return new Response(
      JSON.stringify({ error: "Internal server error", detail: String(err) }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});