-- ═══════════════════════════════════════════════════════════════════════════
-- QR self-order device lock
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Prior fix (ee25ed3, "Prevent disconnected duplicate QR orders at the same
-- table") only warned when a table already had an active order, but still let
-- any browser dismiss the warning and start a second, independent order for
-- the same table ("Start a separate order"). That doesn't match how this
-- restaurant wants QR ordering to work: one active order per table should be
-- owned by whichever browser/device created it, and every other device
-- scanning that table's QR should be forced to finish/pay from the original
-- device rather than being able to add items or start a new order.
--
-- device_id is a random UUID the client generates once and persists in
-- browser localStorage (via shared_preferences) — see
-- lib/features/qr_order/services/qr_device_id_service.dart. It has no
-- relation to auth.uid(), since QR customers are anonymous.
-- ═══════════════════════════════════════════════════════════════════════════

alter table public.orders
  add column if not exists device_id text;

comment on column public.orders.device_id is
  'Client-generated UUID persisted in the ordering browser''s localStorage. '
  'Used by QrMenuScreen to tell whether the device scanning a table''s QR is '
  'the same one that opened the table''s current active order.';
