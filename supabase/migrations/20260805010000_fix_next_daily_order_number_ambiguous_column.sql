-- ═══════════════════════════════════════════════════════════════════════════
-- Fix ambiguous column reference in next_daily_order_number
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Found by actually calling the RPC live (not just reading the SQL) right
-- after 20260805000000 shipped: every call failed with
-- "column reference \"order_date\" is ambiguous" (Postgres code 42702).
--
-- Root cause: `returns table(seq_number int, order_date date)` makes
-- `order_date` an OUT parameter, which PL/pgSQL exposes as an implicit
-- variable in the function body's scope — colliding with
-- daily_order_counters.order_date, the actual table column referenced by
-- `on conflict (branch_id, order_date)`. Every single call failed outright;
-- no order was ever able to reserve a sequence number through this function,
-- so no live traffic was affected (it simply errored, same as any other
-- network failure the existing try/catch in each order-creation path
-- already handles) — but it never actually worked in production even once.
--
-- Fix: rename the OUT parameter so it no longer shares a name with any
-- column of daily_order_counters. The application-facing shape changes from
-- `{seq_number, order_date}` to `{seq_number, result_date}` — updated to
-- match in lib/shared/services/order_number_service.dart in this same commit.
-- ═══════════════════════════════════════════════════════════════════════════

-- CREATE OR REPLACE can't change OUT-parameter names/types on an existing
-- function — Postgres requires DROP first (found live: "cannot change
-- return type of existing function... Row type defined by OUT parameters is
-- different").
drop function if exists public.next_daily_order_number(uuid);

create or replace function public.next_daily_order_number(p_branch_id uuid)
returns table(seq_number int, result_date date)
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
