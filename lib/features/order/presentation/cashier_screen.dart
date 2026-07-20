import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/models/order_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/staff_role.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/widgets/app_drawer.dart';
import '../../payment/presentation/screens/midtrans_payment_screen.dart';

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
            discount_amount, notes, created_at, updated_at, served_at,
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
              : Column(children: [
                  if (_canCancel(_selected!))
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: AppColors.border),
                        ),
                      ),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          icon: const Icon(Icons.cancel_outlined,
                              size: 18, color: _red),
                          label: const Text('Batalkan Order',
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w600,
                                  color: _red)),
                          onPressed: () => _onCancelOrder(_selected!),
                        ),
                      ),
                    ),
                  Expanded(
                    child: MidtransPaymentScreen(
                      order: _selected!,
                      onPaymentSuccess: () {
                        setState(() => _selected = null);
                        _load();
                      },
                      onClose: () => setState(() => _selected = null),
                    ),
                  ),
                ]),
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
          actions: [
            if (_canCancel(_selected!))
              IconButton(
                icon: const Icon(Icons.cancel_outlined),
                tooltip: 'Batalkan Order',
                onPressed: () => _onCancelOrder(_selected!),
              ),
          ],
        ),
        body: MidtransPaymentScreen(
          order: _selected!,
          onPaymentSuccess: () {
            setState(() => _selected = null);
            _load();
          },
          onClose: () => setState(() => _selected = null),
        ),
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
                                if (o.isOvertime) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEE2E2),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: AppColors.accent),
                                    ),
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      const Icon(Icons.timer_outlined, size: 9, color: AppColors.accent),
                                      const SizedBox(width: 3),
                                      Text('+Rp ${o.overtimeCharge}',
                                        style: const TextStyle(
                                          fontFamily: 'Poppins', fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.accent)),
                                    ]),
                                  ),
                                ],
                              ]),
                            ],
                          ),
                        ),
                        Text(
                          'Rp ${o.totalAmountWithOvertime.toStringAsFixed(0)}',
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