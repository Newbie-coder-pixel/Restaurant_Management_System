import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/qr_order_repository.dart';
import '../models/qr_order_model.dart';
import '../../../core/services/prep_time_service.dart'; // ← ML Service
import '../providers/qr_cart_provider.dart';
import '../services/qr_device_id_service.dart';
import '../../payment/models/midtrans_model.dart';

class QrOrderTrackerScreen extends ConsumerWidget {
  final String orderId;
  final String? queueNumber;

  const QrOrderTrackerScreen({
    super.key,
    required this.orderId,
    this.queueNumber,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderAsync = ref.watch(qrOrderWatchProvider(orderId));

    return orderAsync.when(
      loading: () => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('Loading order status...',
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Order Status')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_outlined, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('Unable to load status'),
              const SizedBox(height: 8),
              if (queueNumber != null)
                Text(
                  'Queue No.: $queueNumber',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18),
                ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => ref.invalidate(qrOrderWatchProvider(orderId)),
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      ),
      data: (order) => _TrackerBody(order: order),
    );
  }
}

// ─── Tracker Body ─────────────────────────────────────────────────────────────

class _TrackerBody extends StatelessWidget {
  final QrOrderModel order;

  const _TrackerBody({required this.order});

  static const _steps = [
    (
      status: QrOrderStatus.created,
      label: 'Order Received',
      sublabel: 'Order received, waiting for the kitchen',
      icon: Icons.hourglass_top_outlined,
    ),
    (
      status: QrOrderStatus.preparing,
      label: 'Being Cooked',
      sublabel: 'The kitchen is preparing your order',
      icon: Icons.outdoor_grill_outlined,
    ),
    (
      status: QrOrderStatus.ready,
      label: 'Ready to Serve',
      sublabel: 'Your order is ready, will be served shortly',
      icon: Icons.dining_outlined,
    ),
    (
      status: QrOrderStatus.served,
      label: 'Enjoy Your Meal',
      sublabel: 'Your order is on your table',
      icon: Icons.sentiment_very_satisfied_outlined,
    ),
    (
      status: QrOrderStatus.paid,
      label: 'Completed & Paid',
      sublabel: 'Thank you for dining with us!',
      icon: Icons.celebration_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isCancelled = order.status == QrOrderStatus.cancelled;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      body: CustomScrollView(
        slivers: [
          // ── Header / Queue Number ──────────────────────────────────────
          SliverToBoxAdapter(
            child: _QueueHeader(order: order),
          ),

          // ── ML Time Estimate ──────────────────────────────────────────
          // Only shown while the order is active (created / preparing)
          if (!isCancelled &&
              (order.status == QrOrderStatus.created ||
                  order.status == QrOrderStatus.preparing))
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _PrepTimeCard(order: order),
              ),
            ),

          // ── Cancelled Banner ─────────────────────────────────────────────
          if (isCancelled)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.cancel_outlined,
                          color: colorScheme.error),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Order cancelled. Please contact the cashier.',
                          style: TextStyle(color: colorScheme.error),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Progress Steps ───────────────────────────────────────────────
          if (!isCancelled)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _StatusStepper(
                  currentStatus: order.status,
                  steps: _steps,
                ),
              ),
            ),

          // ── Payment Status ────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _PaymentStatusCard(order: order),
            ),
          ),

          // ── Order Detail ──────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _OrderDetailCard(order: order),
            ),
          ),

          // ── Actions ───────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: _TrackerActions(order: order),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── ML Prep Time Card ────────────────────────────────────────────────────────

class _PrepTimeCard extends StatefulWidget {
  final QrOrderModel order;

  const _PrepTimeCard({required this.order});

  @override
  State<_PrepTimeCard> createState() => _PrepTimeCardState();
}

class _PrepTimeCardState extends State<_PrepTimeCard> {
  late final Future<PrepTimeResult?> _future;
  List<PrepTimeRequestItem> _requestItems = [];

  /// Converts QrOrderItemModel → PrepTimeRequestItem for the ML API.
  /// Fetches the REAL preparation_time_minutes from the menu_items table —
  /// previously hardcoded to 15 for all items because QrOrderItemModel didn't
  /// store this field, which broke weighted_prep_time (Iced Tea and Grilled
  /// Chicken were both treated as 15 minutes). Falls back to 15 only if the
  /// menu item has already been deleted from the menu_items table.
  Future<List<PrepTimeRequestItem>> _buildRequestItems() async {
    final ids = widget.order.items.map((i) => i.menuItemId).toSet().toList();
    final prepTimes = <String, int>{};

    if (ids.isNotEmpty) {
      try {
        final rows = await Supabase.instance.client
            .from('menu_items')
            .select('id, preparation_time_minutes')
            .inFilter('id', ids);
        for (final row in (rows as List)) {
          final id = row['id'] as String?;
          final prep = (row['preparation_time_minutes'] as num?)?.toInt();
          if (id != null && prep != null) prepTimes[id] = prep;
        }
      } catch (e) {
        debugPrint('Failed to fetch preparation_time_minutes: $e');
      }
    }

    return widget.order.items
        .map((item) => PrepTimeRequestItem(
              menuItemName: item.menuItemName,
              quantity: item.quantity,
              preparationTimeMinutes: prepTimes[item.menuItemId] ?? 15,
              specialRequests: item.notes,
            ))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _future = _buildRequestItems().then((items) {
      _requestItems = items;
      return PrepTimeService.predict(
        items: items,
        branchId: widget.order.branchId ?? '',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cs.primaryContainer.withValues(alpha: 0.7),
            cs.secondaryContainer.withValues(alpha: 0.5),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.primary.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: FutureBuilder<PrepTimeResult?>(
        future: _future,
        builder: (context, snap) {
          // Loading
          if (snap.connectionState == ConnectionState.waiting) {
            return Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: cs.primary),
                ),
                const SizedBox(width: 12),
                Text(
                  'Calculating time estimate...',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: cs.onPrimaryContainer),
                ),
              ],
            );
          }

          // Server unreachable (e.g. down/timeout) → show a rough estimate
          // (sum of menu prep times, without ML/buffer) instead of
          // hiding this card entirely. Clearly marked as different from the ML result.
          final result = snap.data;
          final isFallback = snap.hasError || result == null;
          final displayMinutes = isFallback
              ? PrepTimeService.rawFallbackEstimate(_requestItems)
              : result.estimatedMinutes;

          if (isFallback && displayMinutes <= 0) {
            return Row(
              children: [
                Icon(Icons.access_time_outlined,
                    color: cs.outline, size: 20),
                const SizedBox(width: 10),
                Text(
                  'Time estimate not available',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.outline),
                ),
              ],
            );
          }

          return Row(
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                    isFallback
                        ? Icons.access_time_outlined
                        : Icons.soup_kitchen_outlined,
                    color: cs.primary,
                    size: 22),
              ),
              const SizedBox(width: 14),

              // Estimate text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isFallback
                          ? 'Rough Estimate (offline)'
                          : 'Estimated Cooking Time',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.onPrimaryContainer
                            .withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      PrepTimeService.formatEstimate(displayMinutes),
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              // AI Badge
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: cs.primary.withValues(alpha: 0.3), width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.smart_toy_outlined,
                        size: 12, color: cs.primary),
                    const SizedBox(width: 4),
                    Text(
                      'AI',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Queue Header ─────────────────────────────────────────────────────────────

class _QueueHeader extends StatelessWidget {
  final QrOrderModel order;

  const _QueueHeader({required this.order});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: order.status == QrOrderStatus.cancelled
              ? [colorScheme.errorContainer, colorScheme.error.withValues(alpha: 0.3)]
              : order.status == QrOrderStatus.paid
                  ? [Colors.green.shade400, Colors.green.shade600]
                  : [colorScheme.primary, colorScheme.primaryContainer],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            children: [
              // App bar row
              Row(
                children: [
                  Text(
                    'Order Status',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  // Live indicator
                  if (order.isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _PulsingDot(),
                          const SizedBox(width: 4),
                          Text(
                            'Live',
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 20),

              // Queue number (big)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 20),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3), width: 1),
                ),
                child: Column(
                  children: [
                    Text(
                      'Queue No.',
                      style: theme.textTheme.labelLarge?.copyWith(
                          color: colorScheme.onPrimary.withValues(alpha: 0.8)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      order.queueNumber ?? order.orderNumber,
                      style: theme.textTheme.displayMedium?.copyWith(
                        color: colorScheme.onPrimary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(
                            text: order.queueNumber ?? order.orderNumber));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Queue number copied!'),
                              duration: Duration(seconds: 2)),
                        );
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.copy_outlined,
                              size: 14,
                              color: colorScheme.onPrimary.withValues(alpha: 0.7)),
                          const SizedBox(width: 4),
                          Text(
                            'Copy number',
                            style: theme.textTheme.labelSmall?.copyWith(
                                color:
                                    colorScheme.onPrimary.withValues(alpha: 0.7)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Status label
              Text(
                '${order.status.emoji}  ${order.status.label}',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.onPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 4),
              Text(
                '${order.tableName ?? 'Table'} · ${order.customerName}',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onPrimary.withValues(alpha: 0.75)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Pulsing Dot ──────────────────────────────────────────────────────────────

class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          color: Colors.greenAccent,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ─── Status Stepper ───────────────────────────────────────────────────────────

class _StatusStepper extends StatelessWidget {
  final QrOrderStatus currentStatus;
  final List<
      ({
        QrOrderStatus status,
        String label,
        String sublabel,
        IconData icon,
      })> steps;

  const _StatusStepper(
      {required this.currentStatus, required this.steps});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentIdx = currentStatus.stepIndex;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant, width: 0.8),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: currentStatus.progress,
              minHeight: 6,
              backgroundColor: colorScheme.surfaceContainerHighest,
              valueColor:
                  AlwaysStoppedAnimation<Color>(colorScheme.primary),
            ),
          ),
          const SizedBox(height: 20),

          // Steps
          Column(
            children: steps.asMap().entries.map((entry) {
              final idx = entry.key;
              final step = entry.value;
              final isDone = idx <= currentIdx;
              final isCurrent = idx == currentIdx;

              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    // Circle indicator
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDone
                            ? colorScheme.primary
                            : colorScheme.surfaceContainerHighest,
                        border: isCurrent
                            ? Border.all(
                                color: colorScheme.primary, width: 2)
                            : null,
                      ),
                      child: Icon(
                        isDone ? Icons.check : step.icon,
                        size: 18,
                        color: isDone
                            ? colorScheme.onPrimary
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            step.label,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: isCurrent
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isDone
                                  ? colorScheme.primary
                                  : colorScheme.onSurface,
                            ),
                          ),
                          if (isCurrent)
                            Text(
                              step.sublabel,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.outline),
                            ),
                        ],
                      ),
                    ),

                    if (isCurrent)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Now',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ─── Payment Status Card ──────────────────────────────────────────────────────

class _PaymentStatusCard extends StatelessWidget {
  final QrOrderModel order;

  const _PaymentStatusCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isPaid = order.paymentStatus == QrPaymentStatus.paid;
    // Same label source the staff cashier PDF receipt uses (receipt_service.dart)
    // — one mapping, so a payment method never reads differently across receipts.
    // Staff-created dine-in orders never set payment_method (that column is
    // QR-flow-only) — 'kasir' maps to "Cashier", the correct real-world
    // meaning for an order with no online payment method recorded.
    final methodLabel = MidtransPaymentMethod.label(order.paymentMethod ?? 'kasir');

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant, width: 0.8),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isPaid
                  ? Colors.green.shade50
                  : Colors.orange.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isPaid
                  ? Icons.check_circle_outline
                  : Icons.schedule_outlined,
              color:
                  isPaid ? Colors.green.shade600 : Colors.orange.shade600,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPaid ? 'Paid' : 'Pay After Dining',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isPaid
                        ? Colors.green.shade700
                        : Colors.orange.shade700,
                  ),
                ),
                Text(
                  isPaid
                      ? 'Payment via $methodLabel confirmed'
                      : 'Please pay at the cashier after you finish dining',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colorScheme.outline),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatPrice(order.totalAmount),
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                'already includes PB1 & service charge',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: colorScheme.outline, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatPrice(double price) {
    final formatted = price
        .toStringAsFixed(0)
        .replaceAllMapped(
            RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
    return 'Rp $formatted';
  }
}

// ─── Order Detail Card ────────────────────────────────────────────────────────

class _OrderDetailCard extends StatefulWidget {
  final QrOrderModel order;

  const _OrderDetailCard({required this.order});

  @override
  State<_OrderDetailCard> createState() => _OrderDetailCardState();
}

class _OrderDetailCardState extends State<_OrderDetailCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant, width: 0.8),
      ),
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.receipt_long_outlined,
                      size: 18, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Order Details (${widget.order.items.length} item)',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: colorScheme.outline,
                  ),
                ],
              ),
            ),
          ),

          // Items (collapsible)
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: _expanded
                ? Column(
                    children: [
                      Divider(
                          height: 1,
                          color: colorScheme.outlineVariant),
                      ...widget.order.items.map((item) => Padding(
                            padding:
                                const EdgeInsets.fromLTRB(14, 10, 14, 0),
                            child: Row(
                              children: [
                                Text(
                                  '${item.quantity}×',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(item.menuItemName,
                                          style:
                                              theme.textTheme.bodySmall),
                                      if (item.notes != null &&
                                          item.notes!.isNotEmpty)
                                        Text('📝 ${item.notes}',
                                            style: theme
                                                .textTheme.bodySmall
                                                ?.copyWith(
                                                    color: colorScheme
                                                        .outline,
                                                    fontSize: 11)),
                                    ],
                                  ),
                                ),
                                Text(
                                  _formatPrice(item.subtotal),
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ))),
                      const SizedBox(height: 10),
                      Divider(height: 1, color: colorScheme.outlineVariant),
                      // Same row labels & order as the staff cashier PDF
                      // receipt (receipt_service.dart _totalRow calls) —
                      // Subtotal, PB1, Service, [Discount], [Overtime], Total.
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                        child: _PriceRow(
                          label: 'Subtotal',
                          amount: widget.order.items.fold(0.0, (sum, i) => sum + i.subtotal),
                          theme: theme,
                          colorScheme: colorScheme,
                          formatPrice: _formatPrice,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                        child: _PriceRow(
                          label: 'PB1 (10%)',
                          amount: widget.order.items.fold(0.0, (sum, i) => sum + i.subtotal) * 1.03 * 0.10,
                          theme: theme,
                          colorScheme: colorScheme,
                          formatPrice: _formatPrice,
                          isNote: true,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                        child: _PriceRow(
                          label: 'Service (3%)',
                          amount: widget.order.items.fold(0.0, (sum, i) => sum + i.subtotal) * 0.03,
                          theme: theme,
                          colorScheme: colorScheme,
                          formatPrice: _formatPrice,
                          isNote: true,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                        child: Row(
                          children: [
                            Text('Total',
                                style: theme.textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.bold)),
                            const Spacer(),
                            Text(
                              _formatPrice(widget.order.totalAmount),
                              style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  String _formatPrice(double price) {
    final formatted = price
        .toStringAsFixed(0)
        .replaceAllMapped(
            RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
    return 'Rp $formatted';
  }
}

// ─── Price Row Helper ─────────────────────────────────────────────────────────

class _PriceRow extends StatelessWidget {
  final String label;
  final double amount;
  final ThemeData theme;
  final ColorScheme colorScheme;
  final String Function(double) formatPrice;
  final bool isNote;

  const _PriceRow({
    required this.label,
    required this.amount,
    required this.theme,
    required this.colorScheme,
    required this.formatPrice,
    this.isNote = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: isNote ? colorScheme.outline : colorScheme.onSurface,
          ),
        ),
        const Spacer(),
        Text(
          formatPrice(amount),
          style: theme.textTheme.bodySmall?.copyWith(
            color: isNote ? colorScheme.outline : colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

// ─── Tracker Actions ──────────────────────────────────────────────────────────

class _TrackerActions extends ConsumerStatefulWidget {
  final QrOrderModel order;

  const _TrackerActions({required this.order});

  @override
  ConsumerState<_TrackerActions> createState() => _TrackerActionsState();
}

class _TrackerActionsState extends ConsumerState<_TrackerActions> {
  bool _billRequested = false;
  bool _isRequestingBill = false;
  String? _deviceId;

  @override
  void initState() {
    super.initState();
    // Init from the model so it persists after a refresh
    _billRequested = widget.order.billRequested;
    // Only the device that placed this order may add items to it — see
    // supabase/migrations/20260803010000_qr_order_device_id.sql.
    QrDeviceIdService.getDeviceId().then((id) {
      if (!mounted) return;
      setState(() => _deviceId = id);
      // Orders with no device_id recorded (e.g. placed before this feature
      // shipped) can't prove who placed them — claim it for this device
      // instead of permanently locking everyone out. No-op if some other
      // device already claimed it in the meantime (DB-enforced, see
      // 20260803030000_qr_order_device_id_claim.sql).
      final order = widget.order;
      if (order.deviceId == null || order.deviceId!.isEmpty) {
        ref.read(qrOrderRepositoryProvider).claimOrderIfUnowned(order.id, id);
      }
    });
  }

  @override
  void didUpdateWidget(_TrackerActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If a Supabase realtime update sets billRequested to true, follow it
    if (widget.order.billRequested && !_billRequested) {
      setState(() => _billRequested = true);
    }
  }

  Future<void> _requestBill(BuildContext context) async {
    final order = widget.order;
    // Save the messenger before the async gap
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isRequestingBill = true);
    try {
      await Supabase.instance.client.from('orders').update({
        'bill_requested': true,
        'bill_requested_at': DateTime.now().toIso8601String(),
      }).eq('id', order.id);

      if (!mounted) return;
      setState(() {
        _billRequested = true;
        _isRequestingBill = false;
      });
      messenger.showSnackBar(
        const SnackBar(
          content: Text('✅ The cashier is preparing your bill!'),
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isRequestingBill = false);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Failed to send the bill request. Try again.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Navigates to the menu screen in "add order" mode.
  /// Sets addOrderModeProvider → clears the old cart → pushes to the menu.
  void _goToAddOrder(BuildContext context) {
    final order = widget.order;

    // Set add-order mode
    ref.read(addOrderModeProvider.notifier).state = AddOrderModeState(
      orderId: order.id,
      queueNumber: order.queueNumber ?? order.orderNumber,
      tableId: order.tableId,
    );

    // Clear the cart so it doesn't mix with items from the old order
    final table = ref.read(activeQrTableProvider);
    ref.read(qrCartProvider(table).notifier).clearCart();

    // Push to the menu screen (not go, so we can back out to the tracker)
    context.push('/qr/${order.tableId}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final order = widget.order;
    final isCreated = order.status == QrOrderStatus.created;
    final isPreparing = order.status == QrOrderStatus.preparing;
    final isReady = order.status == QrOrderStatus.ready;
    final isServed = order.status == QrOrderStatus.served;
    final isCancelled = order.status == QrOrderStatus.cancelled;

    // Adding to the order is allowed until served/paid/cancelled, and only
    // from the device that placed it — every other device is view-only.
    // An order with no device_id recorded at all (placed before this
    // feature shipped) has no owner to defer to, so this device is treated
    // as the owner and (see initState) claims it for real in the background.
    final orderHasNoOwner =
        order.deviceId == null || order.deviceId!.isEmpty;
    final isOwner = _deviceId != null &&
        (orderHasNoOwner || order.deviceId == _deviceId);
    final canAddOrderStatus = (isCreated || isPreparing || isReady) && !isCancelled;
    final canAddOrder = canAddOrderStatus && isOwner;

    return Column(
      children: [
        // ── Not the owning device: explain why "Add Order" isn't offered ──
        if (canAddOrderStatus && !isOwner) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(Icons.smartphone_outlined, size: 16, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Only the device that placed this order can add items to it.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colorScheme.onSurfaceVariant, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        // ── Add Order button (active until served) ───────
        if (canAddOrder) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _goToAddOrder(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              icon: const Icon(Icons.add_shopping_cart_outlined),
              label: const Text(
                'Add Order',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Info: items already sent cannot be changed
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.tertiaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: colorScheme.tertiary.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    size: 14, color: colorScheme.tertiary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Items already sent to the kitchen cannot be changed or cancelled.',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onTertiaryContainer,
                        fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],

        // ── Pay Now button (self-service Midtrans, only while served) ────────
        if (isServed) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => context.push('/qr/${order.tableId}/pay/${order.id}'),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              icon: const Icon(Icons.payment_rounded),
              label: const Text('Pay Now',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text('or',
                style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline)),
          ),
          const SizedBox(height: 8),
        ],

        // ── Request Bill button (only while served) ──────────────────────────
        if (isServed) ...[
          if (!_billRequested)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isRequestingBill ? null : () => _requestBill(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: _isRequestingBill
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.receipt_outlined),
                label: Text(
                  _isRequestingBill ? 'Sending...' : 'Request Bill',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline,
                      color: Colors.green.shade700, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Bill requested — the cashier is on the way',
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
        ],

        // ── Help info ─────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.help_outline, size: 16, color: colorScheme.outline),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Having an issue? Show this screen to our staff.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colorScheme.outline),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}