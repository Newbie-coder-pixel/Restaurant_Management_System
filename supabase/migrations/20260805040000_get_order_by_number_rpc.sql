-- ═══════════════════════════════════════════════════════════════════════════
-- get_order_by_number RPC — closes a live, unauthenticated PII leak
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Verified live via direct REST call with the (public, committed-in-repo)
-- anon key: a bare GET on /rest/v1/orders with customer_name/customer_phone/
-- customer_email selected and NO filter at all returned 10 real orders
-- across both branches — real customer names, phone numbers, and a real
-- student email address. No order_number, no login, nothing — the
-- anon_read_orders_by_number policy (20260723000000) makes any row from the
-- last 24 hours visible to ANY anon query regardless of what the query
-- actually filters on; RLS restricts which ROWS are visible, not what
-- columns a client is allowed to ask for or whether it supplied a filter at
-- all. That migration's own comment already flagged this as "a mitigation,
-- not a full fix" and named the correct fix — it just was never done.
--
-- Fix: the three places in the app that let someone type an arbitrary
-- order/queue number with NO login (customer_order_tracker_screen.dart,
-- customer_landing_screen.dart's search widget, qr_order_repository.dart's
-- fetchByQueueNumber) now go through this SECURITY DEFINER RPC instead of a
-- direct table SELECT. It does an exact match, returns at most one row, and
-- deliberately excludes customer_phone/customer_email — matching what those
-- screens' own pre-existing comments already said they intentionally never
-- fetch ("sensitive data ... deliberately NOT fetched here"); the RPC just
-- makes that intent actually enforced server-side instead of a client-side
-- gentleman's agreement that a direct REST call could freely ignore.
--
-- Residual scope, not fixed in this migration: several OTHER anon reads of
-- `orders` (fetchOrder, fetchActiveOrderForTable, fetchOrderModelForPayment,
-- customer_pay_now_screen's _payOrderProvider) still rely on the same broad
-- anon_read_orders_by_number/anon_update_recent_order policies to look up an
-- order by its internal `id` right after the customer's own device created
-- it (id is a UUID, not practically guessable — materially lower risk than
-- the order_number/queue_number search box, which is a small guessable
-- keyspace AND was reachable with literally no input at all). Removing
-- those two policies outright would break every one of those flows; doing
-- that properly needs a matching get_order_by_id RPC and swapping every one
-- of those call sites, which is a larger follow-up, not bundled in here to
-- avoid rushing a change to the entire order-confirmation/payment path.
-- order_items has the same shape of gap (no PII, but unrestricted order
-- contents disclosure) — also left for that follow-up.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.get_order_by_number(p_order_number text)
returns table(
  id uuid,
  order_number text,
  queue_number text,
  table_id uuid,
  table_name text,
  branch_id uuid,
  customer_name text,
  status text,
  payment_status text,
  payment_method text,
  order_type text,
  source text,
  subtotal numeric,
  tax_amount numeric,
  discount_amount numeric,
  total_amount numeric,
  notes text,
  bill_requested boolean,
  bill_requested_at timestamptz,
  estimated_prep_minutes int,
  served_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz,
  device_id text
)
language sql security definer set search_path = '' as $$
  select
    o.id, o.order_number, o.queue_number, o.table_id, o.table_name, o.branch_id,
    o.customer_name, o.status, o.payment_status, o.payment_method, o.order_type,
    o.source, o.subtotal, o.tax_amount, o.discount_amount, o.total_amount, o.notes,
    o.bill_requested, o.bill_requested_at, o.estimated_prep_minutes, o.served_at,
    o.created_at, o.updated_at, o.device_id
  from public.orders o
  where o.order_number = p_order_number
  limit 1;
$$;

grant execute on function public.get_order_by_number(text) to anon, authenticated;
