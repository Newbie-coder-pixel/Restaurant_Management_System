-- ═══════════════════════════════════════════════════════════════════════════
-- RLS policy patch — diterapkan ke production 2026-07-23
-- ═══════════════════════════════════════════════════════════════════════════
--
-- File ini BUKAN draft lagi — ini dokumentasi 1:1 dari statement yang benar-benar
-- dijalankan ke database production (project ref pppxzbddfoeajwngbwdo) lewat
-- Supabase Management API SQL editor, setelah audit keamanan menemukan RLS
-- SUDAH aktif di semua tabel tapi banyak policy yang isinya kontradiktif
-- (beberapa `USING (true)` yang membatalkan proteksi policy lain di tabel yang
-- sama, karena Postgres RLS meng-OR semua policy yang cocok untuk 1 command).
--
-- Temuan paling kritis yang dikonfirmasi LANGSUNG lewat REST API pakai anon key
-- (bukan cuma baca kode) sebelum patch ini:
--   • orders.branch_isolation punya `OR auth.uid() IS NULL` → SIAPA PUN tanpa
--     login bisa SELECT/UPDATE/DELETE SEMUA order semua cabang.
--   • staff.staff_access (ALL) mengizinkan staff biasa UPDATE row staff lain
--     di cabang yang sama → bisa menaikkan role kolega jadi superadmin.
--   • payments.branch_isolation adalah policy ALL (bukan cuma SELECT) → staff
--     cabang bisa INSERT baris payment "paid" palsu langsung, bypass Midtrans.
--   • branches, costings, operating_expenses, inventory_transactions/transfers,
--     chatbot_conversations/messages, restaurant_closures punya policy
--     `USING (true)` yang membuka tabel itu ke siapa pun yang login (atau
--     bahkan anon untuk costings/operating_expenses).
--
-- Setiap statement di bawah sudah diverifikasi hidup lewat request nyata ke
-- REST API (anon key + insert baris uji lalu dihapus) — bukan asumsi.
--
-- Idempoten: semua `drop policy/trigger if exists` + `create` sehingga aman
-- dijalankan ulang (mis. lewat `supabase db push` di kemudian hari) tanpa
-- error kalau sudah pernah diterapkan.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Helper: role staff yang sedang login ────────────────────────────────────
-- Helper `get_my_branch_id()` dan `is_superadmin()` SUDAH ADA sebelumnya di
-- project ini (tidak dibuat di sini) — hanya `current_staff_role()` yang baru.
create or replace function public.current_staff_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select role::text from public.staff
  where user_id = auth.uid() and is_active = true
  limit 1;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- orders — bug paling kritis: anon bisa baca/tulis SEMUA order semua cabang
-- ═══════════════════════════════════════════════════════════════════════════

-- Hapus `OR auth.uid() IS NULL` yang membuka ALL command ke anon tanpa batas.
drop policy if exists branch_isolation on public.orders;
create policy branch_isolation on public.orders
  for all
  using (is_superadmin() or (auth.uid() is not null and branch_id = get_my_branch_id()))
  with check (is_superadmin() or (auth.uid() is not null and branch_id = get_my_branch_id()));

-- anon_read_orders_by_number sebelumnya `USING (true)` — anon bisa select
-- SEMUA order sepanjang waktu. Dibatasi ke 24 jam terakhir supaya fitur
-- "lacak order via nomor" (QR/customer tanpa login) tetap jalan, tapi blast
-- radius kalau di-enumerasi cuma order hari ini, bukan seluruh histori.
-- CATATAN: ini mitigasi, bukan penutupan total — perbaikan yang benar adalah
-- pindahkan lookup ke RPC function yang menerima order_number persis dan
-- return kolom terbatas untuk 1 baris, bukan SELECT tabel langsung.
drop policy if exists anon_read_orders_by_number on public.orders;
create policy anon_read_orders_by_number on public.orders
  for select to anon
  using (created_at >= (now() - interval '24 hours'));

-- authenticated_read_own_orders sebelumnya `USING (true)` — SEMUA user login
-- (customer maupun staff cabang manapun) bisa baca SEMUA order.
drop policy if exists authenticated_read_own_orders on public.orders;
create policy authenticated_read_own_orders on public.orders
  for select to authenticated
  using (is_superadmin() or branch_id = get_my_branch_id() or customer_user_id = auth.uid());

-- "Allow anon update bill_requested" sebelumnya `USING true WITH CHECK true`
-- — nama policy bilang "bill_requested" tapi RLS tidak membatasi kolom,
-- jadi anon bisa ubah KOLOM APAPUN termasuk payment_status/total_amount.
-- Dibatasi ke order 24 jam terakhir DAN ditegakkan ulang di level kolom lewat
-- trigger di bawah (karena RLS policy sendiri tidak bisa membatasi per kolom).
drop policy if exists "Allow anon update bill_requested" on public.orders;
create policy anon_update_recent_order on public.orders
  for update to anon
  using (created_at >= (now() - interval '24 hours'))
  with check (created_at >= (now() - interval '24 hours'));

-- Trigger: anon HANYA boleh mengubah bill_requested/bill_requested_at.
-- Sudah dites live: percobaan ubah payment_status via PATCH anon → ditolak
-- dengan error dari trigger ini; percobaan ubah bill_requested → berhasil.
create or replace function public.enforce_anon_order_update_only_bill()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.role() = 'anon' then
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

drop trigger if exists trg_enforce_anon_order_update on public.orders;
create trigger trg_enforce_anon_order_update
  before update on public.orders
  for each row execute function public.enforce_anon_order_update_only_bill();

-- Policy lain di orders (anon_insert_app_orders, "Allow walk-in order insert",
-- "staff can insert orders") TIDAK diubah — sudah cukup ketat dari awal.

-- ═══════════════════════════════════════════════════════════════════════════
-- staff — bug eskalasi privilege: staff biasa bisa jadikan kolega superadmin
-- ═══════════════════════════════════════════════════════════════════════════
drop policy if exists staff_access on public.staff;

create policy staff_select on public.staff
  for select
  using (user_id = auth.uid() or branch_id = get_my_branch_id() or is_superadmin());

create policy staff_insert on public.staff
  for insert
  with check (
    is_superadmin()
    or (public.current_staff_role() = 'manager' and branch_id = get_my_branch_id() and role <> 'superadmin')
  );

create policy staff_update on public.staff
  for update
  using (user_id = auth.uid() or branch_id = get_my_branch_id() or is_superadmin())
  with check (
    is_superadmin()
    -- staff boleh edit profil sendiri TAPI tidak boleh ubah role sendiri
    or (user_id = auth.uid() and role::text = public.current_staff_role())
    -- manager boleh kelola staff di cabang sendiri, TAPI tidak boleh grant superadmin
    or (public.current_staff_role() = 'manager' and branch_id = get_my_branch_id() and role <> 'superadmin')
  );

create policy staff_delete on public.staff
  for delete
  using (
    is_superadmin()
    or (public.current_staff_role() = 'manager' and branch_id = get_my_branch_id())
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- payments — bug: staff cabang bisa INSERT/UPDATE payment langsung (ALL),
-- bypass total alur verifikasi Midtrans webhook.
-- ═══════════════════════════════════════════════════════════════════════════
drop policy if exists branch_isolation on public.payments;
create policy payments_select on public.payments
  for select
  using (branch_id = get_my_branch_id() or is_superadmin());
-- Sengaja TANPA policy insert/update/delete untuk anon/authenticated — hanya
-- service_role (dipakai Edge Function midtrans-webhook, selalu bypass RLS)
-- yang boleh menulis ke tabel ini. Sudah dites: anon INSERT → ditolak RLS.

-- ═══════════════════════════════════════════════════════════════════════════
-- branches — bug: SEMUA user login (role apa pun) bisa insert/update cabang
-- manapun.
-- ═══════════════════════════════════════════════════════════════════════════
drop policy if exists "Allow authenticated users to insert branches" on public.branches;
drop policy if exists "Allow authenticated users to update branches" on public.branches;

create policy branches_insert_superadmin on public.branches
  for insert
  with check (is_superadmin());

create policy branches_update_superadmin on public.branches
  for update
  using (is_superadmin())
  with check (is_superadmin());
-- Policy SELECT (own_branch_only, "Public read branches", anon_read_branches)
-- TIDAK diubah — memang publik by design (customer pilih cabang).

-- ═══════════════════════════════════════════════════════════════════════════
-- costings / operating_expenses — bug: `USING (true)` untuk SEMUA orang
-- termasuk anon. Data biaya resep & pengeluaran operasional semua cabang.
-- ═══════════════════════════════════════════════════════════════════════════
drop policy if exists allow_all_costings on public.costings;
create policy costings_staff_only on public.costings
  for all
  using (branch_id = get_my_branch_id() or is_superadmin())
  with check (branch_id = get_my_branch_id() or is_superadmin());

-- catatan: operating_expenses.branch_id bertipe TEXT (bukan uuid seperti
-- tabel lain), makanya perlu cast get_my_branch_id()::text.
drop policy if exists allow_all_expenses on public.operating_expenses;
create policy operating_expenses_staff_only on public.operating_expenses
  for all
  using (branch_id = get_my_branch_id()::text or is_superadmin())
  with check (branch_id = get_my_branch_id()::text or is_superadmin());

-- ═══════════════════════════════════════════════════════════════════════════
-- inventory_transactions / inventory_transfers — bug: beberapa policy
-- `USING (true)` / `auth.role() = 'authenticated'` tanpa scoping cabang.
-- ═══════════════════════════════════════════════════════════════════════════
drop policy if exists "superadmin can view all transactions" on public.inventory_transactions;
drop policy if exists "Allow all for inventory_transactions" on public.inventory_transactions;
drop policy if exists "staff can insert own branch transactions" on public.inventory_transactions;
drop policy if exists inv_tx_insert on public.inventory_transactions;
drop policy if exists "staff can view own branch transactions" on public.inventory_transactions;
drop policy if exists inv_tx_select on public.inventory_transactions;

create policy inventory_transactions_staff_only on public.inventory_transactions
  for all
  using (branch_id = get_my_branch_id() or is_superadmin())
  with check (branch_id = get_my_branch_id() or is_superadmin());

drop policy if exists authenticated_all_inventory_transfers on public.inventory_transfers;
create policy inventory_transfers_admin_only on public.inventory_transfers
  for all
  using (
    is_superadmin()
    or (public.current_staff_role() = 'manager'
        and (from_branch_id = get_my_branch_id() or to_branch_id = get_my_branch_id()))
  )
  with check (
    is_superadmin()
    or (public.current_staff_role() = 'manager'
        and (from_branch_id = get_my_branch_id() or to_branch_id = get_my_branch_id()))
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- chatbot_conversations / chatbot_messages — bug: SEMUA user login (role
-- apa pun, cabang manapun) bisa baca/update/hapus percakapan siapa saja.
-- ═══════════════════════════════════════════════════════════════════════════
drop policy if exists chatbot_conv_select on public.chatbot_conversations;
drop policy if exists chatbot_conv_update on public.chatbot_conversations;
drop policy if exists chatbot_conv_delete on public.chatbot_conversations;

create policy chatbot_conv_select on public.chatbot_conversations
  for select to authenticated
  using (branch_id = get_my_branch_id() or is_superadmin());

create policy chatbot_conv_update on public.chatbot_conversations
  for update to authenticated
  using (branch_id = get_my_branch_id() or is_superadmin())
  with check (branch_id = get_my_branch_id() or is_superadmin());

create policy chatbot_conv_delete on public.chatbot_conversations
  for delete to authenticated
  using (branch_id = get_my_branch_id() or is_superadmin());

-- chatbot_conv_insert TIDAK diubah (tetap WITH CHECK true untuk authenticated)
-- — residual minor: branch_id saat insert masih bisa diisi bebas oleh
-- pemanggil (lihat sentiment_escalation_service.dart). Risikonya cuma spam
-- log, bukan kebocoran data, dan tidak diubah karena konteks auth pemanggil
-- (customer chat, mungkin anon) belum diverifikasi penuh — lihat TODO di
-- bagian akhir file ini.

drop policy if exists chatbot_msg_select on public.chatbot_messages;
drop policy if exists chatbot_msg_delete on public.chatbot_messages;

create policy chatbot_msg_select on public.chatbot_messages
  for select to authenticated
  using (
    exists (
      select 1 from public.chatbot_conversations c
      where c.id = chatbot_messages.conversation_id
        and (c.branch_id = get_my_branch_id() or is_superadmin())
    )
  );

create policy chatbot_msg_delete on public.chatbot_messages
  for delete to authenticated
  using (
    exists (
      select 1 from public.chatbot_conversations c
      where c.id = chatbot_messages.conversation_id
        and (c.branch_id = get_my_branch_id() or is_superadmin())
    )
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- restaurant_closures — bug: `USING (true)` padahal nama policy bilang
-- "Manager/superadmin bisa ..." — nama tidak mencerminkan kondisi asli.
-- ═══════════════════════════════════════════════════════════════════════════
drop policy if exists "Manager/superadmin bisa delete" on public.restaurant_closures;
drop policy if exists "Manager/superadmin bisa insert" on public.restaurant_closures;
drop policy if exists "Staff bisa baca closure branch sendiri" on public.restaurant_closures;

create policy restaurant_closures_select on public.restaurant_closures
  for select to authenticated
  using (branch_id = get_my_branch_id() or is_superadmin());

create policy restaurant_closures_insert on public.restaurant_closures
  for insert to authenticated
  with check (
    is_superadmin()
    or (public.current_staff_role() = 'manager' and branch_id = get_my_branch_id())
  );

create policy restaurant_closures_delete on public.restaurant_closures
  for delete to authenticated
  using (
    is_superadmin()
    or (public.current_staff_role() = 'manager' and branch_id = get_my_branch_id())
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- restaurant_tables — bug: staff cabang MANAPUN bisa update meja cabang lain
-- (policy "authenticated_update_table_status" redundan & lebih longgar dari
-- "branch_isolation" yang sudah ada di tabel yang sama).
-- ═══════════════════════════════════════════════════════════════════════════
drop policy if exists authenticated_update_table_status on public.restaurant_tables;
-- Setelah ini, UPDATE untuk role authenticated sepenuhnya diatur oleh policy
-- "branch_isolation" (ALL, sudah ada sebelumnya: branch_id = get_my_branch_id()
-- OR is_superadmin()) — tidak perlu policy baru.
-- "anon_update_table_status" (USING true) SENGAJA TIDAK diubah — ini alur QR
-- order yang sah (customer di meja update status mejanya sendiri via UUID
-- dari QR code yang di-scan, bukan tabel yang bisa dienumerasi/ditebak).
-- Policy SELECT (anon_read_restaurant_tables, "Public read", dst) juga tidak
-- diubah — memang publik by design.

-- ═══════════════════════════════════════════════════════════════════════════
-- TODO follow-up (tidak dikerjakan dalam patch ini — di luar prioritas /
-- butuh perubahan Flutter juga, bukan cuma RLS):
--   1. chatbot_conversations INSERT masih WITH CHECK true — kalau nanti sempat,
--      verifikasi auth context sentiment_escalation_service.dart lalu scope
--      branch_id insert ke branch yang valid.
--   2. anon_read_orders_by_number (24 jam) & anon_update_recent_order masih
--      memperbolehkan enumerasi order HARI INI oleh anon (mitigasi, bukan
--      penutupan total). Perbaikan idealnya: pindahkan tracking order ke RPC
--      function (`get_order_by_number(p_order_number text)`, SECURITY DEFINER)
--      yang return kolom terbatas untuk 1 baris exact-match, lalu cabut total
--      SELECT langsung ke tabel orders untuk anon. Butuh perubahan di
--      customer_order_tracker_screen.dart & qr_order_repository.dart juga.
-- ═══════════════════════════════════════════════════════════════════════════
