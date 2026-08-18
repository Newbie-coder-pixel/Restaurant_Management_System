import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/qr_cart_provider.dart';
import '../data/qr_order_repository.dart';
import '../services/qr_device_id_service.dart';
import '../../../../core/services/prep_time_service.dart'; // ← ML Service
import '../../../core/theme/app_theme.dart';

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
  void initState() {
    super.initState();
    // Keep the QR menu assistant FAB off this screen entirely — it must
    // never sit on top of the "Order Now" button. See
    // qrChatbotSuppressedProvider's own doc comment for why this exists
    // alongside QrChatbotOverlay's route-based hiding.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(qrChatbotSuppressedProvider.notifier).state = true;
    });
  }

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
    // Restore the FAB for whichever screen the customer navigates to next
    // (menu/tracker) — only this screen (and pay, which suppresses itself
    // separately) needs it hidden.
    ref.read(qrChatbotSuppressedProvider.notifier).state = false;
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
  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                color: AppColors.textSecondary)),
        Text(value,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      ],
    );
  }

  // ── Show confirmation dialog before ordering ────────────────────────────────
  Future<void> _showOrderConfirmationDialog() async {
    final addMode = ref.read(addOrderModeProvider);
    // In add-order mode, skip name/phone form validation
    if (addMode == null && !_formKey.currentState!.validate()) return;

    final cart = ref.read(activeQrCartProvider);
    final activeTable = ref.read(activeQrTableProvider);
    final tableName = (activeTable.tableName?.isNotEmpty == true)
        ? activeTable.tableName!
        : widget.tableId;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusLg)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ────────────────────────────────────────────
              const Row(children: [
                Icon(Icons.shopping_cart_outlined,
                    color: AppColors.primary, size: 24),
                SizedBox(width: 10),
                Text(
                  'Confirm Order',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 19,
                      fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                ),
              ]),
              const SizedBox(height: 16),

              // ── Detail Info ───────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Column(children: [
                  _buildInfoRow('Name', _nameCtrl.text.trim()),
                  const SizedBox(height: 8),
                  _buildInfoRow('Phone No.',
                      _phoneCtrl.text.trim().isEmpty ? '-' : _phoneCtrl.text.trim()),
                  const SizedBox(height: 8),
                  _buildInfoRow('Table', tableName),
                  const SizedBox(height: 8),
                  _buildInfoRow('Total', _formatPrice(cart.totalAmount)),
                  const SizedBox(height: 8),
                  _buildInfoRow('Items', '${cart.items.length} item'),
                ]),
              ),
              const SizedBox(height: 12),

              // ── Warning ───────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
                ),
                child: Column(children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, size: 16, color: AppColors.accent),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Orders that have been sent to the kitchen cannot be cancelled.',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5,
                              color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle_outline, size: 16, color: AppColors.accent),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Make sure your order is correct before continuing.',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5,
                              color: AppColors.textSecondary),
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
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
                    ),
                    child: const Text('Check Again',
                        style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Order Now',
                      style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700),
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
      final qrAccessToken = ref.read(activeQrTokenProvider);
      final order = await repo.createOrder(
        session:  correctedSession,
        branchId: branchId,
        deviceId: deviceId,
        qrAccessToken: qrAccessToken,
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
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusLg)),
        title: Row(children: [
          const Icon(Icons.edit_note, size: 20, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(item.menuItem.name,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 15,
                fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            overflow: TextOverflow.ellipsis)),
        ]),
        content: TextField(
          controller: ctrl, maxLines: 3, autofocus: true,
          style: const TextStyle(fontFamily: 'Poppins', color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Example: not spicy, no onions...',
            hintStyle: const TextStyle(fontFamily: 'Poppins', color: AppColors.textHint),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              borderSide: const BorderSide(color: AppColors.primary)),
            contentPadding: const EdgeInsets.all(12))),
        actions: [
          TextButton(
            onPressed: () {
              notifier.updateNotes(item.menuItem.id, '');
              Navigator.pop(ctx);
            },
            child: const Text('Remove Note',
                style: TextStyle(fontFamily: 'Poppins', color: AppColors.textHint))),
          ElevatedButton(
            onPressed: () {
              notifier.updateNotes(item.menuItem.id, ctrl.text.trim());
              Navigator.pop(ctx);
              // Update the estimate after notes change
              final cart = ref.read(activeQrCartProvider);
              _fetchEstimate(cart);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary, foregroundColor: Colors.white, elevation: 0),
            child: const Text('Save', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart     = ref.watch(activeQrCartProvider);
    final notifier = ref.read(activeQrCartNotifierProvider);

    if (cart.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              _CartHeader(
                tableName: cart.tableName ?? widget.tableId,
                onBack: () => context.pop(),
                onClear: null,
              ),
              Expanded(
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.shopping_cart_outlined, size: 80, color: AppColors.textHint),
                    const SizedBox(height: 16),
                    const Text('Your cart is empty',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 17,
                            fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    const SizedBox(height: 8),
                    const Text('Choose a menu item first',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                            color: AppColors.textSecondary)),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () => context.pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Back to Menu',
                          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600))),
                  ]),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final addMode = ref.watch(addOrderModeProvider);
    final isAddMode = addMode != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _CartHeader(
                tableName: cart.tableName ?? widget.tableId,
                onBack: () {
                  // When backing out of add mode, reset the mode so it doesn't get stuck
                  if (isAddMode) {
                    ref.read(addOrderModeProvider.notifier).state = null;
                    notifier.clearCart();
                  }
                  context.pop();
                },
                onClear: () {
                  showDialog(
                    context: context,
                    builder: (dialogCtx) => AlertDialog(
                      backgroundColor: AppColors.surface,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.radiusLg)),
                      title: const Text('Clear Cart?',
                          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
                      content: const Text('All items will be removed from the cart.',
                          style: TextStyle(fontFamily: 'Poppins')),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogCtx),
                          child: const Text('Cancel',
                              style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary))),
                        TextButton(
                          onPressed: () {
                            notifier.clearCart();
                            Navigator.pop(dialogCtx);
                            context.pop();
                          },
                          style: TextButton.styleFrom(foregroundColor: AppColors.accent),
                          child: const Text('Clear',
                              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600))),
                      ],
                    ),
                  );
                },
              ),
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    // ── Title block ──────────────────────────────────────
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(isAddMode ? 'Add Order' : 'Your Order',
                                style: const TextStyle(fontFamily: 'Poppins', fontSize: 30,
                                    fontWeight: FontWeight.w800, color: AppColors.primary)),
                            const SizedBox(height: 6),
                            Text(
                              isAddMode
                                  ? 'These new items will be added to your existing order.'
                                  : 'Review your items before sending to the kitchen.',
                              style: const TextStyle(fontFamily: 'Poppins', fontSize: 13.5,
                                  color: AppColors.textSecondary, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ── ML Estimate Banner ─────────────────────────────────────────
                    if (_isFetchingEstimate || _estimatedMinutes != null)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                              border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                            ),
                            child: Row(children: [
                              const Icon(Icons.schedule_rounded, size: 20, color: AppColors.primary),
                              const SizedBox(width: 10),
                              Expanded(child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _isFallbackEstimate
                                        ? 'Rough Estimate (offline)'
                                        : 'Estimated Ready Time',
                                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                                        fontWeight: FontWeight.w700, color: AppColors.textSecondary,
                                        letterSpacing: 0.4)),
                                  const SizedBox(height: 2),
                                  if (_isFetchingEstimate)
                                    Row(children: [
                                      const SizedBox(
                                        width: 12, height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2, color: AppColors.primary)),
                                      const SizedBox(width: 8),
                                      const Text('Calculating...',
                                          style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                                              color: AppColors.textPrimary)),
                                    ])
                                  else
                                    Text(
                                      PrepTimeService.formatEstimate(_estimatedMinutes!),
                                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 16,
                                          fontWeight: FontWeight.w800, color: AppColors.primary)),
                                ],
                              )),
                              Icon(Icons.info_outline, size: 16,
                                  color: AppColors.primary.withValues(alpha: 0.5)),
                            ]),
                          ),
                        ),
                      ),

                    // ── Add-order mode banner ──────────────────────────────────
                    if (isAddMode)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                              border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                            ),
                            child: Row(children: [
                              const Icon(Icons.add_circle_outline, color: AppColors.accent, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Add Order Mode',
                                        style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                                            fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                                    Text(
                                      'Queue No.: ${addMode.queueNumber} · Existing items cannot be changed',
                                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                                          color: AppColors.textSecondary),
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
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                        child: Text('${cart.totalItems} item(s) ordered',
                            style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                                fontWeight: FontWeight.w700, color: AppColors.textSecondary,
                                letterSpacing: 0.4)),
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
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                          child: _CustomerInfoCard(
                            nameCtrl:  _nameCtrl,
                            phoneCtrl: _phoneCtrl,
                            tableName: cart.tableName ?? 'Table'),
                        ),
                      ),

                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                        child: _OrderSummaryCard(cart: cart, isAddMode: isAddMode),
                      ),
                    ),
                  ],
                ),
              ),
              _CartBottomBar(
                cart:      cart,
                onProceed: _showOrderConfirmationDialog,
                isLoading: _isSubmitting,
                isAddMode: isAddMode,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Header ─────────────────────────────────────────────────────────────────
class _CartHeader extends StatelessWidget {
  final String tableName;
  final VoidCallback onBack;
  final VoidCallback? onClear;

  const _CartHeader({required this.tableName, required this.onBack, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: AppColors.textPrimary),
          ),
          Expanded(
            child: Text(
              tableName,
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 15,
                  fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onClear != null)
            IconButton(
              onPressed: onClear,
              icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.accent),
            )
          else
            const SizedBox(width: 48),
        ],
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
    final hasNotes = item.notes != null && item.notes!.isNotEmpty;

    return Dismissible(
      key: ValueKey(item.menuItem.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.accent, borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 24)),
      onDismissed: (_) => onDelete(),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(item.menuItem.name,
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 17,
                          fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Text(_formatPrice(item.menuItem.price),
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 12.5,
                          fontWeight: FontWeight.w700, color: AppColors.primary)),
                ),
              ],
            ),
            if (item.menuItem.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(item.menuItem.description,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                      color: AppColors.textSecondary, height: 1.35),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 6),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.accentOrange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.timer_outlined, size: 11, color: AppColors.accentOrange),
                  const SizedBox(width: 3),
                  Text('${item.menuItem.preparationTimeMinutes} min',
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 10,
                          color: AppColors.accentOrange, fontWeight: FontWeight.w700)),
                ]),
              ),
              const Spacer(),
              Text(_formatPrice(item.subtotal),
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                      fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _QtyBtn(icon: Icons.remove, onTap: onRemove),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text('${item.quantity}',
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 14,
                            fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
                  _QtyBtn(icon: Icons.add, onTap: onAdd),
                ]),
              ),
              const Spacer(),
            ]),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: onEditNotes,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  border: Border.all(
                      color: hasNotes ? AppColors.primary.withValues(alpha: 0.4) : AppColors.border)),
                child: Row(children: [
                  Icon(hasNotes ? Icons.edit_note : Icons.note_add_outlined,
                      size: 15, color: hasNotes ? AppColors.primary : AppColors.textHint),
                  const SizedBox(width: 6),
                  Expanded(child: Text(
                      hasNotes ? item.notes! : 'Add Note (e.g. Extra spicy)',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                          color: hasNotes ? AppColors.textPrimary : AppColors.textHint,
                          fontStyle: hasNotes ? FontStyle.normal : FontStyle.italic),
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

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _QtyBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30, height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill)),
        child: Icon(icon, size: 15, color: AppColors.primary)));
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

  InputDecoration _decoration({required String label, String? hint, String? helper, required IconData icon}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary, fontSize: 13),
      hintText: hint,
      hintStyle: const TextStyle(fontFamily: 'Poppins', color: AppColors.textHint, fontSize: 13),
      helperText: helper,
      helperStyle: const TextStyle(fontFamily: 'Poppins', color: AppColors.textHint, fontSize: 11),
      prefixIcon: Icon(icon, color: AppColors.textHint, size: 20),
      filled: true,
      fillColor: AppColors.surfaceVariant,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.4)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          borderSide: const BorderSide(color: AppColors.accent)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border)),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.person_outline, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          const Text('Customer Information',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 15,
                  fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        ]),
        const SizedBox(height: 14),
        TextFormField(
          initialValue: tableName,
          readOnly: true,
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 14, color: AppColors.textPrimary),
          decoration: _decoration(label: 'Table Number', icon: Icons.table_restaurant_outlined),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: nameCtrl,
          textCapitalization: TextCapitalization.words,
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 14, color: AppColors.textPrimary),
          decoration: _decoration(
              label: 'Customer Name *', hint: 'Example: John', icon: Icons.badge_outlined),
          validator: (val) {
            if (val == null || val.trim().isEmpty) return 'Name cannot be empty';
            if (val.trim().length < 2) return 'Name is too short';
            return null;
          }),
        const SizedBox(height: 10),
        TextFormField(
          controller: phoneCtrl,
          keyboardType: TextInputType.phone,
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 14, color: AppColors.textPrimary),
          decoration: _decoration(
              label: 'Phone Number (optional)',
              hint: 'Example: 08123456789',
              helper: 'Format: 08xxxxxxxxxx (10-13 digits)',
              icon: Icons.phone_outlined),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(color: AppColors.border, height: 1, thickness: 1),
        const SizedBox(height: 16),

        if (!isAddMode) ...[
          _row('Subtotal', _formatPrice(cart.subtotal)),
          const SizedBox(height: 8),
          _row('Service Charge (3%)', _formatPrice(cart.serviceCharge)),
          const SizedBox(height: 8),
          _row('PB1 (10%)', _formatPrice(cart.pb1Amount)),
          const SizedBox(height: 16),
          const Divider(color: AppColors.border, height: 1, thickness: 1),
          const SizedBox(height: 16),
          Row(children: [
            const Text('Total',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 19,
                    fontWeight: FontWeight.w800, color: AppColors.primary)),
            const Spacer(),
            Text(_formatPrice(cart.totalAmount),
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 19,
                    fontWeight: FontWeight.w800, color: AppColors.primary)),
          ]),
        ] else ...[
          _row('New items subtotal', _formatPrice(cart.subtotal), emphasize: true),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline, size: 13, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'PB1 & Service Charge are calculated automatically from the order total.',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: AppColors.textSecondary),
                ),
              ),
            ]),
          ),
        ],
      ],
    );
  }

  Widget _row(String label, String value, {bool emphasize = false}) {
    return Row(children: [
      Text(label,
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 14, color: AppColors.textSecondary)),
      const Spacer(),
      Text(value,
          style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
              color: AppColors.textPrimary)),
    ]);
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
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: const Border(top: BorderSide(color: AppColors.border))),
      child: SizedBox(
        width: double.infinity, height: 54,
        child: ElevatedButton(
          onPressed: isLoading ? null : onProceed,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.accent.withValues(alpha: 0.6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
            elevation: 0),
          child: isLoading
              ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                  SizedBox(width: 10),
                  Text('Sending to Kitchen...',
                      style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
                ])
              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.send_rounded, size: 19, color: Colors.white),
                  const SizedBox(width: 10),
                  Text(isAddMode ? 'Send Additional Order' : 'Send Order',
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 15.5,
                          fontWeight: FontWeight.w700, color: Colors.white)),
                ]),
        ),
      ),
    );
  }
}
