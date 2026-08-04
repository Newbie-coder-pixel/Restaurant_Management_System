-- ═══════════════════════════════════════════════════════════════════════════
-- Fix: the previous column-level revoke didn't actually take effect
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Verified live right after 20260805050000 shipped: the exact same "dump
-- customer_phone/customer_email with no filter" call from before STILL
-- returned them. `revoke select (customer_phone, customer_email) on
-- public.orders from anon` is a no-op when the underlying grant that
-- actually lets anon read the table was made `TO PUBLIC` (Supabase's
-- default schema-exposure grants typically target PUBLIC, not each role by
-- name) — every role, including anon, inherits whatever PUBLIC can do, so
-- revoking from anon specifically left the PUBLIC-level access untouched.
--
-- Fix: revoke SELECT on the whole table from BOTH anon and PUBLIC, then
-- explicitly re-grant SELECT on every column EXCEPT customer_phone/
-- customer_email to anon. This reproduces today's anon-visible column set
-- exactly, minus the two PII columns — nothing else changes.
-- ═══════════════════════════════════════════════════════════════════════════

revoke select on public.orders from anon;
revoke select on public.orders from public;

-- Staff (`authenticated`) access to `orders` is gated by RLS (branch_isolation
-- etc.), not by column restriction — if that access was ALSO only coming
-- through the PUBLIC grant just revoked above, staff would lose all read
-- access to orders entirely. Re-grant full-table SELECT to authenticated
-- explicitly so this migration can't regress staff features (KDS, cashier,
-- reports) regardless of how the original grant was set up.
grant select on public.orders to authenticated;

grant select (
  id, branch_id, booking_id, staff_id, cashier_id, order_number, status, source,
  customer_name, subtotal, discount_amount, tax_amount, total_amount, notes,
  created_at, updated_at, cancel_reason, cancelled_by, queue_number, table_name,
  items, payment_status, payment_method, order_type, table_id, customer_user_id,
  pb1_amount, service_charge_amount, estimated_prep_minutes, bill_requested,
  bill_requested_at, midtrans_snap_token, midtrans_redirect_url,
  midtrans_transaction_id, midtrans_order_id, served_at, device_id
) on public.orders to anon;
