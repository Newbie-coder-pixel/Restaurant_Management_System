// supabase/functions/order-event-notify/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// Push fan-out for the order-progress notification system.
//
// Triggered by a Supabase Database Webhook on INSERT into `order_events`
// (see supabase/migrations/20260808000000_order_events_notification_system.sql
// for the trigger that populates that table — this function never touches
// `orders` directly and never decides *what* changed, only *who to tell*).
//
// Structurally mirrors the two existing fan-out-style edge functions in this
// project: supabase/functions/midtrans-webhook (webhook receiver shape) and
// supabase/functions/notify-staff (multi-recipient fan-out shape) — same
// serve()/createClient(service role) pattern, just a different downstream
// channel (FCM push via the existing api/notify.js Vercel proxy, instead of
// WhatsApp).
//
// QR (anonymous) orders are NOT pushed to — there is no Supabase Auth user
// to key `device_tokens` on for an anonymous session (device_tokens.user_id
// is required by every existing write path in the app). Those customers
// rely on the in-app OrderNotificationOverlay banner only, which is a
// reasonable v1 trade-off since a QR tracker screen is realistically kept
// open at the table. Extending push to anonymous sessions would need a
// schema change (nullable user_id + a device_id column, with anon-write RLS
// implications) — deliberately out of scope here.
//
// This function always returns 200, even on partial FCM failures (logged via
// console.error) — a webhook retry storm on a transient FCM error is worse
// than a dropped push, since the in-app realtime banner is the reliable
// channel and push is best-effort supplementary.
// ─────────────────────────────────────────────────────────────────────────────

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-webhook-secret",
};

type OrderEventRecord = {
  id: string;
  order_id: string;
  branch_id: string;
  customer_user_id: string | null;
  device_id: string | null;
  event_type:
    | "status_changed"
    | "payment_status_changed"
    | "bill_requested"
    | "cancelled";
  old_value: string | null;
  new_value: string | null;
  order_number: string;
  table_name_snapshot: string | null;
};

// ── Staff role→event matrix ────────────────────────────────────────────────
// Deliberately conservative defaults (not every event pushes to every role)
// to avoid paging staff for progress they already see live on KDS/order
// screens — only pushed for the events that matter when a staff member
// ISN'T looking at a screen. Easy to retune later since this is plain
// function logic, not schema.
function staffRolesForEvent(e: OrderEventRecord): string[] {
  if (e.event_type === "status_changed") {
    if (e.old_value === null) return ["kitchen", "waiter"]; // new order
    if (e.new_value === "ready") return ["waiter"];
    return [];
  }
  if (e.event_type === "bill_requested") return ["waiter", "cashier"];
  if (e.event_type === "cancelled") return ["manager", "superadmin"];
  return []; // payment_status_changed — no default staff push
}

// Whether this event should also push to the customer who placed the order.
// Skips the initial "new order" event (old_value null) — the customer just
// placed it themselves, they don't need a push for their own action.
function shouldNotifyCustomer(e: OrderEventRecord): boolean {
  if (e.event_type === "status_changed") return e.old_value !== null;
  if (e.event_type === "payment_status_changed") return e.new_value === "paid";
  if (e.event_type === "cancelled") return true;
  return false; // bill_requested is itself a customer-initiated action
}

function buildMessage(e: OrderEventRecord): { title: string; body: string } {
  switch (e.event_type) {
    case "status_changed":
      if (e.old_value === null) {
        return {
          title: "New order",
          body: `Order ${e.order_number}${e.table_name_snapshot ? ` — ${e.table_name_snapshot}` : ""}`,
        };
      }
      return {
        title: `Order ${e.order_number}`,
        body: `Now "${e.new_value ?? ""}"`,
      };
    case "payment_status_changed":
      return {
        title: `Order ${e.order_number}`,
        body: `Payment is now "${e.new_value ?? ""}"`,
      };
    case "bill_requested":
      return {
        title: "Bill requested",
        body: `Order ${e.order_number}${e.table_name_snapshot ? ` — ${e.table_name_snapshot}` : ""}`,
      };
    case "cancelled":
      return {
        title: "Order cancelled",
        body: `Order ${e.order_number} was cancelled`,
      };
  }
}

async function sendPush(
  notifyApiUrl: string,
  tokens: string[],
  title: string,
  body: string,
  data: Record<string, string>,
) {
  // api/notify.js caps requests at 50 tokens — chunk to stay under that.
  const chunkSize = 50;
  for (let i = 0; i < tokens.length; i += chunkSize) {
    const chunk = tokens.slice(i, i + chunkSize);
    try {
      const res = await fetch(notifyApiUrl, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ tokens: chunk, title, body, data }),
      });
      if (!res.ok) {
        console.error("[order-event-notify] notify API error:", await res.text());
      }
    } catch (e) {
      console.error("[order-event-notify] notify API fetch failed:", e);
    }
  }
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405, headers: corsHeaders });
  }

  // Shared-secret check — Supabase Database Webhooks can be configured to
  // send a custom header; verify it here so this endpoint can't be used by
  // an arbitrary caller to spam pushes. Configure the same value as both
  // the webhook's custom header and this function's secret.
  const expectedSecret = Deno.env.get("ORDER_EVENT_WEBHOOK_SECRET");
  if (expectedSecret && req.headers.get("x-webhook-secret") !== expectedSecret) {
    return new Response("Forbidden", { status: 403, headers: corsHeaders });
  }

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const NOTIFY_API_URL = Deno.env.get("NOTIFY_API_URL"); // e.g. https://<staff-app>.vercel.app/api/notify

    const payload = await req.json();
    const record = payload?.record as OrderEventRecord | undefined;
    if (payload?.type !== "INSERT" || !record) {
      return new Response(JSON.stringify({ skipped: true }), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (!NOTIFY_API_URL) {
      console.error("[order-event-notify] NOTIFY_API_URL not configured — skipping push");
      return new Response(JSON.stringify({ success: false, error: "NOTIFY_API_URL not set" }), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const { title, body } = buildMessage(record);
    const data = {
      order_id: record.order_id,
      order_number: record.order_number,
      event_type: record.event_type,
    };

    // ── Staff recipients (branch-scoped, role-filtered) ──────────────────
    const staffRoles = staffRolesForEvent(record);
    if (staffRoles.length > 0) {
      const { data: staffRows, error: staffErr } = await supabase
        .from("staff")
        .select("user_id")
        .eq("branch_id", record.branch_id)
        .eq("is_active", true)
        .in("role", staffRoles);

      if (staffErr) {
        console.error("[order-event-notify] staff lookup error:", staffErr.message);
      } else if (staffRows && staffRows.length > 0) {
        const userIds = staffRows.map((s: { user_id: string }) => s.user_id);
        const { data: tokenRows, error: tokenErr } = await supabase
          .from("device_tokens")
          .select("token")
          .in("user_id", userIds);

        if (tokenErr) {
          console.error("[order-event-notify] staff token lookup error:", tokenErr.message);
        } else {
          const tokens = (tokenRows ?? [])
            .map((t: { token: string }) => t.token)
            .filter(Boolean);
          if (tokens.length > 0) {
            await sendPush(NOTIFY_API_URL, tokens, title, body, { ...data, audience: "staff" });
          }
        }
      }
    }

    // ── Customer recipient (their own order only) ────────────────────────
    if (record.customer_user_id && shouldNotifyCustomer(record)) {
      const { data: tokenRows, error: tokenErr } = await supabase
        .from("device_tokens")
        .select("token")
        .eq("user_id", record.customer_user_id);

      if (tokenErr) {
        console.error("[order-event-notify] customer token lookup error:", tokenErr.message);
      } else {
        const tokens = (tokenRows ?? [])
          .map((t: { token: string }) => t.token)
          .filter(Boolean);
        if (tokens.length > 0) {
          await sendPush(NOTIFY_API_URL, tokens, title, body, { ...data, audience: "customer" });
        }
      }
    }

    return new Response(JSON.stringify({ success: true }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("[order-event-notify] Error:", error);
    // Still 200 — see file header comment on why we don't want webhook retries here.
    return new Response(JSON.stringify({ success: false, error: String(error) }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
