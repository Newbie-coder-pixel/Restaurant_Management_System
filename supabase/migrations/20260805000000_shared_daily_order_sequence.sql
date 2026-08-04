-- ═══════════════════════════════════════════════════════════════════════════
-- Shared daily order sequence across QR / customer app / staff cashier
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Feature request: order numbers should read as one continuous, chronological
-- sequence per branch per day, regardless of which of the three apps created
-- the order — only the display prefix should differ (QR: "A001" style,
-- customer app: "WEB-YYYYMMDD-NNN", staff: "ORD-YYYYMMDD-NNN").
--
-- Previously all three paths generated their number independently and
-- client-side:
--   • QR (qr_order_repository.dart _generateQueueNumber) — read "today's last
--     queue_number", increment, INSERT. Not atomic: two concurrent QR orders
--     can read the same "last" row and both compute the same next number.
--     Silently fell back to a RANDOM number on any query error, which is
--     exactly the kind of collision risk this migration removes.
--   • Customer app (customer_checkout_screen.dart) — random 6-digit suffix,
--     retried against the DB's partial unique index on a 23505 conflict.
--   • Staff cashier (menu_item_selector.dart) — random 4-digit suffix, no
--     collision handling at all.
-- None of the three shared a counter, so there was never a single ordering
-- across platforms — a customer-app order placed right after a QR order at
-- the same branch had no relationship between their numbers at all.
--
-- Fix: one atomic per-(branch, day) counter table + a SECURITY DEFINER RPC
-- that every order-creation path calls first to reserve the next integer,
-- then formats it into its own display scheme locally (see
-- lib/shared/services/order_number_service.dart). The INSERT ... ON CONFLICT
-- DO UPDATE ... RETURNING pattern is atomic under concurrent callers — as
-- with every other per-row counter in Postgres, the row's write lock
-- serializes concurrent increments so no two callers can ever get the same
-- number, no matter how many app instances are calling it at once.
--
-- Day boundary is Asia/Jakarta local time (not the QR path's old UTC
-- midnight, and not each client device's own local clock) — same choice as
-- enforce_branch_open_for_order_insert in the branch-hours migration, for
-- the same reason: the reset boundary must not depend on which app or device
-- is asking, only on where the branch actually is.
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists public.daily_order_counters (
  branch_id   uuid not null references public.branches(id),
  order_date  date not null,
  last_number int  not null default 0,
  primary key (branch_id, order_date)
);

-- No policies granted — nobody should touch this table directly. The only
-- sanctioned access path is next_daily_order_number() below, which is
-- SECURITY DEFINER and owned by the migration role, so it bypasses RLS on a
-- table that role owns (the standard Postgres "owner bypasses its own
-- table's RLS" behavior) while direct anon/authenticated access stays
-- blocked outright.
alter table public.daily_order_counters enable row level security;

create or replace function public.next_daily_order_number(p_branch_id uuid)
returns table(seq_number int, order_date date)
language plpgsql security definer set search_path = '' as $$
declare
  v_date date := (now() at time zone 'Asia/Jakarta')::date;
  v_seq int;
begin
  insert into public.daily_order_counters (branch_id, order_date, last_number)
  values (p_branch_id, v_date, 1)
  on conflict (branch_id, order_date)
  do update set last_number = public.daily_order_counters.last_number + 1
  returning last_number into v_seq;

  return query select v_seq, v_date;
end;
$$;

grant execute on function public.next_daily_order_number(uuid) to anon, authenticated;

-- ── Fix a pre-existing multi-branch bug in the WEB- uniqueness constraint ──
-- orders_web_order_number_unique (20260803020000) was UNIQUE on order_number
-- ALONE, with no branch_id — harmless while the suffix was a random 6-digit
-- number (900,000 values/day, collision odds negligible even across
-- branches), but now that the suffix is a small shared-sequence integer,
-- EVERY branch's first web order of the day would be "WEB-<date>-001" and
-- collide against this index the moment a second branch tried to insert the
-- same value on the same day. Scoping it to (branch_id, order_number) is what
-- this constraint should always have meant — order numbers are only ever
-- looked up within a single branch's context anyway.
drop index if exists orders_web_order_number_unique;
create unique index if not exists orders_web_order_number_unique
  on public.orders (branch_id, order_number)
  where order_number like 'WEB-%';

-- Staff (ORD-%) never had ANY uniqueness constraint before this migration —
-- not a regression introduced here, just a pre-existing gap. Adding the
-- matching per-branch constraint now that the suffix is sequence-backed
-- costs nothing and closes it.
create unique index if not exists orders_staff_order_number_unique
  on public.orders (branch_id, order_number)
  where order_number like 'ORD-%';
