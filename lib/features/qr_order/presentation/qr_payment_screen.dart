import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/qr_cart_provider.dart';
import '../data/qr_order_repository.dart';

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

    final cart = ref.read(activeQrCartProvider);
    final branchId = cart.branchId.trim();

    if (branchId.isEmpty) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Branch ID tidak ditemukan. Silakan scan ulang QR meja.'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    final repo = ref.read(qrOrderRepositoryProvider);

    try {
      final order = await repo.createOrder(session: cart, branchId: branchId);

      // Untuk QRIS: update payment_method saja, status tetap 'created' sampai kasir konfirmasi
      // Untuk Kasir: tidak ada update — order tetap 'created', kasir yang akan memproses pembayaran
      if (_selected == QrPaymentMethod.qris) {
        await Supabase.instance.client.from('orders').update({
          'payment_method': 'qris',
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', order.id);
      }
      // Kasir: payment_method sudah di-set saat createOrder ('kasir'), tidak perlu update

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
          // Bayar ke Kasir → ke Tracker, status masih 'created' (menunggu kasir)
          context.go('/qr/${widget.tableId}/track/${order.id}?queue=${order.queueNumber}');

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Pesanan #${order.queueNumber} berhasil dibuat. Silakan bayar ke kasir.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membuat pesanan: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _OrderPreviewCard(cart: cart),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Metode Pembayaran',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _PaymentMethodCard(
                    method: QrPaymentMethod.kasir,
                    selected: _selected,
                    title: 'Bayar ke Kasir',
                    subtitle: 'Bayar tunai atau kartu di kasir',
                    icon: Icons.point_of_sale_outlined,
                    badge: 'Rekomendasi',
                    onTap: () => setState(() => _selected = QrPaymentMethod.kasir),
                  ),
                  const SizedBox(height: 10),
                  _PaymentMethodCard(
                    method: QrPaymentMethod.qris,
                    selected: _selected,
                    title: 'QRIS',
                    subtitle: 'Scan QR code untuk bayar digital',
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
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: _QrisInfoCard(totalAmount: cart.totalAmount),
              ),
            ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
              child: _NotesSection(onChanged: (val) {}),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _PaymentBottomBar(
        cart: cart,
        method: _selected,
        isLoading: _isSubmitting,
        onConfirm: _submitOrder,
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
                    color: colorScheme.primaryContainer, borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.receipt_long_outlined, color: colorScheme.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ringkasan Pesanan',
                      style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
                  Text('${cart.tableName ?? "Meja"} · ${cart.customerName ?? "Tamu"}',
                      style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline)),
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
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: colorScheme.primary, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(item.menuItem.name,
                            style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis)),
                    Text(_formatPrice(item.subtotal), style: theme.textTheme.bodySmall),
                  ],
                ),
              )),

          if (cart.items.length > 3)
            Text('+${cart.items.length - 3} item lainnya',
                style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline)),

          const Divider(height: 24, thickness: 0.5),

          Row(
            children: [
              Text('Subtotal', style: theme.textTheme.bodyMedium),
              const Spacer(),
              Text(_formatPrice(cart.subtotal), style: theme.textTheme.bodyMedium),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text('PPN (11%)', style: theme.textTheme.bodyMedium),
              const Spacer(),
              Text(_formatPrice(cart.taxAmount), style: theme.textTheme.bodyMedium),
            ],
          ),
          const Divider(height: 20, thickness: 0.5),
          Row(
            children: [
              Text('Total', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              Text(_formatPrice(cart.totalAmount),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.primary)),
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
          color: isSelected ? colorScheme.primaryContainer.withValues(alpha: 0.5) : colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
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
                color: isSelected ? colorScheme.primary : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  size: 22,
                  color: isSelected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
                      if (badge != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration:
                              BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(4)),
                          child: Text(badge!,
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: Colors.green.shade700, fontSize: 10)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline)),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: isSelected ? colorScheme.primary : colorScheme.outline, width: 2),
                color: isSelected ? colorScheme.primary : Colors.transparent,
              ),
              child: isSelected ? Icon(Icons.check, size: 12, color: colorScheme.onPrimary) : null,
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
              Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
              const SizedBox(width: 6),
              Text('Cara Bayar QRIS',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: Colors.blue.shade700, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 10),
          const _QrisStep(number: '1', text: 'Tekan tombol "Konfirmasi Pesanan" di bawah'),
          const _QrisStep(number: '2', text: 'Tunjukkan nomor antrian ke kasir'),
          const _QrisStep(number: '3', text: 'Kasir akan menampilkan QRIS'),
          const _QrisStep(number: '4', text: 'Scan QR dengan aplikasi dompet digitalmu'),
          const _QrisStep(number: '5', text: 'Order otomatis diproses setelah pembayaran dikonfirmasi kasir'),
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
            decoration: BoxDecoration(color: Colors.blue.shade600, shape: BoxShape.circle),
            child: Center(
                child: Text(number,
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
          ),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.blue.shade800))),
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
              Icon(Icons.edit_note_outlined, size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text('Catatan (Opsional)',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: onChanged,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Contoh: tidak pedas, alergi kacang, dll...',
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
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
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant, width: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text('Total Pembayaran', style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.outline)),
              const Spacer(),
              Text(_formatPrice(cart.totalAmount),
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.primary)),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: isLoading
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                        SizedBox(width: 10),
                        Text('Memproses...'),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                            method == QrPaymentMethod.qris
                                ? Icons.qr_code_scanner_outlined
                                : Icons.check_circle_outline,
                            size: 20),
                        const SizedBox(width: 8),
                        Text(
                          method == QrPaymentMethod.qris ? 'Konfirmasi & Bayar QRIS' : 'Konfirmasi Pesanan',
                          style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
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
        .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
    return 'Rp $formatted';
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
    // Data QRIS sederhana (sesuaikan dengan format QRIS yang benar jika diperlukan)
    final String qrisData =
        "00020101021126670016ID.CO.BANKMANDIRI01189360001100000000000215200000000000000303IDR0109${totalAmount.toInt()}5200000115300036058202ID5915Restoran A1 Kartika6007Jakarta6105123456304XXXX";

    return Scaffold(
      appBar: AppBar(title: const Text('Bayar dengan QRIS')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 20),
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Text('Total yang harus dibayar', style: TextStyle(fontSize: 16)),
                    const SizedBox(height: 8),
                    Text(
                      'Rp ${totalAmount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}',
                      style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 40),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 15)],
              ),
              child: QrImageView(               // ← Sudah diperbaiki
                data: qrisData,
                version: QrVersions.auto,       // ← Sudah diperbaiki
                size: 280,
                gapless: false,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Scan QRIS ini menggunakan aplikasi\nbank atau e-wallet kamu',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, height: 1.4),
            ),
            const SizedBox(height: 40),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(16)),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cara Membayar:', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 12),
                  Text('1. Buka aplikasi bank / dompet digital'),
                  Text('2. Pilih menu Scan QR'),
                  Text('3. Arahkan kamera ke QR code di atas'),
                  Text('4. Nominal akan muncul otomatis'),
                  Text('5. Konfirmasi pembayaran'),
                ],
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: () => context.go('/qr/$tableId/track/$orderId'),
              icon: const Icon(Icons.receipt_long),
              label: const Text('Lihat Status Pesanan'),
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
            ),
          ],
        ),
      ),
    );
  }
}