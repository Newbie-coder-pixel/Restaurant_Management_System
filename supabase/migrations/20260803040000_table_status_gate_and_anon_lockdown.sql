-- ═══════════════════════════════════════════════════════════════════════════
-- Table status gate for QR ordering + anon restaurant_tables lockdown
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Feature request: when a customer scans a table's QR code, show that
-- table's current status first instead of going straight to the menu — if
-- staff marked it 'cleaning' or 'reserved', the customer should be told
-- (and able to flag staff) rather than silently being allowed to order at a
-- table that isn't actually ready. The staff app already enforces the
-- equivalent rule structurally: MenuItemSelector's table dropdown
-- (lib/features/order/presentation/widgets/menu_item_selector.dart) only
-- ever lists `status == available` tables — QR ordering had no such gate at
-- all, since there's no dropdown to filter; the "selection" is just
-- whichever physical QR the customer scanned.
--
-- `customer_reported_at` lets a customer flag from the QR gate screen that
-- a table doesn't match what they see in person (e.g. still dirty despite
-- showing available, or looks fine despite showing cleaning/reserved).
-- Cleared automatically the next time staff changes that table's status
-- (see table_screen.dart _updateStatus).
alter table public.restaurant_tables
  add column if not exists customer_reported_at timestamptz;

comment on column public.restaurant_tables.customer_reported_at is
  'Set when a customer flags via the QR ordering gate that this table''s '
  'real-world state doesn''t match its status. Cleared whenever staff next '
  'changes the table''s status.';

-- ── Close a gap found while building the above: anon_update_table_status ──
-- was `USING (true) WITH CHECK (true)` — completely unrestricted. Verified
-- live: an anon REST call could rewrite table_number, capacity, shape,
-- position, current_booking_id, locked_until, etc. on ANY table, not just
-- the `status` column the app's own code ever touches (QR order creation
-- only ever sets status='occupied' on insert). This also meant
-- current_booking_id/locked_until — the exact columns the booking-lock fix
-- in 20260803020000 added ownership checks for on the RPC path — could be
-- rewritten directly via a raw table UPDATE, bypassing those RPCs entirely.
-- Locked down with the same before-trigger pattern already used for
-- `orders` (enforce_anon_order_update_only_bill): anon may only move status
-- to 'occupied' (order creation) and/or set customer_reported_at (this
-- feature) — every other column, and every other status value, is blocked.
create or replace function public.enforce_anon_table_update()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if auth.role() = 'anon' then
    if new.branch_id is distinct from old.branch_id
       or new.table_number is distinct from old.table_number
       or new.capacity is distinct from old.capacity
       or new.shape is distinct from old.shape
       or new.position_x is distinct from old.position_x
       or new.position_y is distinct from old.position_y
       or new.floor_level is distinct from old.floor_level
       or new.is_mergeable is distinct from old.is_mergeable
       or new.notes is distinct from old.notes
       or new.current_booking_id is distinct from old.current_booking_id
       or new.locked_until is distinct from old.locked_until
    then
      raise exception 'anon hanya boleh mengubah status (ke occupied) atau customer_reported_at pada restaurant_tables';
    end if;
    if new.status is distinct from old.status and new.status <> 'occupied' then
      raise exception 'anon hanya boleh mengubah status meja menjadi occupied';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_anon_table_update on public.restaurant_tables;
create trigger trg_enforce_anon_table_update
before update on public.restaurant_tables
for each row execute function public.enforce_anon_table_update();
