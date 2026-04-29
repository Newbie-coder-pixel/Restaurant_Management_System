import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/qr_cart_provider.dart';
import '../data/qr_order_repository.dart';
import '../../../../core/services/prep_time_service.dart'; // ← ML Service

class QrCartScreen extends ConsumerStatefulWidget {
  final String tableId;
  const QrCartScreen({super.key, required this.tableId});

  @override
  ConsumerState<QrCartScreen> createState() => _QrCartScreenState();
}

class _QrCartScreenState extends ConsumerState<QrCartScreen> {
  final _nameCtrl = TextEditingController();
  final _formKey  = GlobalKey<FormState>();
  bool _isSubmitting = false;

  // ── ML state ────────────────────────────────────────────────────────────────
  int?  _estimatedMinutes;
  bool  _isFetchingEstimate = false;
  List<QrCartItem> _lastCartItems = [];

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
    _nameCtrl.dispose();
    super.dispose();
  }

  // ── ML: Fetch estimasi waktu ───────────────────────────────────────────────
  Future<void> _fetchEstimate(QrOrderSession cart) async {
    if (cart.isEmpty) {
      setState(() => _estimatedMinutes = null);
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
        _estimatedMinutes   = result?.estimatedMinutes;
        _isFetchingEstimate = false;
      });
    }
  }

  // ── Confirm order ──────────────────────────────────────────────────────────
  Future<void> _confirmOrder() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);

    final notifier = ref.read(activeQrCartNotifierProvider);
    notifier.setCustomerInfo(name: _nameCtrl.text.trim());

    final cart     = ref.read(activeQrCartProvider);
    final branchId = cart.branchId.trim();

    final activeTable = ref.read(activeQrTableProvider);
    final tableId     = activeTable.tableId.isNotEmpty
        ? activeTable.tableId
        : widget.tableId;

    debugPrint('🔍 [CartScreen] tableId dari activeQrTableProvider: "${activeTable.tableId}"');
    debugPrint('🔍 [CartScreen] tableId dari widget: "${widget.tableId}"');
    debugPrint('🔍 [CartScreen] tableId yang akan dipakai: "$tableId"');

    if (branchId.isEmpty) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Branch ID tidak ditemukan. Silakan scan ulang QR meja.'),
          backgroundColor: Colors.red));
      }
      return;
    }

    if (tableId.isEmpty) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Table ID tidak ditemukan. Silakan scan ulang QR meja.'),
          backgroundColor: Colors.red));
      }
      return;
    }

    final repo = ref.read(qrOrderRepositoryProvider);

    try {
      final correctedSession = cart.copyWith(tableId: tableId);
      final order = await repo.createOrder(
        session:  correctedSession,
        branchId: branchId,
      );

      notifier.clearCart();

      if (mounted) {
        // Simpan estimasi sebelum clear
        final estimasiText = _estimatedMinutes != null
            ? ' Estimasi siap: ${PrepTimeService.formatEstimate(_estimatedMinutes!)}'
            : '';

        context.go('/qr/${widget.tableId}/track/${order.id}?queue=${order.queueNumber}');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Pesanan #${order.queueNumber} berhasil dikirim ke dapur!$estimasiText'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membuat pesanan: $e'), backgroundColor: Colors.red));
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.edit_note, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(item.menuItem.name,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            overflow: TextOverflow.ellipsis)),
        ]),
        content: TextField(
          controller: ctrl, maxLines: 3, autofocus: true,
          decoration: InputDecoration(
            hintText: 'Contoh: tidak pedas, tanpa bawang...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.all(12))),
        actions: [
          TextButton(
            onPressed: () {
              notifier.updateNotes(item.menuItem.id, '');
              Navigator.pop(ctx);
            },
            child: const Text('Hapus Catatan', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () {
              notifier.updateNotes(item.menuItem.id, ctrl.text.trim());
              Navigator.pop(ctx);
              // Update estimasi setelah notes berubah
              final cart = ref.read(activeQrCartProvider);
              _fetchEstimate(cart);
            },
            child: const Text('Simpan')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart     = ref.watch(activeQrCartProvider);
    final notifier = ref.read(activeQrCartNotifierProvider);
    final theme    = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (cart.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Keranjang'),
          leading: BackButton(onPressed: () => context.pop()),
        ),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.shopping_cart_outlined, size: 80, color: colorScheme.outline),
            const SizedBox(height: 16),
            Text('Keranjangmu kosong', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Pilih menu terlebih dahulu',
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Kembali ke Menu')),
          ]),
        ),
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Keranjang Pesanan'),
        leading: BackButton(onPressed: () => context.pop()),
        actions: [
          TextButton(
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Kosongkan Keranjang?'),
                  content: const Text('Semua item akan dihapus dari keranjang.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Batal')),
                    TextButton(
                      onPressed: () {
                        notifier.clearCart();
                        Navigator.pop(context);
                        context.pop();
                      },
                      style: TextButton.styleFrom(foregroundColor: colorScheme.error),
                      child: const Text('Kosongkan')),
                  ],
                ),
              );
            },
            child: Text('Kosongkan',
              style: TextStyle(color: colorScheme.error, fontSize: 13)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: CustomScrollView(
          slivers: [
            // ── Banner Estimasi ML ─────────────────────────────────────────
            if (_isFetchingEstimate || _estimatedMinutes != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: colorScheme.primary.withValues(alpha: 0.2)),
                    ),
                    child: Row(children: [
                      Icon(Icons.schedule_rounded,
                        size: 20, color: colorScheme.primary),
                      const SizedBox(width: 10),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Estimasi Waktu Siap',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          if (_isFetchingEstimate)
                            Row(children: [
                              SizedBox(
                                width: 12, height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colorScheme.primary)),
                              const SizedBox(width: 8),
                              Text('Menghitung...',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onPrimaryContainer)),
                            ])
                          else
                            Text(
                              PrepTimeService.formatEstimate(_estimatedMinutes!),
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w700)),
                        ],
                      )),
                      Icon(Icons.info_outline,
                        size: 16,
                        color: colorScheme.primary.withValues(alpha: 0.5)),
                    ]),
                  ),
                ),
              ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text('${cart.totalItems} item pesanan',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.outline)),
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

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _CustomerInfoCard(
                  nameCtrl:  _nameCtrl,
                  tableName: cart.tableName ?? 'Meja'),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                child: _OrderSummaryCard(cart: cart),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _CartBottomBar(
        cart:      cart,
        onProceed: _confirmOrder,
        isLoading: _isSubmitting),
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
    final theme       = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dismissible(
      key: ValueKey(item.menuItem.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.error, borderRadius: BorderRadius.circular(14)),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(Icons.delete_outline, color: colorScheme.onError, size: 24)),
      onDismissed: (_) => onDelete(),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colorScheme.outlineVariant, width: 0.8)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(width: 60, height: 60,
                  child: item.menuItem.imageUrl != null
                      ? Image.network(item.menuItem.imageUrl!, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.fastfood_outlined, size: 24, color: Colors.grey)))
                      : Container(
                          color: colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.fastfood_outlined, size: 24, color: Colors.grey)))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.menuItem.name,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Row(children: [
                  Text(_formatPrice(item.menuItem.price),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.primary, fontWeight: FontWeight.w500)),
                  const SizedBox(width: 8),
                  // ── Badge prep time ──────────────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.timer_outlined, size: 11, color: Colors.orange.shade700),
                      const SizedBox(width: 3),
                      Text('${item.menuItem.preparationTimeMinutes} mnt',
                        style: TextStyle(fontSize: 10,
                          color: Colors.orange.shade700, fontWeight: FontWeight.w600)),
                    ])),
                ]),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(_formatPrice(item.subtotal),
                  style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  _SmallQtyBtn(icon: Icons.remove, onTap: onRemove, colorScheme: colorScheme),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text('${item.quantity}',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold))),
                  _SmallQtyBtn(icon: Icons.add, onTap: onAdd, colorScheme: colorScheme),
                ]),
              ]),
            ]),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: onEditNotes,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: (item.notes != null && item.notes!.isNotEmpty)
                      ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                      : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (item.notes != null && item.notes!.isNotEmpty)
                        ? colorScheme.primary.withValues(alpha: 0.3)
                        : colorScheme.outlineVariant)),
                child: Row(children: [
                  Icon(
                    (item.notes != null && item.notes!.isNotEmpty)
                        ? Icons.edit_note : Icons.note_add_outlined,
                    size: 14,
                    color: (item.notes != null && item.notes!.isNotEmpty)
                        ? colorScheme.primary : colorScheme.outline),
                  const SizedBox(width: 6),
                  Expanded(child: Text(
                    (item.notes != null && item.notes!.isNotEmpty)
                        ? item.notes!
                        : 'Tambah catatan (tidak pedas, dll...)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: (item.notes != null && item.notes!.isNotEmpty)
                          ? colorScheme.primary : colorScheme.outline,
                      fontStyle: (item.notes != null && item.notes!.isNotEmpty)
                          ? FontStyle.normal : FontStyle.italic),
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

class _SmallQtyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final ColorScheme colorScheme;

  const _SmallQtyBtn({required this.icon, required this.onTap, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26, height: 26,
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(6)),
        child: Icon(icon, size: 14, color: colorScheme.onPrimaryContainer)));
  }
}

// ─── Customer Info Card ───────────────────────────────────────────────────────
class _CustomerInfoCard extends StatelessWidget {
  final TextEditingController nameCtrl;
  final String tableName;

  const _CustomerInfoCard({required this.nameCtrl, required this.tableName});

  @override
  Widget build(BuildContext context) {
    final theme       = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant, width: 0.8)),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.person_outline, size: 18, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text('Informasi Pelanggan',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 14),
        TextFormField(
          initialValue: tableName,
          readOnly: true,
          decoration: InputDecoration(
            labelText: 'Nomor Meja',
            prefixIcon: const Icon(Icons.table_restaurant_outlined),
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10))),
        const SizedBox(height: 10),
        TextFormField(
          controller: nameCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Nama Pemesan *',
            hintText: 'Contoh: Budi',
            prefixIcon: const Icon(Icons.badge_outlined),
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
          validator: (val) {
            if (val == null || val.trim().isEmpty) return 'Nama tidak boleh kosong';
            if (val.trim().length < 2) return 'Nama terlalu pendek';
            return null;
          }),
      ]),
    );
  }
}

// ─── Order Summary Card ───────────────────────────────────────────────────────
class _OrderSummaryCard extends StatelessWidget {
  final QrOrderSession cart;
  const _OrderSummaryCard({required this.cart});

  @override
  Widget build(BuildContext context) {
    final theme       = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant, width: 0.8)),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.receipt_outlined, size: 18, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text('Ringkasan Pesanan',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 14),
        ...cart.items.map((item) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Text('${item.quantity}×',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.primary, fontWeight: FontWeight.bold)),
            const SizedBox(width: 6),
            Expanded(child: Text(item.menuItem.name,
              style: theme.textTheme.bodySmall,
              maxLines: 1, overflow: TextOverflow.ellipsis)),
            Text(_formatPrice(item.subtotal), style: theme.textTheme.bodySmall),
          ]),
        )),
        Divider(color: colorScheme.outlineVariant, height: 20, thickness: 0.5),
        Row(children: [
          Text('Subtotal',
            style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline)),
          const Spacer(),
          Text(_formatPrice(cart.subtotal), style: theme.textTheme.bodySmall),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Text('PPN (11%)',
            style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline)),
          const Spacer(),
          Text(_formatPrice(cart.taxAmount), style: theme.textTheme.bodySmall),
        ]),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Text('Total', style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold, color: colorScheme.onPrimaryContainer)),
            const Spacer(),
            Text(_formatPrice(cart.totalAmount),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold, color: colorScheme.primary)),
          ])),
      ]),
    );
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

  const _CartBottomBar({
    required this.cart,
    required this.onProceed,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final theme       = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant, width: 0.5))),
      child: SizedBox(
        width: double.infinity, height: 52,
        child: ElevatedButton(
          onPressed: isLoading ? null : onProceed,
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0),
          child: isLoading
              ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                  SizedBox(width: 10),
                  Text('Mengirim ke Dapur...'),
                ])
              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.send_outlined, size: 20),
                  const SizedBox(width: 8),
                  Text('Pesan Sekarang',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.onPrimary, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: colorScheme.onPrimary.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(20)),
                    child: Text(_formatPrice(cart.totalAmount),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onPrimary, fontWeight: FontWeight.bold))),
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