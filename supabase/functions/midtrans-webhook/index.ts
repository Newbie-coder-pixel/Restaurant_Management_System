// supabase/functions/midtrans-webhook/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// Edge Function: Midtrans Payment Notification Webhook
//
// Midtrans POSTs to this URL every time a transaction status changes:
//   settlement → payment succeeded
//   pending    → awaiting payment
//   deny/expire/cancel → failed
//
// This URL is registered at:
//   Midtrans Dashboard → Settings → Configuration → Payment Notification URL
//   Value: https://pppxzbddfoeajwngbwdo.supabase.co/functions/v1/midtrans-webhook
//
// IMPORTANT CHANGE (following the "order_id has already been taken" fix):
//   The `order_id` that Midtrans sends in this notification is NOW a
//   UNIQUE id per payment attempt (format "<uuid-order>-<timestamp>"), no
//   longer the actual UUID row in the `orders` table. So:
//     - Order LOOKUP must use the `midtrans_order_id` column (not `id`)
//     - All subsequent UPDATEs/INSERTs (orders, payments, order_items,
//       restaurant_tables) must use `order.id` (the real UUID from the
//       lookup), NOT the raw `order_id` from the notification.
//   Signature verification STILL uses the raw `order_id` from the
//   notification (do not change this) — because that is the value Midtrans
//   actually uses when computing the signature on their end.
// ─────────────────────────────────────────────────────────────────────────────

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ✅ NO crypto import — verifySignature uses Deno's built-in Web Crypto API

// Midtrans calls this endpoint server-to-server (not from a browser), so the
// CORS headers here are not actually used by Midtrans — but they're still
// restricted (not "*") as defense-in-depth, so it can't be triggered via
// fetch() from an arbitrary browser origin.
const corsHeaders = {
  "Access-Control-Allow-Origin": "https://api.midtrans.com",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// ── Helper: verify the Midtrans signature ─────────────────────────────────────
// Midtrans' official formula: SHA512(order_id + status_code + gross_amount + server_key)
// NOT HMAC — a plain, regular SHA512 hash.
// IMPORTANT: order_id here MUST be the raw value from the notification (the
// unique version), because that is what Midtrans uses when computing their signature.
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

// ── Helper: map Midtrans payment_type → our method ──────────────────────────
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

  // Midtrans sends POST, reject other methods
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405, headers: corsHeaders });
  }

  try {
    const MIDTRANS_SERVER_KEY = Deno.env.get("MIDTRANS_SERVER_KEY")!;
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // ── 1. Parse the notification body from Midtrans ────────────────────────────
    const notification = await req.json();
    console.log("Midtrans webhook received:", JSON.stringify(notification));

    const {
      order_id, // IMPORTANT: this is a UNIQUE id per attempt ("<uuid>-<timestamp>"),
                // NOT the real orders.id UUID. Used for: (a) signature
                // verification, (b) lookup against the `midtrans_order_id` column.
      transaction_id,
      transaction_status,
      fraud_status,
      payment_type,
      gross_amount,
      status_code,
      signature_key,
      va_numbers,        // for bank transfer VA
      acquirer,          // for QRIS
      settlement_time,
    } = notification;

    if (!order_id || !transaction_status) {
      return new Response(
        JSON.stringify({ error: "Missing required fields" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── 2. Verify the signature (security — confirm it's really from Midtrans) ──
    // Still uses the RAW `order_id` from the notification (not the internal
    // order.id), because that's what Midtrans uses when computing their signature.
    // MUST be present & valid — without signature_key, the request is REJECTED
    // (previously a request without signature_key was let through as-is,
    // opening a hole for forged "settlement" notifications sent directly
    // to this webhook).
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

    // ── 3. Determine the final status ────────────────────────────────────────────
    //
    // Midtrans transaction_status:
    //   capture   → credit card, fraud_status must be "accept"
    //   settlement→ all other methods that have settled (PAID IN FULL)
    //   pending   → not yet paid, still waiting
    //   deny      → card declined / fraud
    //   expire    → payment window expired
    //   cancel    → cancelled
    //   refund    → refunded
    //
    let isPaid = false;
    let orderStatus: string | undefined; // undefined = don't change the order status
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
      orderStatus = "served"; // revert to served so the cashier can retry
      paymentStatus = "failed";
    } else if (transaction_status === "refund") {
      orderStatus = "cancelled";
      paymentStatus = "refunded";
    }
    // "pending" → orderStatus stays undefined, don't change the order status

    // ── 4. Initialize the Supabase client ────────────────────────────────────
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // ── 5. Fetch order data from the DB ────────────────────────────────────
    // IMPORTANT: lookup uses the `midtrans_order_id` column (the unique id
    // per attempt saved during createSnapToken), NOT `id` — because the
    // `order_id` from this notification is no longer the real orders.id UUID.
    const { data: order, error: orderError } = await supabase
      .from("orders")
      .select("id, status, table_id, branch_id, subtotal, tax_amount, discount_amount, total_amount, served_at")
      .eq("midtrans_order_id", order_id)
      .single();

    if (orderError || !order) {
      console.error("Order not found for midtrans_order_id:", order_id, orderError);
      // Still return 200 (so Midtrans doesn't keep retrying)
      return new Response(
        JSON.stringify({ message: "Order not found, acknowledged" }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // From this point on, ALWAYS use `order.id` (the real UUID) for
    // updates/inserts to other tables — not the `order_id` from the notification.
    const internalOrderId = order.id;

    // ── 5b. Validate gross_amount against the order's real total in the DB ─────────────────
    // A valid signature only proves the notification came from Midtrans,
    // NOT that the amount is correct. Without this check, an order could be
    // "marked paid" with any gross_amount (e.g. tampered with before reaching
    // Midtrans, or a mismatched order_id) without ever being checked against
    // that order's total_amount.
    if (isPaid) {
      // orders.total_amount NEVER includes the dine-in overtime charge (Rp5000
      // per hour or fraction thereof, after 2 hours from served_at) — it's a
      // purely client-side, live-computed value (see calculateOvertimeCharge()
      // in lib/shared/models/order_model.dart) that's never persisted back to
      // the DB. Without adding it here too, ANY order that went into overtime
      // (and was correctly charged that amount by midtrans-create-token) would
      // permanently fail this check with "Amount mismatch", and since Midtrans
      // retries a failing webhook with the exact same gross_amount, it would
      // never succeed — the order would stay unpaid forever even though the
      // customer paid in full. Mirrors midtrans-create-token/index.ts exactly
      // — keep both in sync.
      const kMaxDineInMinutes = 120; // kMaxDineInDuration = 2 hours
      const kOvertimeChargePerHour = 5000;
      const servedAt = order.served_at as string | null;
      let overtimeCharge = 0;
      if (servedAt) {
        const elapsedMinutes = (Date.now() - new Date(servedAt).getTime()) / 60000;
        const overMinutes = elapsedMinutes - kMaxDineInMinutes;
        if (overMinutes > 0) {
          overtimeCharge = Math.ceil(overMinutes / 60) * kOvertimeChargePerHour;
        }
      }
      const tolerance = overtimeCharge > 0 ? kOvertimeChargePerHour : 1;
      const expected = Number(order.total_amount) + overtimeCharge;
      const received = Number(gross_amount);
      if (
        !Number.isFinite(expected) ||
        !Number.isFinite(received) ||
        Math.abs(expected - received) > tolerance
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

    // Skip if already paid (Midtrans sometimes sends duplicate notifications)
    if (order.status === "paid" && isPaid) {
      console.log("Order already paid, skipping:", internalOrderId);
      return new Response(
        JSON.stringify({ message: "Already processed" }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── 6. Update the order in the DB ──────────────────────────────────────────────
    const vaBank = va_numbers && va_numbers.length > 0 ? va_numbers[0].bank : undefined;
    const mappedMethod = mapPaymentMethod(payment_type, vaBank);

    const orderUpdate: Record<string, unknown> = {
      payment_status: paymentStatus,
      midtrans_transaction_id: transaction_id,
      payment_method: mappedMethod,
      updated_at: new Date().toISOString(),
    };

    // Order status follows the `orderStatus` field determined in step 3
    // (paid / served / cancelled). If still "pending", orderStatus is
    // undefined → the `status` column is not updated.
    if (orderStatus) {
      orderUpdate.status = orderStatus;
    }

    await supabase.from("orders").update(orderUpdate).eq("id", internalOrderId);

    // ── 6b. Refund: mark the original payment as refunded ──────────────────────
    // Previously, a "refund" notification only changed orders.status/payment_status
    // — the row in the `payments` table already recorded as "paid" from the
    // original payment was NEVER updated, so refunded revenue kept being
    // counted forever in every Reports query that filters payments.status='paid'.
    if (transaction_status === "refund") {
      await supabase
        .from("payments")
        .update({ status: "refunded" })
        .eq("order_id", internalOrderId)
        .eq("status", "paid");
    }

    // ── 7. Insert payment record (only if paid) ────────────────────────
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

        // Free up the table → cleaning
        if (order.table_id) {
          await supabase
            .from("restaurant_tables")
            .update({ status: "cleaning" })
            .eq("id", order.table_id);
        }
      }
    }

    // ── 8. Return 200 to Midtrans ──────────────────────────────────────────
    // Midtrans will retry if it doesn't get a 200 response
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
    // Still return 200 so Midtrans doesn't spam retries
    return new Response(
      JSON.stringify({ message: "Error processed", error: String(err) }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});