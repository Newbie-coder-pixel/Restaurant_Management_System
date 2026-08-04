-- Final cleanup: the reset in 20260805020000 was itself verified with one
-- more live RPC call (to confirm it actually returned 1, not a leftover
-- value) — which, correctly, burned that "1". Resetting Second Branch back
-- to 0 once more, and this time NOT re-verifying with another call, so
-- today's actual first order there is the one that gets to consume "1".
update public.daily_order_counters
set last_number = 0
where order_date = (now() at time zone 'Asia/Jakarta')::date
  and branch_id = 'da09e7b8-554e-4201-b303-ab2d1c791700'; -- Second Branch
