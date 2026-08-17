-- ═══════════════════════════════════════════════════════════════════════════
-- Idempotently ensure order_events/table_events/orders/order_items are in
-- the supabase_realtime publication — 2026-08-17
-- ═══════════════════════════════════════════════════════════════════════════
--
-- 20260808000000_order_events_notification_system.sql and
-- 20260814000000_table_events_customer_reported.sql each end with a bare
-- `alter publication supabase_realtime add table ...`, and both explicitly
-- flag the risk in their own comments: a Studio dashboard toggle can add a
-- table to the publication outside of any migration, with no migration
-- history recording it. If that had already happened before either
-- migration ran, `add table` throws "42710: relation already member of
-- publication" instead of no-op'ing — and since a migration file runs in
-- one transaction, that error would roll back everything else in the same
-- file (the order_events/table_events tables + their triggers/RLS
-- policies), silently leaving realtime delivery for that table dependent
-- on whatever the dashboard toggle happened to be at the time, with no
-- record of it in migration history either way.
--
-- Symptom this produces: order_events/table_events rows insert fine (the
-- trigger doesn't care about the publication), staff can even SELECT them
-- directly, but no `postgres_changes` INSERT event ever reaches connected
-- clients for that table — so the in-app banner (order_notification_
-- overlay.dart) and its chime (order_sound_service.dart) never fire, even
-- though the order itself shows up fine via the KDS's own periodic re-fetch
-- (kds_screen.dart's _subscribeRealtime() `_load()` callback on `orders`/
-- `order_items`, which are a separate publication membership).
--
-- This migration checks pg_publication_tables first and only ALTERs when a
-- table is actually missing, so it can be re-run safely regardless of
-- whatever combination of dashboard toggles and prior migrations already
-- got each table into the publication.
do $$
declare
  t text;
begin
  foreach t in array array['orders', 'order_items', 'order_events', 'table_events']
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
