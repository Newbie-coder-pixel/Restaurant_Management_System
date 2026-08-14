-- ═══════════════════════════════════════════════════════════════════════════
-- Rotating per-table QR access tokens — 2026-08-14
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Staff app: table_management/table_qr_codes_screen.dart lets staff generate
-- and print/export a QR code per table that opens the customer-facing QR
-- app at `/qr/<tableId>?t=<token>`. Previously (see qr_order_repository.dart
-- fetchTableInfo) the tableId alone WAS the entire access mechanism — no
-- token, no expiry — so a customer who scanned/bookmarked a table's QR link
-- could keep reopening it indefinitely, including the next day, since a
-- table's UUID never changes.
--
-- Design: the token is deterministic, not stored per-table as a static
-- value — it's `hmac(table_id || issued_date_WIB || qr_epoch, server_secret)`
-- truncated to 32 hex chars. Consequences of that:
--   * It rotates automatically every day at midnight WIB purely because
--     `issued_date_WIB` changes — no cron job / scheduled task needed, and
--     nothing to miss/fail if one didn't run. A token computed for
--     yesterday's date will never match today's expected token again.
--   * `qr_epoch` (new int column on restaurant_tables, default 0) lets staff
--     force-invalidate the CURRENT day's code early (e.g. it was
--     photographed/shared publicly) via regenerate_qr_token(), which bumps
--     the epoch — every previously issued/printed code for that table stops
--     validating immediately, without waiting for the date to roll over.
--   * The server_secret lives in Supabase Vault, never sent to any client.
--     Only two narrow, purpose-built RPCs touch it:
--       - qr_token_for_table(uuid)  → staff-only, returns today's token (so
--         the staff app can render/print the current QR).
--       - regenerate_qr_token(uuid) → staff-only, bumps the epoch and
--         returns the new token.
--       - validate_qr_token(uuid, text) → anon-callable, returns boolean
--         ONLY (never the expected token), used by the customer QR app to
--         gate entry to QrMenuScreen.
--     The actual HMAC computation (_qr_token_compute) is intentionally NOT
--     granted to anon/authenticated at all — Postgres grants EXECUTE on new
--     functions to PUBLIC by default, so this is an explicit revoke, not
--     just an omission, to stop anon from computing valid tokens itself by
--     calling the internal function directly via PostgREST.
--
-- Known limitation (not fixed here — flagged, not silently ignored): the
-- `anon_insert_app_orders` RLS policy (20260724000000_price_integrity.sql)
-- still lets anon insert an `orders` row with ANY table_id, regardless of
-- whether that client ever presented a valid QR token. This migration closes
-- the "can the customer app be *opened*" gap (the literal ask), not the
-- separate pre-existing "can `table_id` be spoofed on an insert" gap — that
-- would need the client to carry its validated token through to the order
-- insert and an RLS check against it, which is a bigger change intentionally
-- left for a follow-up.
-- ═══════════════════════════════════════════════════════════════════════════

alter table public.restaurant_tables
  add column if not exists qr_epoch integer not null default 0;

-- ── One-time secret, stored in Vault (never exposed to any client) ─────────
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'qr_hmac_secret') then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'hex'),
      'qr_hmac_secret',
      'HMAC key for rotating table QR access tokens (see 20260814020000 migration)'
    );
  end if;
end $$;

-- ── Internal: pure computation, deliberately NOT exposed as an RPC ─────────
create or replace function public._qr_token_compute(p_table_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_secret  text;
  v_epoch   integer;
  v_date    text;
  v_payload text;
begin
  select decrypted_secret into v_secret
  from vault.decrypted_secrets
  where name = 'qr_hmac_secret';

  if v_secret is null then
    raise exception 'qr_hmac_secret not configured';
  end if;

  select qr_epoch into v_epoch
  from public.restaurant_tables
  where id = p_table_id;

  if v_epoch is null then
    raise exception 'Table not found';
  end if;

  v_date    := to_char((now() at time zone 'Asia/Jakarta')::date, 'YYYY-MM-DD');
  v_payload := p_table_id::text || '|' || v_date || '|' || v_epoch::text;

  return left(
    encode(extensions.hmac(v_payload::bytea, v_secret::bytea, 'sha256'), 'hex'),
    32
  );
end;
$function$;

revoke execute on function public._qr_token_compute(uuid) from public;

-- ── Staff: read today's token for a table (to render/print its QR) ────────
create or replace function public.qr_token_for_table(p_table_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not exists (
    select 1 from public.staff where user_id = auth.uid() and is_active
  ) then
    raise exception 'Not authorized';
  end if;

  return public._qr_token_compute(p_table_id);
end;
$function$;

revoke execute on function public.qr_token_for_table(uuid) from public;
grant execute on function public.qr_token_for_table(uuid) to authenticated;

-- ── Staff: force-invalidate the currently issued/printed code early ───────
create or replace function public.regenerate_qr_token(p_table_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not exists (
    select 1 from public.staff where user_id = auth.uid() and is_active
  ) then
    raise exception 'Not authorized';
  end if;

  update public.restaurant_tables
  set    qr_epoch   = qr_epoch + 1,
         updated_at = now()
  where  id = p_table_id;

  if not found then
    raise exception 'Table not found';
  end if;

  return public._qr_token_compute(p_table_id);
end;
$function$;

revoke execute on function public.regenerate_qr_token(uuid) from public;
grant execute on function public.regenerate_qr_token(uuid) to authenticated;

-- ── Anon (and staff): check whether a scanned/bookmarked link is still ────
-- today's valid code for that table. Returns a bare boolean — never the
-- expected token — so a caller can't use this to fish for the real value.
create or replace function public.validate_qr_token(p_table_id uuid, p_token text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if p_token is null or length(p_token) = 0 then
    return false;
  end if;
  return public._qr_token_compute(p_table_id) = p_token;
exception when others then
  return false;
end;
$function$;

revoke execute on function public.validate_qr_token(uuid, text) from public;
grant execute on function public.validate_qr_token(uuid, text) to anon, authenticated;
