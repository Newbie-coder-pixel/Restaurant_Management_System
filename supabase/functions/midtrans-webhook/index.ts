// supabase/functions/midtrans-webhook/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// Edge Function: Midtrans Payment Notification Webhook
//
// Midtrans POST ke URL ini setiap kali status transaksi berubah:
//   settlement → bayar berhasil
//   pending    → menunggu
//   deny/expire/cancel → gagal
//
// URL ini didaftarkan di:
//   Midtrans Dashboard → Settings → Configuration → Payment Notification URL
//   Isi: https://pppxzbddfoeajwngbwdo.supabase.co/functions/v1/midtrans-webhook
//
// PERUBAHAN PENTING (mengikuti fix "order_id has already been taken"):
//   `order_id` yang dikirim Midtrans di notifikasi ini SEKARANG adalah id
//   UNIK per percobaan bayar (format "<uuid-order>-<timestamp>"), BUKAN lagi
//   UUID asli row di tabel `orders`. Jadi:
//     - LOOKUP order harus pakai kolom `midtrans_order_id` (bukan `id`)
//     - Semua UPDATE/INSERT selanjutnya (orders, payments, order_items,
//       restaurant_tables) harus pakai `order.id` (UUID asli hasil lookup),
//       BUKAN `order_id` mentah dari notifikasi.
//   Signature verification TETAP pakai `order_id` mentah dari notifikasi
//   (jangan diubah) — karena itu memang nilai yang dipakai Midtrans saat
//   menghitung signature di sisi mereka.
// ─────────────────────────────────────────────────────────────────────────────

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ✅ TIDAK ada import crypto — verifySignature pakai Web Crypto API built-in Deno

// Midtrans memanggil endpoint ini server-to-server (bukan dari browser), jadi
// header CORS di sini sebenarnya tidak dipakai Midtrans — tapi tetap dibatasi
// (bukan "*") sebagai defense-in-depth agar tidak bisa dipicu fetch() dari
// sembarang origin browser.
const corsHeaders = {
  "Access-Control-Allow-Origin": "https://api.midtrans.com",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// ── Helper: verifikasi signature Midtrans ─────────────────────────────────────
// Formula resmi Midtrans: SHA512(order_id + status_code + gross_amount + server_key)
// BUKAN HMAC — plain SHA512 hash biasa.
// PENTING: order_id di sini WAJIB nilai mentah dari notifikasi (yang versi
// unik), karena itu yang dipakai Midtrans saat menghitung signature mereka.
async function verifySignature(
  orderId: string,
  statusCode: string,
  grossAmount: string,
  serverKey: string,
  receivedSignature: string
): Promise<boolean> {
  const rawString = `${orderId}${statusCode}${grossAmount}${serverKey}`;
  const encoder = new TextEncoder();
  const hashBuffer = await crypto.subtle.digest("SHA-512", encoder.encode(rawString));
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  const computed = hashArray.map((b) => b.toString(16).padStart(2, "0")).join("");
  return computed === receivedSignature;
}

// ── Helper: map Midtrans payment_type → metode kita ──────────────────────────
function mapPaymentMethod(paymentType: string, vaBank?: string): string {
  switch (paymentType) {
    case "credit_card":         return "credit_card";
    case "bank_transfer":
    case "bca_va":
    case "bni_va":
    case "bri_va":
    case "permata_va":
    case "mandiri_bill":
    case "other_va":
      return vaBank ? `${vaBank}_va` : "bank_transfer";
    case "gopay":               return "gopay";
    case "shopeepay":           return "shopeepay";
    case "qris":                return "qris";
    case "akulaku":             return "akulaku";
    case "kredivo":             return "kredivo";
    case "indomaret":
    case "alfamart":            return "retail_outlet";
    default:                    return paymentType;
  }
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Midtrans kirim POST, tolak method lain
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405, headers: corsHeaders });
  }

  try {
    const MIDTRANS_SERVER_KEY = Deno.env.get("MIDTRANS_SERVER_KEY")!;
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // ── 1. Parse notification body dari Midtrans ────────────────────────────
    const notification = await req.json();
    console.log("Midtrans webhook received:", JSON.stringify(notification));

    const {
      order_id, // PENTING: ini id UNIK per percobaan ("<uuid>-<timestamp>"),
                // BUKAN UUID asli orders.id. Dipakai untuk: (a) verifikasi
                // signature, (b) lookup ke kolom `midtrans_order_id`.
      transaction_id,
      transaction_status,
      fraud_status,
      payment_type,
      gross_amount,
      status_code,
      signature_key,
      va_numbers,        // untuk bank transfer VA
      acquirer,          // untuk QRIS
      settlement_time,
    } = notification;

    if (!order_id || !transaction_status) {
      return new Response(
        JSON.stringify({ error: "Missing required fields" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── 2. Verifikasi signature (keamanan — pastikan dari Midtrans beneran) ──
    // Tetap pakai `order_id` MENTAH dari notifikasi (bukan order.id internal),
    // karena itu yang dipakai Midtrans saat menghitung signature di sisi mereka.
    // WAJIB ada & valid — tanpa signature_key, request DITOLAK (sebelumnya
    // request tanpa signature_key lolos begitu saja, membuka celah pemalsuan
    // notifikasi "settlement" langsung ke webhook ini).
    if (!signature_key || !MIDTRANS_SERVER_KEY) {
      console.error("Missing signature_key or server key for order:", order_id);
      return new Response(
        JSON.stringify({ error: "Missing signature" }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
    const isValid = await verifySignature(
      order_id,
      status_code || "200",
      gross_amount,
      MIDTRANS_SERVER_KEY,
      signature_key
    );
    if (!isValid) {
      console.error("Invalid signature for order:", order_id);
      return new Response(
        JSON.stringify({ error: "Invalid signature" }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── 3. Tentukan status final ────────────────────────────────────────────
    //
    // Midtrans transaction_status:
    //   capture   → kartu kredit, fraud_status harus "accept"
    //   settlement→ semua metode lain yang sudah settled (LUNAS)
    //   pending   → belum bayar, masih tunggu
    //   deny      → kartu ditolak / fraud
    //   expire    → waktu bayar habis
    //   cancel    → dibatalkan
    //   refund    → dikembalikan
    //
    let isPaid = false;
    let orderStatus: string | undefined; // undefined = jangan ubah status order
    let paymentStatus = "pending";

    if (transaction_status === "capture" && fraud_status === "accept") {
      isPaid = true;
      orderStatus = "paid";
      paymentStatus = "paid";
    } else if (transaction_status === "settlement") {
      isPaid = true;
      orderStatus = "paid";
      paymentStatus = "paid";
    } else if (
      transaction_status === "deny" ||
      transaction_status === "expire" ||
      transaction_status === "cancel"
    ) {
      orderStatus = "served"; // kembalikan ke served supaya kasir bisa coba lagi
      paymentStatus = "failed";
    } else if (transaction_status === "refund") {
      orderStatus = "cancelled";
      paymentStatus = "refunded";
    }
    // "pending" → orderStatus tetap undefined, jangan ubah status order

    // ── 4. Inisialisasi Supabase client ────────────────────────────────────
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // ── 5. Ambil data order dari DB ────────────────────────────────────────
    // PENTING: lookup pakai kolom `midtrans_order_id` (id unik per percobaan
    // yang disimpan saat createSnapToken), BUKAN `id` — karena `order_id`
    // dari notifikasi ini bukan UUID asli orders.id lagi.
    const { data: order, error: orderError } = await supabase
      .from("orders")
      .select("id, status, table_id, branch_id, subtotal, tax_amount, discount_amount, total_amount")
      .eq("midtrans_order_id", order_id)
      .single();

    if (orderError || !order) {
      console.error("Order not found for midtrans_order_id:", order_id, orderError);
      // Return 200 tetap (agar Midtrans tidak retry terus)
      return new Response(
        JSON.stringify({ message: "Order not found, acknowledged" }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Mulai dari sini, SELALU pakai `order.id` (UUID asli) untuk
    // update/insert ke tabel lain — bukan `order_id` dari notifikasi.
    const internalOrderId = order.id;

    // ── 5b. Validasi gross_amount vs total order asli di DB ─────────────────
    // Signature yang valid cuma membuktikan notifikasi datang dari Midtrans,
    // BUKAN bahwa nominalnya benar. Tanpa ini, order bisa "dilunasi" dengan
    // gross_amount berapa pun (mis. dimanipulasi sebelum sampai Midtrans, atau
    // salah order_id) tanpa pernah dicocokkan ke total_amount order tsb.
    if (isPaid) {
      const expected = Number(order.total_amount);
      const received = Number(gross_amount);
      if (
        !Number.isFinite(expected) ||
        !Number.isFinite(received) ||
        Math.abs(expected - received) > 1 // toleransi pembulatan Rp1
      ) {
        console.error(
          `Amount mismatch for order ${internalOrderId}: expected=${expected} received=${received}`
        );
        return new Response(
          JSON.stringify({ error: "Amount mismatch" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    // Skip jika sudah paid (Midtrans kadang kirim duplicate notification)
    if (order.status === "paid" && isPaid) {
      console.log("Order already paid, skipping:", internalOrderId);
      return new Response(
        JSON.stringify({ message: "Already processed" }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── 6. Update order di DB ──────────────────────────────────────────────
    const vaBank = va_numbers && va_numbers.length > 0 ? va_numbers[0].bank : undefined;
    const mappedMethod = mapPaymentMethod(payment_type, vaBank);

    const orderUpdate: Record<string, unknown> = {
      payment_status: paymentStatus,
      midtrans_transaction_id: transaction_id,
      payment_method: mappedMethod,
      updated_at: new Date().toISOString(),
    };

    // Status order ikut field `orderStatus` yang sudah ditentukan di step 3
    // (paid / served / cancelled). Kalau masih "pending", orderStatus
    // undefined → kolom `status` tidak ikut diupdate.
    if (orderStatus) {
      orderUpdate.status = orderStatus;
    }

    await supabase.from("orders").update(orderUpdate).eq("id", internalOrderId);

    // ── 7. Insert payment record (hanya kalau paid) ────────────────────────
    if (isPaid) {
      const { data: existingPayment } = await supabase
        .from("payments")
        .select("id")
        .eq("order_id", internalOrderId)
        .eq("status", "paid")
        .maybeSingle();

      if (!existingPayment) {
        await supabase.from("payments").insert({
          order_id: internalOrderId,
          branch_id: order.branch_id,
          method: mappedMethod,
          amount: parseFloat(gross_amount),
          status: "paid",
          reference_number: transaction_id,
          midtrans_transaction_id: transaction_id,
          midtrans_payment_type: payment_type,
          subtotal: order.subtotal || 0,
          tax_amount: order.tax_amount || 0,
          discount_amount: order.discount_amount || 0,
          acquirer: acquirer || null,
          va_bank: vaBank || null,
          settled_at: settlement_time || new Date().toISOString(),
        });

        // Sync order_items → served
        await supabase
          .from("order_items")
          .update({ status: "served" })
          .eq("order_id", internalOrderId);

        // Bebaskan meja → cleaning
        if (order.table_id) {
          await supabase
            .from("restaurant_tables")
            .update({ status: "cleaning" })
            .eq("id", order.table_id);
        }
      }
    }

    // ── 8. Return 200 ke Midtrans ──────────────────────────────────────────
    // Midtrans akan retry jika tidak dapat response 200
    console.log(
      `Webhook processed: order=${internalOrderId} midtrans_order_id=${order_id} status=${paymentStatus}`
    );
    return new Response(
      JSON.stringify({
        message: "Webhook processed",
        order_id: internalOrderId,
        payment_status: paymentStatus,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (err) {
    console.error("Webhook error:", err);
    // Tetap return 200 agar Midtrans tidak spam retry
    return new Response(
      JSON.stringify({ message: "Error processed", error: String(err) }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});