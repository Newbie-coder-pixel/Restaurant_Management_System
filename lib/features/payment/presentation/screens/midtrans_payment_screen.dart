// lib/features/payment/presentation/screens/midtrans_payment_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Midtrans Payment Screen
// Menggantikan payment_panel_screen.dart yang manual.
// Tampilan: breakdown order → tombol "Bayar Sekarang" → buka Snap Midtrans
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../features/auth/providers/auth_provider.dart';
import '../../../../shared/models/order_model.dart';
import '../../midtrans/midtrans_provider.dart';
import '../../models/midtrans_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HELPER
// ─────────────────────────────────────────────────────────────────────────────

final _currency = NumberFormat.currency(
  locale: 'id_ID',
  symbol: 'Rp ',
  decimalDigits: 0,
);

String _fmtRp(double amount) => _currency.format(amount);

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class MidtransPaymentScreen extends ConsumerStatefulWidget {
  final OrderModel order;
  final VoidCallback? onPaymentSuccess;
  final VoidCallback? onClose;

  const MidtransPaymentScreen({
    super.key,
    required this.order,
    this.onPaymentSuccess,
    this.onClose,
  });

  @override
  ConsumerState<MidtransPaymentScreen> createState() =>
      _MidtransPaymentScreenState();
}

class _MidtransPaymentScreenState extends ConsumerState<MidtransPaymentScreen> {
  String? _branchId;

  // Kalkulasi breakdown
  double get _subtotal => widget.order.subtotal;
  double get _serviceCharge => _subtotal * 0.03;
  double get _pb1 => (_subtotal + _serviceCharge) * 0.10;
  double get _discount => widget.order.discountAmount;
  double get _total => _subtotal + _serviceCharge + _pb1 - _discount;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final staff = ref.read(currentStaffProvider);
      setState(() => _branchId = staff?.branchId);
    });
  }

  Future<void> _pay() async {
    if (_branchId == null) return;

    final notifier = ref.read(activeMidtransProvider.notifier);

    await notifier.pay(
      order: widget.order,
      branchId: _branchId!,
      onStatusConfirmed: (status) {
        if (!mounted) return;
        if (status == MidtransPaymentStatus.paid) {
          _showSuccessSheet();
        } else if (status == MidtransPaymentStatus.failed) {
          _showError('Pembayaran gagal. Silakan coba lagi.');
        } else if (status == MidtransPaymentStatus.pending) {
          _showPendingSheet();
        }
        // cancelled → tidak perlu tampil apa-apa, screen kembali normal
      },
    );
  }

  void _showSuccessSheet() {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _SuccessSheet(
        order: widget.order,
        total: _total,
        onPrint: _printReceipt,
        onDone: () {
          Navigator.pop(context);
          ref.read(activeMidtransProvider.notifier).reset();
          widget.onPaymentSuccess?.call();
        },
      ),
    );
  }

  void _showPendingSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PendingSheet(
        order: widget.order,
        onCheckStatus: () async {
          Navigator.pop(context);
          await ref
              .read(activeMidtransProvider.notifier)
              .checkStatus(widget.order.id);
          final status = ref.read(activeMidtransProvider).confirmedStatus;
          if (!mounted) return;
          if (status == MidtransPaymentStatus.paid) {
            _showSuccessSheet();
          }
        },
        onDone: () {
          Navigator.pop(context);
          ref.read(activeMidtransProvider.notifier).reset();
        },
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(fontFamily: 'Poppins')),
      backgroundColor: AppColors.accent,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _printReceipt() async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Mencetak struk...', style: TextStyle(fontFamily: 'Poppins')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(activeMidtransProvider);

    return Stack(children: [
      SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ─────────────────────────────────────────────────
            _OrderHeader(order: widget.order, onClose: widget.onClose),
            const SizedBox(height: 16),

            // ── Item list ──────────────────────────────────────────────
            _OrderItemsCard(order: widget.order),
            const SizedBox(height: 16),

            // ── Breakdown ──────────────────────────────────────────────
            const _SectionLabel('Rincian Pembayaran'),
            const SizedBox(height: 8),
            _BreakdownCard(
              subtotal: _subtotal,
              serviceCharge: _serviceCharge,
              pb1: _pb1,
              discount: _discount,
              total: _total,
            ),
            const SizedBox(height: 20),

            // ── Info Midtrans ──────────────────────────────────────────
            _MidtransInfoBox(),
            const SizedBox(height: 24),

            // ── Tombol Bayar ───────────────────────────────────────────
            _PayButton(
              total: _total,
              isLoading: state.isLoading,
              onPay: _pay,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),

      // ── Overlay loading + polling ──────────────────────────────────────
      if (state.isLoading)
        Positioned.fill(
          child: _LoadingOverlay(state: state),
        ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ORDER HEADER
// ─────────────────────────────────────────────────────────────────────────────

class _OrderHeader extends StatelessWidget {
  final OrderModel order;
  final VoidCallback? onClose;
  const _OrderHeader({required this.order, this.onClose});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('#${order.orderNumber}',
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const SizedBox(width: 8),
            _TypeBadge(order.orderType ?? 'staff'),
          ]),
          const SizedBox(height: 2),
          Row(children: [
            if (order.tableNumber != null) ...[
              const Icon(Icons.table_restaurant_outlined,
                  size: 13, color: AppColors.textHint),
              const SizedBox(width: 4),
              Text('Meja ${order.tableNumber}',
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: AppColors.textHint)),
              const SizedBox(width: 10),
            ],
            if (order.customerName != null) ...[
              const Icon(Icons.person_outline,
                  size: 13, color: AppColors.textHint),
              const SizedBox(width: 4),
              Text(order.customerName!,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: AppColors.textHint)),
            ],
          ]),
        ]),
      ),
      if (onClose != null)
        IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close, color: AppColors.textHint)),
    ]);
  }
}

class _TypeBadge extends StatelessWidget {
  final String type;
  const _TypeBadge(this.type);

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (type) {
      'qr_order' => ('QR', const Color(0xFF7C3AED)),
      'app_order' || 'takeaway' => ('App', const Color(0xFF2563EB)),
      _ => ('Staff', AppColors.primary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ORDER ITEMS CARD
// ─────────────────────────────────────────────────────────────────────────────

class _OrderItemsCard extends StatelessWidget {
  final OrderModel order;
  const _OrderItemsCard({required this.order});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${order.items.length} Item',
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        ...order.items.take(5).map((item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(
                  child: Text('${item.quantity}× ${item.menuItemName}',
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          color: AppColors.textPrimary)),
                ),
                Text(_fmtRp(item.subtotal),
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ]),
            )),
        if (order.items.length > 5)
          Text('+${order.items.length - 5} item lainnya',
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: AppColors.textHint,
                  fontStyle: FontStyle.italic)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BREAKDOWN CARD
// ─────────────────────────────────────────────────────────────────────────────

class _BreakdownCard extends StatelessWidget {
  final double subtotal, serviceCharge, pb1, discount, total;
  const _BreakdownCard({
    required this.subtotal,
    required this.serviceCharge,
    required this.pb1,
    required this.discount,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: [
        _Row('Subtotal', subtotal),
        _Row('Service Charge (3%)', serviceCharge),
        _Row('PB1 / Pajak (10%)', pb1),
        if (discount > 0) _Row('Diskon', -discount, isDiscount: true),
        const Divider(height: 16, color: AppColors.border),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('TOTAL',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            Text(_fmtRp(total),
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary)),
          ],
        ),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final double amount;
  final bool isDiscount;
  const _Row(this.label, this.amount, {this.isDiscount = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: AppColors.textSecondary)),
          Text(
            isDiscount ? '- ${_fmtRp(amount.abs())}' : _fmtRp(amount),
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDiscount ? AppColors.available : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MIDTRANS INFO BOX
// ─────────────────────────────────────────────────────────────────────────────

class _MidtransInfoBox extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Metode yang didukung lewat Midtrans
    const methods = [
      ('💳', 'Kartu Kredit/Debit'),
      ('📱', 'QRIS (GoPay, OVO, Dana, dll)'),
      ('🟢', 'GoPay'),
      ('🟠', 'ShopeePay'),
      ('🏦', 'Virtual Account (BCA, BNI, BRI, Mandiri)'),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Image.asset('assets/icons/midtrans.png',
              width: 80, errorBuilder: (_, __, ___) =>
                  const Text('Midtrans',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary))),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.available.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text('Aman & Terenkripsi',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.available)),
          ),
        ]),
        const SizedBox(height: 10),
        const Text('Metode pembayaran tersedia:',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: methods.map((m) => _MethodChip(m.$1, m.$2)).toList(),
        ),
      ]),
    );
  }
}

class _MethodChip extends StatelessWidget {
  final String emoji;
  final String label;
  const _MethodChip(this.emoji, this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Text('$emoji $label',
          style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              color: AppColors.textSecondary)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAY BUTTON
// ─────────────────────────────────────────────────────────────────────────────

class _PayButton extends StatelessWidget {
  final double total;
  final bool isLoading;
  final VoidCallback onPay;
  const _PayButton({required this.total, required this.isLoading, required this.onPay});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPay,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 2,
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.white),
              )
            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.payment_rounded, size: 20),
                const SizedBox(width: 10),
                Text('Bayar ${_fmtRp(total)}',
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LOADING OVERLAY
// ─────────────────────────────────────────────────────────────────────────────

class _LoadingOverlay extends StatelessWidget {
  final MidtransState state;
  const _LoadingOverlay({required this.state});

  @override
  Widget build(BuildContext context) {
    final (icon, title, subtitle) = switch (state.step) {
      MidtransFlowStep.creatingToken => (
          Icons.lock_clock_outlined,
          'Menyiapkan pembayaran...',
          'Menghubungkan ke Midtrans',
        ),
      MidtransFlowStep.polling => (
          Icons.sync_rounded,
          'Mengecek status pembayaran...',
          'Mohon tunggu (${state.pollingAttempt}/${state.maxPollingAttempts})',
        ),
      _ => (Icons.hourglass_top, 'Memproses...', ''),
    };

    return Container(
      color: Colors.black.withValues(alpha: 0.45),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15), blurRadius: 24)
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Animasi progress untuk polling
            if (state.step == MidtransFlowStep.polling)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: LinearProgressIndicator(
                  value: state.pollingProgress > 0 ? state.pollingProgress : null,
                  backgroundColor: AppColors.border,
                  valueColor:
                      const AlwaysStoppedAnimation(AppColors.primary),
                  borderRadius: BorderRadius.circular(4),
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation(AppColors.primary),
                    strokeWidth: 3),
              ),
            Icon(icon, size: 36, color: AppColors.primary),
            const SizedBox(height: 12),
            Text(title,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary),
                textAlign: TextAlign.center),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(subtitle,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: AppColors.textSecondary),
                  textAlign: TextAlign.center),
            ],
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SUCCESS BOTTOM SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _SuccessSheet extends StatelessWidget {
  final OrderModel order;
  final double total;
  final VoidCallback? onPrint;
  final VoidCallback onDone;
  const _SuccessSheet({
    required this.order,
    required this.total,
    this.onPrint,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle bar
        Container(
          width: 36, height: 4,
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
              color: AppColors.border, borderRadius: BorderRadius.circular(2)),
        ),
        // Checkmark animation
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: AppColors.available.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_circle_rounded,
              size: 52, color: AppColors.available),
        ),
        const SizedBox(height: 16),
        const Text('Pembayaran Berhasil!',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        Text('Order #${order.orderNumber}',
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        Text(_fmtRp(total),
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppColors.primary)),
        const SizedBox(height: 24),
        Row(children: [
          if (onPrint != null)
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: const Text('Struk',
                    style: TextStyle(
                        fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
                onPressed: onPrint,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  minimumSize: const Size(0, 50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          if (onPrint != null) const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: onDone,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Selesai',
                  style: TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PENDING BOTTOM SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _PendingSheet extends StatelessWidget {
  final OrderModel order;
  final VoidCallback onCheckStatus;
  final VoidCallback onDone;
  const _PendingSheet({
    required this.order,
    required this.onCheckStatus,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 36, height: 4,
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
              color: AppColors.border, borderRadius: BorderRadius.circular(2)),
        ),
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFFD97706).withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.hourglass_top_rounded,
              size: 40, color: Color(0xFFD97706)),
        ),
        const SizedBox(height: 16),
        const Text('Menunggu Pembayaran',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        Text(
          'Order #${order.orderNumber} sedang menunggu konfirmasi pembayaran. '
          'Ini biasa terjadi untuk transfer VA atau QRIS.',
          style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Cek Status Pembayaran',
                style:
                    TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
            onPressed: onCheckStatus,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 50),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: onDone,
          child: const Text('Tutup (cek nanti)',
              style: TextStyle(
                  fontFamily: 'Poppins', color: AppColors.textSecondary)),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION LABEL
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary));
  }
}