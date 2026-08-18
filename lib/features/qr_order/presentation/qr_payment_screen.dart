import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/qr_cart_provider.dart';
import '../data/qr_order_repository.dart';
import '../services/qr_device_id_service.dart';
import '../../../core/theme/app_theme.dart';

class QrPaymentScreen extends ConsumerStatefulWidget {
  final String tableId;
  const QrPaymentScreen({super.key, required this.tableId});

  @override
  ConsumerState<QrPaymentScreen> createState() => _QrPaymentScreenState();
}

class _QrPaymentScreenState extends ConsumerState<QrPaymentScreen> {
  QrPaymentMethod _selected = QrPaymentMethod.kasir;
  bool _isSubmitting = false;
  String _orderNotes = ''; // ✅ FIX: state for notes

  Future<void> _submitOrder() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    final notifier = ref.read(activeQrCartNotifierProvider);
    notifier.setPaymentMethod(_selected);

    final cart = ref.read(activeQrCartProvider);
    final branchId = cart.branchId.trim();

    if (branchId.isEmpty) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Branch ID not found. Please rescan the table QR code.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final repo = ref.read(qrOrderRepositoryProvider);

    try {
      // ✅ FIX: send notes to createOrder
      final deviceId = await QrDeviceIdService.getDeviceId();
      final order = await repo.createOrder(
        session: cart,
        branchId: branchId,
        notes: _orderNotes.trim().isEmpty ? null : _orderNotes.trim(),
        deviceId: deviceId,
      );

      if (_selected == QrPaymentMethod.qris) {
        await Supabase.instance.client.from('orders').update({
          'payment_method': 'qris',
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', order.id);
      }

      notifier.clearCart();

      if (mounted) {
        if (_selected == QrPaymentMethod.qris) {
          context.push('/qr/${widget.tableId}/payment/qris', extra: {
            'orderId': order.id,
            'queueNumber': order.queueNumber,
            'totalAmount': cart.totalAmount,
            'tableId': widget.tableId,
          });
        } else {
          // ✅ NEW FLOW: go straight to the tracker, pay after dining
          context.go('/qr/${widget.tableId}/track/${order.id}?queue=${order.queueNumber}');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Order #${order.queueNumber} sent to the kitchen! Pay at the cashier after dining.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create order: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(activeQrCartProvider);
    final tableName = cart.tableName ?? widget.tableId;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _PaymentHeader(tableName: tableName, onBack: () => context.pop()),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                          ),
                          child: Text(
                            'PAYMENT FOR $tableName'.toUpperCase(),
                            style: const TextStyle(fontFamily: 'Poppins', fontSize: 12.5,
                                fontWeight: FontWeight.w800, color: AppColors.accent,
                                letterSpacing: 0.6),
                          ),
                        ),
                      ),
                    ),
                  ),

                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                      child: _OrderPreviewCard(cart: cart),
                    ),
                  ),

                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Select Payment Method',
                              style: TextStyle(fontFamily: 'Poppins', fontSize: 19,
                                  fontWeight: FontWeight.w800, color: AppColors.accent)),
                          const SizedBox(height: 14),
                          _PaymentMethodCard(
                            method: QrPaymentMethod.kasir,
                            selected: _selected,
                            title: 'Pay at Cashier',
                            subtitle: 'Pay with cash or card at the cashier',
                            icon: Icons.point_of_sale_outlined,
                            badge: 'Recommended',
                            onTap: () => setState(() => _selected = QrPaymentMethod.kasir),
                          ),
                          const SizedBox(height: 12),
                          _PaymentMethodCard(
                            method: QrPaymentMethod.qris,
                            selected: _selected,
                            title: 'QRIS / E-Wallet',
                            subtitle: 'Scan the QR code for digital payment',
                            icon: Icons.qr_code_scanner_outlined,
                            onTap: () => setState(() => _selected = QrPaymentMethod.qris),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (_selected == QrPaymentMethod.qris)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                        child: _QrisInfoCard(totalAmount: cart.totalAmount),
                      ),
                    ),

                  // ✅ FIX: connect onChanged to _orderNotes
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                      child: _NotesSection(
                        onChanged: (val) => setState(() => _orderNotes = val),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _PaymentBottomBar(
              method: _selected,
              isLoading: _isSubmitting,
              onConfirm: _submitOrder,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Header ─────────────────────────────────────────────────────────────────
class _PaymentHeader extends StatelessWidget {
  final String tableName;
  final VoidCallback onBack;
  const _PaymentHeader({required this.tableName, required this.onBack});

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
                  fontWeight: FontWeight.w700, color: AppColors.primary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

// ─── Order Preview Card ───────────────────────────────────────────────────────
class _OrderPreviewCard extends StatelessWidget {
  final QrOrderSession cart;
  const _OrderPreviewCard({required this.cart});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 4, color: AppColors.textPrimary),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Order Summary',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 19,
                        fontWeight: FontWeight.w800, color: AppColors.accent)),
                const SizedBox(height: 4),
                Text(
                  '${cart.tableName ?? "Table"} · ${cart.customerName ?? "Guest"}',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                      color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                Divider(color: AppColors.border, height: 1),
                const SizedBox(height: 12),

                ...cart.items.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.menuItem.name,
                                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 14.5,
                                      fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                                ),
                                const SizedBox(height: 2),
                                Text('x${item.quantity}',
                                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 12.5,
                                        color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                          Text(_formatPrice(item.subtotal),
                              style: const TextStyle(fontFamily: 'Poppins', fontSize: 14.5,
                                  fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                        ],
                      ),
                    )),

                Divider(color: AppColors.border, height: 1),
                const SizedBox(height: 12),

                _summaryRow('SUBTOTAL', _formatPrice(cart.subtotal)),
                const SizedBox(height: 8),
                _summaryRow('TAX & SERVICE (11%)', _formatPrice(cart.taxAmount)),

                const SizedBox(height: 14),
                Divider(color: AppColors.border, height: 1),
                const SizedBox(height: 14),

                Row(
                  children: [
                    const Text('Total',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 18,
                            fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                    const Spacer(),
                    Text(
                      _formatPrice(cart.totalAmount),
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 22,
                          fontWeight: FontWeight.w800, color: AppColors.primary),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Row(
      children: [
        Text(label,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
                fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 0.4)),
        const Spacer(),
        Text(value,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
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

// ─── Payment Method Card ──────────────────────────────────────────────────────
class _PaymentMethodCard extends StatelessWidget {
  final QrPaymentMethod method;
  final QrPaymentMethod selected;
  final String title;
  final String subtitle;
  final IconData icon;
  final String? badge;
  final VoidCallback onTap;

  const _PaymentMethodCard({
    required this.method,
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = method == selected;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(
            color: isSelected ? AppColors.accent : AppColors.border,
            width: isSelected ? 1.6 : 1,
          ),
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 42, height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.accent.withValues(alpha: 0.12)
                    : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Icon(
                icon,
                size: 20,
                color: isSelected ? AppColors.accent : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title,
                          style: const TextStyle(fontFamily: 'Poppins', fontSize: 14.5,
                              fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      if (badge != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            badge!,
                            style: const TextStyle(fontFamily: 'Poppins', fontSize: 10,
                                fontWeight: FontWeight.w700, color: AppColors.primary),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                          color: AppColors.textSecondary)),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppColors.accent : AppColors.border,
                  width: 2,
                ),
                color: Colors.transparent,
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 11, height: 11,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle, color: AppColors.accent),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── QRIS Info Card ───────────────────────────────────────────────────────────
class _QrisInfoCard extends StatelessWidget {
  final double totalAmount;
  const _QrisInfoCard({required this.totalAmount});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              const Text(
                'How to Pay with QRIS',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                    color: AppColors.primary, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const _QrisStep(number: '1', text: 'Tap the "Confirm Payment" button below'),
          const _QrisStep(number: '2', text: 'Show your queue number to the cashier'),
          const _QrisStep(number: '3', text: 'The cashier will display the QRIS code'),
          const _QrisStep(number: '4', text: 'Scan the QR code with your digital wallet app'),
          const _QrisStep(
              number: '5',
              text: 'The order is processed automatically once the cashier confirms payment'),
        ],
      ),
    );
  }
}

class _QrisStep extends StatelessWidget {
  final String number;
  final String text;
  const _QrisStep({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Notes Section ────────────────────────────────────────────────────────────
class _NotesSection extends StatelessWidget {
  final ValueChanged<String>? onChanged;
  const _NotesSection({this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_note_outlined, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text(
                'Notes (Optional)',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 15,
                    fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: onChanged,
            maxLines: 3,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13.5, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Example: not spicy, nut allergy, etc...',
              hintStyle: const TextStyle(fontFamily: 'Poppins', color: AppColors.textHint, fontSize: 13),
              filled: true,
              fillColor: AppColors.surfaceVariant,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Payment Bottom Bar ───────────────────────────────────────────────────────
class _PaymentBottomBar extends StatelessWidget {
  final QrPaymentMethod method;
  final bool isLoading;
  final VoidCallback onConfirm;

  const _PaymentBottomBar({
    required this.method,
    required this.isLoading,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: const Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton(
          onPressed: isLoading ? null : onConfirm,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.accent.withValues(alpha: 0.6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
            elevation: 0,
          ),
          child: isLoading
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    ),
                    SizedBox(width: 10),
                    Text('Processing...',
                        style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      method == QrPaymentMethod.qris
                          ? 'Confirm & Pay with QRIS'
                          : 'Confirm Payment',
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 15.5,
                          fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_rounded, size: 19, color: Colors.white),
                  ],
                ),
        ),
      ),
    );
  }
}

// ─── QRIS Dynamic Screen ──────────────────────────────────────────────────────
class QrQrisScreen extends StatelessWidget {
  final String tableId;
  final String orderId;
  final double totalAmount;

  const QrQrisScreen({
    super.key,
    required this.tableId,
    required this.orderId,
    required this.totalAmount,
  });

  @override
  Widget build(BuildContext context) {
    final String qrisData =
        "00020101021126670016ID.CO.BANKMANDIRI01189360001100000000000215200000000000000303IDR0109${totalAmount.toInt()}5200000115300036058202ID5915Restoran A1 Kartika6007Jakarta6105123456304XXXX";

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: const Text('Pay with QRIS',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  const Text('Total amount due',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 15, color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  Text(
                    'Rp ${totalAmount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}',
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 34,
                        fontWeight: FontWeight.w800, color: AppColors.primary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                border: Border.all(color: AppColors.border),
              ),
              child: QrImageView(
                data: qrisData,
                version: QrVersions.auto,
                size: 260,
                gapless: false,
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Scan this QRIS code using your\nbank or e-wallet app',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 15, color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 32),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('How to Pay:',
                      style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w800,
                          fontSize: 14, color: AppColors.textPrimary)),
                  SizedBox(height: 10),
                  Text('1. Open your bank / e-wallet app',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textSecondary)),
                  Text('2. Select the Scan QR menu',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textSecondary)),
                  Text('3. Point your camera at the QR code above',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textSecondary)),
                  Text('4. The amount will appear automatically',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textSecondary)),
                  Text('5. Confirm the payment',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () => context.go('/qr/$tableId/track/$orderId'),
                icon: const Icon(Icons.receipt_long, color: Colors.white),
                label: const Text('View Order Status',
                    style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
