-- ═══════════════════════════════════════════════════════════════════════════
-- Attendance: self-service GPS clock-in/out + RLS hardening
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Context: `attendance` has never had a tracked migration, RLS policy, or
-- unique constraint in this repo (unlike `staff`/`orders`/`payments`, which
-- got a hardening pass in 20260723000000_rls_policies_applied.sql after a
-- real privilege-escalation incident). The "manager-only" gate on
-- staff_attendance_screen.dart is UI-only — without RLS, any authenticated
-- staff member could plausibly write arbitrary attendance rows for anyone via
-- the REST API. This migration:
--   1. Adds provenance/audit columns + a geofence radius on branches.
--   2. De-dupes any existing (staff_id, date) collisions, then enforces
--      uniqueness.
--   3. Enables RLS on `attendance`, scoping manual manager writes to their
--      own branch (mirrors the staff_insert/staff_update policy idiom).
--   4. Adds two SECURITY DEFINER RPCs (clock_in/clock_out) as the ONLY path
--      for a staff member to write their own attendance — same idiom as the
--      `payments` table (no direct insert/update policy; writes only via a
--      privileged path), since GPS distance validation can't be expressed as
--      a plain RLS USING/WITH CHECK clause.
--
-- Idempotent: `drop ... if exists` / `add column if not exists` throughout,
-- safe to re-run via `supabase db push`.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Branches: configurable per-branch check-in geofence radius ─────────────
alter table public.branches
  add column if not exists checkin_radius_meters integer not null default 150;

-- ── Attendance: provenance / audit columns ──────────────────────────────────
alter table public.attendance
  add column if not exists created_by uuid references auth.users(id),
  add column if not exists updated_by uuid references auth.users(id),
  add column if not exists source text not null default 'manual',
  add column if not exists clock_in_lat double precision,
  add column if not exists clock_in_lng double precision;

alter table public.attendance drop constraint if exists attendance_source_check;
alter table public.attendance add constraint attendance_source_check
  check (source = any (array['manual', 'self_service']::text[]));

-- ── De-dup existing (staff_id, date) collisions before enforcing uniqueness ─
-- Keeps the lowest `id` per (staff_id, date); safe no-op if there are none.
with ranked as (
  select id,
         row_number() over (partition by staff_id, date order by id) as rn
  from public.attendance
)
delete from public.attendance
where id in (select id from ranked where rn > 1);

drop index if exists attendance_staff_date_unique;
create unique index attendance_staff_date_unique
  on public.attendance (staff_id, date);

-- ── Enable RLS ───────────────────────────────────────────────────────────────
-- RLS was already ON with exactly one policy: attendance_branch_isolation
-- (FOR ALL USING (branch_id = get_my_branch_id() OR is_superadmin()), no
-- WITH CHECK — verified live via the Management API). That's the same bug
-- class fixed elsewhere in 20260723000000_rls_policies_applied.sql: it lets
-- ANY authenticated staff member (not just managers) insert/update/delete
-- attendance for anyone in their branch, not just their own row. Since RLS
-- policies for a command are OR'd together, this MUST be dropped — otherwise
-- it would keep granting access underneath the new, correctly-scoped
-- policies below.
alter table public.attendance enable row level security;
drop policy if exists attendance_branch_isolation on public.attendance;

drop policy if exists attendance_select on public.attendance;
drop policy if exists attendance_insert on public.attendance;
drop policy if exists attendance_update on public.attendance;
drop policy if exists attendance_delete on public.attendance;

create policy attendance_select on public.attendance
  for select
  using (
    is_superadmin()
    or branch_id = get_my_branch_id()
    or staff_id = (select id from public.staff where user_id = auth.uid())
  );

-- Manual entry stays a direct client insert/update/delete (existing
-- staff_attendance_screen.dart code), now actually restricted to
-- manager/superadmin of the row's own branch instead of being UI-only.
create policy attendance_insert on public.attendance
  for insert
  with check (
    is_superadmin()
    or (public.current_staff_role() = 'manager' and branch_id = get_my_branch_id())
  );

create policy attendance_update on public.attendance
  for update
  using (
    is_superadmin()
    or (public.current_staff_role() = 'manager' and branch_id = get_my_branch_id())
  )
  with check (
    is_superadmin()
    or (public.current_staff_role() = 'manager' and branch_id = get_my_branch_id())
  );

create policy attendance_delete on public.attendance
  for delete
  using (
    is_superadmin()
    or (public.current_staff_role() = 'manager' and branch_id = get_my_branch_id())
  );

-- Intentionally NO self-service insert/update policy for staff_id = auth.uid()
-- — the only path for a staff member to touch their own row is the RPCs
-- below (SECURITY DEFINER, explicit ownership + distance checks in-body).

-- ═══════════════════════════════════════════════════════════════════════════
-- clock_in / clock_out RPCs
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.clock_in(p_lat double precision, p_lng double precision)
returns public.attendance
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_staff record;
  v_branch record;
  v_distance_m double precision;
  v_row public.attendance;
begin
  select id, branch_id into v_staff
  from public.staff
  where user_id = auth.uid() and is_active = true
  limit 1;

  if v_staff.id is null then
    raise exception 'No active staff record found for the current user';
  end if;
  if v_staff.branch_id is null then
    raise exception 'Your staff record has no assigned branch';
  end if;

  select latitude, longitude, checkin_radius_meters into v_branch
  from public.branches
  where id = v_staff.branch_id;

  if v_branch.latitude is null or v_branch.longitude is null then
    raise exception 'Your branch has no location configured; contact a manager';
  end if;

  -- Haversine distance in meters (mirrors LocationService.calculateDistance)
  v_distance_m := 6371000 * 2 * asin(sqrt(
    sin(radians(v_branch.latitude - p_lat) / 2) ^ 2 +
    cos(radians(p_lat)) * cos(radians(v_branch.latitude)) *
    sin(radians(v_branch.longitude - p_lng) / 2) ^ 2
  ));

  if v_distance_m > v_branch.checkin_radius_meters then
    raise exception 'You are % m from your branch — clock-in requires being within % m',
      round(v_distance_m)::int, v_branch.checkin_radius_meters;
  end if;

  begin
    insert into public.attendance (
      staff_id, branch_id, date, status, clock_in,
      source, created_by, clock_in_lat, clock_in_lng
    ) values (
      v_staff.id, v_staff.branch_id, current_date, 'present', now(),
      'self_service', auth.uid(), p_lat, p_lng
    )
    returning * into v_row;
  exception when unique_violation then
    raise exception 'Attendance already recorded for today — contact your manager to correct it';
  end;

  return v_row;
end;
$$;

grant execute on function public.clock_in(double precision, double precision) to authenticated;

create or replace function public.clock_out(p_lat double precision, p_lng double precision)
returns public.attendance
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_staff record;
  v_branch record;
  v_distance_m double precision;
  v_row public.attendance;
begin
  select id, branch_id into v_staff
  from public.staff
  where user_id = auth.uid() and is_active = true
  limit 1;

  if v_staff.id is null then
    raise exception 'No active staff record found for the current user';
  end if;

  select latitude, longitude, checkin_radius_meters into v_branch
  from public.branches
  where id = v_staff.branch_id;

  if v_branch.latitude is not null and v_branch.longitude is not null then
    v_distance_m := 6371000 * 2 * asin(sqrt(
      sin(radians(v_branch.latitude - p_lat) / 2) ^ 2 +
      cos(radians(p_lat)) * cos(radians(v_branch.latitude)) *
      sin(radians(v_branch.longitude - p_lng) / 2) ^ 2
    ));
    if v_distance_m > v_branch.checkin_radius_meters then
      raise exception 'You are % m from your branch — clock-out requires being within % m',
        round(v_distance_m)::int, v_branch.checkin_radius_meters;
    end if;
  end if;

  update public.attendance
  set clock_out = now(), updated_by = auth.uid()
  where staff_id = v_staff.id
    and date = current_date
    and source = 'self_service'
    and clock_in is not null
    and clock_out is null
  returning * into v_row;

  if v_row.id is null then
    raise exception 'No open self-service clock-in found for today';
  end if;

  return v_row;
end;
$$;

grant execute on function public.clock_out(double precision, double precision) to authenticated;
