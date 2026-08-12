-- inventory_service.rolloverDailyStock() upserts with
-- onConflict: 'branch_id,name,date', but inventory_items had no matching
-- unique constraint, so Postgres rejected the upsert with 42P10
-- ("no unique or exclusion constraint matching the ON CONFLICT specification"),
-- surfacing as an uncaught error when staff used the Daily Stock Rollover
-- dialog in the inventory screen.
alter table public.inventory_items
  add constraint inventory_items_branch_name_date_key
  unique (branch_id, name, date);
