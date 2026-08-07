-- ═══════════════════════════════════════════════════════════════════════════
-- Add per-item spice level choices and paid add-ons to menu_items
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Both are optional per item (null/empty = no picker shown on the customer
-- item-detail screen, which is the existing behavior for every current row).
--
--   spice_levels: jsonb array of plain option labels, e.g.
--     '["Mild (Standard)", "Medium", "Pedas (Spicy)"]'
--
--   add_ons: jsonb array of {"name": "...", "price": number} objects, e.g.
--     '[{"name": "Extra Nasi Putih", "price": 15000}, {"name": "Sambal Ijo Porsi", "price": 20000}]'
--     price is a flat Rupiah amount added per unit of the add-on selected,
--     not per order line.
--
-- Neither is a normalized table (no menu_add_ons/menu_spice_levels join
-- tables) since these are small, item-owned option lists that are always
-- read/written as a whole with their parent menu item, matching how
-- allergens/dietary_labels already work on this table.
-- ═══════════════════════════════════════════════════════════════════════════

alter table public.menu_items
  add column if not exists spice_levels jsonb not null default '[]'::jsonb,
  add column if not exists add_ons      jsonb not null default '[]'::jsonb;

comment on column public.menu_items.spice_levels is
  'Array of spice-level option labels (text). Empty = no spice picker for this item.';
comment on column public.menu_items.add_ons is
  'Array of {name, price} paid add-on objects. Empty = no add-ons for this item.';
