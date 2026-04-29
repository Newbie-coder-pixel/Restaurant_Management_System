import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/models/order_model.dart';
import '../../../core/theme/app_theme.dart';
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
  RealtimeChannel? _channel;
  OrderModel? _selected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    _branchId = ref.read(currentStaffProvider)?.branchId;
    await _load();
    _subscribeRealtime();
  }

  Future<void> _load() async {
    if (_branchId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      // Kasir logic (flow baru: bayar SETELAH makan untuk semua order type):
      // - QR Order   -> muncul saat status 'served' + payment_status 'pending'
      // - Staff Order -> muncul saat status 'served' + payment_status 'pending'
      // Kedua tipe order sekarang bayar setelah makan, cukup 1 query.
      final res = await Supabase.instance.client
    .from('orders')
    .select('*, restaurant_tables(table_number), order_items(*)')
    .eq('branch_id', _branchId!)
    .inFilter('status', ['ready', 'served'])
.inFilter('payment_status', ['pending', 'unpaid'])
    .order('created_at', ascending: true);

      if (mounted) {
        setState(() {
          _orders = (res as List)
              .map((e) => OrderModel.fromJson(e as Map<String, dynamic>))
              .toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error load cashier orders: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _subscribeRealtime() {
    _channel = Supabase.instance.client
        .channel('cashier_orders')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (_) => _load(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  // ─── CASH PAYMENT ────────────────────────────────────────────────────────
  Future<void> _onCashPayment(OrderModel order) async {
    final cashController = TextEditingController();
    double change = 0;

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
              onPressed: change >= 0
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
  bool _canCancel(OrderModel order) =>
      order.status == OrderStatus.new_ ||
      order.status == OrderStatus.preparing;

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

    // Flow pembayaran baru: semua order (QR maupun Staff) bayar setelah makan.
    // Status selalu → 'paid' setelah pembayaran dikonfirmasi kasir.
    await Supabase.instance.client.from('orders').update({
      'status': 'paid',
      'payment_status': 'paid',
      'cashier_id': staff?.id,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', order.id);

    await Supabase.instance.client.from('payments').insert({
      'order_id': order.id,
      'branch_id': _branchId,
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
                  // Badge: QR Order vs Staff Order
                  final isQrOrder = o.orderType == 'qr_order';
                  final badgeColor = isQrOrder
                      ? const Color(0xFF7C3AED)
                      : AppColors.primary;

                  return GestureDetector(
                    onTap: () => setState(() => _selected = o),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary.withValues(alpha: 0.05)
                            : AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? AppColors.primary : AppColors.border,
                          width: isSelected ? 2 : 1,
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
                                      isQrOrder
                                          ? Icons.qr_code_scanner
                                          : Icons.person_outline,
                                      size: 9, color: badgeColor),
                                    const SizedBox(width: 3),
                                    Text(isQrOrder ? 'QR' : 'Staff',
                                      style: TextStyle(
                                        fontFamily: 'Poppins', fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: badgeColor)),
                                  ]),
                                ),
                              ]),
                              Text(
                                '${o.items.length} item • ${o.status.label}',
                                style: AppTextStyles.caption,
                              ),
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
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load)
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
          _summaryRow('PPN (11%)', order.taxAmount),
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