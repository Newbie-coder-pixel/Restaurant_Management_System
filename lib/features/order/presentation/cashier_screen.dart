import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/models/order_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/staff_role.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/widgets/app_drawer.dart';

const _red = AppColors.accent;

class CashierScreen extends ConsumerStatefulWidget {
  const CashierScreen({super.key});

  @override
  ConsumerState<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends ConsumerState<CashierScreen> {
  List<OrderModel> _orders = [];
  bool _isLoading = true;
  String? _branchId;
  bool _isSuperAdmin = false;
  RealtimeChannel? _channel;
  OrderModel? _selected;

  // ── Branch filter (superadmin only) ──────────────────────────────────────
  List<Map<String, dynamic>> _branches = [];
  String? _selectedBranchId; // null = semua cabang

  // ── Bill request notification tracking ───────────────────────────────────
  RealtimeChannel? _billChannel;
  // Apakah bottom sheet sedang terbuka
  bool _billSheetOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final staff = ref.read(currentStaffProvider);
    _isSuperAdmin = staff?.role == StaffRole.superadmin;
    _branchId = _isSuperAdmin ? null : staff?.branchId;
    await _loadBranches();
    await _load();
    _subscribeRealtime();
    _subscribeBillRealtime();
  }

  // ── Load daftar branch (superadmin only) ─────────────────────────────────
  Future<void> _loadBranches() async {
    if (!_isSuperAdmin) return;
    try {
      final res = await Supabase.instance.client
          .from('branches')
          .select('id, name')
          .order('name');
      if (mounted) {
        setState(() => _branches = List<Map<String, dynamic>>.from(res));
      }
    } catch (e) {
      debugPrint('_loadBranches error: $e');
    }
  }

  Future<void> _load() async {
    if (!_isSuperAdmin && _branchId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    if (mounted) setState(() => _isLoading = true);

    final effectiveBranchId = _isSuperAdmin ? _selectedBranchId : _branchId;

    try {
      var query = Supabase.instance.client
          .from('orders')
          .select('''
            id, branch_id, table_id, order_number,
            status, source, order_type, customer_name,
            customer_phone, queue_number, table_name,
            discount_amount, notes, created_at, updated_at,
            payment_status, bill_requested, bill_requested_at,
            total_amount, subtotal, tax_amount,
            restaurant_tables(table_number),
            order_items(*)
          ''')
          .eq('status', 'served')
          // FIX: tambah 'unpaid' (standar baru) dan null-check untuk order lama
          // yang dibuat sebelum kolom payment_status diisi secara konsisten
          .or('payment_status.eq.unpaid,payment_status.eq.pending,payment_status.is.null')
          .gt('total_amount', 0); // exclude order kosong (Rp 0)
      if (effectiveBranchId != null) query = query.eq('branch_id', effectiveBranchId);
      final res = await query.order('created_at', ascending: true);

      if (mounted) {
        setState(() {
          _orders = (res as List)
              .map((e) => OrderModel.fromJson(e as Map<String, dynamic>))
              .toList();
          _isLoading = false;
        });
        // Setelah load: cek order yang sudah bill_requested = true
        // supaya kasir yang baru buka halaman langsung lihat notif
        _checkAndShowBillSheet();
      }
    } catch (e) {
      debugPrint('Error load cashier orders: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _subscribeRealtime() {
    _channel?.unsubscribe();
    if (!_isSuperAdmin && _branchId == null) return;
    final effectiveBranchId = _isSuperAdmin ? _selectedBranchId : _branchId;
    final channelName = effectiveBranchId != null
        ? 'cashier_orders_$effectiveBranchId'
        : 'cashier_orders_all';
    _channel = Supabase.instance.client
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: effectiveBranchId != null
              ? PostgresChangeFilter(
                  type: PostgresChangeFilterType.eq,
                  column: 'branch_id',
                  value: effectiveBranchId)
              : null,
          callback: (_) { if (mounted) _load(); },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _billChannel?.unsubscribe();
    super.dispose();
  }

  // ── Subscribe khusus untuk bill_requested ────────────────────────────────
  void _subscribeBillRealtime() {
    _billChannel?.unsubscribe();
    if (!_isSuperAdmin && _branchId == null) return;

    final effectiveBranchId = _isSuperAdmin ? _selectedBranchId : _branchId;
    final channelName = effectiveBranchId != null
        ? 'bill_requests_$effectiveBranchId'
        : 'bill_requests_all';

    _billChannel = Supabase.instance.client
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          filter: effectiveBranchId != null
              ? PostgresChangeFilter(
                  type: PostgresChangeFilterType.eq,
                  column: 'branch_id',
                  value: effectiveBranchId)
              : null,
          callback: (payload) {
            if (!mounted) return;
            final newRecord = payload.newRecord;
            final billRequested = newRecord['bill_requested'] as bool? ?? false;
            final orderId = newRecord['id'] as String? ?? '';
            if (billRequested && orderId.isNotEmpty) {
              _load(); // refresh list dulu, lalu sheet akan auto-update
            }
          },
        )
        .subscribe();
  }

  // ── Cek & tampilkan bill sheet jika ada order yang minta bill ───────────
  void _checkAndShowBillSheet() {
    final billOrders = _orders.where((o) => o.billRequested).toList();
    if (billOrders.isEmpty) return;
    // Kalau sheet sudah terbuka, tidak perlu buka lagi — sheet
    // akan rebuild sendiri karena setState di _load()
    if (_billSheetOpen) return;
    // Delay supaya widget sudah selesai build setelah setState
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showBillSheet();
    });
  }

  void _showBillSheet() {
    if (_billSheetOpen) return;
    _billSheetOpen = true;

    showModalBottomSheet(
      context: context,
      isDismissible: true,
      enableDrag: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _BillRequestSheet(
        // Kirim getter live supaya sheet bisa rebuild saat _orders berubah
        getOrders: () => _orders.where((o) => o.billRequested).toList(),
        onSelectOrder: (order) {
          Navigator.pop(ctx);
          setState(() => _selected = order);
        },
        onDismiss: () => Navigator.pop(ctx),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _billSheetOpen = false);
    });
  }

  // ─── CASH PAYMENT ────────────────────────────────────────────────────────
  Future<void> _onCashPayment(OrderModel order) async {
    final cashController = TextEditingController();
    double change = -1; // nilai awal negatif agar tombol disabled sebelum nominal diisi

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Pembayaran Tunai',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _totalBox(order.totalAmount),
              const SizedBox(height: 16),
              const Text('Uang Diterima',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextField(
                controller: cashController,
                keyboardType: TextInputType.number,
                autofocus: true,
                style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  prefixText: 'Rp ',
                  prefixStyle: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w600),
                  hintText: '0',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.primary, width: 2),
                  ),
                ),
                onChanged: (v) {
                  final cash = double.tryParse(v.replaceAll('.', '')) ?? 0;
                  setS(() => change = cash - order.totalAmount);
                },
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _quickCash(order.totalAmount).map((nominal) => ActionChip(
                  label: Text('Rp ${_formatNominal(nominal)}',
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 11)),
                  backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                  onPressed: () {
                    cashController.text = nominal.toStringAsFixed(0);
                    setS(() => change = nominal - order.totalAmount);
                  },
                )).toList(),
              ),
              const SizedBox(height: 14),
              _changeBox(change),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal',
                  style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: (change >= 0 &&
                      (double.tryParse(cashController.text.replaceAll('.', '')) ?? 0) > 0)
                  ? () {
                      Navigator.pop(ctx);
                      _processPayment(order, 'cash',
                          cashReceived: double.tryParse(
                                  cashController.text.replaceAll('.', '')) ??
                              0,
                          changeAmount: change);
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Proses Bayar',
                  style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  // ─── NON-CASH PAYMENT ────────────────────────────────────────────────────
  Future<void> _onNonCashPayment(OrderModel order, String method) async {
    final config = _nonCashConfig(method);
    final refCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(config.icon, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 10),
            Text('Bayar ${config.label}',
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 16)),
          ]),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _totalBox(order.totalAmount),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline,
                          size: 14, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(config.instruction,
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                color: AppColors.primary,
                                height: 1.4)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(config.refLabel,
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: config.refRequired
                            ? AppColors.textPrimary
                            : AppColors.textSecondary)),
                if (config.refRequired)
                  const Text('* wajib diisi',
                      style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 11, color: _red)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: refCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1),
                  decoration: InputDecoration(
                    hintText: config.refHint,
                    hintStyle: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        fontWeight: FontWeight.normal,
                        letterSpacing: 0,
                        color: AppColors.textHint),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: AppColors.primary, width: 2),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _red, width: 1.5),
                    ),
                    suffixIcon: config.refRequired
                        ? const Icon(Icons.tag, size: 18, color: AppColors.textHint)
                        : const Icon(Icons.tag_outlined,
                            size: 18, color: AppColors.textHint),
                  ),
                  validator: config.refRequired
                      ? (v) => (v == null || v.trim().isEmpty)
                          ? '${config.refLabel} wajib diisi'
                          : null
                      : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal',
                  style: TextStyle(
                      fontFamily: 'Poppins', color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.pop(ctx);
                  _processPayment(order, method,
                      referenceNumber: refCtrl.text.trim().isEmpty
                          ? null
                          : refCtrl.text.trim());
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Konfirmasi Bayar',
                  style: TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  // ─── CONFIG TIAP METODE ───────────────────────────────────────────────────
  _NonCashConfig _nonCashConfig(String method) {
    switch (method) {
      case 'qris':
        return const _NonCashConfig(
          label: 'QRIS',
          icon: Icons.qr_code_2,
          instruction:
              'Tampilkan QR code ke pelanggan, tunggu konfirmasi pembayaran masuk.',
          refLabel: 'Nomor Referensi QRIS',
          refHint: 'Contoh: QR20260327001',
          refRequired: false,
        );
      case 'debit_card':
        return const _NonCashConfig(
          label: 'Kartu Debit',
          icon: Icons.credit_card,
          instruction:
              'Masukkan kartu ke mesin EDC, minta pelanggan masukkan PIN.',
          refLabel: 'Nomor Approval EDC',
          refHint: 'Contoh: 123456',
          refRequired: true,
        );
      case 'credit_card':
        return const _NonCashConfig(
          label: 'Kartu Kredit',
          icon: Icons.credit_card_outlined,
          instruction:
              'Proses kartu di mesin EDC, pastikan slip pembayaran tercetak.',
          refLabel: 'Nomor Approval EDC',
          refHint: 'Contoh: 789012',
          refRequired: true,
        );
      case 'transfer':
        return const _NonCashConfig(
          label: 'Transfer Bank',
          icon: Icons.account_balance,
          instruction:
              'Konfirmasi transfer dari bukti pembayaran pelanggan sebelum memproses.',
          refLabel: 'Nomor Referensi Transfer',
          refHint: 'Contoh: TRF20260327001',
          refRequired: true,
        );
      case 'voucher':
        return const _NonCashConfig(
          label: 'Voucher',
          icon: Icons.local_offer_outlined,
          instruction:
              'Masukkan kode voucher yang diberikan pelanggan. Pastikan voucher masih berlaku.',
          refLabel: 'Kode Voucher',
          refHint: 'Contoh: DISC50OFF',
          refRequired: true,
        );
      default:
        return _NonCashConfig(
          label: method,
          icon: Icons.payment,
          instruction: 'Konfirmasi pembayaran dari pelanggan.',
          refLabel: 'Nomor Referensi',
          refHint: '-',
          refRequired: false,
        );
    }
  }

  // ─── CANCEL ORDER ─────────────────────────────────────────────────────────
  // Cashier screen hanya load order berstatus ready/served,
  // sehingga cancel hanya relevan untuk kedua status ini.
  bool _canCancel(OrderModel order) =>
      order.status == OrderStatus.ready ||
      order.status == OrderStatus.served;

  Future<void> _onCancelOrder(OrderModel order) async {
    if (!_canCancel(order)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
            Text('Order yang sudah siap/tersaji tidak dapat dibatalkan.'),
        backgroundColor: _red,
      ));
      return;
    }

    if (order.status == OrderStatus.preparing) {
      if (!mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.warning_amber_rounded,
                  color: Colors.orange, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('Perhatian',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 16)),
          ]),
          content: const Text(
            'Dapur sedang memproses order ini.\n\n'
            'Membatalkan order yang sedang dimasak dapat menyebabkan '
            'pemborosan bahan. Yakin ingin melanjutkan?',
            style: TextStyle(
                fontFamily: 'Poppins', fontSize: 13, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Tidak',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Lanjutkan',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    if (!mounted) return;
    final reasonController = TextEditingController();
    String? selectedReason;
    final reasons = [
      'Pelanggan membatalkan',
      'Item tidak tersedia',
      'Kesalahan input',
      'Pesanan duplikat',
      'Lainnya',
    ];

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.cancel_outlined,
                  color: _red, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('Batalkan Order',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 16)),
          ]),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Order #${order.orderNumber}',
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary)),
                const SizedBox(height: 14),
                const Text('Alasan Pembatalan *',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                RadioGroup<String>(
                  groupValue: selectedReason ?? '',
                  onChanged: (v) => setS(() => selectedReason = v),
                  child: Column(
                    children: reasons
                        .map((r) => RadioListTile<String>(
                              value: r,
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              activeColor: AppColors.primary,
                              title: Text(r,
                                  style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 13)),
                            ))
                        .toList(),
                  ),
                ),
                if (selectedReason == 'Lainnya') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: reasonController,
                    maxLines: 2,
                    style: const TextStyle(
                        fontFamily: 'Poppins', fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Tulis alasan...',
                      hintStyle: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          color: AppColors.textHint),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: _red, width: 2),
                      ),
                      contentPadding: const EdgeInsets.all(10),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Tidak',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: selectedReason == null
                  ? null
                  : () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _red,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.border,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Ya, Batalkan',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    final finalReason = selectedReason == 'Lainnya'
        ? (reasonController.text.trim().isEmpty
            ? 'Lainnya'
            : reasonController.text.trim())
        : selectedReason!;

    try {
      final staff = ref.read(currentStaffProvider);
      await Supabase.instance.client.from('orders').update({
        'status': 'cancelled',
        'cancel_reason': finalReason,
        'cancelled_by': staff?.id,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', order.id);

      if (order.tableId != null) {
        await Supabase.instance.client
            .from('restaurant_tables')
            .update({'status': 'available'}).eq('id', order.tableId!);
      }

      if (!mounted) return;
      setState(() => _selected = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Order #${order.orderNumber} dibatalkan.'),
        backgroundColor: _red,
      ));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Gagal membatalkan order.'),
        backgroundColor: _red,
      ));
    }
  }

  // ─── PROCESS PAYMENT ─────────────────────────────────────────────────────
  Future<void> _processPayment(
    OrderModel order,
    String method, {
    double? cashReceived,
    double? changeAmount,
    String? referenceNumber,
  }) async {
    final staff = ref.read(currentStaffProvider);

    // Untuk superadmin: ambil branch_id dari order itu sendiri
    final effectiveBranchId = _isSuperAdmin ? order.branchId : _branchId;

    await Supabase.instance.client.from('orders').update({
      'status': 'paid',
      'payment_status': 'paid',
      'cashier_id': staff?.id,
      'updated_at': DateTime.now().toIso8601String(),
      // Simpan breakdown harga agar riwayat tampil dengan benar
      'subtotal': order.subtotal,
      'tax_amount': order.taxAmount,
      'pb1_amount': order.pb1Amount,
      'service_charge_amount': order.serviceChargeAmount,
      'total_amount': order.totalAmount,
    }).eq('id', order.id);

    // Inventory sudah di-deduct di order_screen saat status → preparing.
    // Tidak perlu deduct lagi di sini untuk menghindari double deduction.

    // FIX: sync status order_items agar konsisten dengan order yang sudah paid
    await Supabase.instance.client.from('order_items').update({
      'status': 'served',
    }).eq('order_id', order.id);

    await Supabase.instance.client.from('payments').insert({
      'order_id': order.id,
      'branch_id': effectiveBranchId,
      'method': method,
      'amount': order.totalAmount,
      'cash_received': cashReceived,
      'change_amount': changeAmount,
      'reference_number': referenceNumber,
      'status': 'paid',
      'processed_by': staff?.id,
    });

    if (order.tableId != null) {
      await Supabase.instance.client
          .from('restaurant_tables')
          .update({'status': 'cleaning'}).eq('id', order.tableId!);
    }

    if (!mounted) return;
    setState(() => _selected = null);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text('Pembayaran order #${order.orderNumber} berhasil!'),
      backgroundColor: AppColors.available,
    ));
    await _load();
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 800;
    return isWide ? _buildWideLayout() : _buildNarrowLayout();
  }

  Widget _buildWideLayout() => Row(children: [
        SizedBox(width: 380, child: _buildOrderList(showAppBar: true)),
        const VerticalDivider(width: 1),
        Expanded(
          child: _selected == null
              ? _buildEmptyDetail()
              : _buildPaymentPanel(_selected!),
        ),
      ]);

  Widget _buildNarrowLayout() {
    if (_selected != null) {
      return Scaffold(
        drawer: const AppDrawer(),
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text('Order #${_selected!.orderNumber}'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => setState(() => _selected = null)),
        ),
        body: _buildPaymentPanel(_selected!),
      );
    }
    return _buildOrderList(showAppBar: true);
  }

  Widget _buildOrderList({bool showAppBar = false}) {
    final body = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _orders.isEmpty
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.receipt_outlined,
                        size: 64, color: AppColors.textHint),
                    SizedBox(height: 12),
                    Text('Tidak ada order pending',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            color: AppColors.textSecondary)),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _orders.length,
                itemBuilder: (_, i) {
                  final o = _orders[i];
                  final isSelected = _selected?.id == o.id;
                  final isBillRequested = o.billRequested;
                  // Badge: QR / App Order / Staff
                  final isQrOrder = o.orderType == 'qr_order';
                  final isAppOrder = o.orderType == 'app_order' || o.orderType == 'takeaway';
                  final badgeColor = isQrOrder
                      ? const Color(0xFF7C3AED)
                      : isAppOrder
                          ? const Color(0xFF0F9D58)
                          : AppColors.primary;
                  final badgeIcon = isQrOrder
                      ? Icons.qr_code_scanner
                      : isAppOrder
                          ? Icons.smartphone_outlined
                          : Icons.person_outline;
                  final badgeLabel = isQrOrder
                      ? 'QR'
                      : isAppOrder
                          ? (o.orderType == 'takeaway' ? 'Takeaway' : 'App Order')
                          : 'Staff';

                  return GestureDetector(
                    onTap: () => setState(() => _selected = o),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isBillRequested && !isSelected
                            ? const Color(0xFFFFFBEB)
                            : isSelected
                                ? AppColors.primary.withValues(alpha: 0.05)
                                : AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isBillRequested
                              ? const Color(0xFFF59E0B)
                              : isSelected ? AppColors.primary : AppColors.border,
                          width: isBillRequested || isSelected ? 2 : 1,
                        ),
                      ),
                      child: Row(children: [
                        // Avatar dengan warna sesuai tipe
                        Container(
                          width: 42, height: 42,
                          decoration: BoxDecoration(
                            color: badgeColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(child: Text(
                            o.orderNumber.split('-').last,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w700,
                              color: Colors.white, fontSize: 13),
                          )),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Text(
                                  o.tableNumber != null
                                      ? 'Meja ${o.tableNumber}'
                                      : o.customerName != null
                                          ? 'Takeaway • ${o.customerName}'
                                          : 'Takeaway',
                                  style: const TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w600, fontSize: 14),
                                ),
                                const SizedBox(width: 6),
                                // Badge QR / Staff
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: badgeColor.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: badgeColor.withValues(alpha: 0.35)),
                                  ),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(
                                      badgeIcon,
                                      size: 9, color: badgeColor),
                                    const SizedBox(width: 3),
                                    Text(badgeLabel,
                                      style: TextStyle(
                                        fontFamily: 'Poppins', fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: badgeColor)),
                                  ]),
                                ),
                              ]),
                              Row(children: [
                                Text(
                                  '${o.items.length} item • ${o.status.label}',
                                  style: AppTextStyles.caption,
                                ),
                                if (isBillRequested) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEF3C7),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: const Color(0xFFF59E0B)),
                                    ),
                                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                      Icon(Icons.notifications_active, size: 9, color: Color(0xFFF59E0B)),
                                      SizedBox(width: 3),
                                      Text('Minta Bill',
                                        style: TextStyle(
                                          fontFamily: 'Poppins', fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFFF59E0B))),
                                    ]),
                                  ),
                                ],
                              ]),
                            ],
                          ),
                        ),
                        Text(
                          'Rp ${o.totalAmount.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                            fontSize: 14, color: AppColors.accent),
                        ),
                      ]),
                    ),
                  );
                },
              );

    if (!showAppBar) return body;
    return Scaffold(
      drawer: const AppDrawer(),
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Kasir'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        titleTextStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white),
        actions: [
          // ── BRANCH FILTER DROPDOWN (superadmin only) ──
          if (_isSuperAdmin)
            DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _selectedBranchId,
                isDense: true,
                dropdownColor: const Color(0xFF1A1A2E),
                iconEnabledColor: Colors.white60,
                icon: const Icon(Icons.keyboard_arrow_down, size: 16),
                style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 11, color: Colors.white70),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Semua Cabang',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            color: Colors.white70))),
                  ..._branches.map((b) => DropdownMenuItem<String?>(
                        value: b['id'] as String,
                        child: Text(b['name'] as String,
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11,
                                color: Colors.white)))),
                ],
                onChanged: (val) {
                  setState(() {
                    _selectedBranchId = val;
                    _orders = [];
                    _selected = null;
                  });
                  _load();
                  _subscribeRealtime();
                },
              ),
            ),
          const SizedBox(width: 4),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: body,
    );
  }

  Widget _buildEmptyDetail() => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.touch_app_outlined,
                size: 64, color: AppColors.textHint),
            SizedBox(height: 12),
            Text('Pilih order untuk proses pembayaran',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    color: AppColors.textSecondary)),
          ],
        ),
      );

  Widget _buildPaymentPanel(OrderModel order) {
    final canCancel = _canCancel(order);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header (sama seperti sebelumnya)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Order #${order.orderNumber}',
                        style: AppTextStyles.heading2),
                    if (order.tableNumber != null)
                      Text('Meja ${order.tableNumber}',
                          style: AppTextStyles.bodySecondary)
                    else if (order.customerName != null)
                      Text('Takeaway • ${order.customerName}',
                          style: AppTextStyles.bodySecondary),
                    const SizedBox(height: 6),
                    _buildStatusBadge(order.status),
                  ],
                ),
              ),
              if (canCancel)
                TextButton.icon(
                  onPressed: () => _onCancelOrder(order),
                  icon: const Icon(Icons.cancel_outlined, size: 16, color: _red),
                  label: const Text('Batalkan',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          color: _red,
                          fontWeight: FontWeight.w600)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    backgroundColor: _red.withValues(alpha: 0.06),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
            ],
          ),

          if (!canCancel && order.status != OrderStatus.paid) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: const Row(children: [
                Icon(Icons.info_outline, size: 14, color: Colors.orange),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Order sudah siap/tersaji — tidak dapat dibatalkan.',
                    style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 11, color: Colors.orange),
                  ),
                ),
              ]),
            ),
          ],

          const SizedBox(height: 20),

          // Rincian Pesanan
          const Text('Rincian Pesanan',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ...order.items.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text('${item.menuItemName} x${item.quantity}',
                            style: AppTextStyles.body),
                      ),
                      Text('Rp ${item.subtotal.toStringAsFixed(0)}',
                          style: AppTextStyles.body),
                    ]),
                    if (item.specialRequests != null &&
                        item.specialRequests!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('⚡ ${item.specialRequests}',
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11,
                                color: AppColors.reserved)),
                      ),
                  ],
                ),
              )),
          const Divider(height: 24),

          // Summary yang sekarang benar
          _summaryRow('Subtotal', order.subtotal),
          _summaryRow('PB1 (10%)', order.pb1Amount),
          _summaryRow('Service Charge (3%)', order.serviceChargeAmount),
          if (order.discountAmount > 0)
            _summaryRow('Diskon', -order.discountAmount, color: AppColors.available),

          const SizedBox(height: 8),
          Row(children: [
            const Text('TOTAL',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 16)),
            const Spacer(),
            Text('Rp ${order.totalAmount.toStringAsFixed(0)}',
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    color: AppColors.accent)),
          ]),
          const SizedBox(height: 28),

          const Text('Metode Pembayaran',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 16)),
          const SizedBox(height: 16),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2,
            children: [
              _payBtn('Tunai', Icons.money, 'cash', order, isCash: true),
              _payBtn('QRIS', Icons.qr_code_2, 'qris', order),
              _payBtn('Debit', Icons.credit_card, 'debit_card', order),
              _payBtn('Kredit', Icons.credit_card_outlined, 'credit_card', order),
              _payBtn('Transfer', Icons.account_balance, 'transfer', order),
              _payBtn('Voucher', Icons.local_offer_outlined, 'voucher', order),
            ],
          ),
        ],
      ),
    );
  }

  // ─── SHARED WIDGETS (tetap sama) ─────────────────────────────────────────
  Widget _totalBox(double amount) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Total Tagihan',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: AppColors.textSecondary)),
            Text('Rp ${amount.toStringAsFixed(0)}',
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent)),
          ],
        ),
      );

  Widget _changeBox(double change) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: change >= 0
              ? AppColors.available.withValues(alpha: 0.1)
              : _red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: change >= 0
                ? AppColors.available.withValues(alpha: 0.4)
                : _red.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Kembalian',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            Text(
              change < 0
                  ? '- Rp ${(-change).toStringAsFixed(0)}'
                  : 'Rp ${change.toStringAsFixed(0)}',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: change >= 0 ? AppColors.available : _red),
            ),
          ],
        ),
      );

  Widget _buildStatusBadge(OrderStatus status) {
    final Map<OrderStatus, (String, Color)> map = {
      OrderStatus.new_: ('Baru', AppColors.orderNew),
      OrderStatus.preparing: ('Sedang Dimasak', AppColors.orderPreparing),
      OrderStatus.ready: ('Siap Disajikan', AppColors.orderReady),
      OrderStatus.served: ('Sudah Tersaji', AppColors.primary),
    };
    final info = map[status];
    if (info == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: info.$2.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: info.$2.withValues(alpha: 0.4)),
      ),
      child: Text(info.$1,
          style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: info.$2)),
    );
  }

  Widget _summaryRow(String label, double amount, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Text(label, style: AppTextStyles.bodySecondary),
          const Spacer(),
          Text('Rp ${amount.abs().toStringAsFixed(0)}',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  color: color ?? AppColors.textPrimary,
                  fontWeight: FontWeight.w500)),
        ]),
      );

  Widget _payBtn(
    String label,
    IconData icon,
    String method,
    OrderModel order, {
    bool isCash = false,
  }) =>
      ElevatedButton.icon(
        onPressed: () => isCash
            ? _onCashPayment(order)
            : _onNonCashPayment(order, method),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        icon: Icon(icon, size: 16),
        label: Text(label,
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      );

  List<double> _quickCash(double total) {
    final pecahan = [10000.0, 20000.0, 50000.0, 100000.0, 200000.0, 500000.0];
    final result = <double>[];
    for (final p in pecahan) {
      final rounded = (total / p).ceil() * p;
      if (!result.contains(rounded) && result.length < 4) {
        result.add(rounded);
      }
    }
    return result;
  }

  String _formatNominal(double n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(0)}jt';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}rb';
    return n.toStringAsFixed(0);
  }
}

// ─── Config model untuk non-cash ─────────────────────────────────────────────
class _NonCashConfig {
  final String label;
  final IconData icon;
  final String instruction;
  final String refLabel;
  final String refHint;
  final bool refRequired;

  const _NonCashConfig({
    required this.label,
    required this.icon,
    required this.instruction,
    required this.refLabel,
    required this.refHint,
    required this.refRequired,
  });
}

// ─── Bill Request Bottom Sheet ────────────────────────────────────────────────
// Stateful supaya bisa polling perubahan _orders dari parent via getOrders()
class _BillRequestSheet extends StatefulWidget {
  final List<OrderModel> Function() getOrders;
  final void Function(OrderModel) onSelectOrder;
  final VoidCallback onDismiss;

  const _BillRequestSheet({
    required this.getOrders,
    required this.onSelectOrder,
    required this.onDismiss,
  });

  @override
  State<_BillRequestSheet> createState() => _BillRequestSheetState();
}

class _BillRequestSheetState extends State<_BillRequestSheet> {
  @override
  Widget build(BuildContext context) {
    final orders = widget.getOrders();

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Handle bar ──────────────────────────────────────────────────
          const SizedBox(height: 12),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFD1D5DB),
              borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),

          // ── Header ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3CD),
                  borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.notifications_active,
                    color: Color(0xFFF59E0B), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('🔔 Minta Bill',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: Color(0xFF1A1A2E))),
                  Text(
                    orders.length == 1
                        ? '1 customer menunggu bill'
                        : '${orders.length} customer menunggu bill',
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: AppColors.textSecondary)),
                ]),
              ),
              // Badge jumlah
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B),
                  borderRadius: BorderRadius.circular(20)),
                child: Text('${orders.length}',
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: Colors.white)),
              ),
            ]),
          ),

          const SizedBox(height: 16),
          const Divider(height: 1),

          // ── List orders ─────────────────────────────────────────────────
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: orders.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 20, endIndent: 20),
              itemBuilder: (_, i) {
                final o = orders[i];
                final lokasi = o.tableNumber != null
                    ? 'Meja ${o.tableNumber}'
                    : o.customerName != null
                        ? o.customerName!
                        : 'Takeaway';
                final queueNum = o.queueNumber;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(children: [
                    // Avatar nomor antrian / meja
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFF59E0B), width: 1.5)),
                      child: Center(
                        child: Text(
                          queueNum ?? o.orderNumber.split('-').last,
                          style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              color: Color(0xFFB45309)))),
                    ),
                    const SizedBox(width: 12),

                    // Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(lokasi,
                              style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: Color(0xFF1A1A2E))),
                          const SizedBox(height: 2),
                          Row(children: [
                            if (o.customerName != null && o.tableNumber != null) ...[
                              Text(o.customerName!,
                                  style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 12,
                                      color: AppColors.textSecondary)),
                              const Text(' · ',
                                  style: TextStyle(color: AppColors.textSecondary)),
                            ],
                            Text('Rp ${o.totalAmount.toStringAsFixed(0)}',
                                style: const TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.accent)),
                          ]),
                        ],
                      ),
                    ),

                    // Tombol Proses
                    ElevatedButton(
                      onPressed: () => widget.onSelectOrder(o),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Proses',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                    ),
                  ]),
                );
              },
            ),
          ),

          // ── Footer ──────────────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(
                20, 8, 20, MediaQuery.of(context).padding.bottom + 16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: widget.onDismiss,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: const BorderSide(color: Color(0xFFD1D5DB)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Tutup — Proses Nanti',
                    style: TextStyle(
                        fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}