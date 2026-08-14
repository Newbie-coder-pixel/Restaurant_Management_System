-- ═══════════════════════════════════════════════════════════════════════════
-- Customer-facing reservation duration + overlap-safe table assignment
-- ═══════════════════════════════════════════════════════════════════════════
--
-- The customer app's "New Reservation" form only let guests pick a date and
-- an arrival hour — duration was never collected, so every booking silently
-- used the `bookings.duration_minutes` column default (90). The staff-side
-- booking dialogs (add_booking_dialog.dart / edit_booking_dialog.dart) do
-- offer a static duration dropdown (60/90/120/180 min) and correctly check
-- for overlapping bookings on the same table before assigning it.
--
-- assign_table_to_booking() — the SECURITY DEFINER RPC the customer app
-- calls to auto-assign a table — never did that overlap check. It only
-- filtered on `restaurant_tables.status = 'available'`, which reflects
-- *live floor status*, not future reservations. Since customers can book up
-- to 60 days ahead, two different customers requesting the same branch,
-- same future date, and overlapping times could both be handed the same
-- table — a genuine double-booking, only caught later if a human noticed.
--
-- Fix: add p_duration_minutes (default 90, matches the column default) and
-- exclude any table that already has an active (pending/confirmed/seated)
-- booking on the same date whose [start, start+duration) interval overlaps
-- the new request — the same interval-overlap test already used client-side
-- by the staff dialogs, now enforced atomically in the DB (the existing
-- `for update skip locked` already serializes concurrent calls per table row,
-- so this closes the race too, not just the logic gap).
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.assign_table_to_booking(
  p_booking_id        uuid,
  p_branch_id         uuid,
  p_guest_count       integer,
  p_booking_date      date,
  p_booking_time      time without time zone,
  p_duration_minutes  integer default 90
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
  v_new_start    integer;
  v_new_end      integer;
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

  if p_duration_minutes is null or p_duration_minutes <= 0 then
    p_duration_minutes := 90;
  end if;

  v_locked_until := (p_booking_date::text || ' ' || p_booking_time::text)::timestamptz
                    + interval '30 minutes';

  v_new_start := extract(hour from p_booking_time)::integer * 60
               + extract(minute from p_booking_time)::integer;
  v_new_end   := v_new_start + p_duration_minutes;

  select t.id, t.table_number
  into   v_table_id, v_table_number
  from   public.restaurant_tables t
  where  t.branch_id = p_branch_id
    and  t.status    = 'available'
    and  t.capacity  >= p_guest_count
    and  not exists (
      select 1
      from public.bookings b
      where b.table_id     = t.id
        and b.booking_date = p_booking_date
        and b.id           <> p_booking_id
        and b.status in ('pending', 'confirmed', 'seated')
        and v_new_start < (
              extract(hour from b.booking_time)::integer * 60
              + extract(minute from b.booking_time)::integer
              + coalesce(b.duration_minutes, 90)
            )
        and v_new_end > (
              extract(hour from b.booking_time)::integer * 60
              + extract(minute from b.booking_time)::integer
            )
    )
  order  by t.capacity asc
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
  set    status           = 'confirmed',
         table_id         = v_table_id,
         duration_minutes = p_duration_minutes,
         updated_at       = now()
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
