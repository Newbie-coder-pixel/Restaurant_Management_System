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

      // Bail out before the order row is ever inserted if the cart has
      // nothing valid in it — checking this only after the order insert (as
      // before) left an orphaned zero-item order committed in 'new' status,
      // invisible everywhere in the UI (every screen filters on
      // items.isNotEmpty) but still counted as "active" in dashboards.
      final hasValidItems = ref
          .read(cartProvider)
          .items
          .any((item) => item.menuItemId.isNotEmpty);
      if (!hasValidItems) throw Exception('No valid items in cart.');

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

      try {
        await Supabase.instance.client.from('order_items').insert(orderItems);
      } catch (_) {
        // The order row above already committed — clean it up rather than
        // leaving an orphaned zero-item order behind (see the upfront
        // hasValidItems check above for why that matters). Requires the
        // customer_update_own_recent_order RLS policy (migration
        // 20260812010000) since customers otherwise have no UPDATE rights
        // on `orders` at all.
        await Supabase.instance.client.from('orders').update({
          'status': 'cancelled',
          'cancel_reason': 'Order items failed to save',
        }).eq('id', orderId);
        rethrow;
      }

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
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: cart.isEmpty
                  ? _buildEmptyState()
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Checkout',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Complete your order details below.',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 24),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isWide = constraints.maxWidth > 860;
                              final left = Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _sectionCard('Your Details', [
                                    _field(
                                      'Your name *',
                                      _nameCtrl,
                                      Icons.person_outline,
                                    ),
                                    const SizedBox(height: 16),
                                    _phoneField(),
                                  ]),
                                  const SizedBox(height: 20),
                                  _sectionCard('Order Notes', [
                                    _field(
                                      'Any special requests or dietary requirements?',
                                      _notesCtrl,
                                      Icons.notes_outlined,
                                      maxLines: 3,
                                    ),
                                  ]),
                                ],
                              );

                              if (isWide) {
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(flex: 3, child: left),
                                    const SizedBox(width: 24),
                                    SizedBox(
                                      width: 360,
                                      child: _buildSummaryColumn(cart),
                                    ),
                                  ],
                                );
                              }
                              return Column(
                                children: [
                                  left,
                                  const SizedBox(height: 20),
                                  _buildSummaryColumn(cart),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── TOP BAR ──────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.go('/customer'),
            child: const Text(
              'Restaurant',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ),
          const Spacer(),
          const Icon(Icons.lock_outline, size: 16, color: AppColors.textPrimary),
          const SizedBox(width: 6),
          const Text(
            'Secure Checkout',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  // ── EMPTY STATE ──────────────────────────────────────────────────────────
  Widget _buildEmptyState() {
    return Center(
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
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              elevation: 0,
            ),
            child: const Text(
              'View Menu',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ── Left column: muted detail cards ─────────────────────────────────────
  Widget _sectionCard(String title, List<Widget> children) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w800,
            fontSize: 20,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 18),
        ...children,
      ],
    ),
  );

  Widget _field(
    String hint,
    TextEditingController ctrl,
    IconData icon, {
    int maxLines = 1,
  }) => TextField(
    controller: ctrl,
    maxLines: maxLines,
    style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        fontFamily: 'Poppins',
        fontSize: 14,
        color: AppColors.textHint,
      ),
      isDense: true,
      filled: false,
      border: const UnderlineInputBorder(
        borderSide: BorderSide(color: AppColors.border),
      ),
      enabledBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: AppColors.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 10),
    ),
  );

  Widget _phoneField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Phone number (e.g. 08123456789)',
            hintStyle: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              color: AppColors.textHint,
            ),
            isDense: true,
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
            filled: false,
            border: UnderlineInputBorder(
              borderSide: BorderSide(
                color:
                    _phoneCtrl.text.trim().isNotEmpty &&
                        !_isValidPhone(_phoneCtrl.text.trim())
                    ? Colors.red
                    : AppColors.border,
              ),
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                color:
                    _phoneCtrl.text.trim().isNotEmpty &&
                        !_isValidPhone(_phoneCtrl.text.trim())
                    ? Colors.red
                    : AppColors.border,
              ),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.primary, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
        if (_phoneCtrl.text.trim().isNotEmpty &&
            !_isValidPhone(_phoneCtrl.text.trim())) ...[
          const SizedBox(height: 4),
          const Text(
            'Format: 08xxxxxxxxxx (10–13 digits)',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              color: Colors.red,
            ),
          ),
        ],
      ],
    );
  }

  bool _isValidPhone(String phone) {
    return RegExp(r'^08[0-9]{8,11}$').hasMatch(phone);
  }

  // ── Right column: order summary + place order ───────────────────────────
  Widget _buildSummaryColumn(CartState cart) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Order Summary',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Icon(
                    Icons.keyboard_arrow_up,
                    size: 20,
                    color: AppColors.textHint,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...cart.items.map(_summaryItemRow),
              const SizedBox(height: 4),
              const Divider(color: AppColors.border, height: 24),
              _summaryRow('Subtotal', cart.subtotal),
              const SizedBox(height: 10),
              _summaryRow('Service Charge (3%)', cart.serviceCharge),
              const SizedBox(height: 10),
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
            ],
          ),
        ),
        const SizedBox(height: 16),
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
                        'Place Order',
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
    );
  }

  Widget _summaryItemRow(CartItem item) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
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
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Qty: ${item.quantity}',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Text(
          'Rp${_fmt(item.subtotal)}',
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: AppColors.textPrimary,
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
