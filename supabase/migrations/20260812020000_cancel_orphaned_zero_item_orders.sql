-- One-time cleanup for orders left orphaned by the non-atomic order/order_items
-- insert (see migration 20260812010000): 374 orders in active statuses with
-- zero order_items were found in production — 342 from a single burst on
-- 2026-05-17 (load-test/demo data, given the generic customer names and
-- multi-second cadence), the rest scattered in ones and twos across many
-- other dates through 2026-08-03 (genuine occurrences of the race). None of
-- them are actionable (nothing to prepare/pay for), and all were already
-- invisible in every screen (every screen filters on items.isNotEmpty) —
-- this just corrects their status so branch dashboards stop counting them
-- as "active".
update public.orders o
set status = 'cancelled',
    cancel_reason = 'Cleanup: order had zero items (orphaned by non-atomic insert, fixed in app)'
where o.status in ('new', 'created', 'paid', 'preparing', 'ready', 'served')
  and not exists (
    select 1 from public.order_items oi where oi.order_id = o.id
  );
