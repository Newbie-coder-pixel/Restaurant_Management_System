// lib/features/qr_order/presentation/qr_pay_now_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Self-service Midtrans payment for QR dine-in customers.
//
// Reuses the exact same MidtransService/midtransProvider state machine as the
// staff cashier screen (lib/features/payment/...) — same Snap token creation,
// same webhook, same overtime-charge formula — so a payment made from here
// behaves identically to one a cashier processes. The only thing this screen
// owns is a customer-facing UI around that shared flow, with an explicit,
// unmissable outcome for every possible result (paid / pending / failed /
// cancelled / token-creation error), since a silently-stuck payment state is
// worse than a slow one.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/models/order_model.dart';
import '../../payment/midtrans/midtrans_provider.dart';
import '../../payment/models/midtrans_model.dart' show MidtransPaymentStatus, MidtransPaymentMethod;
import '../data/qr_order_repository.dart';

// autoDispose: this must never serve a stale cached order across visits to
// this screen. Without it, coming back here (e.g. browser back button) after
// the order was already paid — by this device, another device, or the
// cashier — could keep showing a payable "Pay Now" screen for an order
// that's actually already settled.
final _payOrderProvider = FutureProvider.autoDispose.family<OrderModel, String>(
  (ref, orderId) => ref.read(qrOrderRepositoryProvider).fetchOrderModelForPayment(orderId),
);

String _fmtRp(double amount) {
  final formatted = amount
      .toStringAsFixed(0)
      .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
  return 'Rp $formatted';
}

class QrPayNowScreen extends ConsumerStatefulWidget {
  final String tableId;
  final String orderId;

  const QrPayNowScreen({super.key, required this.tableId, required this.orderId});

  @override
  ConsumerState<QrPayNowScreen> createState() => _QrPayNowScreenState();
}

class _QrPayNowScreenState extends ConsumerState<QrPayNowScreen> {
  void _goToTracker(OrderModel order) {
    final queue = order.queueNumber;
    context.go('/qr/${widget.tableId}/track/${order.id}${queue != null ? '?queue=$queue' : ''}');
  }

  Future<void> _pay(OrderModel order) async {
    final notifier = ref.read(midtransProvider(order.id).notifier);
    await notifier.pay(
      order: order,
      branchId: order.branchId,
      onStatusConfirmed: (status) {
        if (!mounted) return;
        switch (status) {
          case MidtransPaymentStatus.paid:
            _showSuccessSheet(order);
            break;
          case MidtransPaymentStatus.failed:
            _showSnack(
              'Payment failed. You can try again, or ask a staff member for help.',
              isError: true,
            );
            break;
          case MidtransPaymentStatus.pending:
            _showPendingSheet(order);
            break;
          case MidtransPaymentStatus.cancelled:
            _showSnack('Payment window closed — nothing was charged. You can try again anytime.');
            break;
          case MidtransPaymentStatus.refunded:
          case MidtransPaymentStatus.unknown:
            _showSnack('Could not confirm the payment result. Please check status again.', isError: true);
            break;
        }
      },
    );
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(fontFamily: 'Poppins')),
      backgroundColor: isError ? Colors.red.shade600 : Colors.orange.shade700,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
    ));
  }

  void _showSuccessSheet(OrderModel order) {
    final overtimeCharge = order.overtimeCharge.toDouble();
    // The raw Midtrans payment_type from the Snap result, e.g. 'gopay',
    // 'bca_va' — same values MidtransPaymentMethod.label() (also used by
    // the staff cashier PDF receipt) already knows how to format.
    final paymentType = ref.read(midtransProvider(order.id)).result?.paymentType;
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PaySuccessSheet(
        order: order,
        overtimeCharge: overtimeCharge,
        total: order.totalAmount + overtimeCharge,
        paidAt: DateTime.now(),
        paymentMethodLabel: paymentType != null && paymentType.isNotEmpty
            ? MidtransPaymentMethod.label(paymentType)
            : 'Midtrans',
        onDone: () {
          Navigator.pop(context);
          ref.read(midtransProvider(order.id).notifier).reset();
          _goToTracker(order);
        },
      ),
    );
  }

  void _showPendingSheet(OrderModel order) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PayPendingSheet(
        order: order,
        onCheckStatus: () async {
          Navigator.pop(context);
          await ref.read(midtransProvider(order.id).notifier).checkStatus(order.id);
          if (!mounted) return;
          final status = ref.read(midtransProvider(order.id)).confirmedStatus;
          if (status == MidtransPaymentStatus.paid) {
            _showSuccessSheet(order);
          } else {
            _showSnack('Still awaiting confirmation. This is normal for VA transfer or QRIS — try again shortly.');
          }
        },
        onDone: () {
          Navigator.pop(context);
          ref.read(midtransProvider(order.id).notifier).reset();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(_payOrderProvider(widget.orderId));
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Pay Now', style: TextStyle(fontFamily: 'Poppins')),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: orderAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.wifi_off_outlined, size: 48),
              const SizedBox(height: 12),
              Text('Failed to load order: $e', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => ref.invalidate(_payOrderProvider(widget.orderId)),
                child: const Text('Try Again'),
              ),
            ]),
          ),
        ),
        data: (order) {
          // Already settled (e.g. the cashier processed it, or the customer
          // paid from another device already) — never show a Pay button for
          // a paid order, so it's structurally impossible to double-charge
          // from this screen.
          if (order.status == OrderStatus.paid) {
            return _AlreadyPaidView(
              order: order,
              onDone: () => _goToTracker(order),
            );
          }

          final state = ref.watch(midtransProvider(order.id));

          // Surface token-creation failures explicitly — createSnapToken()
          // can fail (network, amount mismatch, order already paid
          // elsewhere, missing branch, etc.) BEFORE the Snap UI ever opens.
          // That specific failure (step: creatingToken → idle) never reaches
          // onStatusConfirmed() in _pay(), so without this listener it would
          // be silent: the loading overlay just disappears and the customer
          // is left wondering whether anything happened.
          ref.listen<MidtransState>(midtransProvider(order.id), (previous, next) {
            if (previous?.step == MidtransFlowStep.creatingToken &&
                next.step == MidtransFlowStep.idle &&
                next.errorMessage != null) {
              _showSnack(next.errorMessage!, isError: true);
              // The order may already be paid (e.g. the cashier just
              // processed it) — refresh so _AlreadyPaidView takes over
              // instead of leaving a stale Pay button on screen.
              ref.invalidate(_payOrderProvider(order.id));
            }
          });

          final overtimeCharge = order.overtimeCharge.toDouble();
          final total = order.totalAmount + overtimeCharge;

          return Stack(children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Order #${order.orderNumber}',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  _BreakdownCard(order: order, overtimeCharge: overtimeCharge, total: total),
                  const SizedBox(height: 16),
                  _InfoBox(cs: cs),
                  const SizedBox(height: 90),
                ],
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
                decoration: BoxDecoration(
                  color: cs.surface,
                  border: Border(top: BorderSide(color: cs.outlineVariant, width: 0.5)),
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: state.isLoading ? null : () => _pay(order),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: state.isLoading
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.payment_rounded, size: 20),
                              const SizedBox(width: 8),
                              Text('Pay ${_fmtRp(total)}',
                                  style: const TextStyle(
                                      fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
                            ],
                          ),
                  ),
                ),
              ),
            ),
            if (state.isLoading)
              Positioned.fill(
                child: _LoadingOverlay(
                  state: state,
                  onCancel: () => ref.read(midtransProvider(order.id).notifier).reset(),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

// ─── Breakdown Card ───────────────────────────────────────────────────────────
class _BreakdownCard extends StatelessWidget {
  final OrderModel order;
  final double overtimeCharge;
  final double total;

  const _BreakdownCard({required this.order, required this.overtimeCharge, required this.total});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${order.items.length} item${order.items.length == 1 ? '' : 's'}',
              style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          ...order.items.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Expanded(
                    child: Text('${item.quantity}× ${item.menuItemName}',
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
                  ),
                  Text(_fmtRp(item.subtotal),
                      style: const TextStyle(
                          fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600)),
                ]),
              )),
          const Divider(height: 20, thickness: 0.5),
          // Same row labels & order as the staff cashier PDF receipt
          // (receipt_service.dart _totalRow calls) so the bill reads
          // identically whether it's self-paid here or printed at the till.
          _row(cs, 'Subtotal', order.subtotal),
          _row(cs, 'PB1 (10%)', order.pb1Amount),
          _row(cs, 'Service (3%)', order.serviceChargeAmount),
          if (order.discountAmount > 0) _row(cs, 'Discount', -order.discountAmount, isDiscount: true),
          if (overtimeCharge > 0) _row(cs, 'Extra Dining Time', overtimeCharge),
          const Divider(height: 20, thickness: 0.5),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Total',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w800)),
            Text(_fmtRp(total),
                style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w800, color: cs.primary)),
          ]),
        ],
      ),
    );
  }

  Widget _row(ColorScheme cs, String label, double amount, {bool isDiscount = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: cs.onSurfaceVariant)),
        Text(
          isDiscount ? '- ${_fmtRp(amount.abs())}' : _fmtRp(amount),
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDiscount ? Colors.green.shade700 : cs.onSurface,
          ),
        ),
      ]),
    );
  }
}

// ─── Info Box ─────────────────────────────────────────────────────────────────
class _InfoBox extends StatelessWidget {
  final ColorScheme cs;
  const _InfoBox({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Icon(Icons.shield_outlined, size: 18, color: cs.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Secure payment via Midtrans — card, GoPay, ShopeePay, QRIS, or Virtual '
            'Account. Once confirmed, this order is marked paid instantly for staff too.',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: cs.onSurfaceVariant, height: 1.4),
          ),
        ),
      ]),
    );
  }
}

// ─── Loading / Polling Overlay ────────────────────────────────────────────────
class _LoadingOverlay extends StatelessWidget {
  final MidtransState state;
  final VoidCallback onCancel;
  const _LoadingOverlay({required this.state, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final (icon, title, subtitle) = switch (state.step) {
      MidtransFlowStep.creatingToken => (
          Icons.lock_clock_outlined,
          'Preparing payment...',
          'Connecting to Midtrans',
        ),
      MidtransFlowStep.polling => (
          Icons.sync_rounded,
          'Checking payment status...',
          'Please wait (${state.pollingAttempt}/${state.maxPollingAttempts})',
        ),
      _ => (Icons.hourglass_top, 'Processing...', ''),
    };

    return Container(
      color: Colors.black.withValues(alpha: 0.45),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 24)],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (state.step == MidtransFlowStep.polling)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: LinearProgressIndicator(
                  value: state.pollingProgress > 0 ? state.pollingProgress : null,
                  borderRadius: BorderRadius.circular(4),
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            Icon(icon, size: 36, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(title,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(subtitle,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 12), textAlign: TextAlign.center),
            ],
            // Only the polling step is cancellable from here — a token has
            // already been created by then. Closing this overlay only stops
            // this screen from watching/polling; it does NOT cancel the
            // transaction on Midtrans's side, so a customer who already
            // completed payment on the Snap page is unaffected — the webhook
            // still lands and the tracker screen will reflect it regardless.
            if (state.step == MidtransFlowStep.polling) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: onCancel,
                child: const Text('Close',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

// ─── Success Sheet ────────────────────────────────────────────────────────────
// Shows the full itemized receipt right here, immediately after payment —
// the whole point of self-service Pay Now is that the customer shouldn't
// have to flag down staff and ask for a bill afterward.
class _PaySuccessSheet extends StatelessWidget {
  final OrderModel order;
  final double overtimeCharge;
  final double total;
  final DateTime paidAt;
  final String paymentMethodLabel;
  final VoidCallback onDone;
  const _PaySuccessSheet({
    required this.order,
    required this.overtimeCharge,
    required this.total,
    required this.paidAt,
    required this.paymentMethodLabel,
    required this.onDone,
  });

  String _fmtDateTime(DateTime dt) {
    final local = dt.toLocal();
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '${local.day} ${months[local.month]} ${local.year}, $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: const Icon(Icons.check_circle_rounded, size: 44, color: Colors.green),
          ),
          const SizedBox(height: 14),
          const Text('Payment Successful!',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Thank you for dining with us — here is your receipt.',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.grey.shade600),
              textAlign: TextAlign.center),
          const SizedBox(height: 20),
          // ── Receipt ────────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outlineVariant, width: 0.8),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Order #${order.orderNumber}',
                    style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                  child: const Text('PAID',
                      style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w800, color: Colors.green)),
                ),
              ]),
              const SizedBox(height: 2),
              Text('Paid via $paymentMethodLabel · ${_fmtDateTime(paidAt)}',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: cs.onSurfaceVariant)),
            ]),
          ),
          const SizedBox(height: 12),
          _BreakdownCard(order: order, overtimeCharge: overtimeCharge, total: total),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onDone,
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                minimumSize: const Size(0, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Done', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Pending Sheet ────────────────────────────────────────────────────────────
class _PayPendingSheet extends StatelessWidget {
  final OrderModel order;
  final VoidCallback onCheckStatus;
  final VoidCallback onDone;
  const _PayPendingSheet({required this.order, required this.onCheckStatus, required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 36, height: 4,
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
        ),
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(color: const Color(0xFFD97706).withValues(alpha: 0.1), shape: BoxShape.circle),
          child: const Icon(Icons.hourglass_top_rounded, size: 40, color: Color(0xFFD97706)),
        ),
        const SizedBox(height: 16),
        const Text('Awaiting Payment Confirmation',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
          'Order #${order.orderNumber} is awaiting payment confirmation. This is normal '
          'for VA transfer or QRIS — it can take a minute.',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Colors.grey.shade600, height: 1.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Check Payment Status',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
            onPressed: onCheckStatus,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              minimumSize: const Size(0, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: onDone,
          child: const Text('Close (check later on the tracker)',
              style: TextStyle(fontFamily: 'Poppins')),
        ),
      ]),
    );
  }
}

// ─── Already Paid View ─────────────────────────────────────────────────────────
class _AlreadyPaidView extends StatelessWidget {
  final OrderModel order;
  final VoidCallback onDone;
  const _AlreadyPaidView({required this.order, required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: const Icon(Icons.check_circle_rounded, size: 52, color: Colors.green),
          ),
          const SizedBox(height: 16),
          const Text('This order is already paid',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(
            'Order #${order.orderNumber} was already settled — no need to pay again.',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: onDone,
            child: const Text('View Order Status', style: TextStyle(fontFamily: 'Poppins')),
          ),
        ]),
      ),
    );
  }
}
