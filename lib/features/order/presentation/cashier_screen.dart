import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/models/order_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/widgets/app_drawer.dart';

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
      final res = await Supabase.instance.client
          .from('orders')
          .select('*, restaurant_tables(table_number), order_items(*, menu_items(name))')
          .eq('branch_id', _branchId!)
          .inFilter('status', ['new', 'preparing', 'ready', 'served'])
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _orders = (res as List).map((e) => OrderModel.fromJson(e)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _subscribeRealtime() {
    _channel = Supabase.instance.client
        .channel('cashier_orders')
        .onPostgresChanges(
          event: PostgresChangeEvent.all, schema: 'public',
          table: 'orders', callback: (_) => _load())
        .subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _processPayment(OrderModel order, String method) async {
    final staff = ref.read(currentStaffProvider);
    await Supabase.instance.client.from('orders').update({
      'status': 'paid',
      'cashier_id': staff?.id,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', order.id);

    await Supabase.instance.client.from('payments').insert({
      'order_id': order.id,
      'branch_id': _branchId,
      'method': method,
      'amount': order.totalAmount,
      'status': 'paid',
      'processed_by': staff?.id,
    });

    if (order.tableId != null) {
      await Supabase.instance.client.from('restaurant_tables')
          .update({'status': 'cleaning'}).eq('id', order.tableId!);
    }

    if (mounted) {
      setState(() => _selected = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Pembayaran order #${order.orderNumber} berhasil!'),
        backgroundColor: AppColors.available,
      ));
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 800;
    return isWide ? _buildWideLayout() : _buildNarrowLayout();
  }

  Widget _buildWideLayout() => Row(children: [
    SizedBox(width: 380, child: _buildOrderList(showAppBar: true)),
    const VerticalDivider(width: 1),
    Expanded(
      child: _selected == null ? _buildEmptyDetail() : _buildPaymentPanel(_selected!)),
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
            ? const Center(child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_outlined, size: 64, color: AppColors.textHint),
                  SizedBox(height: 12),
                  Text('Tidak ada order pending',
                    style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)),
                ]))
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _orders.length,
                itemBuilder: (_, i) {
                  final o = _orders[i];
                  final isSelected = _selected?.id == o.id;
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
                          width: isSelected ? 2 : 1),
                      ),
                      child: Row(children: [
                        Container(
                          width: 42, height: 42,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(10)),
                          child: Center(child: Text(
                            o.orderNumber.split('-').last,
                            style: const TextStyle(
                              fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                              color: Colors.white, fontSize: 13))),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(o.tableNumber != null ? 'Meja ${o.tableNumber}' : 'Takeaway',
                              style: const TextStyle(
                                fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14)),
                            Text('${o.items.length} item • ${o.status.label}',
                              style: AppTextStyles.caption),
                          ])),
                        Text('Rp ${o.totalAmount.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                            fontSize: 14, color: AppColors.accent)),
                      ]),
                    ),
                  );
                });

    if (!showAppBar) return body;
    return Scaffold(
      drawer: const AppDrawer(),
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Kasir'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        titleTextStyle: const TextStyle(
          fontFamily: 'Poppins', fontSize: 18,
          fontWeight: FontWeight.w600, color: Colors.white),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: body,
    );
  }

  Widget _buildEmptyDetail() => const Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.touch_app_outlined, size: 64, color: AppColors.textHint),
      SizedBox(height: 12),
      Text('Pilih order untuk proses pembayaran',
        style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)),
    ]),
  );

  Widget _buildPaymentPanel(OrderModel order) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Order #${order.orderNumber}', style: AppTextStyles.heading2),
      if (order.tableNumber != null)
        Text('Meja ${order.tableNumber}', style: AppTextStyles.bodySecondary),
      const SizedBox(height: 20),
      const Text('Rincian Pesanan',
        style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      ...order.items.map((item) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Text('${item.menuItemName} x${item.quantity}',
            style: AppTextStyles.body)),
          Text('Rp ${item.subtotal.toStringAsFixed(0)}', style: AppTextStyles.body),
        ]),
      )),
      const Divider(height: 24),
      _summaryRow('Subtotal', order.subtotal),
      _summaryRow('PPN (11%)', order.taxAmount),
      if (order.discountAmount > 0)
        _summaryRow('Diskon', -order.discountAmount, color: AppColors.available),
      const SizedBox(height: 8),
      Row(children: [
        const Text('TOTAL',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
        const Spacer(),
        Text('Rp ${order.totalAmount.toStringAsFixed(0)}',
          style: const TextStyle(
            fontFamily: 'Poppins', fontWeight: FontWeight.w700,
            fontSize: 20, color: AppColors.accent)),
      ]),
      const SizedBox(height: 28),
      const Text('Metode Pembayaran',
        style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 16)),
      const SizedBox(height: 16),
      GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 2,
        children: [
          _payBtn('Tunai',    Icons.money,                  'cash',        order),
          _payBtn('QRIS',     Icons.qr_code,                'qris',        order),
          _payBtn('Debit',    Icons.credit_card,             'debit_card',  order),
          _payBtn('Kredit',   Icons.credit_card_outlined,    'credit_card', order),
          _payBtn('Transfer', Icons.account_balance,         'transfer',    order),
          _payBtn('Voucher',  Icons.local_offer_outlined,    'voucher',     order),
        ],
      ),
    ]),
  );

  Widget _summaryRow(String label, double amount, {Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Text(label, style: AppTextStyles.bodySecondary),
      const Spacer(),
      Text('Rp ${amount.abs().toStringAsFixed(0)}',
        style: TextStyle(
          fontFamily: 'Poppins', fontSize: 14,
          color: color ?? AppColors.textPrimary,
          fontWeight: FontWeight.w500)),
    ]),
  );

  Widget _payBtn(String label, IconData icon, String method, OrderModel order) =>
    ElevatedButton.icon(
      onPressed: () => _processPayment(order, method),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary, foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: Icon(icon, size: 16),
      label: Text(label,
        style: const TextStyle(
          fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600)),
    );
}