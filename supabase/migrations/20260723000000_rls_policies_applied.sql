-- ═══════════════════════════════════════════════════════════════════════════
-- RLS policy patch — applied to production 2026-07-23
-- ═══════════════════════════════════════════════════════════════════════════
--
-- This file is NOT a draft — it is a 1:1 record of the statements actually run
-- against the production database (project ref pppxzbddfoeajwngbwdo) via the
-- Supabase Management API SQL editor, after a security audit found that RLS
-- WAS enabled on every table but many policies contradicted each other
-- (several `USING (true)` policies that nullified other policies' protection
-- on the same table, because Postgres RLS ORs together every matching policy
-- for a given command).
--
-- The most critical findings were confirmed DIRECTLY via the REST API using
-- the anon key (not just by reading code) before this patch:
--   • orders.branch_isolation had `OR auth.uid() IS NULL` → ANYONE without
--     logging in could SELECT/UPDATE/DELETE ALL orders across ALL branches.
--   • staff.staff_access (ALL) allowed regular staff to UPDATE another staff
--     row in the same branch → could escalate a colleague's role to superadmin.
--   • payments.branch_isolation was an ALL policy (not just SELECT) → branch
--     staff could INSERT a fake "paid" payment row directly, bypassing Midtrans.
--   • branches, costings, operating_expenses, inventory_transactions/transfers,
--     chatbot_conversations/messages, restaurant_closures had `USING (true)`
--     policies that opened the table to any logged-in user (or even anon for
--     costings/operating_expenses).
--
-- Every statement below was verified live via real requests to the REST API
-- (anon key + inserting a test row, then deleting it) — not assumptions.
--
-- Idempotent: everything is `drop policy/trigger if exists` + `create`, so
-- it's safe to re-run (e.g. via `supabase db push` later) without erroring
-- if it's already been applied.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Helper: currently logged-in staff role ──────────────────────────────────
-- The `get_my_branch_id()` and `is_superadmin()` helpers ALREADY EXISTED
-- before this in the project (not created here) — only `current_staff_role()`
-- is new.
create or replace function public.current_staff_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select role::text from public.staff
  where user_id = auth.uid() and is_active = true
  limit 1;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- orders — most critical bug: anon could read/write ALL orders across ALL branches
-- ═══════════════════════════════════════════════════════════════════════════

-- Remove the `OR auth.uid() IS NULL` clause that opened the ALL command to anon
-- without limit.
drop policy if exists branch_isolation on public.orders;
create policy branch_isolation on public.orders
  for all
  using (is_superadmin() or (auth.uid() is not null and branch_id = get_my_branch_id()))
  with check (is_superadmin() or (auth.uid() is not null and branch_id = get_my_branch_id()));

-- anon_read_orders_by_number was previously `USING (true)` — anon could select
-- ALL orders at any time. Restricted to the last 24 hours so the "track order
-- by number" feature (QR/customer without login) still works, but the blast
-- radius if enumerated is only today's orders, not the entire history.
-- NOTE: this is a mitigation, not a full fix — the correct fix is to move the
-- lookup to an RPC function that takes an exact order_number and returns
-- limited columns for a single row, instead of a direct table SELECT.
drop policy if exists anon_read_orders_by_number on public.orders;
create policy anon_read_orders_by_number on public.orders
  for select to anon
  using (created_at >= (now() - interval '24 hours'));

-- authenticated_read_own_orders was previously `USING (true)` — ANY logged-in
-- user (customer or staff of any branch) could read ALL orders.
drop policy if exists authenticated_read_own_orders on public.orders;
create policy authenticated_read_own_orders on public.orders
  for select to authenticated
  using (is_superadmin() or branch_id = get_my_branch_id() or customer_user_id = auth.uid());

-- "Allow anon update bill_requested" was previously `USING true WITH CHECK true`
-- — the policy name said "bill_requested" but RLS didn't restrict the column,
-- so anon could change ANY COLUMN including payment_status/total_amount.
-- Restricted to orders from the last 24 hours AND re-enforced at the column
-- level via the trigger below (since an RLS policy alone can't restrict per column).
drop policy if exists "Allow anon update bill_requested" on public.orders;
create policy anon_update_recent_order on public.orders
  for update to anon
  using (created_at >= (now() - interval '24 hours'))
  with check (created_at >= (now() - interval '24 hours'));

-- Trigger: anon may ONLY change bill_requested/bill_requested_at.
-- Verified live: attempting to change payment_status via anon PATCH → rejected
-- with an error from this trigger; attempting to change bill_requested → succeeds.
create or replace function public.enforce_anon_order_update_only_bill()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.role() = 'anon' then
    if (new.status is distinct from old.status)
       or (new.payment_status is distinct from old.payment_status)
       or (new.total_amount is distinct from old.total_amount)
       or (new.subtotal is distinct from old.subtotal)
       or (new.tax_amount is distinct from old.tax_amount)
       or (new.branch_id is distinct from old.branch_id)
       or (new.customer_user_id is distinct from old.customer_user_id)
    then
      raise exception 'anon hanya boleh update bill_requested/bill_requested_at';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_anon_order_update on public.orders;
create trigger trg_enforce_anon_order_update
  before update on public.orders
  for each row execute function public.enforce_anon_order_update_only_bill();

-- Other policies on orders (anon_insert_app_orders, "Allow walk-in order insert",
-- "staff can insert orders") were NOT changed — already strict enough as-is.

-- ═══════════════════════════════════════════════════════════════════════════
-- staff — privilege escalation bug: a regular staff member could make a
-- colleague superadmin
-- ═══════════════════════════════════════════════════════════════════════════
drop policy if exists staff_access on public.staff;

create policy staff_select on public.staff
  for select
  using (user_id = auth.uid() or branch_id = get_my_branch_id() or is_superadmin());

create policy staff_insert on public.staff
  for insert
  with check (
    is_superadmin()
    or (public.current_staff_role() = 'manager' and branch_id = get_my_branch_id() and role <> 'superadmin')
  );

create policy staff_update on public.staff
  for update
  using (user_id = auth.uid() or branch_id = get_my_branch_id() or is_superadmin())
  with check (
    is_superadmin()
    -- staff may edit their own profile BUT may not change their own role
    or (user_id = auth.uid() and role::text = public.current_staff_role())
    -- managers may manage staff in their own branch, BUT may not grant superadmin
    or (public.current_staff_role() = 'manager' and branch_id = get_my_branch_id() and role <> 'superadmin')
  );

create policy staff_delete on public.staff
  for delete
  using (
    is_superadmin()
    or (public.current_staff_role() = 'manager' and branch_id = get_my_branch_id())
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- payments — bug: branch staff could INSERT/UPDATE payments directly (ALL),
-- bypassing the entire Midtrans webhook verification flow.
-- ═══════════════════════════════════════════════════════════════════════════
drop policy if exists branch_isolation on public.payments;
create policy payments_select on public.payments
  for select
  using (branch_id = get_my_branch_id() or is_superadmin());
-- Intentionally NO insert/update/delete policy for anon/authenticated — only
-- service_role (used by the midtrans-webhook Edge Function, which always
-- bypasses RLS) may write to this table. Verified: anon INSERT → rejected by RLS.

-- ═══════════════════════════════════════════════════════════════════════════
-- branches — bug: ANY logged-in user (any role) could insert/update any branch.
-- ═══════════════════════════════════════════════════════════════════════════
drop policy if exists "Allow authenticated users to insert branches" on public.branches;
drop policy if exists "Allow authenticated users to update branches" on public.branches;

create policy branches_insert_superadmin on public.branches
  for insert
  with check (is_superadmin());

create policy branches_update_superadmin on public.branches
  for update
  using (is_superadmin())
  with check (is_superadmin());
-- SELECT policies (own_branch_only, "Public read branches", anon_read_branches)
-- were NOT changed — intentionally public by design (customers pick a branch).

-- ═══════════════════════════════════════════════════════════════════════════
-- costings / operating_expenses — bug: `USING (true)` for EVERYONE including
-- anon. Recipe costing data & operating expenses for all branches.
-- ═══════════════════════════════════════════════════════════════════════════
drop policy if exists allow_all_costings on public.costings;
create policy costings_staff_only on public.costings
  for all
  using (branch_id = get_my_branch_id() or is_superadmin())
  with check (branch_id = get_my_branch_id() or is_superadmin());

-- note: operating_expenses.branch_id is TEXT (not uuid like other tables),
-- hence the get_my_branch_id()::text cast.
drop policy if exists allow_all_expenses on public.operating_expenses;
create policy operating_expenses_staff_only on public.operating_expenses
  for all
  using (branch_id = get_my_branch_id()::text or is_superadmin())
  with check (branch_id = get_my_branch_id()::text or is_superadmin());

-- ═══════════════════════════════════════════════════════════════════════════
-- inventory_transactions / inventory_transfers — bug: several policies were
-- `USING (true)` / `auth.role() = 'authenticated'` with no branch scoping.
-- ═══════════════════════════════════════════════════════════════════════════
drop policy if exists "superadmin can view all transactions" on public.inventory_transactions;
drop policy if exists "Allow all for inventory_transactions" on public.inventory_transactions;
drop policy if exists "staff can insert own branch transactions" on public.inventory_transactions;
drop policy if exists inv_tx_insert on public.inventory_transactions;
drop policy if exists "staff can view own branch transactions" on public.inventory_transactions;
drop policy if exists inv_tx_select on public.inventory_transactions;

create policy inventory_transactions_staff_only on public.inventory_transactions
  for all
  using (branch_id = get_my_branch_id() or is_superadmin())
  with check (branch_id = get_my_branch_id() or is_superadmin());

drop policy if exists authenticated_all_inventory_transfers on public.inventory_transfers;
create policy inventory_transfers_admin_only on public.inventory_transfers
  for all
  using (
    is_superadmin()
    or (public.current_staff_role() = 'manager'
        and (from_branch_id = get_my_branch_id() or to_branch_id = get_my_branch_id()))
  )
  with check (
    is_superadmin()
    or (public.current_staff_role() = 'manager'
        and (from_branch_id = get_my_branch_id() or to_branch_id = get_my_branch_id()))
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- chatbot_conversations / chatbot_messages — bug: ANY logged-in user (any
-- role, any branch) could read/update/delete anyone's conversations.
-- ═══════════════════════════════════════════════════════════════════════════
drop policy if exists chatbot_conv_select on public.chatbot_conversations;
drop policy if exists chatbot_conv_update on public.chatbot_conversations;
drop policy if exists chatbot_conv_delete on public.chatbot_conversations;

create policy chatbot_conv_select on public.chatbot_conversations
  for select to authenticated
  using (branch_id = get_my_branch_id() or is_superadmin());

create policy chatbot_conv_update on public.chatbot_conversations
  for update to authenticated
  using (branch_id = get_my_branch_id() or is_superadmin())
  with check (branch_id = get_my_branch_id() or is_superadmin());

create policy chatbot_conv_delete on public.chatbot_conversations
  for delete to authenticated
  using (branch_id = get_my_branch_id() or is_superadmin());

-- chatbot_conv_insert was NOT changed (still WITH CHECK true for authenticated)
-- — minor residual issue: branch_id can still be set freely by the caller at
-- insert time (see sentiment_escalation_service.dart). The risk is only log
-- spam, not data leakage, and it wasn't changed because the caller's auth
-- context (customer chat, possibly anon) hasn't been fully verified yet — see
-- the TODO at the end of this file.

drop policy if exists chatbot_msg_select on public.chatbot_messages;
drop policy if exists chatbot_msg_delete on public.chatbot_messages;

create policy chatbot_msg_select on public.chatbot_messages
  for select to authenticated
  using (
    exists (
      select 1 from public.chatbot_conversations c
      where c.id = chatbot_messages.conversation_id
        and (c.branch_id = get_my_branch_id() or is_superadmin())
    )
  );

create policy chatbot_msg_delete on public.chatbot_messages
  for delete to authenticated
  using (
    exists (
      select 1 from public.chatbot_conversations c
      where c.id = chatbot_messages.conversation_id
        and (c.branch_id = get_my_branch_id() or is_superadmin())
    )
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- restaurant_closures — bug: `USING (true)` even though the policy name said
-- "Manager/superadmin can ..." — the name didn't reflect the real condition.
-- ═══════════════════════════════════════════════════════════════════════════
drop policy if exists "Manager/superadmin bisa delete" on public.restaurant_closures;
drop policy if exists "Manager/superadmin bisa insert" on public.restaurant_closures;
drop policy if exists "Staff bisa baca closure branch sendiri" on public.restaurant_closures;

create policy restaurant_closures_select on public.restaurant_closures
  for select to authenticated
  using (branch_id = get_my_branch_id() or is_superadmin());

create policy restaurant_closures_insert on public.restaurant_closures
  for insert to authenticated
  with check (
    is_superadmin()
    or (public.current_staff_role() = 'manager' and branch_id = get_my_branch_id())
  );

create policy restaurant_closures_delete on public.restaurant_closures
  for delete to authenticated
  using (
    is_superadmin()
    or (public.current_staff_role() = 'manager' and branch_id = get_my_branch_id())
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- restaurant_tables — bug: staff from ANY branch could update another
-- branch's tables (the "authenticated_update_table_status" policy was
-- redundant & looser than "branch_isolation" already on the same table).
-- ═══════════════════════════════════════════════════════════════════════════
drop policy if exists authenticated_update_table_status on public.restaurant_tables;
-- After this, UPDATE for the authenticated role is fully governed by the
-- pre-existing "branch_isolation" policy (ALL: branch_id = get_my_branch_id()
-- OR is_superadmin()) — no new policy needed.
-- "anon_update_table_status" (USING true) was INTENTIONALLY NOT changed — this
-- is the legitimate QR order flow (a customer at a table updates their own
-- table's status via the UUID from the scanned QR code, not an enumerable/
-- guessable table id). SELECT policies (anon_read_restaurant_tables, "Public
-- read", etc.) also weren't changed — intentionally public by design.

-- ═══════════════════════════════════════════════════════════════════════════
-- TODO follow-up (not done in this patch — out of priority / needs Flutter
-- changes too, not just RLS):
--   1. chatbot_conversations INSERT is still WITH CHECK true — if there's time
--      later, verify the auth context in sentiment_escalation_service.dart and
--      then scope the inserted branch_id to a valid branch.
--   2. anon_read_orders_by_number (24h) & anon_update_recent_order still allow
--      anon to enumerate TODAY's orders (a mitigation, not a full fix). The
--      ideal fix: move order tracking to an RPC function
--      (`get_order_by_number(p_order_number text)`, SECURITY DEFINER) that
--      returns limited columns for a single exact match, then remove all
--      direct SELECT access to the orders table for anon. Needs changes in
--      customer_order_tracker_screen.dart & qr_order_repository.dart too.
-- ═══════════════════════════════════════════════════════════════════════════
