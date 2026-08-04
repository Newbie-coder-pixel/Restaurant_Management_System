-- ═══════════════════════════════════════════════════════════════════════════
-- Enforce branch operating hours on order creation (anon/QR self-order)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Reported gap: the QR self-order flow (/qr/:tableId) never checked the
-- branch's opening_time/closing_time before allowing a menu view or order
-- insert. A customer who scans a table's QR once can keep that link/tab and
-- reopen it at any later time — including outside operating hours — and
-- still place an order, since nothing tied order creation to "is this branch
-- currently open".
--
-- The Flutter client now also checks this (qr_menu_screen.dart gates the
-- whole menu screen on it, and QrOrderRepository re-checks fresh right
-- before every order-creating write), but that's UX only — the anon key is
-- public (see CLAUDE.md), so a client-side check can always be skipped by
-- calling the REST API directly. This migration is the actual, unbypassable
-- gate: it runs in Postgres regardless of how the insert was made.
--
-- Deliberately scoped to auth.role() = 'anon' only — staff-created orders
-- (walk-in at the cashier, etc.) must NOT be blocked by this. Staff routinely
-- serve guests already seated right up to (and sometimes past) the nominal
-- closing time; that's an operational judgment call for a logged-in staff
-- member, not something this trigger should second-guess.
--
-- Timezone note: branch hours are local Indonesian time (see the "WIB"
-- labels throughout the customer/staff UI). now() in Postgres is UTC, so it's
-- converted via `at time zone 'Asia/Jakarta'` rather than trusting any
-- client-supplied timestamp — the whole point is that this must not depend
-- on anything the client controls.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.is_branch_open(p_branch_id uuid)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare
  v_opening time;
  v_closing time;
  v_now time;
begin
  select opening_time::time, closing_time::time
    into v_opening, v_closing
    from public.branches
    where id = p_branch_id;

  -- No hours configured for this branch → fail open (don't block orders for
  -- a branch that was never given hours; matches the Dart-side helpers,
  -- which also fail open when opening_time/closing_time is null).
  if v_opening is null or v_closing is null then
    return true;
  end if;

  v_now := (now() at time zone 'Asia/Jakarta')::time;

  if v_closing < v_opening then
    -- Overnight window, e.g. 10:00–01:00.
    return v_now >= v_opening or v_now < v_closing;
  end if;
  return v_now >= v_opening and v_now < v_closing;
end;
$$;

-- ── Gate 1: creating a brand-new order (the exact scenario reported) ───────
create or replace function public.enforce_branch_open_for_order_insert()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if auth.role() = 'anon'
     and new.branch_id is not null
     and not public.is_branch_open(new.branch_id)
  then
    raise exception 'Restoran sedang tutup, tidak bisa membuat pesanan baru saat ini';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_branch_open_for_order_insert on public.orders;
create trigger trg_enforce_branch_open_for_order_insert
before insert on public.orders
for each row execute function public.enforce_branch_open_for_order_insert();

-- ── Gate 2: adding items to an already-existing order (addItemsToOrder) ────
-- Covers a customer who placed a legitimate order while open, then keeps
-- adding items well past closing time on the same still-`created` order.
create or replace function public.enforce_branch_open_for_order_item_insert()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_branch_id uuid;
begin
  if auth.role() = 'anon' then
    select branch_id into v_branch_id from public.orders where id = new.order_id;
    if v_branch_id is not null and not public.is_branch_open(v_branch_id) then
      raise exception 'Restoran sedang tutup, tidak bisa menambah pesanan saat ini';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_branch_open_for_order_item_insert on public.order_items;
create trigger trg_enforce_branch_open_for_order_item_insert
before insert on public.order_items
for each row execute function public.enforce_branch_open_for_order_item_insert();
