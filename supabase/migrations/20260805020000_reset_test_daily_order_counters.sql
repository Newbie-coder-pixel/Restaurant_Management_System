-- ═══════════════════════════════════════════════════════════════════════════
-- One-time data cleanup: reset today's counter after live-testing it
-- ═══════════════════════════════════════════════════════════════════════════
--
-- While verifying next_daily_order_number() actually works in production
-- (see 20260805000000, 20260805010000), it was called directly ~20 times
-- against two real branches to prove atomicity/isolation — no orders were
-- created, but each call still burned a real sequence number. Left as-is,
-- today's first genuine order at these branches would show e.g. "A019"
-- instead of "A001", contradicting the entire point of this feature.
-- Resetting last_number back to 0 for TODAY only (order_date is a primary
-- key column, so this can't affect any other day, past or future).
-- ═══════════════════════════════════════════════════════════════════════════

update public.daily_order_counters
set last_number = 0
where order_date = (now() at time zone 'Asia/Jakarta')::date
  and branch_id in (
    '27fb221d-e59c-464a-86fc-9c7f19627beb', -- Main Branch
    'da09e7b8-554e-4201-b303-ab2d1c791700'  -- Second Branch
  );
