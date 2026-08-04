-- ═══════════════════════════════════════════════════════════════════════════
-- Full closure pass on the anon order-data exposure (follow-up to
-- 20260805040000, which only fixed the "type any number" search box)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- A full audit of every anon-reachable read of `orders`/`order_items` found
-- ~15 more direct table reads across the customer app and QR self-order flow
-- (fetchOrder, fetchActiveOrderForTable, fetchOrderModelForPayment,
-- addItemsToOrder, customer_pay_now_screen, midtrans_service.checkPaymentStatus,
-- and every order_items companion fetch) — all of them relying on the same
-- broad anon_read_orders_by_number / anon_update_recent_order policies
-- (any row from the last 24h, no column restriction) that 20260805040000's
-- doc comment already flagged as a residual risk.
--
-- Three new SECURITY DEFINER RPCs replace every one of those direct reads:
--   • get_order_by_id(uuid)        — exact match on the internal id (a UUID,
--     not a guessable keyspace like order_number/queue_number) — INCLUDES
--     customer_phone/customer_email since Midtrans payment genuinely needs
--     them and knowing the specific UUID already implies the caller is the
--     device that created (or was redirected to) this exact order.
--   • get_active_order_for_table(uuid) — for the "does this table already
--     have an order" check when a QR is (re)scanned. Table_id is also a
--     UUID, but a DIFFERENT customer could physically scan the same table's
--     QR — so this one does NOT return phone/email, only what the existing
--     "this table already has an order" dialog actually displays.
--   • get_order_items(uuid)        — order_items has no direct PII, but was
--     just as openly readable (verified live: a bare GET with no filter
--     returned order contents across random orders) — every direct
--     order_items-by-order_id read now goes through this instead.
--
-- Column-level lockdown (works regardless of the row-visibility window
-- below, and is what actually closes the PII leak permanently): anon can no
-- longer SELECT customer_phone/customer_email off `orders` AT ALL, for any
-- query, through any filter. The three RPCs above are unaffected — a
-- SECURITY DEFINER function executes as its owner, not as 'anon', so it
-- bypasses this column revoke exactly as it already bypasses RLS.
--
-- Row-visibility window shrunk from 24 hours to 3 (still generous over the
-- 2-hour kMaxDineInDuration used elsewhere for overtime charges) — kept
-- specifically because Supabase Realtime's postgres_changes subscriptions
-- (the QR/customer tracker screens' live status updates) evaluate RLS
-- per-row and have no equivalent "via RPC" path; removing anon row
-- visibility entirely would silently break live order-status updates for
-- every anonymous customer. This window is the one deliberately-accepted
-- residual: a raw REST call within it can still see non-PII columns
-- (status, totals, table_name) for other branches' recent orders. Closing
-- that fully needs migrating Realtime to authorized private channels
-- (broadcast, not postgres_changes) — a larger architecture change, not
-- bundled into this pass.
--
-- order_items has the same Realtime dependency and is left similarly open
-- at the row level (no PII there, lower severity) — but every application
-- read of it now goes through get_order_items regardless.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.get_order_by_id(p_order_id uuid)
returns table(
  id uuid,
  order_number text,
  queue_number text,
  table_id uuid,
  table_name text,
  branch_id uuid,
  customer_name text,
  customer_phone text,
  customer_email text,
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
  device_id text,
  midtrans_transaction_id text
)
language sql security definer set search_path = '' as $$
  select
    o.id, o.order_number, o.queue_number, o.table_id, o.table_name, o.branch_id,
    o.customer_name, o.customer_phone, o.customer_email, o.status, o.payment_status,
    o.payment_method, o.order_type, o.source, o.subtotal, o.tax_amount,
    o.discount_amount, o.total_amount, o.notes, o.bill_requested, o.bill_requested_at,
    o.estimated_prep_minutes, o.served_at, o.created_at, o.updated_at, o.device_id,
    o.midtrans_transaction_id
  from public.orders o
  where o.id = p_order_id
  limit 1;
$$;

grant execute on function public.get_order_by_id(uuid) to anon, authenticated;

create or replace function public.get_active_order_for_table(p_table_id uuid)
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
  where o.table_id = p_table_id
    and o.status not in ('paid', 'cancelled')
  order by o.created_at desc
  limit 1;
$$;

grant execute on function public.get_active_order_for_table(uuid) to anon, authenticated;

create or replace function public.get_order_items(p_order_id uuid)
returns table(
  id uuid,
  order_id uuid,
  menu_item_id uuid,
  menu_item_name text,
  unit_price numeric,
  quantity int,
  subtotal numeric,
  special_requests text,
  status text,
  sent_to_kitchen_at timestamptz,
  preparation_time_minutes int
)
language sql security definer set search_path = '' as $$
  select
    oi.id, oi.order_id, oi.menu_item_id, oi.menu_item_name, oi.unit_price,
    oi.quantity, oi.subtotal, oi.special_requests, oi.status, oi.sent_to_kitchen_at,
    mi.preparation_time_minutes
  from public.order_items oi
  left join public.menu_items mi on mi.id = oi.menu_item_id
  where oi.order_id = p_order_id
  order by oi.created_at;
$$;

grant execute on function public.get_order_items(uuid) to anon, authenticated;

-- ── Column-level lockdown: the actual permanent fix for the PII leak ──────
revoke select (customer_phone, customer_email) on public.orders from anon;

-- ── Shrink the anon row-visibility window (Realtime still needs one) ──────
drop policy if exists anon_read_orders_by_number on public.orders;
create policy anon_read_orders_by_number on public.orders
  for select to anon
  using (created_at >= (now() - interval '3 hours'));

drop policy if exists anon_update_recent_order on public.orders;
create policy anon_update_recent_order on public.orders
  for update to anon
  using (created_at >= (now() - interval '3 hours'))
  with check (created_at >= (now() - interval '3 hours'));
