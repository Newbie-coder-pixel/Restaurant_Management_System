-- ═══════════════════════════════════════════════════════════════════════════
-- DRAFT — Row Level Security policies
-- ═══════════════════════════════════════════════════════════════════════════
--
-- KENAPA FILE INI ADA:
-- Audit keamanan menemukan bahwa repo ini TIDAK PUNYA satu pun file migration
-- SQL — semua RLS (kalau ada) hanya hidup di dashboard Supabase live, tidak
-- versioned, tidak bisa direview. Ini draft awal supaya minimal ada definisi
-- policy yang bisa dibaca ulang, dibandingkan dengan yang aktif di dashboard,
-- dan dijadikan starting point.
--
-- ⚠️  JANGAN langsung `supabase db push` / jalankan file ini ke project
--     production tanpa:
--     1. Membandingkannya dulu dengan policy yang SUDAH aktif di dashboard
--        (Supabase Dashboard → Authentication → Policies, atau
--        `supabase db dump --schema-only` / `--data-only=false --role-only=false`
--        dari project yang sudah jalan) — supaya tidak menimpa/mengubah
--        perilaku yang saat ini sudah benar.
--     2. Menjalankannya dulu di project STAGING/duplikat, lalu tes ulang
--        SEMUA alur: staff login semua role, customer checkout, QR order,
--        booking, tracking order, laporan — pastikan tidak ada yang tiba-tiba
--        dapat "permission denied".
--     3. Menyesuaikan nama kolom/tabel di bawah dengan skema asli kamu — ini
--        disusun berdasarkan pembacaan kode Flutter (lib/**/*.dart), BUKAN
--        dump skema asli, jadi ada kemungkinan nama kolom sedikit meleset
--        untuk tabel yang jarang dipakai.
--
-- Prinsip yang dipakai di sini:
--   • Staff (anggota tabel `staff`, login via Supabase Auth) hanya boleh
--     baca/tulis data cabang (branch_id) miliknya sendiri, KECUALI superadmin
--     yang boleh semua cabang.
--   • Customer (login via Supabase Auth di app customer/QR) hanya boleh
--     baca/tulis baris miliknya sendiri (customer_user_id / user_id).
--   • Anon (belum login, dipakai QR self-order & tracking tanpa akun) dibatasi
--     seketat mungkin: cuma insert order miliknya sendiri di meja yang valid,
--     dan select terbatas untuk tracking (bukan select * ke semua kolom/baris).
--   • Semua mutasi status pembayaran HARUS lewat service_role (Edge Function
--     midtrans-webhook), bukan langsung dari client — client tidak diberi
--     hak UPDATE ke kolom payment_status/status pada `orders` maupun INSERT
--     ke `payments` sama sekali.
--
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Helper: role & branch staff yang sedang login ───────────────────────────
-- SECURITY DEFINER supaya tidak kena RLS tabel `staff` sendiri saat dipanggil
-- dari dalam policy tabel `staff` (mencegah infinite recursion / lock-out).
create or replace function public.current_staff_role()
returns text
language sql
security definer
stable
set search_path = public
as $$
  select role::text from staff where user_id = auth.uid() and is_active = true limit 1;
$$;

create or replace function public.current_staff_branch_id()
returns uuid
language sql
security definer
stable
set search_path = public
as $$
  select branch_id from staff where user_id = auth.uid() and is_active = true limit 1;
$$;

create or replace function public.is_superadmin()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select coalesce(public.current_staff_role() = 'superadmin', false);
$$;

create or replace function public.is_staff_of_branch(target_branch_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select public.is_superadmin()
      or public.current_staff_branch_id() = target_branch_id;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- staff
-- ═══════════════════════════════════════════════════════════════════════════
alter table public.staff enable row level security;

drop policy if exists staff_select on public.staff;
create policy staff_select on public.staff
  for select
  using (
    public.is_superadmin()
    or branch_id = public.current_staff_branch_id()
    or user_id = auth.uid()
  );

-- Insert/Update/Delete staff HANYA lewat Edge Function `create-staff-user`
-- (service_role, bypass RLS) — jangan buka insert/update langsung dari client
-- anon/authenticated supaya tidak ada jalur eskalasi role lewat REST API.
drop policy if exists staff_update_own_profile on public.staff;
create policy staff_update_own_profile on public.staff
  for update
  using (user_id = auth.uid())
  with check (
    user_id = auth.uid()
    -- staff TIDAK BOLEH mengubah role/branch_id/is_active miliknya sendiri —
    -- baris ini hanya untuk field profil non-sensitif (nama, foto, dst).
    -- Sesuaikan/enforce lebih ketat lewat trigger kalau perlu kolom spesifik.
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- branches — baca boleh semua staff aktif, tulis hanya superadmin
-- ═══════════════════════════════════════════════════════════════════════════
alter table public.branches enable row level security;

drop policy if exists branches_select_staff on public.branches;
create policy branches_select_staff on public.branches
  for select
  using (public.current_staff_role() is not null or auth.role() = 'anon');
  -- catatan: anon perlu SELECT terbatas untuk customer/QR pilih cabang —
  -- pertimbangkan bikin VIEW publik (nama, alamat, jam buka saja, TANPA
  -- kolom finansial kalau ada) daripada expose seluruh tabel ke anon.

drop policy if exists branches_write_superadmin on public.branches;
create policy branches_write_superadmin on public.branches
  for all
  using (public.is_superadmin())
  with check (public.is_superadmin());

-- ═══════════════════════════════════════════════════════════════════════════
-- orders — inti dari temuan audit (harga & kepemilikan)
-- ═══════════════════════════════════════════════════════════════════════════
alter table public.orders enable row level security;

drop policy if exists orders_select on public.orders;
create policy orders_select on public.orders
  for select
  using (
    public.is_staff_of_branch(branch_id)
    or customer_user_id = auth.uid()
    -- Anon/QR tracking by order_number ditangani di level APLIKASI dengan
    -- kolom yang dibatasi (lihat customer_order_tracker_screen.dart) — kalau
    -- mau anon bisa SELECT sama sekali, tambahkan baris berikut dan pastikan
    -- kamu tahu risikonya (order_number bisa ditebak/dienumerasi):
    -- or auth.role() = 'anon'
  );

-- Insert order dari QR/customer: HANYA boleh insert (bukan select bebas),
-- dan branch_id/table_id harus merujuk baris yang benar-benar ada & aktif.
drop policy if exists orders_insert_customer on public.orders;
create policy orders_insert_customer on public.orders
  for insert
  with check (
    public.is_staff_of_branch(branch_id)
    or (
      auth.role() in ('anon', 'authenticated')
      and exists (
        select 1 from public.restaurant_tables t
        where t.id = orders.table_id and t.branch_id = orders.branch_id
      )
    )
  );
  -- ⚠️  Ini TIDAK mencegah manipulasi subtotal/tax_amount/total_amount yang
  --     dikirim client (temuan audit #6 — QR order repository). RLS hanya
  --     bisa membatasi SIAPA yang boleh insert, bukan memvalidasi NILAI harga
  --     terhadap harga menu asli. Untuk menutup itu, tambahkan trigger
  --     BEFORE INSERT yang menghitung ulang subtotal/tax_amount/total_amount
  --     dari menu_items + order_items yang di-insert bersamaan (atau pindah
  --     proses insert order ke Edge Function service_role yang menghitung
  --     ulang harga dari DB, bukan dari client).

-- Update status/payment_status HANYA lewat service_role (Edge Function) —
-- staff boleh update baris cabangnya sendiri untuk operasional (ubah status
-- served/cancelled dari layar kasir/dapur), tapi TIDAK untuk payment_status.
drop policy if exists orders_update_staff on public.orders;
create policy orders_update_staff on public.orders
  for update
  using (public.is_staff_of_branch(branch_id))
  with check (public.is_staff_of_branch(branch_id));
  -- Kalau mau lebih ketat lagi: pisahkan hak update payment_status dari hak
  -- update status operasional pakai kolom-level privilege (GRANT ... (col)),
  -- karena RLS policy standar tidak bisa membedakan kolom mana yang diubah.

-- ═══════════════════════════════════════════════════════════════════════════
-- order_items
-- ═══════════════════════════════════════════════════════════════════════════
alter table public.order_items enable row level security;

drop policy if exists order_items_access on public.order_items;
create policy order_items_access on public.order_items
  for all
  using (
    exists (
      select 1 from public.orders o
      where o.id = order_items.order_id
        and (public.is_staff_of_branch(o.branch_id) or o.customer_user_id = auth.uid())
    )
  )
  with check (
    exists (
      select 1 from public.orders o
      where o.id = order_items.order_id
        and (public.is_staff_of_branch(o.branch_id) or o.customer_user_id = auth.uid())
    )
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- payments — HANYA service_role (Edge Function midtrans-webhook) yang boleh
-- insert/update. Staff boleh baca cabangnya sendiri untuk rekonsiliasi.
-- ═══════════════════════════════════════════════════════════════════════════
alter table public.payments enable row level security;

drop policy if exists payments_select_staff on public.payments;
create policy payments_select_staff on public.payments
  for select
  using (public.is_staff_of_branch(branch_id));

-- Sengaja TIDAK ada policy insert/update/delete untuk role anon/authenticated
-- — service_role selalu bypass RLS, jadi Edge Function midtrans-webhook tetap
-- bisa insert/update tanpa policy tambahan. Ini menutup total kemungkinan
-- client memalsukan/mengubah record payment langsung lewat REST API.

-- ═══════════════════════════════════════════════════════════════════════════
-- bookings
-- ═══════════════════════════════════════════════════════════════════════════
alter table public.bookings enable row level security;

drop policy if exists bookings_select on public.bookings;
create policy bookings_select on public.bookings
  for select
  using (
    public.is_staff_of_branch(branch_id)
    or customer_user_id = auth.uid()
  );

drop policy if exists bookings_insert on public.bookings;
create policy bookings_insert on public.bookings
  for insert
  with check (
    public.is_staff_of_branch(branch_id)
    or auth.role() in ('anon', 'authenticated')
  );

drop policy if exists bookings_update on public.bookings;
create policy bookings_update on public.bookings
  for update
  using (public.is_staff_of_branch(branch_id) or customer_user_id = auth.uid())
  with check (public.is_staff_of_branch(branch_id) or customer_user_id = auth.uid());

-- ═══════════════════════════════════════════════════════════════════════════
-- device_tokens — HANYA pemilik token, TIDAK BOLEH dibaca customer lain
-- (temuan audit: sentiment_escalation_service.dart membaca token manager
-- langsung dari client — ganti pemanggilan itu supaya lewat Edge Function
-- service_role, karena policy di bawah akan memblokir customer membaca token
-- staff manapun, termasuk untuk keperluan push notifikasi eskalasi).
-- ═══════════════════════════════════════════════════════════════════════════
alter table public.device_tokens enable row level security;

drop policy if exists device_tokens_owner_only on public.device_tokens;
create policy device_tokens_owner_only on public.device_tokens
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ═══════════════════════════════════════════════════════════════════════════
-- menu_items / menu_categories — data publik (perlu tampil di customer/QR
-- tanpa login), jadi SELECT dibuka ke semua (termasuk anon). Tulis hanya
-- staff cabang terkait.
-- ═══════════════════════════════════════════════════════════════════════════
alter table public.menu_items enable row level security;
alter table public.menu_categories enable row level security;

drop policy if exists menu_items_select_public on public.menu_items;
create policy menu_items_select_public on public.menu_items
  for select using (true);

drop policy if exists menu_items_write_staff on public.menu_items;
create policy menu_items_write_staff on public.menu_items
  for all
  using (public.is_staff_of_branch(branch_id))
  with check (public.is_staff_of_branch(branch_id));

drop policy if exists menu_categories_select_public on public.menu_categories;
create policy menu_categories_select_public on public.menu_categories
  for select using (true);

drop policy if exists menu_categories_write_staff on public.menu_categories;
create policy menu_categories_write_staff on public.menu_categories
  for all
  using (public.is_staff_of_branch(branch_id))
  with check (public.is_staff_of_branch(branch_id));

-- ═══════════════════════════════════════════════════════════════════════════
-- inventory_items / inventory_transactions / inventory_transfers — internal,
-- staff cabang terkait saja (TIDAK untuk anon/customer sama sekali).
-- ═══════════════════════════════════════════════════════════════════════════
alter table public.inventory_items enable row level security;
alter table public.inventory_transactions enable row level security;
alter table public.inventory_transfers enable row level security;

drop policy if exists inventory_items_staff_only on public.inventory_items;
create policy inventory_items_staff_only on public.inventory_items
  for all
  using (public.is_staff_of_branch(branch_id))
  with check (public.is_staff_of_branch(branch_id));

drop policy if exists inventory_transactions_staff_only on public.inventory_transactions;
create policy inventory_transactions_staff_only on public.inventory_transactions
  for all
  using (public.is_staff_of_branch(branch_id))
  with check (public.is_staff_of_branch(branch_id));

-- Transfer antar cabang: superadmin/manager saja (lintas branch_id), jadi
-- tidak dibatasi is_staff_of_branch biasa — sesuaikan kalau tabel ini punya
-- from_branch_id/to_branch_id, bukan branch_id tunggal.
drop policy if exists inventory_transfers_admin_only on public.inventory_transfers;
create policy inventory_transfers_admin_only on public.inventory_transfers
  for all
  using (public.current_staff_role() in ('superadmin', 'manager'))
  with check (public.current_staff_role() in ('superadmin', 'manager'));

-- ═══════════════════════════════════════════════════════════════════════════
-- restaurant_tables — perlu dibaca anon (QR scan perlu tahu meja valid),
-- tulis staff cabang terkait saja.
-- ═══════════════════════════════════════════════════════════════════════════
alter table public.restaurant_tables enable row level security;

drop policy if exists restaurant_tables_select_public on public.restaurant_tables;
create policy restaurant_tables_select_public on public.restaurant_tables
  for select using (true);

drop policy if exists restaurant_tables_write_staff on public.restaurant_tables;
create policy restaurant_tables_write_staff on public.restaurant_tables
  for all
  using (public.is_staff_of_branch(branch_id))
  with check (public.is_staff_of_branch(branch_id));

-- ═══════════════════════════════════════════════════════════════════════════
-- staff_password_reset_otps — HANYA service_role (Edge Function
-- staff-password-reset) yang boleh akses. Sengaja TIDAK ada policy untuk
-- anon/authenticated sama sekali supaya kode OTP tidak pernah bisa dibaca
-- langsung lewat REST API oleh siapa pun selain service_role.
-- ═══════════════════════════════════════════════════════════════════════════
alter table public.staff_password_reset_otps enable row level security;
-- (sengaja tanpa create policy apa pun untuk anon/authenticated)

-- ═══════════════════════════════════════════════════════════════════════════
-- TABEL LAIN yang dipakai app tapi BELUM ada policy di draft ini — audit
-- menemukan tabel-tabel ini juga dipakai langsung lewat anon key:
--   attendance, chatbot_conversations, customer_chat_sessions, customers,
--   menu_ingredients, menu_item_allergens, menu_item_dietary,
--   restaurant_closures, staff_login_history, staff_shifts
-- Aktifkan RLS untuk semua tabel ini juga (minimal `staff_of_branch` atau
-- `owner only` sesuai isinya) SEBELUM sidang — tabel tanpa RLS aktif di
-- Postgres yang bisa diakses PostgREST akan ke-return SEMUA baris ke siapa
-- pun yang punya anon key, tidak peduli policy tabel lain sudah benar.
-- ═══════════════════════════════════════════════════════════════════════════
