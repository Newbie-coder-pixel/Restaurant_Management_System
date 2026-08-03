import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/cart_provider.dart';
import '../../../core/services/prep_time_service.dart';

// ── Order Success Screen ───────────────────────────────────────────
class CustomerOrderSuccessScreen extends StatelessWidget {
  final String orderNumber;
  const CustomerOrderSuccessScreen({super.key, required this.orderNumber});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF9F9FB),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated check icon
            TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 600),
              tween: Tween(begin: 0.0, end: 1.0),
              builder: (_, scale, child) => Transform.scale(
                scale: scale,
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [const Color(0xFF1D9E75), const Color(0xFF1D9E75).withValues(alpha: 0.6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: const Color(0xFF1D9E75).withValues(alpha: 0.3), blurRadius: 20, spreadRadius: 2)
                    ],
                  ),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 56),
                ),
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'Order Successful! 🎉',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A2E),
                letterSpacing: -0.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Your order has been sent to the kitchen.\nPlease show this code to the cashier.',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            // Order number card with glassmorphism effect
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 16, offset: const Offset(0, 8))
                ],
                border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
              ),
              child: Column(
                children: [
                  const Text(
                    'Order No.',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white70,
                      fontSize: 13,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    orderNumber,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            // Primary button
            ElevatedButton(
              onPressed: () => context.go('/customer/track/$orderNumber'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE94560),
                foregroundColor: Colors.white,
                minimumSize: const Size(220, 52),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                textStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700),
              ),
              child: const Text('Check Order Status'),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => context.go('/customer'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              ),
              child: const Text(
                'Back to Home',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 14, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ── Booking Success Screen ─────────────────────────────────────────
class CustomerBookingSuccessScreen extends StatelessWidget {
  const CustomerBookingSuccessScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF9F9FB),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 600),
              tween: Tween(begin: 0.0, end: 1.0),
              builder: (_, scale, child) => Transform.scale(
                scale: scale,
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [const Color(0xFF0F3460), const Color(0xFF0F3460).withValues(alpha: 0.7)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: const Color(0xFF0F3460).withValues(alpha: 0.3), blurRadius: 20, spreadRadius: 2)
                    ],
                  ),
                  child: const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 52),
                ),
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'Reservation Confirmed! 📅',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A2E),
                letterSpacing: -0.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Your reservation has been recorded.\nWe look forward to your visit!',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),
            ElevatedButton(
              onPressed: () => context.go('/customer'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F3460),
                foregroundColor: Colors.white,
                minimumSize: const Size(220, 52),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                textStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700),
              ),
              child: const Text('Back to Home'),
            ),
          ],
        ),
      ),
    ),
  );
}

// ── Order Tracker Screen ───────────────────────────────────────────
class CustomerOrderTrackerScreen extends ConsumerStatefulWidget {
  final String? initialOrderNumber;
  const CustomerOrderTrackerScreen({super.key, this.initialOrderNumber});

  @override
  ConsumerState<CustomerOrderTrackerScreen> createState() =>
      _CustomerOrderTrackerScreenState();
}

class _CustomerOrderTrackerScreenState
    extends ConsumerState<CustomerOrderTrackerScreen> {
  final _ctrl = TextEditingController();
  Map<String, dynamic>? _order;
  List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  String? _error;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    if (widget.initialOrderNumber != null) {
      _ctrl.text = widget.initialOrderNumber!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _channel?.unsubscribe();
    super.dispose();
  }

  void _subscribeRealtime(String orderId) {
    _channel?.unsubscribe();
    _channel = Supabase.instance.client
        .channel('tracker_$orderId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: orderId),
          callback: (payload) {
            if (mounted && payload.newRecord.isNotEmpty) {
              setState(() => _order = {..._order!, ...payload.newRecord});
            }
          })
        .subscribe();
  }

  Future<void> _search() async {
    final code = _ctrl.text.trim().toUpperCase();
    if (code.isEmpty) return;

    setState(() { _loading = true; _error = null; _order = null; _items = []; });
    _channel?.unsubscribe();

    try {
      final user = Supabase.instance.client.auth.currentUser;

      if (user != null) {
        // First try to find an order belonging to this user
        final ownOrders = await Supabase.instance.client
            .from('orders')
            // Columns explicitly restricted (not select all) — order_number can
            // be guessed/enumerated (short format A001..Z999) and this endpoint
            // is accessible without login, so sensitive data such as customer
            // phone number & email is deliberately NOT fetched here.
            .select('id, order_number, queue_number, table_id, table_name, '
                'branch_id, customer_name, status, payment_status, '
                'payment_method, order_type, source, subtotal, tax_amount, '
                'discount_amount, total_amount, notes, bill_requested, '
                'bill_requested_at, estimated_prep_minutes, sent_to_kitchen_at, '
                'served_at, created_at, updated_at')
            .eq('order_number', code)
            .eq('customer_user_id', user.id)
            .limit(1);

        if ((ownOrders as List).isNotEmpty) {
          await _processOrderResult(ownOrders.first);
          return;
        }

        // Fallback: find any order with this number
        final anyOrder = await Supabase.instance.client
            .from('orders')
            // Columns explicitly restricted (not select all) — order_number can
            // be guessed/enumerated (short format A001..Z999) and this endpoint
            // is accessible without login, so sensitive data such as customer
            // phone number & email is deliberately NOT fetched here.
            .select('id, order_number, queue_number, table_id, table_name, '
                'branch_id, customer_name, status, payment_status, '
                'payment_method, order_type, source, subtotal, tax_amount, '
                'discount_amount, total_amount, notes, bill_requested, '
                'bill_requested_at, estimated_prep_minutes, sent_to_kitchen_at, '
                'served_at, created_at, updated_at')
            .eq('order_number', code)
            .limit(1);

        if ((anyOrder as List).isNotEmpty) {
          await _processOrderResult(anyOrder.first);
          return;
        }
      } else {
        // Anon user: build a new query (do not reuse the old query object)
        final res = await Supabase.instance.client
            .from('orders')
            // Columns explicitly restricted (not select all) — order_number can
            // be guessed/enumerated (short format A001..Z999) and this endpoint
            // is accessible without login, so sensitive data such as customer
            // phone number & email is deliberately NOT fetched here.
            .select('id, order_number, queue_number, table_id, table_name, '
                'branch_id, customer_name, status, payment_status, '
                'payment_method, order_type, source, subtotal, tax_amount, '
                'discount_amount, total_amount, notes, bill_requested, '
                'bill_requested_at, estimated_prep_minutes, sent_to_kitchen_at, '
                'served_at, created_at, updated_at')
            .eq('order_number', code)
            .limit(1);

        if ((res as List).isNotEmpty) {
          await _processOrderResult(res.first);
          return;
        }
      }

      if (mounted) {
        setState(() {
          _error = 'Order "$code" not found.\nMake sure the order number is correct.';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() { _error = 'An error occurred. Please try again.'; _loading = false; });
      }
    }
  }

  // ── FIX 1: Add preparation_time_minutes to the select ──────────────
  Future<void> _processOrderResult(Map<String, dynamic> order) async {
    try {
      final items = await Supabase.instance.client
          .from('order_items')
          .select('*, menu_items(name, preparation_time_minutes)') // <-- FIXED
          .eq('order_id', order['id'])
          .order('created_at');

      if (mounted) {
        setState(() {
          _order = order;
          _items = (items as List).cast();
          _loading = false;
        });
        _subscribeRealtime(order['id'] as String);
      }
    } catch (e) {
      if (mounted) {
        setState(() { _error = 'Failed to load order details.'; _loading = false; });
      }
    }
  }

  Future<void> _reorder() async {
    if (_order == null || _items.isEmpty) return;

    final branchId = _order!['branch_id'] as String?;
    if (branchId == null) return;

    final validItems = _items
        .where((i) => i['menu_item_id'] != null && i['menu_items'] != null)
        .toList();

    if (validItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No items available to reorder.'),
        backgroundColor: Colors.orange));
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Reorder?',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: Text(
            'All items from order #${_order!['order_number']} will be added to the cart.',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(fontFamily: 'Poppins', color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE94560),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
            child: const Text('Yes, Reorder',
                style: TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w600))),
        ]));

    if (confirm != true || !mounted) return;

    // Prices are re-validated server-side on checkout insert anyway (menu
    // price always wins), but fetch current prices here too so the cart the
    // customer sees isn't silently stale versus what they'll actually pay.
    final menuItemIds =
        validItems.map((i) => i['menu_item_id'] as String).toSet().toList();
    final currentPrices = <String, double>{};
    try {
      final rows = await Supabase.instance.client
          .from('menu_items')
          .select('id, price')
          .inFilter('id', menuItemIds);
      for (final r in (rows as List)) {
        currentPrices[r['id'] as String] = (r['price'] as num).toDouble();
      }
    } catch (_) {
      // Fall back to historical prices below if this fails.
    }

    bool priceChanged = false;
    ref.read(cartProvider.notifier).setBranch(branchId, '');
    for (final item in validItems) {
      final menuItemId = item['menu_item_id'] as String;
      final historicalPrice = (item['unit_price'] as num).toDouble();
      final currentPrice = currentPrices[menuItemId] ?? historicalPrice;
      if ((currentPrice - historicalPrice).abs() > 0.01) priceChanged = true;
      ref.read(cartProvider.notifier).addItem(CartItem(
        menuItemId: menuItemId,
        name: (item['menu_items'] as Map)['name'] as String,
        price: currentPrice,
        quantity: item['quantity'] as int? ?? 1,
      ));
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(priceChanged
            ? '✅ Items added to cart. Some prices have changed since your last order.'
            : '✅ Item added to cart!'),
        backgroundColor: const Color(0xFF1D9E75)));
      context.go('/customer/checkout');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF9F9FB),
    appBar: AppBar(
      backgroundColor: const Color(0xFF1A1A2E),
      foregroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, size: 18),
        onPressed: () => context.go('/customer')),
      title: const Text('Track Order',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 18)),
      centerTitle: false,
      actions: [
        if (_order != null)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1D9E75),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                const Text('Live',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF1D9E75))),
              ],
            ),
          ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      physics: const BouncingScrollPhysics(),
      children: [
        // Search box
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 12, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter Order Number',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'The order number is on your receipt or confirmation screen.',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: Colors.grey.shade500,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      textCapitalization: TextCapitalization.characters,
                      onSubmitted: (_) => _search(),
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Example: WEB-20260327-1234',
                        hintStyle: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          color: Colors.grey.shade400,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF5F7FA),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: Color(0xFFE94560), width: 1.5),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _loading ? null : _search,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE94560),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(56, 56),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5),
                          )
                        : const Icon(Icons.search_rounded, size: 26),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Error message
        if (_error != null) ...[
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F0),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFFC4C0), width: 1),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Color(0xFFE94560), size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      color: Color(0xFFB91C1C),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // Order card
        if (_order != null) ...[
          const SizedBox(height: 24),
          AnimatedSize(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            child: _OrderStatusCard(order: _order!, items: _items),
          ),
          if (_order!['status'] == 'paid') ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _reorder,
                icon: const Icon(Icons.replay_outlined, size: 20, color: Color(0xFFE94560)),
                label: const Text(
                  'Reorder',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: Color(0xFFE94560),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(color: Color(0xFFE94560), width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
        ],

        // Empty state
        if (_order == null && _error == null && !_loading) ...[
          const SizedBox(height: 60),
          Column(
            children: [
              Icon(Icons.receipt_long_outlined, size: 72, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              Text(
                'Enter your order number above\nto see its status.',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  color: Colors.grey.shade500,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

// ── Order Status Card ──────────────────────────────────────────────
class _OrderStatusCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final List<Map<String, dynamic>> items;
  const _OrderStatusCard({required this.order, required this.items});

  static const _statusLabels = {
    'new':       '🆕 New Order',
    'preparing': '👨‍🍳 Preparing',
    'ready':     '✅ Ready to Serve',
    'served':    '🍽️ Served',
    'paid':      '💳 Paid',
    'cancelled': '❌ Cancelled',
  };
  static const _statusColors = {
    'new':       Color(0xFF6B7280),
    'preparing': Color(0xFFD97706),
    'ready':     Color(0xFF1D9E75),
    'served':    Color(0xFF0F3460),
    'paid':      Color(0xFF1D9E75),
    'cancelled': Color(0xFFE94560),
  };
  static const _statusMessages = {
    'new':       '⏳ Your order is waiting for kitchen confirmation.',
    'preparing': '🔥 The kitchen is preparing your order, almost there!',
    'ready':     '🎉 Your order is ready! A server will bring it to you shortly.',
    'served':    '😊 Your order has been served. Enjoy your meal!',
    'paid':      '✅ Payment complete. Thank you for visiting!',
    'cancelled': '❌ This order was cancelled.',
  };

  @override
  Widget build(BuildContext context) {
    final status      = order['status'] as String? ?? 'new';
    final statusLabel = _statusLabels[status] ?? status;
    final statusColor = _statusColors[status] ?? Colors.grey;
    final statusMsg   = _statusMessages[status] ?? '';
    // Calculate subtotal from items (not from order['total_amount'] which can be 0/null)
    final subtotal     = items.fold<double>(0, (sum, item) => sum + ((item['subtotal'] as num?)?.toDouble() ?? 0));
    final discount     = (order['discount_amount'] as num?)?.toDouble() ?? 0;
    final serviceCharge = subtotal * 0.03;
    // PB1 is computed from subtotal only, matching the formula the customer
    // actually confirmed at checkout (see cart_provider.dart pb1Amount) —
    // this used to be (subtotal + serviceCharge) * 0.10 here, which showed a
    // different total post-order than what was agreed to at checkout.
    final pb1Amount    = subtotal * 0.10;
    final total        = subtotal + serviceCharge + pb1Amount - discount;
    final customerName = order['customer_name'] as String?;
    final notes        = order['notes'] as String?;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 16, offset: const Offset(0, 6)),
        ],
        border: Border.all(color: Colors.grey.shade100, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order['order_number'] as String? ?? '',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    if (customerName != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Under the name: $customerName',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),

          if (statusMsg.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: statusColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      statusMsg,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: statusColor,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const Divider(height: 28, thickness: 1, color: Color(0xFFEEEEEE)),

          // Progress indicator
          _StatusProgress(status: status),

          // ── ML Time Estimate (only when new / preparing) ────────────
          if (status == 'new' || status == 'preparing') ...[
            const SizedBox(height: 16),
            _CustomerPrepTimeCard(order: order, items: items),
          ],

          const SizedBox(height: 24),

          // Items list
          const Text(
            'Order Items',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 12),
          ...items.map((item) {
            final name    = (item['menu_items'] as Map?)?['name'] as String?
                          ?? item['menu_item_name'] as String? // fallback to the order_items column
                          ?? '-';
            final qty     = item['quantity'] as int? ?? 1;
            final sub     = (item['subtotal'] as num?)?.toDouble() ?? 0;
            final special = item['special_requests'] as String?;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 28,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${qty}x',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.grey.shade500,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            color: Color(0xFF1A1A2E),
                          ),
                        ),
                      ),
                      Text(
                        'Rp ${_fmt(sub)}',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFE94560),
                        ),
                      ),
                    ],
                  ),
                  if (special != null && special.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 32, top: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.edit_note, size: 14, color: Color(0xFFD97706)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              special,
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                color: Color(0xFFD97706),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          }),

          if (notes != null && notes.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FC),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.note_add_rounded, size: 18, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      notes,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const Divider(height: 24, thickness: 1, color: Color(0xFFEEEEEE)),

          // Subtotal
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Subtotal',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
              Text(
                'Rp ${_fmt(subtotal)}',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Service Charge & PB1
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Service Charge (3%)',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
              Text(
                'Rp ${_fmt(serviceCharge)}',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'PB1 (10%)',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
              Text(
                'Rp ${_fmt(pb1Amount)}',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),

          // Discount (only shown if present)
          if (discount > 0) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Discount',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
                Text(
                  '- Rp ${_fmt(discount)}',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: Color(0xFF1D9E75),
                  ),
                ),
              ],
            ),
          ],

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(thickness: 1, color: Color(0xFFEEEEEE)),
          ),

          // Total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              Text(
                'Rp ${_fmt(total)}',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: Color(0xFFE94560),
                ),
              ),
            ],
          ),

          if (status != 'paid' && status != 'cancelled') ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF7E0),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFFB45309)),
                  SizedBox(width: 8),
                  Text(
                    '💡 Pay at the cashier when the order is ready.',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: Color(0xFFB45309),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _fmt(double v) {
    final s = v.toStringAsFixed(0);
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write('.');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }
}

// ── ML Prep Time Card (Customer) ─────────────────────────────────
class _CustomerPrepTimeCard extends StatefulWidget {
  final Map<String, dynamic> order;
  final List<Map<String, dynamic>> items;

  const _CustomerPrepTimeCard({required this.order, required this.items});

  @override
  State<_CustomerPrepTimeCard> createState() => _CustomerPrepTimeCardState();
}

class _CustomerPrepTimeCardState extends State<_CustomerPrepTimeCard> {
  late final Future<PrepTimeResult?> _future;
  late final List<PrepTimeRequestItem> _requestItems;

  // ── FIX 2: Use preparation_time_minutes from the join, not hardcoded 15 ──
  List<PrepTimeRequestItem> _buildRequestItems() {
    return widget.items.map((item) {
      // Name: from the menu_items join, fallback to the menu_item_name column in order_items
      final name = (item['menu_items'] as Map?)?['name'] as String?
                 ?? item['menu_item_name'] as String?
                 ?? '-';
      final qty  = item['quantity'] as int? ?? 1;
      final special = item['special_requests'] as String?;

      // Prep time: from the menu_items join, fallback to 15 minutes if the item was deleted
      final prepTime = (item['menu_items'] as Map?)?['preparation_time_minutes'] as int?
                     ?? 15;

      return PrepTimeRequestItem(
        menuItemName:           name,
        quantity:               qty,
        preparationTimeMinutes: prepTime, // <-- FIXED: use the real value from the DB
        specialRequests:        special,
      );
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _requestItems = _buildRequestItems();
    _future = PrepTimeService.predict(
      items: _requestItems,
      branchId: widget.order['branch_id'] as String? ?? '',
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PrepTimeResult?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF0F3460),
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  'Calculating cooking time estimate...',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: Color(0xFF0F3460),
                  ),
                ),
              ],
            ),
          );
        }

        final result = snap.data;
        // Server unreachable (e.g. down/timeout) → show a rough estimate
        // (sum of menu prep times, without ML/buffer) rather than have this
        // card disappear entirely with no information at all.
        final isFallback = snap.hasError || result == null;
        final displayMinutes = isFallback
            ? PrepTimeService.rawFallbackEstimate(_requestItems)
            : result.estimatedMinutes;
        if (isFallback && displayMinutes <= 0) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFF7ED), Color(0xFFFFF1DC)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFD97706).withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFD97706).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                    isFallback
                        ? Icons.access_time_outlined
                        : Icons.soup_kitchen_outlined,
                    color: const Color(0xFFD97706),
                    size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isFallback ? 'Rough Estimate (offline)' : 'Cooking Time Estimate',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: Color(0xFFB45309),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      PrepTimeService.formatEstimate(displayMinutes),
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFD97706),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFD97706).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: const Color(0xFFD97706).withValues(alpha: 0.3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.smart_toy_outlined,
                        size: 11, color: Color(0xFFD97706)),
                    SizedBox(width: 3),
                    Text(
                      'AI',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFD97706),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Progress Bar ──────────────────────────────────────────────────
class _StatusProgress extends StatelessWidget {
  final String status;
  const _StatusProgress({required this.status});

  @override
  Widget build(BuildContext context) {
    const steps  = ['new', 'preparing', 'ready', 'served', 'paid'];
    const labels = ['New', 'Cooking', 'Ready', 'Served', 'Paid'];
    final currentIdx  = steps.indexOf(status);
    final isCancelled = status == 'cancelled';

    if (isCancelled) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1F0),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cancel_outlined, color: Color(0xFFE94560), size: 20),
            SizedBox(width: 8),
            Text(
              'Order cancelled',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: Color(0xFFE94560),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: steps.asMap().entries.map((e) {
        final idx = e.key;
        final isActive = idx <= currentIdx;
        final isCurrent = idx == currentIdx;
        final isLast = idx == steps.length - 1;

        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      width: isCurrent ? 28 : 22,
                      height: isCurrent ? 28 : 22,
                      decoration: BoxDecoration(
                        color: isActive ? const Color(0xFFE94560) : const Color(0xFFE9ECF0),
                        shape: BoxShape.circle,
                        boxShadow: isCurrent
                            ? [BoxShadow(color: const Color(0xFFE94560).withValues(alpha: 0.4), blurRadius: 12)]
                            : [],
                      ),
                      child: Center(
                        child: isActive
                            ? const Icon(Icons.check, color: Colors.white, size: 14)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      labels[idx],
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10,
                        fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                        color: isActive ? const Color(0xFFE94560) : Colors.grey.shade500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              if (!isLast)
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    height: 3,
                    color: idx < currentIdx
                        ? const Color(0xFFE94560)
                        : const Color(0xFFE9ECF0),
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }
}