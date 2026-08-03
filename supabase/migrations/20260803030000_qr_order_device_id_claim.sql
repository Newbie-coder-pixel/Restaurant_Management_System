-- ═══════════════════════════════════════════════════════════════════════════
-- QR order device_id: allow one-time claim, block hijack — 2026-08-03
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Reported bug: a customer refreshed the QR order tracker for an order they
-- had just placed and were told "Only the device that placed this order can
-- add items to it" — on the SAME device. Root cause confirmed live: that
-- order (925b418f..., queue A001, created 2026-08-03 01:05:14 UTC) was
-- placed a few minutes BEFORE the device-lock feature (commit bf0060b,
-- deployed 2026-08-03 01:47:57 UTC) went live, so its device_id column was
-- never populated at insert time — the client code that writes device_id
-- didn't exist yet when this order was created. Every QR order created
-- before that deploy has device_id = null (confirmed: all of the 15 most
-- recent QR orders in the live table have device_id null), so the
-- device-lock UI correctly refuses to treat any device as the owner for
-- them — there's no way to tell who placed a legacy order — which is safe
-- but permanently locks out real customers from orders that predate the
-- column being populated.
--
-- Fix (paired with a Flutter change in this same commit): let the first
-- device that opens an ownerless order (device_id IS NULL) claim it by
-- writing its device_id once, exactly like it would have been written at
-- insert time.
--
-- While reviewing enforce_anon_order_update_only_bill (added in
-- 20260723000000_rls_policies_applied.sql) to add this, found it does NOT
-- currently restrict device_id at all — an anon REST call could already
-- overwrite device_id on ANY order, including one that already has an
-- owner, and silently steal ownership of somebody else's in-progress QR
-- order. Tightened it here at the same time: anon may only set device_id
-- while it is still NULL (the claim case); changing an already-set
-- device_id is blocked, same as status/payment_status/totals.
-- ═══════════════════════════════════════════════════════════════════════════

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
       or (old.device_id is not null and new.device_id is distinct from old.device_id)
    then
      raise exception 'anon hanya boleh update bill_requested/bill_requested_at, atau claim device_id yang masih kosong';
    end if;
  end if;
  return new;
end;
$$;
