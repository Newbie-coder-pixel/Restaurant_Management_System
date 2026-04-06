import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/qr_cart_provider.dart';
import '../data/qr_order_repository.dart';

// Branch ID provider (set from tableInfo in menu screen via activeQrTableProvider)
final _activeBranchIdProvider = StateProvider<String>((ref) => '');

class QrPaymentScreen extends ConsumerStatefulWidget {
  final String tableId;

  const QrPaymentScreen({super.key, required this.tableId});

  @override
  ConsumerState<QrPaymentScreen> createState() => _QrPaymentScreenState();
}

class _QrPaymentScreenState extends ConsumerState<QrPaymentScreen> {
  QrPaymentMethod _selected = QrPaymentMethod.kasir;
  bool _isSubmitting = false;

  Future<void> _submitOrder() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    final notifier = ref.read(activeQrCartNotifierProvider);
    notifier.setPaymentMethod(_selected);

    // Re-read after update
    final updatedCart = ref.read(activeQrCartProvider);
    final branchId = ref.read(_activeBranchIdProvider);

    final repo = ref.read(qrOrderRepositoryProvider);

    try {
      final order = await repo.createOrder(
        session: updatedCart,
        branchId: branchId.isNotEmpty ? branchId : 'default',
      );

      // Clear cart after success
      notifier.clearCart();

      if (mounted) {
        // Navigate to tracker, remove all previous routes (can't go back to order)
        context.go('/qr/${widget.tableId}/track/${order.id}?queue=${order.queueNumber}');
      }
    } catch (e) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal membuat pesanan: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(activeQrCartProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Pembayaran'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: CustomScrollView(
        slivers: [
          // ── Order Preview ────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _OrderPreviewCard(cart: cart),
            ),
          ),

          // ── Payment Methods ──────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Metode Pembayaran',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _PaymentMethodCard(
                    method: QrPaymentMethod.kasir,
                    selected: _selected,
                    title: 'Bayar ke Kasir',
                    subtitle: 'Bayar tunai atau kartu di kasir',
                    icon: Icons.point_of_sale_outlined,
                    badge: 'Rekomendasi',
                    onTap: () =>
                        setState(() => _selected = QrPaymentMethod.kasir),
                  ),
                  const SizedBox(height: 10),
                  _PaymentMethodCard(
                    method: QrPaymentMethod.qris,
                    selected: _selected,
                    title: 'QRIS',
                    subtitle: 'Scan QR code untuk bayar digital',
                    icon: Icons.qr_code_scanner_outlined,
                    onTap: () =>
                        setState(() => _selected = QrPaymentMethod.qris),
                  ),
                ],
              ),
            ),
          ),

          // ── QRIS Info (conditional) ──────────────────────────────────────
          if (_selected == QrPaymentMethod.qris)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: _QrisInfoCard(totalAmount: cart.totalAmount),
              ),
            ),

          // ── Notes ────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
              child: _NotesSection(
                onChanged: (val) {
                  // notes for the whole order can be stored separately
                },
              ),
            ),
          ),
        ],
      ),

      // ── Bottom: Confirm Order ──────────────────────────────────────────────
      bottomNavigationBar: _PaymentBottomBar(
        cart: cart,
        method: _selected,
        isLoading: _isSubmitting,
        onConfirm: _submitOrder,
      ),
    );
  }
}

// ─── Order Preview ────────────────────────────────────────────────────────────

class _OrderPreviewCard extends StatelessWidget {
  final QrOrderSession cart;

  const _OrderPreviewCard({required this.cart});

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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.receipt_long_outlined,
                    color: colorScheme.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ringkasan Pesanan',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  Text(
                    '${cart.tableName ?? "Meja"} · ${cart.customerName ?? "Tamu"}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colorScheme.outline),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...cart.items.take(3).map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Text('${item.quantity}×',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(item.menuItem.name,
                            style: theme.textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis)),
                    Text(_formatPrice(item.subtotal),
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              )),
          if (cart.items.length > 3)
            Text(
              '+${cart.items.length - 3} item lainnya',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colorScheme.outline),
            ),
          Divider(
              color: colorScheme.outlineVariant, height: 20, thickness: 0.5),
          Row(
            children: [
              Text('Total',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              Text(
                _formatPrice(cart.totalAmount),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSelected = method == selected;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer.withValues(alpha: 0.5)
              : colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color:
                isSelected ? colorScheme.primary : colorScheme.outlineVariant,
            width: isSelected ? 2 : 0.8,
          ),
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 22,
                color: isSelected
                    ? colorScheme.onPrimary
                    : colorScheme.onSurfaceVariant,
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
                          style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.bold)),
                      if (badge != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            badge!,
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.green.shade700,
                                fontSize: 10),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colorScheme.outline)),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.outline,
                  width: 2,
                ),
                color: isSelected ? colorScheme.primary : Colors.transparent,
              ),
              child: isSelected
                  ? Icon(Icons.check,
                      size: 12, color: colorScheme.onPrimary)
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
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.blue.shade200, width: 0.8),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline,
                  size: 16, color: Colors.blue.shade700),
              const SizedBox(width: 6),
              Text(
                'Cara Bayar QRIS',
                style: theme.textTheme.labelMedium?.copyWith(
                    color: Colors.blue.shade700,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const _QrisStep(
              number: '1',
              text: 'Tekan tombol "Konfirmasi Pesanan" di bawah'),
          const _QrisStep(
              number: '2', text: 'Tunjukkan nomor antrian ke kasir'),
          const _QrisStep(number: '3', text: 'Kasir akan menampilkan QRIS'),
          const _QrisStep(
              number: '4',
              text: 'Scan QR dengan aplikasi dompet digitalmu'),
          const _QrisStep(
              number: '5',
              text:
                  'Order otomatis diproses setelah pembayaran dikonfirmasi kasir'),
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
            decoration: BoxDecoration(
              color: Colors.blue.shade600,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.blue.shade800,
                  ),
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant, width: 0.8),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_note_outlined,
                  size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text('Catatan (Opsional)',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: onChanged,
            maxLines: 3,
            decoration: InputDecoration(
              hintText:
                  'Contoh: tidak pedas, alergi kacang, dll...',
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
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
  final QrOrderSession cart;
  final QrPaymentMethod method;
  final bool isLoading;
  final VoidCallback onConfirm;

  const _PaymentBottomBar({
    required this.cart,
    required this.method,
    required this.isLoading,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
            top: BorderSide(color: colorScheme.outlineVariant, width: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text('Total Pembayaran',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: colorScheme.outline)),
              const Spacer(),
              Text(
                _formatPrice(cart.totalAmount),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: isLoading ? null : onConfirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                disabledBackgroundColor:
                    colorScheme.primary.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: isLoading
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: colorScheme.onPrimary,
                            strokeWidth: 2,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text('Memproses...',
                            style: theme.textTheme.labelLarge?.copyWith(
                                color: colorScheme.onPrimary)),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          method == QrPaymentMethod.qris
                              ? Icons.qr_code_scanner_outlined
                              : Icons.check_circle_outline,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          method == QrPaymentMethod.qris
                              ? 'Konfirmasi & Bayar QRIS'
                              : 'Konfirmasi Pesanan',
                          style: theme.textTheme.labelLarge?.copyWith(
                              color: colorScheme.onPrimary,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
            ),
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