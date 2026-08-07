-- ═══════════════════════════════════════════════════════════════════════════
-- Order-progress notification system: order_events log + triggers — 2026-08-08
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Problem: `orders.status`/`payment_status`/`bill_requested` are written
-- directly via `.update()` from ~8 separate call sites across the Flutter
-- codebase (order_screen.dart, kds_screen.dart x4, cashier_screen.dart,
-- qr_order_repository.dart, qr_order_tracker_screen.dart,
-- qr_payment_screen.dart) with no central OrderService. Instrumenting every
-- call site to also emit a notification is guaranteed to be missed the next
-- time someone adds a 9th call site. A row-level AFTER trigger on `orders`
-- is the only place that sees every write regardless of origin (client,
-- RPC, edge function, future admin tool), so it is the single source of
-- truth for "what changed and who needs to know."
--
-- This migration does NOT send push notifications itself. It only appends
-- one row per meaningful change to `order_events`. Realtime clients (staff
-- KDS/order/cashier screens, customer/QR trackers) subscribe directly to
-- INSERTs on this table for in-app banners. A Database Webhook (configured
-- separately in the Supabase dashboard, see supabase/functions/
-- order-event-notify) fires on the same INSERTs to invoke an edge function
-- that does the FCM fan-out via the existing api/notify.js proxy.
--
-- Item-level OrderItemStatus changes are deliberately NOT tracked here —
-- only order-level status/payment_status/bill_requested/cancellation, to
-- keep event volume sane (see plan doc for the explicit v1 scope decision).
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists public.order_events (
  id                 uuid primary key default gen_random_uuid(),
  order_id           uuid not null references public.orders(id) on delete cascade,
  branch_id          uuid not null,          -- denormalized from orders.branch_id so staff RLS/filter doesn't need a join
  customer_user_id   uuid,                   -- denormalized from orders.customer_user_id, nullable (QR/anon orders)
  device_id          text,                   -- denormalized from orders.device_id, nullable
  event_type         text not null check (event_type in (
                       'status_changed', 'payment_status_changed',
                       'bill_requested', 'cancelled'
                     )),
  old_value          text,
  new_value          text,
  order_number       text not null,          -- denormalized so notification UI/push payload never needs a follow-up SELECT on orders
  table_name_snapshot text,                  -- denormalized orders.table_name, for staff banners ("Table 4 — order ready")
  created_at         timestamptz not null default now()
);

-- Staff feed: "give me everything for my branch since X" ordered by time.
create index if not exists idx_order_events_branch_created
  on public.order_events (branch_id, created_at desc);

-- Customer/QR feed: "give me everything for my order(s)."
create index if not exists idx_order_events_order_id
  on public.order_events (order_id, created_at desc);

alter table public.order_events enable row level security;

-- ── Trigger function: UPDATE ─────────────────────────────────────────────
-- Fires AFTER UPDATE on orders. Emits one row per distinct kind of change
-- that happened in this single UPDATE statement (an update can legitimately
-- change status AND payment_status together, e.g. cashier marking
-- paid+served at once — each becomes its own event row so staff/customer
-- feeds and push payloads stay unambiguous about what happened).
create or replace function public.log_order_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status is distinct from old.status then
    insert into public.order_events (
      order_id, branch_id, customer_user_id, device_id, event_type,
      old_value, new_value, order_number, table_name_snapshot
    ) values (
      new.id, new.branch_id, new.customer_user_id, new.device_id,
      case when new.status = 'cancelled' then 'cancelled' else 'status_changed' end,
      old.status, new.status, new.order_number, new.table_name
    );
  end if;

  if new.payment_status is distinct from old.payment_status then
    insert into public.order_events (
      order_id, branch_id, customer_user_id, device_id, event_type,
      old_value, new_value, order_number, table_name_snapshot
    ) values (
      new.id, new.branch_id, new.customer_user_id, new.device_id,
      'payment_status_changed', old.payment_status, new.payment_status,
      new.order_number, new.table_name
    );
  end if;

  if new.bill_requested is distinct from old.bill_requested and new.bill_requested = true then
    insert into public.order_events (
      order_id, branch_id, customer_user_id, device_id, event_type,
      old_value, new_value, order_number, table_name_snapshot
    ) values (
      new.id, new.branch_id, new.customer_user_id, new.device_id,
      'bill_requested', 'false', 'true', new.order_number, new.table_name
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_log_order_event on public.orders;
create trigger trg_log_order_event
  after update on public.orders
  for each row
  execute function public.log_order_event();

-- ── Trigger function: INSERT ("new order placed") ────────────────────────
-- No "old" row to diff against, so this is a separate, lighter trigger.
create or replace function public.log_order_created_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.order_events (
    order_id, branch_id, customer_user_id, device_id, event_type,
    old_value, new_value, order_number, table_name_snapshot
  ) values (
    new.id, new.branch_id, new.customer_user_id, new.device_id,
    'status_changed', null, new.status, new.order_number, new.table_name
  );
  return new;
end;
$$;

drop trigger if exists trg_log_order_created_event on public.orders;
create trigger trg_log_order_created_event
  after insert on public.orders
  for each row
  execute function public.log_order_created_event();

-- ── RLS ────────────────────────────────────────────────────────────────
-- Staff: same branch-isolation shape used everywhere else in this schema.
create policy order_events_staff_select on public.order_events
  for select to authenticated
  using (public.is_superadmin() or branch_id = public.get_my_branch_id());

-- Authed customer: only their own orders' events.
create policy order_events_customer_select on public.order_events
  for select to authenticated
  using (customer_user_id = auth.uid());

-- Anon/QR: scoped in practice by the client only ever querying/subscribing
-- with a specific order_id filter — the same trust boundary QR already
-- accepts today via watchOrder(orderId) and get_order_by_number (knowing
-- the exact order id/number is already sufficient to read that order's
-- live status). This table carries NO PII columns (unlike orders), so a
-- table-wide anon grant here is materially lower-risk than the existing
-- anon grant on orders itself.
create policy order_events_anon_select on public.order_events
  for select to anon
  using (true);

-- No insert/update/delete grants to anon or authenticated — order_events is
-- written exclusively by the SECURITY DEFINER trigger functions above.
grant select on public.order_events to anon;
grant select on public.order_events to authenticated;

-- ── Realtime ──────────────────────────────────────────────────────────
-- orders/order_items were enabled for realtime via the Studio dashboard
-- (no migration adds them), so this table has no prior toggle history —
-- add it here for reproducibility, but still verify live in Studio →
-- Database → Replication before relying on it (alter publication can
-- no-op silently if a dashboard toggle already covers it).
alter publication supabase_realtime add table public.order_events;
