-- ═══════════════════════════════════════════════════════════════════════════
-- Table-service notification log: table_events + trigger — 2026-08-14
-- ═══════════════════════════════════════════════════════════════════════════
--
-- QrOrderRepository.reportTableIssue() ("Notify Staff" button on the QR
-- "this table is still being cleaned/reserved" screen — see
-- qr_menu_screen.dart's _TableNotReadyScreen) already writes
-- restaurant_tables.customer_reported_at, but nothing ever read that column
-- back out: no bell entry, no banner, no chime. Staff had no way to know a
-- customer tapped that button short of noticing the timestamp by chance.
--
-- Mirrors order_events_notification_system.sql's shape (append-only log
-- populated by a trigger, subscribed to via Realtime) rather than trying to
-- diff old/new values out of a raw restaurant_tables UPDATE payload
-- client-side — restaurant_tables has REPLICA IDENTITY default, so the
-- Realtime "old record" only carries the primary key, not enough to tell
-- "customer just reported this" apart from any other unrelated column
-- update on the same row.
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists public.table_events (
  id            uuid primary key default gen_random_uuid(),
  table_id      uuid not null references public.restaurant_tables(id) on delete cascade,
  branch_id     uuid not null,   -- denormalized from restaurant_tables.branch_id, same reason order_events denormalizes it
  table_number  text not null,   -- denormalized from restaurant_tables.table_number, for banners ("Table A3 needs attention")
  event_type    text not null default 'customer_reported'
                  check (event_type in ('customer_reported')),
  created_at    timestamptz not null default now()
);

create index if not exists idx_table_events_branch_created
  on public.table_events (branch_id, created_at desc);

alter table public.table_events enable row level security;

-- Fires AFTER UPDATE on restaurant_tables; only logs when
-- customer_reported_at actually moved forward (a customer tapping "Notify
-- Staff" again on an already-reported table still counts as a new nudge,
-- but any other column changing on the row — status, position, etc. —
-- must not).
create or replace function public.log_table_customer_reported_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.customer_reported_at is distinct from old.customer_reported_at
     and new.customer_reported_at is not null then
    insert into public.table_events (table_id, branch_id, table_number, event_type)
    values (new.id, new.branch_id, new.table_number, 'customer_reported');
  end if;
  return new;
end;
$$;

drop trigger if exists trg_log_table_customer_reported_event on public.restaurant_tables;
create trigger trg_log_table_customer_reported_event
  after update on public.restaurant_tables
  for each row
  execute function public.log_table_customer_reported_event();

-- ── RLS ────────────────────────────────────────────────────────────────
-- Staff-only feed — no customer/anon read path needed, unlike order_events
-- (customers never need to read back their own "I notified staff" report).
create policy table_events_staff_select on public.table_events
  for select to authenticated
  using (public.is_superadmin() or branch_id = public.get_my_branch_id());

grant select on public.table_events to authenticated;

-- ── Realtime ──────────────────────────────────────────────────────────
alter publication supabase_realtime add table public.table_events;
