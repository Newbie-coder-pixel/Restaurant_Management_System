import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../providers/cart_provider.dart';
import '../../../shared/services/order_number_service.dart';
import '../../../core/theme/app_theme.dart';

class CustomerCheckoutScreen extends ConsumerStatefulWidget {
  const CustomerCheckoutScreen({super.key});
  @override
  ConsumerState<CustomerCheckoutScreen> createState() =>
      _CustomerCheckoutScreenState();
}

class _CustomerCheckoutScreenState
    extends ConsumerState<CustomerCheckoutScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _submitting = false;

  final Map<String, TextEditingController> _itemNotesCtrls = {};

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _notesCtrl.dispose();
    for (final c in _itemNotesCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncItemNotesControllers(List<CartItem> items) {
    for (final item in items) {
      if (!_itemNotesCtrls.containsKey(item.menuItemId)) {
        _itemNotesCtrls[item.menuItemId] = TextEditingController(
          text: item.notes ?? '',
        );
      }
    }
    _itemNotesCtrls.removeWhere(
      (id, _) => !items.any((i) => i.menuItemId == id),
    );
  }

  // Order number is the only lookup key anonymous customers have for
  // tracking their order (see customer_order_tracker_screen.dart). The
  // numeric suffix now comes from the same shared per-branch daily sequence
  // the QR and staff cashier paths use (OrderNumberService) — order numbers
  // across all three apps read as one continuous sequence per branch, only
  // the prefix differs. Still enforced unique at the DB level, per-branch
  // (see migration 20260805000000); _placeOrder() still retries on a 23505
  // conflict as a defensive fallback, though a genuine collision should no
  // longer be possible since each call reserves a fresh integer atomically.
  Future<String> _generateOrderNumber(String branchId) async {
    final result = await OrderNumberService.nextSequence(branchId);
    return OrderNumberService.formatWebOrderNumber(
      result.seq,
      result.orderDate,
    );
  }

  // order_items has one free-text special_requests column and no dedicated
  // spice-level/add-ons columns, so customization is folded into that same
  // text field for the kitchen/staff UIs that already render it (e.g.
  // _OrderStatusCard in customer_landing_screen.dart) to pick up for free.
  String? _customizationSummary(CartItem item) {
    final parts = <String>[];
    if (item.spiceLevel != null && item.spiceLevel!.isNotEmpty) {
      parts.add('Spice: ${item.spiceLevel}');
    }
    if (item.addOns.isNotEmpty) {
      parts.add('Add-ons: ${item.addOns.map((a) => a.name).join(', ')}');
    }
    if (item.notes != null && item.notes!.trim().isNotEmpty) {
      parts.add(item.notes!.trim());
    }
    return parts.isEmpty ? null : parts.join(' • ');
  }

  Future<bool> _showConfirmDialog(CartState cart) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.shopping_cart_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Confirm Order',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Info rows ───────────────────────────────────────────
              _dialogRow('Name', _nameCtrl.text.trim()),
              if (_phoneCtrl.text.trim().isNotEmpty)
                _dialogRow('Phone', _phoneCtrl.text.trim()),
              _dialogRow('Type', 'Takeaway'),
              _dialogRow('Total', 'Rp ${_fmt(cart.total)}'),
              _dialogRow('Items', '${cart.itemCount} item(s)'),
              const SizedBox(height: 14),

              // ── Warning box ─────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.25),
                  ),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: AppColors.accent,
                          size: 16,
                        ),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Orders that have been sent to the kitchen cannot be canceled.',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          color: AppColors.accent,
                          size: 16,
                        ),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Make sure your order is correct before continuing.',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              color: AppColors.accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Buttons ─────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: const BorderSide(color: AppColors.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        minimumSize: const Size(0, 44),
                      ),
                      child: const Text(
                        'Check Again',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        minimumSize: const Size(0, 44),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Order Now',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return result ?? false;
  }

  Widget _dialogRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
      ],
    ),
  );

  Future<void> _placeOrder() async {
    final cart = ref.read(cartProvider);

    if (cart.isEmpty || cart.branchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cart is empty, please add a menu item first.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Name is required'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final phone = _phoneCtrl.text.trim();
    if (phone.isNotEmpty) {
      final phoneRegex = RegExp(r'^08[0-9]{8,11}$');
      if (!phoneRegex.hasMatch(phone)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid phone number format. Example: 08123456789'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    for (final entry in _itemNotesCtrls.entries) {
      ref
          .read(cartProvider.notifier)
          .updateNotes(
            entry.key,
            entry.value.text.trim().isEmpty ? null : entry.value.text.trim(),
          );
    }

    final confirmed = await _showConfirmDialog(cart);
    if (!confirmed || !mounted) return;

    setState(() => _submitting = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;

      // order_number is unique-constrained for the WEB- scheme at the DB
      // level (migration 20260803020000); retry with a fresh number on the
      // rare chance of a same-day random collision (postgres code 23505).
      String orderId = const Uuid().v4();
      String orderNumber = await _generateOrderNumber(cart.branchId!);
      const maxAttempts = 3;
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          await Supabase.instance.client.from('orders').insert({
            'id': orderId,
            'branch_id': cart.branchId,
            'order_number': orderNumber,
            'status': 'new',
            'source': 'takeaway',
            'order_type': 'takeaway',
            'customer_name': _nameCtrl.text.trim(),
            'customer_phone': _phoneCtrl.text.trim().isEmpty
                ? null
                : _phoneCtrl.text.trim(),
            'customer_email': user?.email,
            'customer_user_id': user?.id,
            'table_id': null,
            'table_name': null,
            'discount_amount': 0,
            'subtotal': cart.subtotal,
            'tax_amount': cart.pb1Amount,
            'total_amount': cart.total,
            'payment_status': 'unpaid',
            'notes': _notesCtrl.text.trim().isEmpty
                ? null
                : _notesCtrl.text.trim(),
          });
          break;
        } on PostgrestException catch (e) {
          final isConflict = e.code == '23505';
          if (!isConflict || attempt == maxAttempts) rethrow;
          // Fresh id + number, try again.
          orderId = const Uuid().v4();
          orderNumber = await _generateOrderNumber(cart.branchId!);
        }
      }

      final orderItems = ref
          .read(cartProvider)
          .items
          .map(
            (item) => {
              'order_id': orderId,
              'menu_item_id': item.menuItemId,
              'menu_item_name': item.name,
              'quantity': item.quantity,
              // Includes add-ons so unit_price * quantity matches the subtotal the
              // customer saw at checkout (order_items has no separate columns for
              // spice level/add-ons — see _customizationSummary for how they're
              // surfaced to kitchen/staff instead).
              'unit_price': item.unitPrice,
              // subtotal is not inserted because it's a generated column in Supabase
              'status': 'pending',
              if (_customizationSummary(item) != null)
                'special_requests': _customizationSummary(item),
            },
          )
          .where((i) => (i['menu_item_id'] as String).isNotEmpty)
          .toList();

      if (orderItems.isEmpty) throw Exception('No valid items in cart.');

      await Supabase.instance.client.from('order_items').insert(orderItems);

      ref.read(cartProvider.notifier).clear();

      if (mounted) {
        context.go('/customer/payment/$orderId');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to place order: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    _syncItemNotesControllers(cart.items);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: cart.isEmpty ? _buildEmptyState(cart) : _buildBasket(cart),
      ),
    );
  }

  // ── TOP NAV (Pusaka header, shared visual language with the menu screen) ──
  Widget _buildTopNav(CartState cart) {
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
              'Pusaka',
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
                _NavLink(
                  label: 'Menu',
                  onTap: () => cart.branchId != null
                      ? context.go('/customer/menu/${cart.branchId}')
                      : context.go('/customer'),
                ),
                const SizedBox(width: 24),
                _NavLink(label: 'Locations', onTap: () => context.go('/customer')),
                const SizedBox(width: 24),
                _NavLink(label: 'Our Story', onTap: () => context.go('/customer')),
              ],
            ),
          ),
          GestureDetector(
            onTap: () =>
                context.canPop() ? context.pop() : context.go('/customer?tab=0'),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(
                  Icons.shopping_cart_outlined,
                  color: AppColors.textPrimary,
                  size: 24,
                ),
                if (!cart.isEmpty)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      decoration: const BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${cart.itemCount}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── EMPTY STATE ──────────────────────────────────────────────────────────
  Widget _buildEmptyState(CartState cart) {
    return Column(
      children: [
        _buildTopNav(cart),
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.shopping_cart_outlined,
                  size: 64,
                  color: AppColors.textHint,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Your basket is empty',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Add a menu item first',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => context.go('/customer'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'View Menu',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── BASKET (main layout) ────────────────────────────────────────────────
  Widget _buildBasket(CartState cart) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildTopNav(cart)),
const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 28, 20, 20),
            child: Text(
              'Your Basket',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 34,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 860;
                final left = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...cart.items.map(_buildItemCard),
                    const SizedBox(height: 8),
                    _orderTypeCard(),
                    const SizedBox(height: 20),
                    _customerInfoCard(),
                    const SizedBox(height: 20),
                    _orderNotesCard(),
                  ],
                );
                final right = _summaryCard(cart);

                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: left),
                      const SizedBox(width: 24),
                      SizedBox(width: 340, child: right),
                    ],
                  );
                }
                return Column(
                  children: [left, const SizedBox(height: 20), right],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // ── Basket item card ─────────────────────────────────────────────────────
  Widget _buildItemCard(CartItem item) {
    final notesCtrl = _itemNotesCtrls[item.menuItemId];
    final customization = [
      if (item.spiceLevel != null) item.spiceLevel!,
      ...item.addOns.map((a) => '+ ${a.name}'),
    ].join('  •  ');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            child: SizedBox(
              width: 72,
              height: 72,
              child: item.imageUrl != null
                  ? Image.network(
                      item.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _imgPlaceholder(),
                    )
                  : _imgPlaceholder(),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (customization.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          customization,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () => ref
                            .read(cartProvider.notifier)
                            .removeItem(item.menuItemId),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.delete_outline,
                              size: 14,
                              color: AppColors.accent,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'REMOVE',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                                color: AppColors.accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (notesCtrl != null) ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: notesCtrl,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Notes for this item (e.g. not spicy...)',
                            hintStyle: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              color: AppColors.textHint,
                            ),
                            filled: true,
                            fillColor: AppColors.surfaceVariant,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            isDense: true,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Rp${_fmt(item.subtotal)}',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _qtyStepper(item),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _imgPlaceholder() => Container(
    color: AppColors.surfaceVariant,
    alignment: Alignment.center,
    child: const Icon(
      Icons.restaurant_menu_outlined,
      size: 24,
      color: AppColors.textHint,
    ),
  );

  Widget _qtyStepper(CartItem item) => Container(
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _stepBtn(
          Icons.remove,
          () => ref
              .read(cartProvider.notifier)
              .updateQuantity(item.menuItemId, item.quantity - 1),
        ),
        SizedBox(
          width: 28,
          child: Text(
            '${item.quantity}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        _stepBtn(
          Icons.add,
          () => ref
              .read(cartProvider.notifier)
              .updateQuantity(item.menuItemId, item.quantity + 1),
        ),
      ],
    ),
  );

  Widget _stepBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Icon(icon, size: 14, color: AppColors.textPrimary),
    ),
  );

  // ── Order type ────────────────────────────────────────────────────────
  Widget _orderTypeCard() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.shopping_bag_outlined,
            color: Colors.white,
            size: 18,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Takeaway',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Pick up your order at the restaurant',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  // ── Customer info ────────────────────────────────────────────────────────
  Widget _customerInfoCard() => _card('Your Details', [
    _field('Your name *', _nameCtrl, Icons.person_outline),
    const SizedBox(height: 10),
    _phoneField(),
  ]);

  Widget _orderNotesCard() => _card('Order Notes', [
    TextField(
      controller: _notesCtrl,
      maxLines: 4,
      style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
      decoration: InputDecoration(
        hintText: 'Any special requests or dietary requirements?',
        hintStyle: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 13,
          color: AppColors.textHint,
        ),
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
        contentPadding: const EdgeInsets.all(14),
      ),
    ),
  ]);

  Widget _card(String title, List<Widget> children) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 14),
        ...children,
      ],
    ),
  );

  Widget _phoneField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Example: 08123456789',
            hintStyle: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: AppColors.textHint,
            ),
            prefixIcon: const Icon(
              Icons.phone_outlined,
              size: 18,
              color: AppColors.textHint,
            ),
            suffixIcon: _phoneCtrl.text.trim().isNotEmpty
                ? Icon(
                    _isValidPhone(_phoneCtrl.text.trim())
                        ? Icons.check_circle
                        : Icons.cancel,
                    size: 18,
                    color: _isValidPhone(_phoneCtrl.text.trim())
                        ? Colors.green
                        : Colors.red,
                  )
                : null,
            filled: true,
            fillColor: AppColors.surfaceVariant,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              borderSide:
                  _phoneCtrl.text.trim().isNotEmpty &&
                      !_isValidPhone(_phoneCtrl.text.trim())
                  ? const BorderSide(color: Colors.red, width: 1.5)
                  : BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
        ),
        if (_phoneCtrl.text.trim().isNotEmpty &&
            !_isValidPhone(_phoneCtrl.text.trim())) ...[
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Text(
              'Format: 08xxxxxxxxxx (10–13 digits)',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                color: Colors.red,
              ),
            ),
          ),
        ],
      ],
    );
  }

  bool _isValidPhone(String phone) {
    return RegExp(r'^08[0-9]{8,11}$').hasMatch(phone);
  }

  Widget _field(
    String hint,
    TextEditingController ctrl,
    IconData icon, {
    int maxLines = 1,
    TextInputType? keyboardType,
  }) => TextField(
    controller: ctrl,
    maxLines: maxLines,
    keyboardType: keyboardType,
    style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        fontFamily: 'Poppins',
        fontSize: 13,
        color: AppColors.textHint,
      ),
      prefixIcon: Icon(icon, size: 18, color: AppColors.textHint),
      filled: true,
      fillColor: AppColors.surfaceVariant,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
  );

  // ── Summary sidebar ──────────────────────────────────────────────────────
  Widget _summaryCard(CartState cart) => Container(
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
          'Summary',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        const Divider(color: AppColors.border, height: 1),
        const SizedBox(height: 16),
        _summaryRow('Subtotal', cart.subtotal),
        const SizedBox(height: 12),
        _summaryRow('Service Charge (3%)', cart.serviceCharge),
        const SizedBox(height: 12),
        _summaryRow('PB1 (10%)', cart.pb1Amount),
        const SizedBox(height: 16),
        const Divider(color: AppColors.border, height: 1),
        const SizedBox(height: 16),
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
              'Rp${_fmt(cart.total)}',
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w800,
                fontSize: 22,
                color: AppColors.accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          "You'll pay online on the next step",
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 11,
            color: AppColors.textHint,
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _submitting ? null : _placeOrder,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              elevation: 0,
            ),
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Order Now',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward, size: 18),
                    ],
                  ),
          ),
        ),
      ],
    ),
  );

  Widget _summaryRow(String label, double value) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
      ),
      Text(
        'Rp${_fmt(value)}',
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
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

// ── Top nav text link (shared visual language with customer_menu_screen) ──
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
