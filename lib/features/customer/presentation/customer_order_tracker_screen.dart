import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/cart_provider.dart';
import '../../../core/services/prep_time_service.dart';
import '../../../shared/models/order_model.dart';
import '../../payment/services/receipt_service.dart';
import '../../../core/theme/app_theme.dart';

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
                color: AppColors.primary,
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
                color: AppColors.primary,
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
                backgroundColor: AppColors.accent,
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
                      colors: [AppColors.primaryLight, AppColors.primaryLight.withValues(alpha: 0.7)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: AppColors.primaryLight.withValues(alpha: 0.3), blurRadius: 20, spreadRadius: 2)
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
                color: AppColors.primary,
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
                backgroundColor: AppColors.primaryLight,
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
  bool _printingReceipt = false;

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

  // Deliberately does NOT merge payload.newRecord directly into _order — the
  // Postgres change payload comes off the WAL and it's unclear whether
  // Supabase Realtime enforces the same column-level grants a REST SELECT
  // does (see the column revoke in
  // supabase/migrations/20260805050000_full_order_pii_lockdown.sql). Since
  // _order never held customer_phone/customer_email in the first place,
  // re-fetching through get_order_by_number (NOT get_order_by_id, which
  // deliberately DOES include them) on every change event guarantees this
  // screen can't accidentally pick them up via a live-update path that
  // bypasses the same protection its initial fetch already has.
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
          callback: (_) async {
            final orderNumber = _order?['order_number'] as String?;
            if (orderNumber == null) return;
            final rows = await Supabase.instance.client.rpc('get_order_by_number', params: {
              'p_order_number': orderNumber,
            }) as List<dynamic>;
            if (mounted && rows.isNotEmpty) {
              setState(() => _order = rows.first as Map<String, dynamic>);
            }
          })
        .subscribe();
  }

  // Goes through the get_order_by_number RPC rather than a direct table
  // SELECT — this is reachable with no login and a guessable "A001"/"WEB-..."
  // style number, so it must never be able to return more than the one exact
  // match, and must never expose customer_phone/customer_email (see
  // supabase/migrations/20260805040000_get_order_by_number_rpc.sql — a direct
  // SELECT here was, until this fix, live-exploitable to dump every
  // customer's name/phone/email from the last 24 hours with no filter at all).
  Future<Map<String, dynamic>?> _fetchAnyOrderByNumber(String code) async {
    final rows = await Supabase.instance.client.rpc('get_order_by_number', params: {
      'p_order_number': code,
    }) as List<dynamic>;
    if (rows.isEmpty) return null;
    return rows.first as Map<String, dynamic>;
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
                'bill_requested_at, estimated_prep_minutes, '
                'served_at, created_at, updated_at')
            .eq('order_number', code)
            .eq('customer_user_id', user.id)
            .limit(1);

        if ((ownOrders as List).isNotEmpty) {
          await _processOrderResult(ownOrders.first);
          return;
        }

        // Fallback: find any order with this number — via RPC, not a direct
        // table SELECT (see _fetchAnyOrderByNumber).
        final anyOrder = await _fetchAnyOrderByNumber(code);
        if (anyOrder != null) {
          await _processOrderResult(anyOrder);
          return;
        }
      } else {
        // Anon user — via RPC, not a direct table SELECT.
        final res = await _fetchAnyOrderByNumber(code);
        if (res != null) {
          await _processOrderResult(res);
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
      debugPrint('CustomerOrderTrackerScreen._search failed: $e');
      if (mounted) {
        setState(() { _error = 'An error occurred. Please try again.'; _loading = false; });
      }
    }
  }

  // ── FIX 1: Add preparation_time_minutes to the select ──────────────
  Future<void> _processOrderResult(Map<String, dynamic> order) async {
    try {
      // get_order_items RPC rather than a direct SELECT — see
      // supabase/migrations/20260805050000_full_order_pii_lockdown.sql.
      final items = await Supabase.instance.client.rpc('get_order_items', params: {
        'p_order_id': order['id'],
      }) as List<dynamic>;

      if (mounted) {
        setState(() {
          _order = order;
          _items = items.cast();
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

  // Gated on payment_status (not the kitchen-progress `status`) — an order
  // paid up front (Midtrans/QRIS) can have a receipt printed as soon as
  // payment clears, regardless of whether the kitchen has served it yet; an
  // order still `served` but unpaid (pay-at-cashier flow, if this app ever
  // supports it) has nothing to receipt yet. Mirrors the existing QR
  // self-service flow's receipt button (qr_pay_now_screen.dart), which gates
  // the same way.
  Future<void> _printReceipt() async {
    if (_order == null || _printingReceipt) return;
    setState(() => _printingReceipt = true);
    try {
      final order = OrderModel.fromJson({
        ..._order!,
        'order_items': _items,
        'restaurant_tables': {'table_number': _order!['table_name']},
      });
      await ReceiptService.printReceipt(order: order);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to open receipt: $e'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _printingReceipt = false);
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
              backgroundColor: AppColors.accent,
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

  // ── TOP BAR (Cita Rasa header, shared visual language with other customer screens) ──
  Widget _buildTopBar() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.go('/customer'),
            child: const Text(
              'Cita Rasa',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 28),
          Expanded(
            child: Row(
              children: [
                _NavLink(label: 'Menu', onTap: () => context.go('/customer')),
                const SizedBox(width: 24),
                _NavLink(label: 'Locations', onTap: () => context.go('/customer')),
                const SizedBox(width: 24),
                _NavLink(label: 'Reservations', onTap: () => context.go('/customer?tab=1')),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => context.go('/customer/checkout'),
            child: const Icon(
              Icons.shopping_cart_outlined,
              color: AppColors.textPrimary,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () => context.go('/customer?tab=2'),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.arrow_back, size: 16, color: AppColors.textPrimary),
                              SizedBox(width: 8),
                              Text(
                                'Back to Current Orders',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (_order != null)
                          _buildOrderView(context)
                        else
                          _buildSearchView(context),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── SEARCH / EMPTY / ERROR STATE ─────────────────────────────────────
  Widget _buildSearchView(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Track Order',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: AppColors.border),
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
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'The order number is on your receipt or confirmation screen.',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: AppColors.textSecondary,
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
                        hintStyle: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          color: AppColors.textHint,
                        ),
                        filled: true,
                        fillColor: AppColors.surfaceVariant,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _loading ? null : _search,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(56, 56),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusSm)),
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

        if (_error != null) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.statusClosed.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: AppColors.statusClosed),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: AppColors.accent, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      color: AppColors.accent,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        if (_order == null && _error == null && !_loading) ...[
          const SizedBox(height: 60),
const Center(
            child: Column(
              children: [
                Icon(Icons.receipt_long_outlined, size: 72, color: AppColors.textHint),
                SizedBox(height: 16),
                Text(
                  'Enter your order number above\nto see its status.',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ── LOADED ORDER VIEW ─────────────────────────────────────────────────
  Widget _buildOrderView(BuildContext context) {
    final order = _order!;
    final tableName = order['table_name'] as String?;
    final orderType = order['order_type'] as String?;
    final typeLabel = tableName != null
        ? 'Table $tableName • Dine In'
        : switch (orderType) {
            'qr_order' => 'Dine In',
            _ => 'Takeaway',
          };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                'Order #${order['order_number'] ?? ''}',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ),
const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LiveDot(),
                  SizedBox(width: 6),
                  Text(
                    'Live',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1D9E75),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          typeLabel,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 15,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 860;
            final mainColumn = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TrackerStatusCard(order: order, items: _items),
                const SizedBox(height: 16),
                _TrackerItemsCard(order: order, items: _items),
              ],
            );
            final sidebar = _TrackerSidebar(
              order: order,
              items: _items,
              printing: _printingReceipt,
              onPrintReceipt: _printReceipt,
              onReorder: _reorder,
            );

            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: mainColumn),
                  const SizedBox(width: 24),
                  SizedBox(width: 320, child: sidebar),
                ],
              );
            }
            return Column(
              children: [mainColumn, const SizedBox(height: 16), sidebar],
            );
          },
        ),
      ],
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot();
  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 8,
    height: 8,
    child: DecoratedBox(
      decoration: BoxDecoration(color: Color(0xFF1D9E75), shape: BoxShape.circle),
    ),
  );
}

class _NavLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _NavLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

// ── Status header card (title + est. time + stepper) ────────────────────
class _TrackerStatusCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final List<Map<String, dynamic>> items;
  const _TrackerStatusCard({required this.order, required this.items});

  static const _titles = {
    'new': 'Order Received',
    'preparing': 'Preparing',
    'ready': 'Ready to Serve',
    'served': 'Served',
    'paid': 'Paid',
    'cancelled': 'Cancelled',
  };
  static const _subtitles = {
    'new': 'Your order is waiting for kitchen confirmation.',
    'preparing': 'Your food is being crafted in the kitchen.',
    'ready': 'Your order is ready! A server will bring it to you shortly.',
    'served': 'Your order has been served. Enjoy your meal!',
    'paid': 'Payment complete. Thank you for visiting!',
    'cancelled': 'This order was cancelled.',
  };

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String? ?? 'new';
    final paymentStatus = order['payment_status'] as String?;
    final title = _titles[status] ?? status;
    final subtitle = _subtitles[status] ?? '';
    final showEstimate = status == 'new' || status == 'preparing';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (showEstimate) ...[
                const SizedBox(width: 16),
                _CustomerPrepTimeCard(order: order, items: items),
              ],
            ],
          ),
          const SizedBox(height: 28),
          _StatusProgress(status: status, paymentStatus: paymentStatus),
        ],
      ),
    );
  }
}

// ── Items card ────────────────────────────────────────────────────────
class _TrackerItemsCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final List<Map<String, dynamic>> items;
  const _TrackerItemsCard({required this.order, required this.items});

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String? ?? 'new';
    final title = status == 'preparing' ? 'Items in Preparation' : 'Order Items';
    final notes = order['notes'] as String?;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.restaurant_outlined, size: 18, color: AppColors.accent),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: AppColors.border, height: 1),
          ...items.map((item) {
            final name = (item['menu_items'] as Map?)?['name'] as String?
                ?? item['menu_item_name'] as String?
                ?? '-';
            final qty = item['quantity'] as int? ?? 1;
            final sub = (item['subtotal'] as num?)?.toDouble() ?? 0;
            final special = item['special_requests'] as String?;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${qty}x',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (special != null && special.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            special,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Rp ${_fmt(sub)}',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            );
          }),
          if (notes != null && notes.isNotEmpty) ...[
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.note_add_rounded, size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      notes,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
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

// ── Sidebar: order summary + actions ─────────────────────────────────
class _TrackerSidebar extends StatelessWidget {
  final Map<String, dynamic> order;
  final List<Map<String, dynamic>> items;
  final bool printing;
  final VoidCallback onPrintReceipt;
  final VoidCallback onReorder;
  const _TrackerSidebar({
    required this.order,
    required this.items,
    required this.printing,
    required this.onPrintReceipt,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String? ?? 'new';
    final paymentStatus = order['payment_status'] as String?;
    // Calculate subtotal from items (not from order['total_amount'] which can be 0/null)
    final subtotal = items.fold<double>(0, (sum, item) => sum + ((item['subtotal'] as num?)?.toDouble() ?? 0));
    final discount = (order['discount_amount'] as num?)?.toDouble() ?? 0;
    final serviceCharge = subtotal * 0.03;
    // PB1 is computed from subtotal only, matching the formula the customer
    // actually confirmed at checkout (see cart_provider.dart pb1Amount).
    final pb1Amount = subtotal * 0.10;
    final total = subtotal + serviceCharge + pb1Amount - discount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ORDER SUMMARY',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              const Divider(color: AppColors.border, height: 1),
              const SizedBox(height: 14),
              _summaryRow('Subtotal', subtotal),
              const SizedBox(height: 10),
              _summaryRow('Service Charge (3%)', serviceCharge),
              const SizedBox(height: 10),
              _summaryRow('PB1 (10%)', pb1Amount),
              if (discount > 0) ...[
                const SizedBox(height: 10),
                _summaryRow('Discount', -discount, isDiscount: true),
              ],
              const SizedBox(height: 14),
              const Divider(color: AppColors.border, height: 1),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    'Rp ${_fmt(total)}',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      color: AppColors.accent,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // `status` tracks kitchen progress and (for orders paid up front, e.g.
        // the customer app) may never literally become 'paid' at all —
        // payment_status is the real signal for whether this still needs
        // paying, independent of how far the kitchen has got.
        if (paymentStatus == 'paid') ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onReorder,
              icon: const Icon(Icons.replay_outlined, size: 18),
              label: const Text('Reorder'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusSm)),
                textStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: printing ? null : onPrintReceipt,
              icon: printing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary),
                    )
                  : const Icon(Icons.receipt_long_outlined, size: 18),
              label: const Text('Receipt'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusSm)),
                textStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
          ),
        ] else if (status != 'cancelled') ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.statusWaitlist.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: AppColors.statusWaitlist),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pay at the cashier when the order is ready.',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: AppColors.statusWaitlist,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _summaryRow(String label, double amount, {bool isDiscount = false}) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textSecondary),
      ),
      Text(
        isDiscount ? '- Rp ${_fmt(amount.abs())}' : 'Rp ${_fmt(amount)}',
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: isDiscount ? AppColors.available : AppColors.textPrimary,
        ),
      ),
    ],
  );

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
// Renders as the "EST. TIME REMAINING" badge in the status header. Fetch
// logic (ML prediction + offline fallback) is unchanged from before — only
// how the result is displayed has moved (used to be its own block below the
// header; now it's the badge in the header's top-right, matching the design).
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
          return const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
          );
        }

        final result = snap.data;
        // Server unreachable (e.g. down/timeout) → show a rough estimate
        // (sum of menu prep times, without ML/buffer) rather than have this
        // badge disappear entirely with no information at all.
        final isFallback = snap.hasError || result == null;
        final displayMinutes = isFallback
            ? PrepTimeService.rawFallbackEstimate(_requestItems)
            : result.estimatedMinutes;
        if (isFallback && displayMinutes <= 0) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              isFallback ? 'ROUGH ESTIMATE' : 'EST. TIME REMAINING',
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              PrepTimeService.formatEstimate(displayMinutes),
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.accent,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Progress Stepper (kitchen-ticket style) ──────────────────────────
class _StatusProgress extends StatelessWidget {
  final String status;
  final String? paymentStatus;
  const _StatusProgress({required this.status, this.paymentStatus});

  @override
  Widget build(BuildContext context) {
    const steps  = ['new', 'preparing', 'ready', 'served', 'paid'];
    const labels = ['Received', 'Preparing', 'Ready', 'Served', 'Paid'];
    final currentIdx  = steps.indexOf(status);
    final isCancelled = status == 'cancelled';
    // Orders paid up front (customer app: pay before the kitchen even sees
    // the order) never actually get `status` set to 'paid' by the webhook —
    // that column tracks kitchen progress, not money, so it keeps advancing
    // through new/preparing/ready/served on its own. payment_status is the
    // real signal for the last step, independent of how far cooking has got.
    final isPaid = paymentStatus == 'paid';

    if (isCancelled) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.statusClosed.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cancel_outlined, color: AppColors.accent, size: 20),
            SizedBox(width: 8),
            Text(
              'Order cancelled',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: AppColors.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    // Precomputed once so the connecting line between two steps can check
    // whether BOTH of its endpoints are active — previously the line used
    // `idx < currentIdx`, which ignored the `isLast && isPaid` special case
    // entirely: an order sitting at status 'served' with payment_status
    // 'paid' had every circle checkmarked (including Paid, via that special
    // case) but the last line segment stayed grey, since 3 < 3 is false.
    final activeFlags = List<bool>.generate(
      steps.length,
      (i) => i <= currentIdx || (i == steps.length - 1 && isPaid),
    );

    return Row(
      children: steps.asMap().entries.map((e) {
        final idx = e.key;
        final isLast = idx == steps.length - 1;
        final isActive = activeFlags[idx];
        final isCurrent = idx == currentIdx;

        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      width: isCurrent ? 26 : 16,
                      height: isCurrent ? 26 : 16,
                      decoration: BoxDecoration(
                        color: isActive ? AppColors.primary : AppColors.surfaceVariant,
                        shape: BoxShape.circle,
                        border: isActive ? null : Border.all(color: AppColors.border),
                        boxShadow: isCurrent
                            ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 10)]
                            : [],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      labels[idx],
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                        color: isActive ? AppColors.textPrimary : AppColors.textHint,
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
                    height: 2,
                    margin: const EdgeInsets.only(bottom: 22),
                    color: (activeFlags[idx] && activeFlags[idx + 1])
                        ? AppColors.primary
                        : AppColors.border,
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
