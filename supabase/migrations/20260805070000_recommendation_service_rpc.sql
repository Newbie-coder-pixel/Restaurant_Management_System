-- ═══════════════════════════════════════════════════════════════════════════
-- Lock down recommendation_service.dart's branch-wide order_items reads
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Different risk tier from the PII leak fixed in 20260805040000/050000/060000
-- (order_items has no customer name/phone/email at all) — but the same
-- underlying shape of problem: recommendation_service.dart ran 4 different
-- raw `.from('order_items').select(...)` queries reachable with no login,
-- one of which (_getPopularItems) is explicitly branch-wide with NO
-- per-customer scoping by design. Anyone could call these directly via REST
-- with broader filters than the app itself ever sends and scrape branch-wide
-- order/menu-popularity data.
--
-- Fix mirrors the same approach as the orders/order_items lockdown: 4 new
-- SECURITY DEFINER RPCs that reproduce the EXACT SAME filters the Dart code
-- already applies (branch_id, status='paid', a time cutoff, optionally
-- customer_user_id) — the scoring/ranking logic stays in Dart, unchanged;
-- only the raw row access moves server-side so a direct REST call can't ask
-- for anything broader than what these functions allow.
-- ═══════════════════════════════════════════════════════════════════════════

-- Layers 1 & 2's seed step: this customer's own paid order items in a
-- branch, since a cutoff date. (_getPersonalRecommendations, _getCustomerFavorites)
create or replace function public.get_customer_order_items(
  p_branch_id uuid,
  p_customer_user_id uuid,
  p_since timestamptz
)
returns table(menu_item_id uuid, menu_item_name text, quantity int)
language sql security definer set search_path = '' as $$
  select oi.menu_item_id, oi.menu_item_name, oi.quantity
  from public.order_items oi
  join public.orders o on o.id = oi.order_id
  where o.branch_id = p_branch_id
    and o.customer_user_id = p_customer_user_id
    and o.status = 'paid'
    and o.created_at >= p_since;
$$;

grant execute on function public.get_customer_order_items(uuid, uuid, timestamptz) to anon, authenticated;

-- Layer 2a (_getCollaborativeRecommendations): which orders contain any of
-- the seed menu items, within a branch/time window.
create or replace function public.get_orders_containing_items(
  p_branch_id uuid,
  p_menu_item_ids uuid[],
  p_since timestamptz
)
returns table(order_id uuid)
language sql security definer set search_path = '' as $$
  select distinct oi.order_id
  from public.order_items oi
  join public.orders o on o.id = oi.order_id
  where oi.menu_item_id = any(p_menu_item_ids)
    and o.branch_id = p_branch_id
    and o.status = 'paid'
    and o.created_at >= p_since;
$$;

grant execute on function public.get_orders_containing_items(uuid, uuid[], timestamptz) to anon, authenticated;

-- Layer 2b (_getCollaborativeRecommendations): the other items in those
-- specific orders, excluding the seed items themselves.
create or replace function public.get_items_in_orders(
  p_order_ids uuid[],
  p_exclude_menu_item_ids uuid[]
)
returns table(menu_item_id uuid, menu_item_name text, quantity int)
language sql security definer set search_path = '' as $$
  select oi.menu_item_id, oi.menu_item_name, oi.quantity
  from public.order_items oi
  where oi.order_id = any(p_order_ids)
    and not (oi.menu_item_id = any(p_exclude_menu_item_ids));
$$;

grant execute on function public.get_items_in_orders(uuid[], uuid[]) to anon, authenticated;

-- Layer 3 (_getPopularItems): branch-wide by design, no customer scoping —
-- still bounded to a branch + time window, not an unrestricted table scan.
create or replace function public.get_branch_popular_items(
  p_branch_id uuid,
  p_since timestamptz
)
returns table(menu_item_id uuid, menu_item_name text, quantity int)
language sql security definer set search_path = '' as $$
  select oi.menu_item_id, oi.menu_item_name, oi.quantity
  from public.order_items oi
  join public.orders o on o.id = oi.order_id
  where o.branch_id = p_branch_id
    and o.status = 'paid'
    and o.created_at >= p_since;
$$;

grant execute on function public.get_branch_popular_items(uuid, timestamptz) to anon, authenticated;
