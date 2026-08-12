-- Order creation in menu_item_selector.dart / customer_checkout_screen.dart /
-- qr_order_repository.dart inserts the `orders` row, then `order_items` in a
-- separate client call. If the items insert fails (network drop, validation
-- error), the order row was already committed with zero items and nothing
-- could clean it up client-side — 374 such orphaned orders were found in
-- production, invisible everywhere in the UI (every screen filters on
-- items.isNotEmpty) but still counted as "active" in dashboards.
--
-- The app code now marks the order 'cancelled' as a compensating action when
-- the items insert fails. Staff (branch_isolation, an ALL policy) and anon/QR
-- customers (anon_update_recent_order) already have UPDATE rights that cover
-- this. Authenticated customer-app users had no UPDATE policy on `orders` at
-- all, so this adds one scoped to their own order, shortly after creation —
-- mirrors anon_update_recent_order's recency window but additionally requires
-- true ownership via customer_user_id, since customers (unlike anon QR
-- sessions) are identifiable.
create policy customer_update_own_recent_order on public.orders
  for update
  to authenticated
  using (customer_user_id = auth.uid() and created_at >= now() - interval '1 hour')
  with check (customer_user_id = auth.uid() and created_at >= now() - interval '1 hour');
