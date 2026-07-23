-- ═══════════════════════════════════════════════════════════════════════════
-- Price integrity patch — diterapkan ke production 2026-07-24
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Lanjutan dari 20260723000000_rls_policies_applied.sql. Menutup temuan
-- kritis yang belum disentuh di patch sebelumnya: harga order (QR order dan
-- jalur lain) dihitung di Flutter dan dipercaya mentah-mentah saat insert ke
-- `orders`/`order_items`, tanpa validasi ke harga menu asli di server.
--
-- Root cause yang dikonfirmasi lewat baca kode (qr_order_repository.dart) +
-- test langsung ke REST API pakai anon key:
--   • order_items.unit_price diambil dari objek menu di sisi Flutter, BUKAN
--     di-lookup ulang ke menu_items.price di server.
--   • orders.subtotal/tax_amount/total_amount juga dihitung di Flutter saat
--     INSERT awal (sebelum order_items ada), jadi tidak ada apa pun di server
--     yang mencocokkan totalnya ke isi keranjang sebenarnya.
--   • midtrans-create-token (Edge Function, tidak ada di repo sebelumnya,
--     di-download dari project untuk pertama kali di patch ini) fetch
--     order.total_amount dari DB tapi TIDAK PERNAH memakainya untuk
--     memvalidasi `gross_amount` yang dikirim client — gross_amount client
--     dipakai mentah-mentah untuk membuat transaksi Midtrans.
--
-- Semua fix di bawah sudah dites langsung: insert order dengan total_amount
-- dipalsukan Rp1 lalu order_items dengan unit_price Rp1 → DITOLAK dengan
-- error jelas ("total_amount tidak boleh lebih kecil dari subtotal..").
-- Insert order dengan total yang benar (formula QR: subtotal + 3% service
-- charge + 10% PB1) → tetap berhasil normal, tidak ada regresi.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. order_items: paksa unit_price = harga asli menu_items ────────────────
-- subtotal adalah GENERATED ALWAYS (unit_price * quantity) — begitu unit_price
-- benar, subtotal otomatis ikut benar, tidak bisa dimanipulasi client sama
-- sekali (Postgres menolak insert value ke generated column).
create or replace function public.enforce_order_item_true_price()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  true_price numeric;
begin
  select price into true_price from public.menu_items where id = new.menu_item_id;
  if true_price is not null then
    new.unit_price := true_price;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_order_item_true_price on public.order_items;
create trigger trg_enforce_order_item_true_price
before insert or update on public.order_items
for each row execute function public.enforce_order_item_true_price();

-- ── 2. Setiap order_items berubah → recompute orders.subtotal dari SUM ──────
-- item asli (yang sekarang sudah pasti benar berkat trigger #1).
-- set_config('app.trusted_recompute', ...) menandai UPDATE ini sebagai update
-- terpercaya dari sistem, supaya tidak diblokir oleh trigger
-- enforce_anon_order_update_only_bill (lihat migration sebelumnya) yang
-- membatasi anon cuma boleh ubah kolom bill_requested — tanpa flag ini,
-- update subtotal otomatis akan ikut diblokir untuk order QR yang JUJUR
-- sekalipun, bukan cuma yang dipalsukan.
create or replace function public.recompute_order_subtotal()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  affected_order_id uuid;
  new_subtotal numeric;
begin
  affected_order_id := coalesce(new.order_id, old.order_id);
  select coalesce(sum(subtotal), 0) into new_subtotal
    from public.order_items where order_id = affected_order_id;
  perform set_config('app.trusted_recompute', 'true', true);
  update public.orders set subtotal = new_subtotal, updated_at = now()
    where id = affected_order_id;
  return null;
end;
$$;

drop trigger if exists trg_recompute_order_subtotal on public.order_items;
create trigger trg_recompute_order_subtotal
after insert or update or delete on public.order_items
for each row execute function public.recompute_order_subtotal();

-- Update trigger anon supaya mengizinkan update trusted-recompute di atas.
create or replace function public.enforce_anon_order_update_only_bill()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if auth.role() = 'anon' and coalesce(current_setting('app.trusted_recompute', true), 'false') <> 'true' then
    if (new.status is distinct from old.status)
       or (new.payment_status is distinct from old.payment_status)
       or (new.total_amount is distinct from old.total_amount)
       or (new.subtotal is distinct from old.subtotal)
       or (new.tax_amount is distinct from old.tax_amount)
       or (new.branch_id is distinct from old.branch_id)
       or (new.customer_user_id is distinct from old.customer_user_id)
    then
      raise exception 'anon hanya boleh update bill_requested/bill_requested_at';
    end if;
  end if;
  return new;
end;
$$;

-- ── 3. Sanity bound: total_amount tidak boleh < subtotal - diskon ───────────
-- Tidak mencoba mereplikasi formula pajak/service-charge persis (ada minimal
-- 2 formula berbeda antar jalur order — lihat qr_cart_provider.dart vs
-- customer/providers/cart_provider.dart — jadi trigger universal yang
-- menghitung ulang total_amount penuh berisiko salah formula untuk salah satu
-- jalur dan merusak order yang sah). Sebagai gantinya cukup pastikan
-- total_amount tidak pernah lebih kecil dari subtotal (yang sekarang sudah
-- pasti jujur) dikurangi diskon — pajak/service charge/biaya overtime semua
-- SIFATNYA NAMBAH, jadi invariant ini aman untuk semua jenis order.
create or replace function public.enforce_order_total_sanity()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.total_amount is not null and new.subtotal is not null then
    if new.total_amount < (new.subtotal - coalesce(new.discount_amount, 0) - 1) then
      raise exception 'total_amount (%) tidak boleh lebih kecil dari subtotal dikurangi diskon (%)',
        new.total_amount, (new.subtotal - coalesce(new.discount_amount, 0));
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_order_total_sanity on public.orders;
create trigger trg_enforce_order_total_sanity
before insert or update on public.orders
for each row execute function public.enforce_order_total_sanity();

-- ── 4. Fix bug pra-existing (tidak berkaitan dengan audit ini): order_type ──
-- 'qr_order' tidak pernah ada di daftar order_type yang diizinkan RLS insert
-- untuk anon, jadi QR order sungguhan kemungkinan gagal di production
-- sebelum patch ini (ditemukan tidak sengaja saat menguji trigger di atas).
drop policy if exists anon_insert_app_orders on public.orders;
create policy anon_insert_app_orders on public.orders
  for insert to anon
  with check (order_type = any (array['app_order', 'takeaway', 'walk_in', 'qr_order']));

-- ═══════════════════════════════════════════════════════════════════════════
-- Edge Functions yang ikut diperbaiki di patch yang sama (lihat file masing-
-- masing di supabase/functions/ — didownload dari project untuk pertama kali
-- karena sebelumnya tidak ada di repo sama sekali):
--
--   • midtrans-create-token/index.ts — sebelumnya fetch order.total_amount
--     dari DB tapi tidak pernah memakainya untuk validasi; sekarang menolak
--     (400) kalau gross_amount yang dikirim client tidak cocok dengan
--     total_amount asli di DB (toleransi Rp1 pembulatan). CORS juga dibatasi
--     lewat ALLOWED_ORIGINS (sebelumnya "*").
--
--   • create-staff-user/index.ts — sebelumnya SAMA SEKALI TIDAK memverifikasi
--     siapa pemanggilnya; role & branchId dari body dipercaya mentah-mentah,
--     jadi staff role apa pun bisa membuat akun superadmin baru. Sekarang:
--       - wajib ada Authorization header dengan sesi user yang valid
--         (diverifikasi via supabaseAdmin.auth.getUser)
--       - caller wajib staff aktif dengan role superadmin/manager
--       - manager tidak boleh membuat akun role superadmin
--       - manager cuma boleh membuat staff di branch_id miliknya sendiri
--     Sudah dites: request tanpa Authorization header → 401; request dengan
--     anon key sebagai Bearer token (bukan sesi user asli) → ditolak juga.
--     CORS dibatasi lewat ALLOWED_ORIGINS.
-- ═══════════════════════════════════════════════════════════════════════════
