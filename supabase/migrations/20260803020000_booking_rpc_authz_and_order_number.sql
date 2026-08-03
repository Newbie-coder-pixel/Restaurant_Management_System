-- ═══════════════════════════════════════════════════════════════════════════
-- Booking RPC authorization + WEB order_number uniqueness — 2026-08-03
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Found while reviewing the customer app (lib/features/customer/**):
--
--   1. `release_table` and `assign_table_to_booking` are SECURITY DEFINER
--      functions granted EXECUTE to `anon` (confirmed live via
--      information_schema.routine_privileges) with NO ownership check inside
--      the function body at all. Any holder of the public anon key — logged
--      in or not — could call `release_table` via
--      POST /rest/v1/rpc/release_table with an arbitrary p_table_id /
--      p_booking_id / p_new_status and cancel or mutate ANY customer's
--      booking and free ANY table, or call `assign_table_to_booking` for a
--      booking_id they don't own. Only lib/features/customer/** ever calls
--      these RPCs (grepped the whole lib/ tree) — the staff booking screen
--      updates `bookings`/`restaurant_tables` directly under RLS instead —
--      so there is no legitimate need for anon/other-customer access here.
--      Fixed by requiring the caller to either own the booking
--      (bookings.customer_user_id = auth.uid()) or be active staff, checked
--      inside the SECURITY DEFINER body before any mutation. Also added
--      `set search_path = ''` + schema-qualified all references, matching
--      the pattern already used by the trigger functions in
--      20260723000000_rls_policies_applied.sql / 20260724000000_price_integrity.sql.
--
--   2. orders.order_number has no uniqueness constraint at all. Confirmed
--      live: order numbers under the walk-in/QR 'A0xx' scheme are reused by
--      design (A001 appears 15 times — a per-day queue number, not a
--      permanent id), so a table-wide UNIQUE constraint would break that
--      existing data. But the customer web-checkout scheme
--      (customer_checkout_screen.dart, 'WEB-yyyymmdd-nnnn', 4-digit random
--      client-generated suffix) is the ONLY key anonymous customers can use
--      to look up their order (see customer_order_tracker_screen.dart) and
--      currently has no DB-level protection against collisions. No existing
--      'WEB-%' collisions were found live, so a partial unique index is safe
--      to add now and prevents two unrelated customers from silently sharing
--      a lookup key going forward. The Flutter side (this commit) also adds
--      retry-on-conflict + a larger random suffix.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. assign_table_to_booking: require ownership (customer) or active staff ──
create or replace function public.assign_table_to_booking(
  p_booking_id   uuid,
  p_branch_id    uuid,
  p_guest_count  integer,
  p_booking_date date,
  p_booking_time time without time zone
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_table_id     uuid;
  v_table_number text;
  v_locked_until timestamptz;
  v_authorized   boolean;
begin
  select exists (
    select 1 from public.bookings
    where id = p_booking_id
      and (
        customer_user_id = auth.uid()
        or exists (
          select 1 from public.staff
          where user_id = auth.uid() and is_active
        )
      )
  ) into v_authorized;

  if not v_authorized then
    return jsonb_build_object(
      'success', false,
      'status',  'error',
      'message', 'Not authorized for this booking'
    );
  end if;

  v_locked_until := (p_booking_date::text || ' ' || p_booking_time::text)::timestamptz
                    + interval '30 minutes';

  select id, table_number
  into   v_table_id, v_table_number
  from   public.restaurant_tables
  where  branch_id = p_branch_id
    and  status    = 'available'
    and  capacity  >= p_guest_count
  order  by capacity asc
  limit  1
  for update skip locked;

  if v_table_id is null then
    update public.bookings
    set    status     = 'waitlisted',
           updated_at = now()
    where  id = p_booking_id;

    return jsonb_build_object(
      'success', false,
      'status',  'waitlisted',
      'message', 'Semua meja penuh, Anda masuk waitlist'
    );
  end if;

  update public.restaurant_tables
  set    status             = 'reserved',
         current_booking_id = p_booking_id,
         locked_until       = v_locked_until,
         updated_at         = now()
  where  id = v_table_id;

  update public.bookings
  set    status     = 'confirmed',
         table_id   = v_table_id,
         updated_at = now()
  where  id = p_booking_id;

  return jsonb_build_object(
    'success',      true,
    'status',       'confirmed',
    'table_id',     v_table_id,
    'table_number', v_table_number
  );

exception when others then
  return jsonb_build_object(
    'success', false,
    'status',  'error',
    'message', sqlerrm
  );
end;
$function$;

-- ── 2. release_table: require ownership (customer) or active staff, and ───
-- require p_table_id to actually be the booking's own table (prevents an
-- authorized caller from releasing an unrelated table by passing a mismatched id).
create or replace function public.release_table(
  p_table_id   uuid,
  p_booking_id uuid,
  p_new_status text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_authorized boolean;
begin
  select exists (
    select 1 from public.bookings
    where id = p_booking_id
      and table_id = p_table_id
      and (
        customer_user_id = auth.uid()
        or exists (
          select 1 from public.staff
          where user_id = auth.uid() and is_active
        )
      )
  ) into v_authorized;

  if not v_authorized then
    raise exception 'Not authorized to release this table/booking';
  end if;

  update public.restaurant_tables
  set    status             = 'available',
         current_booking_id = null,
         locked_until       = null,
         updated_at         = now()
  where  id = p_table_id;

  execute format(
    'update public.bookings set status = $1::public.booking_status, updated_at = now() where id = $2'
  ) using p_new_status, p_booking_id;
end;
$function$;

-- ── 3. WEB order_number uniqueness (partial — only the customer checkout ──
-- scheme, other order sources reuse numbers by design, see comment above).
create unique index if not exists orders_web_order_number_unique
  on public.orders (order_number)
  where order_number like 'WEB-%';
