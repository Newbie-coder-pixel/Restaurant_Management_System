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
import '../../../core/theme/app_theme.dart';
import '../../../shared/services/customer_sound_preference.dart';

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
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(height: 16),
              const Text('Loading order status...',
                  style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          foregroundColor: AppColors.textPrimary,
          title: const Text('Order Status', style: TextStyle(fontFamily: 'Poppins')),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_outlined, size: 64, color: AppColors.textHint),
              const SizedBox(height: 16),
              const Text('Unable to load status',
                  style: TextStyle(fontFamily: 'Poppins', color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              if (queueNumber != null)
                Text(
                  'Queue No.: $queueNumber',
                  style: const TextStyle(fontFamily: 'Poppins',
                      fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.textPrimary),
                ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => ref.invalidate(qrOrderWatchProvider(orderId)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary, foregroundColor: Colors.white, elevation: 0),
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again', style: TextStyle(fontFamily: 'Poppins')),
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
      label: 'Received',
      sublabel: 'Order received, waiting for the kitchen',
      icon: Icons.hourglass_top_outlined,
    ),
    (
      status: QrOrderStatus.preparing,
      label: 'Preparing',
      sublabel: 'Our chefs are crafting your order with care.',
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
      label: 'Served',
      sublabel: 'Your order is on your table. Enjoy!',
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
    final isCancelled = order.status == QrOrderStatus.cancelled;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _TrackerHeader(order: order),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  // ── Status Hero ─────────────────────────────────────────────
                  SliverToBoxAdapter(child: _StatusHero(order: order)),

                  // ── ML Time Estimate ──────────────────────────────────────────
                  // Only shown while the order is active (created / preparing)
                  if (!isCancelled &&
                      (order.status == QrOrderStatus.created ||
                          order.status == QrOrderStatus.preparing))
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                        child: _PrepTimeCard(order: order),
                      ),
                    ),

                  // ── Cancelled Banner ─────────────────────────────────────────────
                  if (isCancelled)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                            border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.cancel_outlined, color: AppColors.accent),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Order cancelled. Please contact the cashier.',
                                  style: TextStyle(fontFamily: 'Poppins', color: AppColors.accent,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // ── Timeline ───────────────────────────────────────────────
                  if (!isCancelled)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                        child: _StatusTimeline(order: order, steps: _steps),
                      ),
                    ),

                  // ── Payment Status ────────────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: _PaymentStatusCard(order: order),
                    ),
                  ),

                  // ── Order Items ──────────────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                      child: _OrderDetailCard(order: order),
                    ),
                  ),

                  // ── Actions ───────────────────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                      child: _TrackerActions(order: order),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Header ─────────────────────────────────────────────────────────────────
class _TrackerHeader extends StatelessWidget {
  final QrOrderModel order;
  const _TrackerHeader({required this.order});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: AppColors.textPrimary),
          ),
          Expanded(
            child: Text(
              order.tableName ?? 'Table',
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 15,
                  fontWeight: FontWeight.w700, color: AppColors.primary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ValueListenableBuilder<int>(
            valueListenable: CustomerSoundPreference.revision,
            builder: (context, _, __) {
              final enabled = CustomerSoundPreference.valueFor(order.id);
              return IconButton(
                tooltip: enabled == true
                    ? 'Sound notifications on'
                    : 'Sound notifications off',
                onPressed: () =>
                    CustomerSoundPreference.setEnabled(order.id, enabled != true),
                icon: Icon(
                  enabled == true
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded,
                  size: 20,
                  color: enabled == true
                      ? AppColors.primary
                      : AppColors.textHint,
                ),
              );
            },
          ),
          SizedBox(
            width: 24,
            child: order.isActive
                ? const Center(child: _PulsingDot(color: AppColors.primary))
                : null,
          ),
        ],
      ),
    );
  }
}

// ─── Status Hero ──────────────────────────────────────────────────────────────
class _StatusHero extends StatelessWidget {
  final QrOrderModel order;
  const _StatusHero({required this.order});

  String get _headline {
    switch (order.status) {
      case QrOrderStatus.created:   return 'Order Received';
      case QrOrderStatus.preparing: return 'Order is Preparing';
      case QrOrderStatus.ready:     return 'Ready to Serve!';
      case QrOrderStatus.served:    return 'Enjoy Your Meal!';
      case QrOrderStatus.paid:      return 'Thank You!';
      case QrOrderStatus.cancelled: return 'Order Cancelled';
    }
  }

  List<Color> get _gradient {
    switch (order.status) {
      case QrOrderStatus.cancelled:
        return [AppColors.accent.withValues(alpha: 0.85), AppColors.accent];
      case QrOrderStatus.paid:
        return [Colors.green.shade400, Colors.green.shade700];
      default:
        return [AppColors.primaryLight, AppColors.accent];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _gradient,
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              AppColors.textPrimary.withValues(alpha: 0.55),
            ],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'STATUS',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                  fontWeight: FontWeight.w800, color: Colors.white.withValues(alpha: 0.85),
                  letterSpacing: 1.2),
            ),
            const SizedBox(height: 6),
            Text(
              _headline,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 28,
                  fontWeight: FontWeight.w800, color: Colors.white),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: order.queueNumber ?? order.orderNumber));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Queue number copied!'), duration: Duration(seconds: 2)),
                );
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Queue No. ${order.queueNumber ?? order.orderNumber} · ${order.customerName}',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5,
                        color: Colors.white.withValues(alpha: 0.9), fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.copy_outlined, size: 13, color: Colors.white.withValues(alpha: 0.8)),
                ],
              ),
            ),
          ],
        ),
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
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      padding: const EdgeInsets.all(16),
      child: FutureBuilder<PrepTimeResult?>(
        future: _future,
        builder: (context, snap) {
          // Loading
          if (snap.connectionState == ConnectionState.waiting) {
            return Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Calculating time estimate...',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textPrimary),
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
            return const Row(
              children: [
                Icon(Icons.access_time_outlined, color: AppColors.textHint, size: 20),
                SizedBox(width: 10),
                Text(
                  'Time estimate not available',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: AppColors.textSecondary),
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
                  color: AppColors.primary.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                    isFallback ? Icons.access_time_outlined : Icons.soup_kitchen_outlined,
                    color: AppColors.primary,
                    size: 22),
              ),
              const SizedBox(width: 14),

              // Estimate text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isFallback ? 'Rough Estimate (offline)' : 'Estimated Cooking Time',
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
                          fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      PrepTimeService.formatEstimate(displayMinutes),
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 18,
                          fontWeight: FontWeight.w800, color: AppColors.primary),
                    ),
                  ],
                ),
              ),

              // AI Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 1),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.smart_toy_outlined, size: 12, color: AppColors.primary),
                    SizedBox(width: 4),
                    Text(
                      'AI',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                          fontWeight: FontWeight.w800, color: AppColors.primary),
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

// ─── Pulsing Dot ──────────────────────────────────────────────────────────────

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({this.color = Colors.greenAccent});

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
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

// ─── Status Timeline ──────────────────────────────────────────────────────────

class _StatusTimeline extends StatelessWidget {
  final QrOrderModel order;
  final List<
      ({
        QrOrderStatus status,
        String label,
        String sublabel,
        IconData icon,
      })> steps;

  const _StatusTimeline({required this.order, required this.steps});

  String _fmtTime(DateTime dt) {
    final local = dt.toLocal();
    final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour12:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final currentIdx = order.status.stepIndex;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Timeline',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 19,
                  fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 18),
          ...steps.asMap().entries.map((entry) {
            final idx = entry.key;
            final step = entry.value;
            final isCompleted = idx < currentIdx;
            final isCurrent = idx == currentIdx;
            final isLast = idx == steps.length - 1;

            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isCompleted
                              ? AppColors.textPrimary
                              : Colors.transparent,
                          border: isCurrent
                              ? Border.all(color: AppColors.accent, width: 2)
                              : (!isCompleted
                                  ? Border.all(color: AppColors.border, width: 1.5)
                                  : null),
                        ),
                        child: Icon(
                          isCompleted ? Icons.check_rounded : step.icon,
                          size: 17,
                          color: isCompleted
                              ? Colors.white
                              : (isCurrent ? AppColors.accent : AppColors.textHint),
                        ),
                      ),
                      if (!isLast)
                        Expanded(
                          child: Container(
                            width: 2,
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            color: isCompleted ? AppColors.textPrimary : AppColors.border,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(top: 6, bottom: isLast ? 0 : 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            step.label,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 15,
                              fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w700,
                              color: isCurrent
                                  ? AppColors.accent
                                  : (isCompleted ? AppColors.textPrimary : AppColors.textHint),
                            ),
                          ),
                          if (idx == 0 && (isCompleted || isCurrent)) ...[
                            const SizedBox(height: 3),
                            Text(
                              'Order confirmed by kitchen at ${_fmtTime(order.createdAt)}.',
                              style: const TextStyle(fontFamily: 'Poppins', fontSize: 12.5,
                                  color: AppColors.textSecondary, height: 1.35),
                            ),
                          ] else if (isCurrent) ...[
                            const SizedBox(height: 3),
                            Text(
                              step.sublabel,
                              style: const TextStyle(fontFamily: 'Poppins', fontSize: 12.5,
                                  color: AppColors.textSecondary, height: 1.35),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
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
    final isPaid = order.paymentStatus == QrPaymentStatus.paid;
    // Same label source the staff cashier PDF receipt uses (receipt_service.dart)
    // — one mapping, so a payment method never reads differently across receipts.
    // Staff-created dine-in orders never set payment_method (that column is
    // QR-flow-only) — 'kasir' maps to "Cashier", the correct real-world
    // meaning for an order with no online payment method recorded.
    final methodLabel = MidtransPaymentMethod.label(order.paymentMethod ?? 'kasir');

    final statusColor = isPaid ? Colors.green.shade700 : AppColors.accentOrange;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Icon(
              isPaid ? Icons.check_circle_outline : Icons.schedule_outlined,
              color: statusColor,
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
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                      fontWeight: FontWeight.w700, color: statusColor),
                ),
                Text(
                  isPaid
                      ? 'Payment via $methodLabel confirmed'
                      : 'Please pay at the cashier after you finish dining',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatPrice(order.totalAmount),
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 14,
                    fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
              const Text(
                'incl. PB1 & service',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: AppColors.textHint),
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
        .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
    return 'Rp $formatted';
  }
}

// ─── Order Detail Card ────────────────────────────────────────────────────────

class _OrderDetailCard extends StatelessWidget {
  final QrOrderModel order;

  const _OrderDetailCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final subtotal = order.items.fold(0.0, (sum, i) => sum + i.subtotal);
    final pb1 = subtotal * 1.03 * 0.10;
    final service = subtotal * 0.03;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Order Items',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 22,
                fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 14),

        ...order.items.map((item) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: Text('${item.quantity}x',
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 12.5,
                            fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.menuItemName,
                            style: const TextStyle(fontFamily: 'Poppins', fontSize: 14.5,
                                fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                        if (item.notes != null && item.notes!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(item.notes!,
                              style: const TextStyle(fontFamily: 'Poppins', fontSize: 12.5,
                                  color: AppColors.textSecondary)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(_formatPrice(item.subtotal),
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 13.5,
                          fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                ],
              ),
            )),

        const SizedBox(height: 6),
        Divider(color: AppColors.border, height: 1),
        const SizedBox(height: 12),

        _PriceRow(label: 'Subtotal', amount: subtotal, formatPrice: _formatPrice),
        const SizedBox(height: 6),
        _PriceRow(
            label: 'Tax & Service (13%)', amount: pb1 + service, formatPrice: _formatPrice),

        const SizedBox(height: 16),
        Container(
          height: 3,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            gradient: LinearGradient(colors: [
              AppColors.textPrimary,
              AppColors.textPrimary.withValues(alpha: 0.0),
            ]),
          ),
        ),
        const SizedBox(height: 16),

        Row(
          children: [
            const Text('Total',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 18,
                    fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const Spacer(),
            Text(
              _formatPrice(order.totalAmount),
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 20,
                  fontWeight: FontWeight.w800, color: AppColors.primary),
            ),
          ],
        ),
      ],
    );
  }

  String _formatPrice(double price) {
    final formatted = price
        .toStringAsFixed(0)
        .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
    return 'Rp $formatted';
  }
}

// ─── Price Row Helper ─────────────────────────────────────────────────────────

class _PriceRow extends StatelessWidget {
  final String label;
  final double amount;
  final String Function(double) formatPrice;

  const _PriceRow({
    required this.label,
    required this.amount,
    required this.formatPrice,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13.5, color: AppColors.textSecondary)),
        const Spacer(),
        Text(formatPrice(amount),
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13.5,
                fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
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

    // Push to the menu screen (not go, so we can back out to the tracker).
    // Must carry the `t=` token this session already validated on the
    // original scan (see activeQrTokenProvider, set by QrMenuScreen once
    // validateQrToken() passes) — QrMenuScreen re-validates the token on
    // every entry including this one, and validateQrToken() treats a
    // missing token as invalid outright (no server round-trip at all), so
    // omitting it here always landed on the "QR code has expired" screen
    // even for the still-current code the customer scanned minutes ago.
    final token = ref.read(activeQrTokenProvider);
    context.push(
      '/qr/${order.tableId}${token != null && token.isNotEmpty ? '?t=$token' : ''}',
    );
  }

  @override
  Widget build(BuildContext context) {
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
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              border: Border.all(color: AppColors.border),
            ),
            child: const Row(
              children: [
                Icon(Icons.smartphone_outlined, size: 16, color: AppColors.textSecondary),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Only the device that placed this order can add items to it.',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: AppColors.textSecondary),
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
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
                elevation: 0,
              ),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Add to Order',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                    fontSize: 15.5, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Info: items already sent cannot be changed
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: AppColors.primary),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Items already sent to the kitchen cannot be changed or cancelled.',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: AppColors.textSecondary),
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
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
                elevation: 0,
              ),
              icon: const Icon(Icons.payment_rounded, color: Colors.white),
              label: const Text('Pay Now',
                  style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                      fontSize: 15.5, color: Colors.white)),
            ),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text('or', style: TextStyle(fontFamily: 'Poppins', color: AppColors.textHint)),
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
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
                  elevation: 0,
                ),
                icon: _isRequestingBill
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.receipt_outlined, color: Colors.white),
                label: Text(
                  _isRequestingBill ? 'Sending...' : 'Request Bill',
                  style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                      fontSize: 15.5, color: Colors.white),
                ),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline, color: Colors.green.shade700, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Bill requested — the cashier is on the way',
                    style: TextStyle(
                      fontFamily: 'Poppins',
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
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: const Row(
            children: [
              Icon(Icons.help_outline, size: 16, color: AppColors.textSecondary),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Having an issue? Show this screen to our staff.',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
