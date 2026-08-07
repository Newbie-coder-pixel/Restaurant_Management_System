-- ═══════════════════════════════════════════════════════════════════════════
-- Wire order_events INSERT -> order-event-notify edge function — 2026-08-08
-- ═══════════════════════════════════════════════════════════════════════════
--
-- This is the equivalent of clicking "Create a new hook" in Studio ->
-- Database -> Webhooks, done in SQL so it's version-controlled instead of
-- living only as unaudited dashboard state. It's a plpgsql trigger (rather
-- than the simpler supabase_functions.http_request(...) trigger form the
-- dashboard normally generates) specifically so the shared auth secret can
-- be pulled from Supabase Vault at call time instead of being embedded as a
-- literal string in this file — this file is committed to a git repo with
-- other real contributors, so no secret value may appear in it.
--
-- Setup performed once, outside this migration (via the Management API,
-- not committed anywhere): `select vault.create_secret(<random-hex>,
-- 'order_event_webhook_secret', ...)`, and the SAME value set as the
-- deployed order-event-notify function's ORDER_EVENT_WEBHOOK_SECRET secret
-- (`supabase secrets set`). This trigger and that function only agree
-- because both read the same Vault-stored/env-stored value — no value is
-- ever written to a tracked file.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.notify_order_event_webhook()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  webhook_secret text;
begin
  select decrypted_secret into webhook_secret
    from vault.decrypted_secrets
    where name = 'order_event_webhook_secret'
    limit 1;

  perform net.http_post(
    url := 'https://pppxzbddfoeajwngbwdo.supabase.co/functions/v1/order-event-notify',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', coalesce(webhook_secret, '')
    ),
    body := jsonb_build_object(
      'type', 'INSERT',
      'table', 'order_events',
      'schema', 'public',
      'record', to_jsonb(new)
    )
  );

  return new;
end;
$$;

drop trigger if exists trg_order_events_push_webhook on public.order_events;
create trigger trg_order_events_push_webhook
  after insert on public.order_events
  for each row
  execute function public.notify_order_event_webhook();
