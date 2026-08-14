-- ═══════════════════════════════════════════════════════════════════════════
-- Bind QR order inserts to a valid table QR token — 2026-08-14
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Follow-up to 20260814020000_table_qr_rotation.sql. That migration made
-- QrMenuScreen (the entry point) refuse to *load* without a valid, current
-- token for the table — but it never touched the `anon_insert_app_orders`
-- RLS policy (20260724000000_price_integrity.sql), which lets `anon` insert
-- an `orders` row with ANY `table_id` and no token at all. In other words:
-- the UI gate could be entirely bypassed by calling
-- POST /rest/v1/orders directly with order_type='qr_order' and any
-- table_id — including a stale/expired one, or one belonging to a
-- different branch/table than whatever QR was actually scanned (or never
-- scanned at all).
--
-- Fix: add `orders.qr_access_token` (nullable — only meaningful for
-- order_type='qr_order') and require, at INSERT time only, that
-- validate_qr_token(table_id, qr_access_token) is true whenever
-- order_type='qr_order'. Other order_types (app_order/takeaway/walk_in)
-- are untouched — they aren't table-scoped the same way and weren't part
-- of this gap.
--
-- Deliberately NOT re-checked on UPDATE (anon_update_recent_order): the
-- token that validated at creation proves the customer had a legitimate,
-- currently-valid code the moment the order was placed — like a session
-- cookie, it shouldn't need to keep re-validating on every subsequent
-- request against an order that already exists. Re-checking on update would
-- actively break legitimate in-progress orders that cross the midnight WIB
-- rollover (bill_requested, status polling, etc. on an order placed at
-- 23:50 would start failing at 00:00 even though nothing about the order
-- itself is illegitimate) — re-validating only at creation avoids that
-- regression while still closing the actual spoofing gap.
--
-- `qr_access_token` is intentionally left OUT of the anon column-level
-- SELECT grant (20260805060000_fix_orders_column_revoke.sql) — anon can
-- write it once at insert time but never read it back; column-level GRANT
-- SELECT is an explicit allowlist, so simply not adding it there is
-- sufficient, no revoke needed.
-- ═══════════════════════════════════════════════════════════════════════════

alter table public.orders
  add column if not exists qr_access_token text;

drop policy if exists anon_insert_app_orders on public.orders;
create policy anon_insert_app_orders on public.orders
  for insert to anon
  with check (
    order_type = any (array['app_order', 'takeaway', 'walk_in', 'qr_order'])
    and (
      order_type <> 'qr_order'
      or (
        table_id is not null
        and public.validate_qr_token(table_id, qr_access_token)
      )
    )
  );
