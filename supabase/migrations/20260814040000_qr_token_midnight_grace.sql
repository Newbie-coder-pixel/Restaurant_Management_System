-- ═══════════════════════════════════════════════════════════════════════════
-- Small grace window around the WIB midnight token rollover — 2026-08-14
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Known limitation flagged when 20260814020000_table_qr_rotation.sql shipped:
-- a party still mid-visit right at the midnight WIB boundary who reloads/
-- reopens the QR menu link a few seconds after 00:00 would see the
-- "expired" screen even though nothing about their visit is illegitimate —
-- purely because the date component of the token just changed.
--
-- Fix: validate_qr_token() now also accepts YESTERDAY's token, but only
-- during the first 15 minutes after midnight WIB. This is a narrow overlap
-- window, not "yesterday's code still works all day" — outside those 15
-- minutes, only today's token validates, same as before.
--
-- _qr_token_compute(uuid) is generalized into _qr_token_compute_for_date
-- (uuid, date) so both "today" and "yesterday" can be computed without
-- duplicating the HMAC/secret-lookup logic. qr_token_for_table() and
-- regenerate_qr_token() are untouched — staff should only ever be shown
-- TODAY's canonical code, never a grace-window blend.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public._qr_token_compute_for_date(p_table_id uuid, p_date date)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_secret  text;
  v_epoch   integer;
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

  v_payload := p_table_id::text || '|' || to_char(p_date, 'YYYY-MM-DD') || '|' || v_epoch::text;

  return left(
    encode(extensions.hmac(v_payload::bytea, v_secret::bytea, 'sha256'), 'hex'),
    32
  );
end;
$function$;

revoke execute on function public._qr_token_compute_for_date(uuid, date) from public;

create or replace function public._qr_token_compute(p_table_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  return public._qr_token_compute_for_date(
    p_table_id,
    (now() at time zone 'Asia/Jakarta')::date
  );
end;
$function$;

revoke execute on function public._qr_token_compute(uuid) from public;

create or replace function public.validate_qr_token(p_table_id uuid, p_token text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_now_wib timestamp;
begin
  if p_token is null or length(p_token) = 0 then
    return false;
  end if;

  v_now_wib := now() at time zone 'Asia/Jakarta';

  if public._qr_token_compute_for_date(p_table_id, v_now_wib::date) = p_token then
    return true;
  end if;

  -- Grace window: first 15 minutes past midnight WIB also accept yesterday's
  -- token, so an in-progress visit isn't forced to re-scan the instant the
  -- date rolls over.
  if extract(hour from v_now_wib) = 0 and extract(minute from v_now_wib) < 15 then
    if public._qr_token_compute_for_date(p_table_id, (v_now_wib::date - 1)) = p_token then
      return true;
    end if;
  end if;

  return false;
exception when others then
  return false;
end;
$function$;

revoke execute on function public.validate_qr_token(uuid, text) from public;
grant execute on function public.validate_qr_token(uuid, text) to anon, authenticated;
