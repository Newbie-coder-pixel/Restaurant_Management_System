import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/qr_order_repository.dart';
import '../models/qr_order_model.dart';

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
              Text('Memuat status pesanan...',
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Status Pesanan')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_outlined, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('Tidak dapat memuat status'),
              const SizedBox(height: 8),
              if (queueNumber != null)
                Text(
                  'No. Antrian: $queueNumber',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18),
                ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => ref.invalidate(qrOrderWatchProvider(orderId)),
                icon: const Icon(Icons.refresh),
                label: const Text('Coba Lagi'),
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

  // stepIndex dari model: created=0, preparing=1, ready=2, served=3, paid=4
  static const _steps = [
    (
      status: QrOrderStatus.created,
      label: 'Pesanan Masuk',
      sublabel: 'Pesanan diterima, menunggu dapur',
      icon: Icons.hourglass_top_outlined,
    ),
    (
      status: QrOrderStatus.preparing,
      label: 'Sedang Dimasak',
      sublabel: 'Dapur sedang memproses pesanan',
      icon: Icons.outdoor_grill_outlined,
    ),
    (
      status: QrOrderStatus.ready,
      label: 'Siap Disajikan',
      sublabel: 'Pesanan sudah siap, segera diantar',
      icon: Icons.dining_outlined,
    ),
    (
      status: QrOrderStatus.served,
      label: 'Selamat Menikmati',
      sublabel: 'Pesanan sudah ada di meja kamu',
      icon: Icons.sentiment_very_satisfied_outlined,
    ),
    (
      status: QrOrderStatus.paid,
      label: 'Selesai & Lunas',
      sublabel: 'Terima kasih sudah makan di sini!',
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
                          'Pesanan dibatalkan. Silakan hubungi kasir.',
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
                    'Status Pesanan',
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
                      'No. Antrian',
                      style: theme.textTheme.labelLarge?.copyWith(
                          color: colorScheme.onPrimary.withValues(alpha: 0.8)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      order.queueNumber,
                      style: theme.textTheme.displayMedium?.copyWith(
                        color: colorScheme.onPrimary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(
                            ClipboardData(text: order.queueNumber));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Nomor antrian disalin!'),
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
                            'Salin nomor',
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
                '${order.tableName} · ${order.customerName}',
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

                    // Connector line (except last)
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
                          'Sekarang',
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
    final methodLabel =
        order.paymentMethod == 'qris' ? 'QRIS' : 'Kasir';

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
                  isPaid ? 'Sudah Dibayar' : 'Bayar Setelah Makan',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isPaid
                        ? Colors.green.shade700
                        : Colors.orange.shade700,
                  ),
                ),
                Text(
                  isPaid
                      ? 'Pembayaran via $methodLabel dikonfirmasi'
                      : 'Silakan bayar ke kasir setelah selesai makan',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colorScheme.outline),
                ),
              ],
            ),
          ),
          Text(
            _formatPrice(order.totalAmount),
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
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
                    'Detail Pesanan (${widget.order.items.length} item)',
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
                            ),
                          )),
                      Padding(
                        padding: const EdgeInsets.all(14),
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

// ─── Tracker Actions ──────────────────────────────────────────────────────────

class _TrackerActions extends StatelessWidget {
  final QrOrderModel order;

  const _TrackerActions({required this.order});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        // Pesan lagi setelah lunas
        if (order.status == QrOrderStatus.paid)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                // Go back to menu for same table
                context.go('/qr/${order.tableId}');
              },
              icon: const Icon(Icons.add_shopping_cart_outlined),
              label: const Text('Pesan Lagi'),
            ),
          ),

        const SizedBox(height: 10),

        // Help info
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.help_outline,
                  size: 16, color: colorScheme.outline),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ada masalah? Tunjukkan layar ini ke staf kami.',
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