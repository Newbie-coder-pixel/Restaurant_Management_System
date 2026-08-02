-- ═══════════════════════════════════════════════════════════════════════════
-- Price integrity patch — applied to production 2026-07-24
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Follow-up to 20260723000000_rls_policies_applied.sql. Closes a critical
-- finding not touched by the previous patch: order prices (QR orders and
-- other paths) are computed in Flutter and trusted as-is on insert into
-- `orders`/`order_items`, with no server-side validation against the real
-- menu prices.
--
-- Root cause confirmed by reading the code (qr_order_repository.dart) + live
-- testing against the REST API with the anon key:
--   • order_items.unit_price is taken from the menu object on the Flutter
--     side, NOT re-looked-up against menu_items.price on the server.
--   • orders.subtotal/tax_amount/total_amount are also computed in Flutter
--     during the initial INSERT (before order_items exist), so nothing on
--     the server ever matches the total to what's actually in the cart.
--   • midtrans-create-token (Edge Function, not previously in the repo,
--     downloaded from the project for the first time as part of this patch)
--     fetches order.total_amount from the DB but NEVER used it to validate
--     the client-sent `gross_amount` — the client's gross_amount was used
--     as-is to create the Midtrans transaction.
--
-- All fixes below have been tested live: inserting an order with a forged
-- total_amount of Rp1, then order_items with a unit_price of Rp1 → REJECTED
-- with a clear error ("total_amount tidak boleh lebih kecil dari subtotal..").
-- Inserting an order with the correct total (QR formula: subtotal + 3%
-- service charge + 10% PB1) → still succeeds normally, no regression.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. order_items: force unit_price = the real menu_items price ───────────
-- subtotal is GENERATED ALWAYS (unit_price * quantity) — once unit_price is
-- correct, subtotal is automatically correct too and cannot be manipulated by
-- the client at all (Postgres rejects inserting a value into a generated column).
create or replace function public.enforce_order_item_true_price()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  true_price numeric;
begin
  select price into true_price from public.menu_items where id = new.menu_item_id;
  if true_price is not null then
    new.unit_price := true_price;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_order_item_true_price on public.order_items;
create trigger trg_enforce_order_item_true_price
before insert or update on public.order_items
for each row execute function public.enforce_order_item_true_price();

-- ── 2. Whenever order_items change → recompute orders.subtotal from the SUM ─
-- of the real items (which is now guaranteed correct thanks to trigger #1).
-- set_config('app.trusted_recompute', ...) marks this UPDATE as a trusted
-- system update, so it isn't blocked by the enforce_anon_order_update_only_bill
-- trigger (see previous migration) which restricts anon to only changing the
-- bill_requested column — without this flag, the automatic subtotal update
-- would get blocked even for HONEST QR orders, not just forged ones.
create or replace function public.recompute_order_subtotal()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  affected_order_id uuid;
  new_subtotal numeric;
begin
  affected_order_id := coalesce(new.order_id, old.order_id);
  select coalesce(sum(subtotal), 0) into new_subtotal
    from public.order_items where order_id = affected_order_id;
  perform set_config('app.trusted_recompute', 'true', true);
  update public.orders set subtotal = new_subtotal, updated_at = now()
    where id = affected_order_id;
  return null;
end;
$$;

drop trigger if exists trg_recompute_order_subtotal on public.order_items;
create trigger trg_recompute_order_subtotal
after insert or update or delete on public.order_items
for each row execute function public.recompute_order_subtotal();

-- Update the anon trigger to allow the trusted-recompute update above.
create or replace function public.enforce_anon_order_update_only_bill()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if auth.role() = 'anon' and coalesce(current_setting('app.trusted_recompute', true), 'false') <> 'true' then
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

-- ── 3. Sanity bound: total_amount must not be < subtotal - discount ────────
-- This doesn't try to replicate the exact tax/service-charge formula (there
-- are at least 2 different formulas across order paths — see
-- qr_cart_provider.dart vs customer/providers/cart_provider.dart — so a
-- universal trigger that fully recomputes total_amount risks using the wrong
-- formula for one of the paths and breaking legitimate orders). Instead, it's
-- enough to ensure total_amount is never smaller than the subtotal (now
-- guaranteed honest) minus the discount — tax/service charge/overtime fees
-- are all ADDITIVE, so this invariant is safe for every order type.
create or replace function public.enforce_order_total_sanity()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.total_amount is not null and new.subtotal is not null then
    if new.total_amount < (new.subtotal - coalesce(new.discount_amount, 0) - 1) then
      raise exception 'total_amount (%) tidak boleh lebih kecil dari subtotal dikurangi diskon (%)',
        new.total_amount, (new.subtotal - coalesce(new.discount_amount, 0));
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_order_total_sanity on public.orders;
create trigger trg_enforce_order_total_sanity
before insert or update on public.orders
for each row execute function public.enforce_order_total_sanity();

-- ── 4. Fix a pre-existing bug (unrelated to this audit): order_type ────────
-- 'qr_order' was never in the list of order_types RLS allowed anon to insert,
-- so real QR orders were likely failing in production before this patch
-- (found by accident while testing the trigger above).
drop policy if exists anon_insert_app_orders on public.orders;
create policy anon_insert_app_orders on public.orders
  for insert to anon
  with check (order_type = any (array['app_order', 'takeaway', 'walk_in', 'qr_order']));

-- ═══════════════════════════════════════════════════════════════════════════
-- Edge Functions also fixed in this same patch (see the respective files in
-- supabase/functions/ — downloaded from the project for the first time here
-- because they weren't previously in the repo at all):
--
--   • midtrans-create-token/index.ts — previously fetched order.total_amount
--     from the DB but never used it for validation; now rejects (400) if the
--     client-sent `gross_amount` doesn't match the real total_amount in the
--     DB (Rp1 rounding tolerance). CORS is also restricted via
--     ALLOWED_ORIGINS (previously "*").
--
--   • create-staff-user/index.ts — previously did NOT verify the caller AT
--     ALL; role & branchId from the request body were trusted as-is, so any
--     staff role could create a new superadmin account. Now:
--       - a valid Authorization header with a real user session is required
--         (verified via supabaseAdmin.auth.getUser)
--       - the caller must be an active staff member with role superadmin/manager
--       - a manager may not create a superadmin account
--       - a manager may only create staff within their own branch_id
--     Tested: a request with no Authorization header → 401; a request using
--     the anon key as a Bearer token (not a real user session) → also rejected.
--     CORS is restricted via ALLOWED_ORIGINS.
-- ═══════════════════════════════════════════════════════════════════════════
