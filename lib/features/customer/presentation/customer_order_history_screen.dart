import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/cart_provider.dart';
import '../../../core/theme/app_theme.dart';

// ── User's order history provider ─────────────────────────────────
final _orderHistoryProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return [];

  final res = await Supabase.instance.client
      .from('orders')
      .select('*, order_items(*, menu_items(name))')
      .eq('customer_user_id', user.id)
      .order('created_at', ascending: false)
      .limit(50);

  return (res as List).cast<Map<String, dynamic>>();
});

// ── Screen ─────────────────────────────────────────────────────────
class CustomerOrderHistoryScreen extends ConsumerStatefulWidget {
  const CustomerOrderHistoryScreen({super.key});

  @override
  ConsumerState<CustomerOrderHistoryScreen> createState() =>
      _CustomerOrderHistoryScreenState();
}

class _CustomerOrderHistoryScreenState
    extends ConsumerState<CustomerOrderHistoryScreen> {
  String _filter = 'all';

  // ── Reorder ────────────────────────────────────────────────────
  Future<void> _reorder(
      BuildContext context, Map<String, dynamic> order) async {
    final branchId = order['branch_id'] as String?;
    if (branchId == null) return;

    final rawItems = order['order_items'] as List? ?? [];
    final validItems = rawItems
        .cast<Map<String, dynamic>>()
        .where((i) =>
            i['menu_item_id'] != null && i['menu_items'] != null)
        .toList();

    // Capture context-dependent objects BEFORE any async gaps
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    if (validItems.isEmpty) {
      messenger.showSnackBar(const SnackBar(
        content: Text('No items available to reorder.'),
        backgroundColor: Colors.orange));
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.replay_outlined, color: AppColors.primary, size: 24),
            ),
            const SizedBox(width: 12),
            const Text('Reorder?',
                style: TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 18)),
          ],
        ),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${validItems.length} item(s) from this order will be added to the cart.',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, height: 1.4)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(children: [
              ...validItems.take(3).map((i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Container(
                    width: 6, height: 6,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.5),
                      shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${i['quantity']}x ${(i['menu_items'] as Map)['name']}',
                    style: const TextStyle(
                        fontFamily: 'Poppins', fontSize: 12, color: AppColors.textPrimary),
                  ),
                ]))),
              if (validItems.length > 3)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('+ ${validItems.length - 3} more item(s)',
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          color: AppColors.textHint)),
                ),
            ]),
          )
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text('Cancel',
                style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 14, color: AppColors.textSecondary))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
            child: const Text('Reorder',
                style: TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14))),
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

    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle, color: Colors.white, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(priceChanged
            ? 'Items added to cart. Some prices have changed since your last order.'
            : 'Item added to cart!')),
      ]),
      backgroundColor: const Color(0xFF1D9E75),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
    router.go('/customer/checkout');
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
    final historyAsync = ref.watch(_orderHistoryProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: historyAsync.when(
                loading: () => const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: AppColors.primary),
                      SizedBox(height: 16),
                      Text('Loading history...',
                          style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                error: (e, _) => Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.statusClosed.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.error_outline, size: 48, color: AppColors.accent),
                    ),
                    const SizedBox(height: 20),
                    const Text('Failed to load history',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text('$e',
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            color: AppColors.textSecondary),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () => ref.invalidate(_orderHistoryProvider),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Try Again'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
                      )),
                  ])),
                data: (orders) {
                  if (orders.isEmpty) return _emptyState(context);
                  return _buildContent(orders);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(List<Map<String, dynamic>> orders) {
    final filtered = _filter == 'all'
        ? orders
        : orders.where((o) => o['status'] == _filter).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Order History',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Review your past culinary journeys.',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 15, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              _filterRow(),
              const SizedBox(height: 24),
              if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 60),
                  child: Center(
                    child: Column(
                      children: [
                        const Icon(Icons.receipt_long_outlined, size: 64, color: AppColors.textHint),
                        const SizedBox(height: 16),
                        Text(
                          'No orders with status "$_filter"',
                          style: const TextStyle(fontFamily: 'Poppins', fontSize: 14, color: AppColors.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...filtered.map(
                  (order) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _OrderHistoryCard(
                      order: order,
                      onReorder: () => _reorder(context, order),
                      onTrack: () => context.go('/customer/track/${order['order_number']}'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterRow() {
    const filters = [
      ('all', 'All'),
      ('paid', 'Paid'),
      ('new', 'New'),
      ('preparing', 'Cooking'),
      ('served', 'Served'),
      ('cancelled', 'Cancelled'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((f) {
          final selected = _filter == f.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _filter = f.$1),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : AppColors.surface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  border: Border.all(color: selected ? AppColors.primary : AppColors.border),
                ),
                child: Text(
                  f.$2,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? Colors.white : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _emptyState(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 100, height: 100,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            shape: BoxShape.circle),
          child: const Icon(Icons.receipt_long_outlined,
              color: AppColors.primary, size: 48)),
        const SizedBox(height: 24),
        const Text('No Orders Yet',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        const SizedBox(height: 12),
        const Text(
          'Start ordering your favorite food now!',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              color: AppColors.textSecondary)),
        const SizedBox(height: 32),
        ElevatedButton.icon(
          onPressed: () => context.go('/customer'),
          icon: const Icon(Icons.restaurant_menu_outlined, size: 20),
          label: const Text('View Menu',
              style: TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 15)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(
                horizontal: 32, vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd)))),
      ])));
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

// ── Order History Card ─────────────────────────────────────────────
class _OrderHistoryCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final VoidCallback onReorder;
  final VoidCallback onTrack;

  const _OrderHistoryCard({
    required this.order,
    required this.onReorder,
    required this.onTrack,
  });

  static const _statusColors = {
    'new':       Color(0xFF3B82F6),
    'preparing': Color(0xFFF59E0B),
    'ready':     AppColors.available,
    'served':    AppColors.primary,
    'paid':      AppColors.available,
    'cancelled': AppColors.accent,
  };
  static const _statusLabels = {
    'new':       'New',
    'preparing': 'Cooking',
    'ready':     'Ready',
    'served':    'Served',
    'paid':      'Paid',
    'cancelled': 'Cancelled',
  };
  static const _statusIcons = {
    'new':       Icons.fiber_new_outlined,
    'preparing': Icons.soup_kitchen_outlined,
    'ready':     Icons.check_circle_outline,
    'served':    Icons.check_circle_outline,
    'paid':      Icons.check_circle_outline,
    'cancelled': Icons.cancel_outlined,
  };

  bool get _isActive {
    final s = order['status'] as String? ?? '';
    return s == 'new' || s == 'preparing' || s == 'ready' || s == 'served';
  }

  // payment_status, not status — orders paid up front (customer app) never
  // get `status` set to 'paid' by the webhook, since that column tracks
  // kitchen progress, not money (see midtrans-webhook/index.ts).
  bool get _isPaid => order['payment_status'] == 'paid';

  String _fmtDate(String? iso) {
    if (iso == null) return '-';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '-';
    const months = [
      '', 'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'
    ];
    final time = '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
    return '${months[dt.month]} ${dt.day.toString().padLeft(2, '0')}, ${dt.year} • $time';
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

  @override
  Widget build(BuildContext context) {
    final status      = order['status'] as String? ?? 'new';
    final statusColor = _statusColors[status] ?? Colors.grey;
    final statusLabel = _statusLabels[status] ?? status;
    final statusIcon  = _statusIcons[status] ?? Icons.receipt_outlined;
    final total       = (order['total_amount'] as num?)?.toDouble() ?? 0;
    final rawItems    = order['order_items'] as List? ?? [];
    // Reorder — for all statuses except an unpaid cancelled order (nothing
    // was ever actually charged/served in that case).
    final showReorder = !(!_isPaid && status == 'cancelled') || _isPaid;

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
                      _fmtDate(order['created_at'] as String?),
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      order['order_number'] as String? ?? '-',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Rp ${_fmt(total)}',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 14, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                      if (_isActive) ...[
                        const SizedBox(width: 6),
                        AnimatedContainer(
                          duration: const Duration(seconds: 1),
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: rawItems.map((i) {
                    final m = i as Map;
                    final name = (m['menu_items'] as Map?)?['name'] ?? '-';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.eco_outlined, size: 14, color: AppColors.accent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${m['quantity']}x $name',
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 14,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 130,
                child: Column(
                  children: [
                    if (_isActive) ...[
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: onTrack,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            side: const BorderSide(color: AppColors.border),
                            foregroundColor: AppColors.textPrimary,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(AppSpacing.radiusSm)),
                          ),
                          child: const Text('Track',
                              style: TextStyle(
                                  fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (showReorder)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: onReorder,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(AppSpacing.radiusSm)),
                          ),
                          child: const Text('Reorder',
                              style: TextStyle(
                                  fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
