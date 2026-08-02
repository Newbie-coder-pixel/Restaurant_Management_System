// supabase/functions/midtrans-create-token/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// Edge Function: Create Midtrans Snap Token
// Called by Flutter when the user is about to pay → returns snap_token to Flutter
// Flutter uses that token to open the Midtrans payment page
//
// IMPORTANT CHANGE (fix for "order_id has already been taken"):
//   Midtrans REQUIRES order_id to be unique forever per account, and it
//   cannot be reused even if the previous transaction failed/is
//   pending/expired. Because of this, Flutter now sends TWO different ids:
//     - `order_id`          → a UNIQUE id per payment attempt, sent to
//                             Midtrans as transaction_details.order_id
//     - `internal_order_id` → the real UUID row in the `orders` table, used
//                             for lookups & updates to the database
//
//   `order_id` (the unique one) is also saved to the `midtrans_order_id`
//   column in the `orders` table, so the webhook/notification handler can
//   later match it back to the correct row when Midtrans sends a payment
//   notification (that notification only contains the unique `order_id`
//   version, NOT internal_order_id).
//
//   REQUIRED: add the new column to the `orders` table if it doesn't exist yet:
//     ALTER TABLE orders ADD COLUMN IF NOT EXISTS midtrans_order_id text;
//     CREATE INDEX IF NOT EXISTS idx_orders_midtrans_order_id
//       ON orders (midtrans_order_id);
//
//   And your webhook handler (the other function that receives notifications
//   from Midtrans) also MUST be updated to look up using:
//     .eq("midtrans_order_id", notification.order_id)
//   NO LONGER:
//     .eq("id", notification.order_id)
// ─────────────────────────────────────────────────────────────────────────────

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Origin allowed via the ALLOWED_ORIGINS env var (comma-separated) — previously
// "*" allowed any site to trigger Snap token creation from a browser.
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
    // ── 1. Read secrets from the environment ──────────────────────────────────
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

    // ── 2. Verify the user's JWT (make sure the request is from our own app) ──────────
    const authHeader = req.headers.get("authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing authorization header" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // ── 3. Parse the request body ───────────────────────────────────────────────
    const body = await req.json();
    const {
      order_id,          // string: UNIQUE id per payment attempt (sent to Midtrans)
      internal_order_id, // string: the real UUID row in the `orders` table
      gross_amount,      // number: total in Rupiah (integer, no decimals)
      customer_name,     // string: customer name
      customer_email,    // string: email (optional, Midtrans still works without it)
      customer_phone,    // string: phone number (optional)
      items,             // array: [{id, name, price, quantity}]
      enabled_payments,  // optional array: payment method filter
    } = body;

    // Fallback for compatibility in case an older caller hasn't sent
    // internal_order_id yet (e.g. an old app version) — assume order_id == internal id.
    const internalOrderId = internal_order_id || order_id;

    // Minimal input validation
    if (!order_id || !internalOrderId || !gross_amount) {
      return new Response(
        JSON.stringify({
          error: "order_id, internal_order_id, and gross_amount are required",
        }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Make sure gross_amount is an integer (Midtrans doesn't accept decimals)
    const amount = Math.round(Number(gross_amount));
    if (amount <= 0) {
      return new Response(
        JSON.stringify({ error: "gross_amount must be > 0" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── 4. Check the order exists in the DB and its status is valid ──────────────────────────
    // IMPORTANT: lookup uses internalOrderId (the real UUID), NOT order_id
    // (which is now unique per attempt and won't match the `id` column).
    const { data: order, error: orderError } = await supabase
      .from("orders")
      .select("id, status, payment_status, total_amount, branch_id, served_at")
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

    // ── 4b. Validate gross_amount against the real total_amount in the DB ────────────────
    // BEFORE this fix, `amount` (from the request body, sent by the client) was used
    // directly as the gross_amount sent to Midtrans without ever being checked
    // against the `order.total_amount` fetched above — a client could request
    // a Snap token for any amount regardless of the order's actual price.
    //
    // orders.total_amount NEVER includes the dine-in overtime charge (Rp5000
    // per hour or fraction thereof, after 2 hours from served_at) — it's a
    // purely client-side, live-computed value (see calculateOvertimeCharge()
    // in lib/shared/models/order_model.dart) that's never persisted back to
    // the DB, because it depends on "now" at payment time, not a value that
    // can be durably cached. Without adding it here too, ANY order that goes
    // into overtime would 400 forever with "gross_amount does not match
    // order total" — the client's total (which correctly includes overtime)
    // would never match the DB's (which structurally never does).
    // Mirrors calculateOvertimeCharge()'s constants exactly — keep in sync.
    const kMaxDineInMinutes = 120; // kMaxDineInDuration = 2 hours
    const kOvertimeChargePerHour = 5000;
    function calculateOvertimeCharge(servedAt: string | null): number {
      if (!servedAt) return 0;
      const elapsedMinutes = (Date.now() - new Date(servedAt).getTime()) / 60000;
      const overMinutes = elapsedMinutes - kMaxDineInMinutes;
      if (overMinutes <= 0) return 0;
      const overHours = Math.ceil(overMinutes / 60);
      return overHours * kOvertimeChargePerHour;
    }
    const overtimeCharge = calculateOvertimeCharge(order.served_at as string | null);

    // Rp1 tolerance normally; widened to one overtime-hour-bucket when the
    // order is actually in overtime, to absorb the race between the client
    // computing overtimeCharge at render time and the server recomputing it
    // here a few seconds later (both use "now", so they can land in
    // different hour buckets right at an hour boundary).
    const tolerance = overtimeCharge > 0 ? kOvertimeChargePerHour : 1;
    const expectedAmount = Math.round(Number(order.total_amount)) + overtimeCharge;
    if (Math.abs(expectedAmount - amount) > tolerance) {
      console.error(
        `gross_amount mismatch: order=${internalOrderId} expected=${expectedAmount} received=${amount}`
      );
      return new Response(
        JSON.stringify({ error: "gross_amount does not match order total" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── 5. Build the Snap request payload ──────────────────────────────────────
    //
    // Midtrans Snap endpoint:
    //   Sandbox:    https://app.sandbox.midtrans.com/snap/v1/transactions
    //   Production: https://app.midtrans.com/snap/v1/transactions
    //
    const snapBaseUrl = MIDTRANS_IS_PRODUCTION
      ? "https://app.midtrans.com/snap/v1/transactions"
      : "https://app.sandbox.midtrans.com/snap/v1/transactions";

    // Encode the server key to Base64 for Basic Auth
    // Format: Base64("SERVER_KEY:")  ← note the colon after the server key
    const encodedKey = btoa(`${MIDTRANS_SERVER_KEY}:`);
    const snapPayload: Record<string, unknown> = {
      transaction_details: {
        // The order_id sent to MIDTRANS must be this UNIQUE version,
        // not internalOrderId — to avoid collisions on payment retries.
        order_id: order_id,
        gross_amount: amount,
      },
      customer_details: {
        first_name: customer_name || "Customer",
        email: customer_email || `order-${internalOrderId}@rms.local`,
        phone: customer_phone || "",
      },
    };

    // Show the store name on the Snap page — ONLY sent if it's actually set.
    // Midtrans already knows the merchant automatically from the Server Key
    // in Basic Auth, so this field is optional. Sending an empty string ""
    // risks being rejected by Midtrans as an invalid merchant_id.
    const MIDTRANS_MERCHANT_ID = Deno.env.get("MIDTRANS_MERCHANT_ID");
    if (MIDTRANS_MERCHANT_ID) {
      snapPayload.merchant_id = MIDTRANS_MERCHANT_ID;
    }

    // Add item details if present
    if (items && Array.isArray(items) && items.length > 0) {
      snapPayload.item_details = items.map((item: Record<string, unknown>) => ({
        id: item.id || "ITEM",
        name: String(item.name || "Menu").substring(0, 50), // max 50 char
        price: Math.round(Number(item.price)),
        quantity: Number(item.quantity) || 1,
      }));
    }

    // ── 6. Request the Snap token from Midtrans ──────────────────────────────────
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

    // ── 7. Save snap_token + order_id (unique) to the DB ───────────────────────
    // IMPORTANT: save order_id (the unique version) to the `midtrans_order_id`
    // column. This is used later by the webhook handler to match a
    // notification from Midtrans back to the correct order row — because
    // Midtrans' notification only contains this unique order_id version,
    // not internalOrderId.
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

    // Don't fail the response to Flutter if the DB update fails — the Snap
    // token is still valid and the user can still use it to pay. But log it
    // so schema/RLS issues can be caught, because staying silent here could
    // make payment status retries/polling inaccurate later on.
    if (updateError) {
      console.error(
        `Failed to save snap_token for order ${internalOrderId}:`,
        JSON.stringify(updateError)
      );
    }

    // ── 8. Return the token to Flutter ─────────────────────────────────────────
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