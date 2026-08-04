// lib/features/customer/presentation/customer_pay_now_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Mandatory payment step for the customer app, shown right after an order is
// placed and before the order tracker. Moving payment ahead of the tracker
// means the kitchen isn't left holding an order the customer may abandon
// mid-process — the same Midtrans flow the QR self-service screen already
// uses (same state machine, same webhook), just without a tableId.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/order_model.dart';
import '../../payment/midtrans/midtrans_provider.dart';
import '../../payment/models/midtrans_model.dart' show MidtransPaymentStatus, MidtransPaymentMethod;

// autoDispose: never serve a stale cached order across visits to this screen
// (e.g. browser back button after the order was already paid elsewhere).
//
// Reassembled from get_order_by_id + get_order_items + a plain
// restaurant_tables select (table_number is public-readable by design,
// unaffected by this lockdown) into the same shape OrderModel.fromJson
// expects, instead of one direct nested SELECT on `orders` — see
// supabase/migrations/20260805050000_full_order_pii_lockdown.sql.
// get_order_by_id legitimately includes customer_phone/customer_email,
// which Midtrans needs.
final _payOrderProvider = FutureProvider.autoDispose.family<OrderModel, String>(
  (ref, orderId) async {
    final client = Supabase.instance.client;
    final rows = await client.rpc('get_order_by_id', params: {
      'p_order_id': orderId,
    }) as List<dynamic>;
    if (rows.isEmpty) throw Exception('Order not found');
    final order = rows.first as Map<String, dynamic>;

    final items = await client.rpc('get_order_items', params: {
      'p_order_id': orderId,
    }) as List<dynamic>;

    Map<String, dynamic>? table;
    final tableId = order['table_id'] as String?;
    if (tableId != null) {
      table = await client
          .from('restaurant_tables')
          .select('table_number')
          .eq('id', tableId)
          .maybeSingle();
    }

    return OrderModel.fromJson({
      ...order,
      'restaurant_tables': table,
      'order_items': items,
    });
  },
);

String _fmtRp(double amount) {
  final formatted = amount
      .toStringAsFixed(0)
      .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
  return 'Rp $formatted';
}

class CustomerPayNowScreen extends ConsumerStatefulWidget {
  final String orderId;
  const CustomerPayNowScreen({super.key, required this.orderId});

  @override
  ConsumerState<CustomerPayNowScreen> createState() => _CustomerPayNowScreenState();
}

class _CustomerPayNowScreenState extends ConsumerState<CustomerPayNowScreen> {
  void _goToTracker(OrderModel order) {
    context.go('/customer/order-success/${order.orderNumber}');
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
        total: order.totalAmount,
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
        title: const Text('Payment', style: TextStyle(fontFamily: 'Poppins')),
        automaticallyImplyLeading: false,
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
          // Already settled (e.g. paid on another device, or by staff) — never
          // show a Pay button for a paid order, so double-charging from here
          // is structurally impossible. Checks paymentStatus, not status —
          // pay-up-front orders never get status set to OrderStatus.paid at
          // all (see supabase/functions/midtrans-webhook/index.ts), so status
          // alone would never catch an already-paid order here.
          if (order.isPaid) {
            return _AlreadyPaidView(
              order: order,
              onDone: () => _goToTracker(order),
            );
          }

          final state = ref.watch(midtransProvider(order.id));

          // Surface token-creation failures explicitly — createSnapToken() can
          // fail (network, amount mismatch, missing branch, etc.) before the
          // Snap UI ever opens, which never reaches onStatusConfirmed() above.
          ref.listen<MidtransState>(midtransProvider(order.id), (previous, next) {
            if (previous?.step == MidtransFlowStep.creatingToken &&
                next.step == MidtransFlowStep.idle &&
                next.errorMessage != null) {
              _showSnack(next.errorMessage!, isError: true);
              ref.invalidate(_payOrderProvider(order.id));
            }
          });

          final total = order.totalAmount;

          return Stack(children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Order #${order.orderNumber}',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    'One last step — pay now to confirm your order with the kitchen.',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  _BreakdownCard(order: order, total: total),
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
  final double total;

  const _BreakdownCard({required this.order, required this.total});

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
          _row(cs, 'Subtotal', order.subtotal),
          _row(cs, 'PB1 (10%)', order.pb1Amount),
          _row(cs, 'Service (3%)', order.serviceChargeAmount),
          if (order.discountAmount > 0) _row(cs, 'Discount', -order.discountAmount, isDiscount: true),
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
            'Account. Once confirmed, your order is sent to the kitchen.',
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
class _PaySuccessSheet extends StatelessWidget {
  final OrderModel order;
  final double total;
  final DateTime paidAt;
  final String paymentMethodLabel;
  final VoidCallback onDone;
  const _PaySuccessSheet({
    required this.order,
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
          Text('Thank you — your order is on its way to the kitchen.',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.grey.shade600),
              textAlign: TextAlign.center),
          const SizedBox(height: 20),
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
          _BreakdownCard(order: order, total: total),
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
              child: const Text('Track My Order', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
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
          child: const Text('Close (check status later)',
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
