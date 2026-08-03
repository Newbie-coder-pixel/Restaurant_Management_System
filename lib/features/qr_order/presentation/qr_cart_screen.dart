import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/qr_cart_provider.dart';
import '../data/qr_order_repository.dart';
import '../services/qr_device_id_service.dart';
import '../../../../core/services/prep_time_service.dart'; // ← ML Service

class QrCartScreen extends ConsumerStatefulWidget {
  final String tableId;
  const QrCartScreen({super.key, required this.tableId});

  @override
  ConsumerState<QrCartScreen> createState() => _QrCartScreenState();
}

class _QrCartScreenState extends ConsumerState<QrCartScreen> {
  final _nameCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _formKey   = GlobalKey<FormState>();
  bool _isSubmitting = false;

  // ── ML state ────────────────────────────────────────────────────────────────
  int?  _estimatedMinutes;   // ML prediction result, OR a rough fallback estimate
  bool  _isFetchingEstimate = false;
  bool  _isFallbackEstimate = false; // true if _estimatedMinutes is not from ML
  List<QrCartItem> _lastCartItems = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cart = ref.read(activeQrCartProvider);
    final cartChanged = cart.items.length != _lastCartItems.length ||
        (cart.items.isNotEmpty && !List.generate(cart.items.length, (i) =>
          i < _lastCartItems.length &&
          cart.items[i].menuItem.id == _lastCartItems[i].menuItem.id &&
          cart.items[i].quantity   == _lastCartItems[i].quantity &&
          cart.items[i].notes      == _lastCartItems[i].notes
        ).every((e) => e));

    if (cartChanged && !_isFetchingEstimate) {
      _lastCartItems = List.from(cart.items);
      _fetchEstimate(cart);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  // ── ML: Fetch time estimate ───────────────────────────────────────────────
  Future<void> _fetchEstimate(QrOrderSession cart) async {
    if (cart.isEmpty) {
      setState(() {
        _estimatedMinutes = null;
        _isFallbackEstimate = false;
      });
      return;
    }

    setState(() => _isFetchingEstimate = true);

    final items = cart.items.map((e) => PrepTimeRequestItem(
      menuItemName:           e.menuItem.name,
      quantity:               e.quantity,
      preparationTimeMinutes: e.menuItem.preparationTimeMinutes,
      specialRequests:        (e.notes != null && e.notes!.isNotEmpty) ? e.notes : null,
    )).toList();

    final result = await PrepTimeService.predict(
      items:    items,
      branchId: cart.branchId,
    );

    if (mounted) {
      setState(() {
        // Server unreachable → rough estimate (sum of menu prep times,
        // without ML/buffer) rather than the estimate banner disappearing with no explanation.
        _estimatedMinutes = result?.estimatedMinutes ??
            PrepTimeService.rawFallbackEstimate(items);
        _isFallbackEstimate = result == null;
        _isFetchingEstimate = false;
      });
    }
  }

  // ── Helper: Format price ───────────────────────────────────────────────────
  String _formatPrice(double price) {
    final formatted = price
        .toStringAsFixed(0)
        .replaceAllMapped(
            RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
    return 'Rp $formatted';
  }

  // ── Helper: Info Row ───────────────────────────────────────────────────────
  Widget _buildInfoRow(ThemeData theme, ColorScheme colorScheme,
      String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: colorScheme.outline)),
        Text(value,
            style: theme.textTheme.bodySmall
                ?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }

  // ── Show confirmation dialog before ordering ────────────────────────────────
  Future<void> _showOrderConfirmationDialog() async {
    final addMode = ref.read(addOrderModeProvider);
    // In add-order mode, skip name/phone form validation
    if (addMode == null && !_formKey.currentState!.validate()) return;

    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final cart = ref.read(activeQrCartProvider);
    final activeTable = ref.read(activeQrTableProvider);
    final tableName = (activeTable.tableName?.isNotEmpty == true)
        ? activeTable.tableName!
        : widget.tableId;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ────────────────────────────────────────────
              Row(children: [
                Icon(Icons.shopping_cart_outlined,
                    color: colorScheme.primary, size: 24),
                const SizedBox(width: 10),
                Text(
                  'Confirm Order',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ]),
              const SizedBox(height: 16),

              // ── Detail Info ───────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(children: [
                  _buildInfoRow(theme, colorScheme, 'Name',
                      _nameCtrl.text.trim()),
                  const SizedBox(height: 8),
                  _buildInfoRow(theme, colorScheme, 'Phone No.',
                      _phoneCtrl.text.trim().isEmpty ? '-' : _phoneCtrl.text.trim()),
                  const SizedBox(height: 8),
                  _buildInfoRow(theme, colorScheme, 'Table', tableName),
                  const SizedBox(height: 8),
                  _buildInfoRow(theme, colorScheme, 'Total',
                      _formatPrice(cart.totalAmount)),
                  const SizedBox(height: 8),
                  _buildInfoRow(theme, colorScheme, 'Items',
                      '${cart.items.length} item'),
                ]),
              ),
              const SizedBox(height: 12),

              // ── Warning ───────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: colorScheme.error.withValues(alpha: 0.2)),
                ),
                child: Column(children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline,
                          size: 16, color: colorScheme.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Orders that have been sent to the kitchen cannot be cancelled.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onErrorContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 16, color: colorScheme.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Make sure your order is correct before continuing.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ]),
              ),
              const SizedBox(height: 20),

              // ── Buttons ───────────────────────────────────────────
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Check Again'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Order Now',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ]),
            ],
          ),
        ),
        ),
      ),
    );

    if (confirmed == true) {
      _confirmOrder();
    }
  }

  // ── Confirm order ──────────────────────────────────────────────────────────
  Future<void> _confirmOrder() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    final addMode = ref.read(addOrderModeProvider);

    // ── Add-Order Mode (order already exists) ──────────────────────────────
    if (addMode != null) {
      await _confirmAddItems(addMode);
      return;
    }

    // ── Normal Mode (create a new order) ──────────────────────────────────────
    final notifier = ref.read(activeQrCartNotifierProvider);
    notifier.setCustomerInfo(name: _nameCtrl.text.trim(), phone: _phoneCtrl.text.trim());

    final cart     = ref.read(activeQrCartProvider);
    final branchId = cart.branchId.trim();

    final activeTable = ref.read(activeQrTableProvider);
    final tableId     = activeTable.tableId.isNotEmpty
        ? activeTable.tableId
        : widget.tableId;

    debugPrint('🔍 [CartScreen] tableId from activeQrTableProvider: "${activeTable.tableId}"');
    debugPrint('🔍 [CartScreen] tableId from widget: "${widget.tableId}"');
    debugPrint('🔍 [CartScreen] tableId that will be used: "$tableId"');

    if (branchId.isEmpty) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Branch ID not found. Please rescan the table QR code.'),
          backgroundColor: Colors.red));
      }
      return;
    }

    if (tableId.isEmpty) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Table ID not found. Please rescan the table QR code.'),
          backgroundColor: Colors.red));
      }
      return;
    }

    final repo = ref.read(qrOrderRepositoryProvider);

    try {
      final correctedSession = cart.copyWith(tableId: tableId);
      final deviceId = await QrDeviceIdService.getDeviceId();
      final order = await repo.createOrder(
        session:  correctedSession,
        branchId: branchId,
        deviceId: deviceId,
      );

      notifier.clearCart();

      if (mounted) {
        final estimasiText = _estimatedMinutes != null
            ? ' Estimated ready: ${PrepTimeService.formatEstimate(_estimatedMinutes!)}'
            : '';

        context.go('/qr/${widget.tableId}/track/${order.id}?queue=${order.queueNumber}');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Order #${order.queueNumber} sent to the kitchen!$estimasiText'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create order: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ── Confirm adding items to an existing order ────────────────────────────
  Future<void> _confirmAddItems(AddOrderModeState addMode) async {
    final cart = ref.read(activeQrCartProvider);
    final notifier = ref.read(activeQrCartNotifierProvider);

    try {
      final addNotifier = ref.read(qrAddItemsProvider.notifier);
      final updatedOrder = await addNotifier.submit(
        orderId: addMode.orderId,
        newItems: cart.items,
      );

      if (updatedOrder == null) throw Exception('Failed to add to order');

      // Clear cart & reset mode
      notifier.clearCart();
      ref.read(addOrderModeProvider.notifier).state = null;

      if (mounted) {
        final estimasiText = _estimatedMinutes != null
            ? ' Estimated ready: ${PrepTimeService.formatEstimate(_estimatedMinutes!)}'
            : '';

        // Return to the same order's tracker screen
        context.go(
          '/qr/${addMode.tableId}/track/${addMode.orderId}?queue=${addMode.queueNumber}',
        );
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            '✅ Additional order sent to the kitchen!$estimasiText',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add to order: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _showNotesDialog(QrCartItem item) async {
    final notifier = ref.read(activeQrCartNotifierProvider);
    final ctrl = TextEditingController(text: item.notes ?? '');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.edit_note, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(item.menuItem.name,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            overflow: TextOverflow.ellipsis)),
        ]),
        content: TextField(
          controller: ctrl, maxLines: 3, autofocus: true,
          decoration: InputDecoration(
            hintText: 'Example: not spicy, no onions...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.all(12))),
        actions: [
          TextButton(
            onPressed: () {
              notifier.updateNotes(item.menuItem.id, '');
              Navigator.pop(ctx);
            },
            child: const Text('Remove Note', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () {
              notifier.updateNotes(item.menuItem.id, ctrl.text.trim());
              Navigator.pop(ctx);
              // Update the estimate after notes change
              final cart = ref.read(activeQrCartProvider);
              _fetchEstimate(cart);
            },
            child: const Text('Save')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart     = ref.watch(activeQrCartProvider);
    final notifier = ref.read(activeQrCartNotifierProvider);
    final theme    = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (cart.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Cart'),
          leading: BackButton(onPressed: () => context.pop()),
        ),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.shopping_cart_outlined, size: 80, color: colorScheme.outline),
            const SizedBox(height: 16),
            Text('Your cart is empty', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Choose a menu item first',
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back to Menu')),
          ]),
        ),
      );
    }

    final addMode = ref.watch(addOrderModeProvider);
    final isAddMode = addMode != null;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: Text(isAddMode ? 'Add Order' : 'Order Cart'),
        leading: BackButton(onPressed: () {
          // When backing out of add mode, reset the mode so it doesn't get stuck
          if (isAddMode) {
            ref.read(addOrderModeProvider.notifier).state = null;
            notifier.clearCart();
          }
          context.pop();
        }),
        actions: [
          TextButton(
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Clear Cart?'),
                  content: const Text('All items will be removed from the cart.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel')),
                    TextButton(
                      onPressed: () {
                        notifier.clearCart();
                        Navigator.pop(context);
                        context.pop();
                      },
                      style: TextButton.styleFrom(foregroundColor: colorScheme.error),
                      child: const Text('Clear')),
                  ],
                ),
              );
            },
            child: Text('Clear',
              style: TextStyle(color: colorScheme.error, fontSize: 13)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: CustomScrollView(
          slivers: [
            // ── ML Estimate Banner ─────────────────────────────────────────
            if (_isFetchingEstimate || _estimatedMinutes != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: colorScheme.primary.withValues(alpha: 0.2)),
                    ),
                    child: Row(children: [
                      Icon(Icons.schedule_rounded,
                        size: 20, color: colorScheme.primary),
                      const SizedBox(width: 10),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isFallbackEstimate
                                ? 'Rough Estimate (offline)'
                                : 'Estimated Ready Time',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          if (_isFetchingEstimate)
                            Row(children: [
                              SizedBox(
                                width: 12, height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colorScheme.primary)),
                              const SizedBox(width: 8),
                              Text('Calculating...',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onPrimaryContainer)),
                            ])
                          else
                            Text(
                              PrepTimeService.formatEstimate(_estimatedMinutes!),
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w700)),
                        ],
                      )),
                      Icon(Icons.info_outline,
                        size: 16,
                        color: colorScheme.primary.withValues(alpha: 0.5)),
                    ]),
                  ),
                ),
              ),

            // ── Add-order mode banner ──────────────────────────────────
            if (isAddMode)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colorScheme.secondary.withValues(alpha: 0.4)),
                    ),
                    child: Row(children: [
                      Icon(Icons.add_circle_outline,
                        color: colorScheme.secondary, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Add Order Mode',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colorScheme.onSecondaryContainer,
                                fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Queue No.: ${addMode.queueNumber} · Existing items cannot be changed',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSecondaryContainer
                                    .withValues(alpha: 0.75)),
                            ),
                          ],
                        ),
                      ),
                    ]),
                  ),
                ),
              ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text('${cart.totalItems} item(s) ordered',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.outline)),
              ),
            ),

            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final item = cart.items[index];
                  return _CartItemTile(
                    item: item,
                    onAdd:      () {
                      notifier.addItem(item.menuItem);
                      _fetchEstimate(ref.read(activeQrCartProvider));
                    },
                    onRemove:   () {
                      notifier.removeItem(item.menuItem.id);
                      _fetchEstimate(ref.read(activeQrCartProvider));
                    },
                    onDelete:   () {
                      notifier.deleteItem(item.menuItem.id);
                      _fetchEstimate(ref.read(activeQrCartProvider));
                    },
                    onEditNotes: () => _showNotesDialog(item),
                  );
                },
                childCount: cart.items.length,
              ),
            ),

            // In add-order mode, the name/phone form is not needed
            if (!isAddMode)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _CustomerInfoCard(
                    nameCtrl:  _nameCtrl,
                    phoneCtrl: _phoneCtrl,
                    tableName: cart.tableName ?? 'Table'),
                ),
              ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                child: _OrderSummaryCard(cart: cart, isAddMode: isAddMode),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _CartBottomBar(
        cart:      cart,
        onProceed: _showOrderConfirmationDialog,
        isLoading: _isSubmitting,
        isAddMode: isAddMode,
      ),
    );
  }
}

// ─── Cart Item Tile ───────────────────────────────────────────────────────────
class _CartItemTile extends StatelessWidget {
  final QrCartItem item;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onDelete;
  final VoidCallback onEditNotes;

  const _CartItemTile({
    required this.item,
    required this.onAdd,
    required this.onRemove,
    required this.onDelete,
    required this.onEditNotes,
  });

  @override
  Widget build(BuildContext context) {
    final theme       = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dismissible(
      key: ValueKey(item.menuItem.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.error, borderRadius: BorderRadius.circular(14)),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(Icons.delete_outline, color: colorScheme.onError, size: 24)),
      onDismissed: (_) => onDelete(),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colorScheme.outlineVariant, width: 0.8)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(width: 60, height: 60,
                  child: item.menuItem.imageUrl != null
                      ? Image.network(item.menuItem.imageUrl!, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.fastfood_outlined, size: 24, color: Colors.grey)))
                      : Container(
                          color: colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.fastfood_outlined, size: 24, color: Colors.grey)))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.menuItem.name,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Row(children: [
                  Text(_formatPrice(item.menuItem.price),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.primary, fontWeight: FontWeight.w500)),
                  const SizedBox(width: 8),
                  // ── Prep time badge ──────────────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.timer_outlined, size: 11, color: Colors.orange.shade700),
                      const SizedBox(width: 3),
                      Text('${item.menuItem.preparationTimeMinutes} min',
                        style: TextStyle(fontSize: 10,
                          color: Colors.orange.shade700, fontWeight: FontWeight.w600)),
                    ])),
                ]),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(_formatPrice(item.subtotal),
                  style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  _SmallQtyBtn(icon: Icons.remove, onTap: onRemove, colorScheme: colorScheme),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text('${item.quantity}',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold))),
                  _SmallQtyBtn(icon: Icons.add, onTap: onAdd, colorScheme: colorScheme),
                ]),
              ]),
            ]),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: onEditNotes,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: (item.notes != null && item.notes!.isNotEmpty)
                      ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                      : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (item.notes != null && item.notes!.isNotEmpty)
                        ? colorScheme.primary.withValues(alpha: 0.3)
                        : colorScheme.outlineVariant)),
                child: Row(children: [
                  Icon(
                    (item.notes != null && item.notes!.isNotEmpty)
                        ? Icons.edit_note : Icons.note_add_outlined,
                    size: 14,
                    color: (item.notes != null && item.notes!.isNotEmpty)
                        ? colorScheme.primary : colorScheme.outline),
                  const SizedBox(width: 6),
                  Expanded(child: Text(
                    (item.notes != null && item.notes!.isNotEmpty)
                        ? item.notes!
                        : 'Add a note (not spicy, etc...)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: (item.notes != null && item.notes!.isNotEmpty)
                          ? colorScheme.primary : colorScheme.outline,
                      fontStyle: (item.notes != null && item.notes!.isNotEmpty)
                          ? FontStyle.normal : FontStyle.italic),
                    maxLines: 2, overflow: TextOverflow.ellipsis)),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  String _formatPrice(double price) {
    final formatted = price.toStringAsFixed(0)
        .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
    return 'Rp $formatted';
  }
}

class _SmallQtyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final ColorScheme colorScheme;

  const _SmallQtyBtn({required this.icon, required this.onTap, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26, height: 26,
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(6)),
        child: Icon(icon, size: 14, color: colorScheme.onPrimaryContainer)));
  }
}

// ─── Customer Info Card ───────────────────────────────────────────────────────
class _CustomerInfoCard extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;
  final String tableName;

  const _CustomerInfoCard({
    required this.nameCtrl,
    required this.phoneCtrl,
    required this.tableName,
  });

  @override
  Widget build(BuildContext context) {
    final theme       = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant, width: 0.8)),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.person_outline, size: 18, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text('Customer Information',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 14),
        TextFormField(
          initialValue: tableName,
          readOnly: true,
          decoration: InputDecoration(
            labelText: 'Table Number',
            prefixIcon: const Icon(Icons.table_restaurant_outlined),
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10))),
        const SizedBox(height: 10),
        TextFormField(
          controller: nameCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Customer Name *',
            hintText: 'Example: John',
            prefixIcon: const Icon(Icons.badge_outlined),
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
          validator: (val) {
            if (val == null || val.trim().isEmpty) return 'Name cannot be empty';
            if (val.trim().length < 2) return 'Name is too short';
            return null;
          }),
        const SizedBox(height: 10),
        TextFormField(
          controller: phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: 'Phone Number (optional)',
            hintText: 'Example: 08123456789',
            prefixIcon: const Icon(Icons.phone_outlined),
            helperText: 'Format: 08xxxxxxxxxx (10-13 digits)',
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
          validator: (val) {
            if (val == null || val.trim().isEmpty) return null;
            final digits = val.trim().replaceAll(RegExp(r'\s+'), '');
            if (!RegExp(r'^08\d{8,11}$').hasMatch(digits)) {
              return 'Enter a valid number (08xxxxxxxxxx, 10-13 digits)';
            }
            return null;
          }),
      ]),
    );
  }
}

// ─── Order Summary Card ───────────────────────────────────────────────────────
class _OrderSummaryCard extends StatelessWidget {
  final QrOrderSession cart;
  final bool isAddMode;

  const _OrderSummaryCard({required this.cart, this.isAddMode = false});

  @override
  Widget build(BuildContext context) {
    final theme       = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant, width: 0.8)),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.receipt_outlined, size: 18, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text('Additional Summary',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 14),

        // Item list
        ...cart.items.map((item) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Text('${item.quantity}×',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.primary, fontWeight: FontWeight.bold)),
            const SizedBox(width: 6),
            Expanded(child: Text(item.menuItem.name,
              style: theme.textTheme.bodySmall,
              maxLines: 1, overflow: TextOverflow.ellipsis)),
            Text(_formatPrice(item.subtotal), style: theme.textTheme.bodySmall),
          ]),
        )),

        Divider(color: colorScheme.outlineVariant, height: 20, thickness: 0.5),

        if (!isAddMode) ...[
          // Normal mode: show the full breakdown
          Row(children: [
            Text('Subtotal',
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline)),
            const Spacer(),
            Text(_formatPrice(cart.subtotal), style: theme.textTheme.bodySmall),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            Text('Service Charge (3%)',
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline)),
            const Spacer(),
            Text(_formatPrice(cart.serviceCharge), style: theme.textTheme.bodySmall),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            Text('PB1 (10%)',
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline)),
            const Spacer(),
            Text(_formatPrice(cart.pb1Amount), style: theme.textTheme.bodySmall),
          ]),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              Text('Total', style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold, color: colorScheme.onPrimaryContainer)),
              const Spacer(),
              Text(_formatPrice(cart.totalAmount),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold, color: colorScheme.primary)),
            ])),
        ] else ...[
          // Add-order mode: only show new items' subtotal + note that tax is auto-calculated
          Row(children: [
            Text('New items subtotal',
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline)),
            const Spacer(),
            Text(_formatPrice(cart.subtotal), style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              Icon(Icons.info_outline, size: 13, color: colorScheme.outline),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'PB1 & Service Charge are calculated automatically from the order total.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline, fontSize: 11),
                ),
              ),
            ]),
          ),
        ],
      ]),
    );
  }

  String _formatPrice(double price) {
    final formatted = price.toStringAsFixed(0)
        .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
    return 'Rp $formatted';
  }
}

// ─── Bottom Bar ───────────────────────────────────────────────────────────────
class _CartBottomBar extends StatelessWidget {
  final QrOrderSession cart;
  final VoidCallback onProceed;
  final bool isLoading;
  final bool isAddMode;

  const _CartBottomBar({
    required this.cart,
    required this.onProceed,
    required this.isLoading,
    this.isAddMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme       = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant, width: 0.5))),
      child: SizedBox(
        width: double.infinity, height: 52,
        child: ElevatedButton(
          onPressed: isLoading ? null : onProceed,
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0),
          child: isLoading
              ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                  SizedBox(width: 10),
                  Text('Sending to Kitchen...'),
                ])
              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.send_outlined, size: 20),
                  const SizedBox(width: 8),
                  Text('Order Now',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.onPrimary, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: colorScheme.onPrimary.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(20)),
                    // In add mode: show only the new items' subtotal (not total+tax)
                    child: Text(
                      isAddMode
                          ? '${_formatPrice(cart.subtotal)} (new items)'
                          : _formatPrice(cart.totalAmount),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onPrimary, fontWeight: FontWeight.bold))),
                ]),
        ),
      ),
    );
  }

  String _formatPrice(double price) {
    final formatted = price.toStringAsFixed(0)
        .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
    return 'Rp $formatted';
  }
}