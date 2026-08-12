import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../shared/models/menu_model.dart';
import '../../../../shared/models/table_model.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/prep_time_service.dart'; // ← ML Service
import '../../../../core/config/app_config.dart';
import '../../../../shared/services/order_number_service.dart';

const double _kPosPanelBreakpoint = 900;

class MenuItemSelector extends StatefulWidget {
  final String branchId;
  final List<TableModel> tables;
  final VoidCallback onOrderCreated;

  const MenuItemSelector({
    super.key,
    required this.branchId,
    required this.tables,
    required this.onOrderCreated,
  });

  @override
  State<MenuItemSelector> createState() => _MenuItemSelectorState();
}

class _MenuItemSelectorState extends State<MenuItemSelector> {
  List<MenuCategory> _categories = [];
  List<MenuItem> _allItems       = [];
  String? _selectedCatId;
  String? _selectedTableId;

  final Map<String, _CartEntry> _cart = {};
  final _nameCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();

  bool _isLoading    = true;
  bool _isSubmitting = false;

  // ── ML state ────────────────────────────────────────────────────────────────
  int?  _estimatedMinutes;   // ML prediction result, OR a rough fallback estimate
  bool  _isFetchingEstimate  = false;
  bool  _isFallbackEstimate  = false; // true if _estimatedMinutes isn't from ML

  // ── Load data ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final catRes = await Supabase.instance.client
          .from('menu_categories').select()
          .eq('branch_id', widget.branchId).order('sort_order');
      final itemRes = await Supabase.instance.client
          .from('menu_items').select()
          .eq('branch_id', widget.branchId).eq('is_available', true).order('name');

      if (mounted) {
        setState(() {
          _categories    = catRes.map((e) => MenuCategory.fromJson(e)).toList();
          _allItems      = itemRes.map((e) => MenuItem.fromJson(e)).toList();
          _selectedCatId = null;
          _isLoading     = false;
        });
      }
    } catch (e) {
      debugPrint('MenuItemSelector _load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Cart helpers ───────────────────────────────────────────────────────────
  List<MenuItem> get _filtered => _selectedCatId == null
      ? _allItems
      : _allItems.where((m) => m.categoryId == _selectedCatId).toList();

  int    get _cartTotal => _cart.values.fold(0, (a, b) => a + b.qty);
  bool   get _isTakeaway => _selectedTableId == null;

  double get _cartPrice => _cart.entries.fold(0.0, (a, e) {
    final item = _allItems.firstWhere((m) => m.id == e.key,
        orElse: () => _allItems.first);
    return a + item.price * e.value.qty;
  });

  double get _cartTax   => _cartPrice * AppConfig.defaultTaxRate;
  double get _cartGrandTotal => _cartPrice + _cartTax;

  void _addToCart(MenuItem item) {
    setState(() {
      if (_cart.containsKey(item.id)) { _cart[item.id]!.qty++; }
      else { _cart[item.id] = _CartEntry(qty: 1, notes: ''); }
    });
    _fetchEstimate(); // ← update the estimate every time the cart changes
  }

  void _removeFromCart(MenuItem item) {
    setState(() {
      if (!_cart.containsKey(item.id)) return;
      if (_cart[item.id]!.qty <= 1) { _cart.remove(item.id); }
      else { _cart[item.id]!.qty--; }
    });
    _fetchEstimate(); // ← update the estimate every time the cart changes
  }

  // ── ML: Fetch the time estimate ──────────────────────────────────────────
  Future<void> _fetchEstimate() async {
    if (_cart.isEmpty) {
      setState(() {
        _estimatedMinutes = null;
        _isFallbackEstimate = false;
      });
      return;
    }

    setState(() => _isFetchingEstimate = true);

    final items = _cart.entries.map((e) {
      final menu = _allItems.firstWhere((m) => m.id == e.key);
      return PrepTimeRequestItem(
        menuItemName:           menu.name,
        quantity:               e.value.qty,
        preparationTimeMinutes: menu.preparationTimeMinutes,
        specialRequests:        e.value.notes.isNotEmpty ? e.value.notes : null,
      );
    }).toList();

    final result = await PrepTimeService.predict(
      items:    items,
      branchId: widget.branchId,
    );

    if (mounted) {
      setState(() {
        // Server unreachable → use a rough estimate (sum of menu prep times,
        // without ML/buffer) rather than the estimate card disappearing with no explanation.
        _estimatedMinutes = result?.estimatedMinutes ??
            PrepTimeService.rawFallbackEstimate(items);
        _isFallbackEstimate = result == null;
        _isFetchingEstimate = false;
      });
    }
  }

  // ── Notes dialog ───────────────────────────────────────────────────────────
  Future<void> _showNotesDialog(MenuItem item) async {
    final ctrl = TextEditingController(text: _cart[item.id]?.notes ?? '');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.edit_note, color: AppColors.primary, size: 20)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.name,
              style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14),
              overflow: TextOverflow.ellipsis),
            const Text('Special notes for this item',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textHint)),
          ])),
        ]),
        content: TextField(
          controller: ctrl, maxLines: 3, autofocus: true,
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Example: not spicy, no onions, extra sauce...',
            hintStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textHint),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.primary, width: 2)),
            contentPadding: const EdgeInsets.all(12))),
        actions: [
          TextButton(
            onPressed: () {
              setState(() { if (_cart.containsKey(item.id)) _cart[item.id]!.notes = ''; });
              Navigator.pop(ctx);
            },
            child: const Text('Remove Note',
              style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary, fontSize: 12))),
          ElevatedButton(
            onPressed: () {
              setState(() { if (_cart.containsKey(item.id)) _cart[item.id]!.notes = ctrl.text.trim(); });
              Navigator.pop(ctx);
              _fetchEstimate(); // ← update the estimate after notes change
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('Save', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  // ── Submit ─────────────────────────────────────────────────────────────────
  Future<void> _submitOrder() async {
    if (_cart.isEmpty) return;
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Customer name is required.'),
        backgroundColor: AppColors.accent));
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      // Numeric suffix comes from the same shared per-branch daily sequence
      // the QR and customer-app paths use (OrderNumberService) — order
      // numbers across all three apps read as one continuous sequence per
      // branch, only the prefix differs.
      final seqResult = await OrderNumberService.nextSequence(widget.branchId);
      final orderNumber =
          OrderNumberService.formatStaffOrderNumber(seqResult.seq, seqResult.orderDate);

      // Compute subtotal/tax/total up front — order_items are inserted right
      // after this, and the price-integrity trigger (trg_enforce_order_total_sanity)
      // rejects the resulting orders.subtotal recompute if total_amount is left
      // at its 0 default, since total_amount must never be < subtotal - discount.
      final subtotal   = _cartPrice;
      final taxAmount  = subtotal * AppConfig.defaultTaxRate;
      final totalAmount = subtotal + taxAmount;

      final orderRes = await Supabase.instance.client.from('orders').insert({
        'branch_id':      widget.branchId,
        'table_id':       _selectedTableId,
        'order_number':   orderNumber,
        'status':         'new',
        'source':         _isTakeaway ? 'takeaway' : 'dine_in',
        'order_type':     'staff_order',
        'customer_name':  _nameCtrl.text.trim().isNotEmpty ? _nameCtrl.text.trim() : null,
        'customer_phone': _phoneCtrl.text.trim().isNotEmpty ? _phoneCtrl.text.trim() : null,
        'discount_amount': 0,
        'subtotal':       subtotal,
        'tax_amount':     taxAmount,
        'total_amount':   totalAmount,
        'payment_status': 'unpaid', // required so the order shows up on the cashier screen
        // Store the ML estimate in the DB so the KDS can show it without re-predicting
        if (_estimatedMinutes != null)
          'estimated_prep_minutes': _estimatedMinutes,
      }).select().single();

      final orderId = orderRes['id'] as String;

      try {
        await Supabase.instance.client.from('order_items').insert(
          _cart.entries.map((e) {
            final m = _allItems.firstWhere((x) => x.id == e.key);
            return {
              'order_id':       orderId,
              'menu_item_id':   m.id,
              'menu_item_name': m.name,
              'quantity':       e.value.qty,
              'unit_price':     m.price,
              // subtotal isn't inserted since it's a generated column in Supabase
              'status':         'pending',
              if (e.value.notes.isNotEmpty) 'special_requests': e.value.notes,
            };
          }).toList(),
        );
      } catch (_) {
        // The order row above already committed. Without this, a failed
        // items insert (network drop, RLS/validation error) leaves an
        // orphaned order with zero items sitting in 'new' status forever —
        // invisible everywhere in the UI (every screen filters on
        // items.isNotEmpty) but still counted as "active" in dashboards.
        await Supabase.instance.client.from('orders').update({
          'status': 'cancelled',
          'cancel_reason': 'Order items failed to save',
        }).eq('id', orderId);
        rethrow;
      }

      if (_selectedTableId != null) {
        await Supabase.instance.client.from('restaurant_tables').update({
          'status': 'occupied',
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', _selectedTableId!);
      }

      if (mounted) {
        // Show a snackbar with the time estimate if available
        final estimateText = _estimatedMinutes != null
            ? ' Estimated ready: ${PrepTimeService.formatEstimate(_estimatedMinutes!)}'
            : '';
        setState(() {
          _cart.clear();
          _nameCtrl.clear();
          _phoneCtrl.clear();
          _estimatedMinutes = null;
          _isSubmitting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ Order successfully sent to the kitchen!$estimateText'),
          backgroundColor: const Color(0xFF43A047),
          duration: const Duration(seconds: 4),
        ));
        widget.onOrderCreated();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'), backgroundColor: AppColors.accent));
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth >= _kPosPanelBreakpoint;
      return Column(children: [
        _buildOrderInfoBar(isWide),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _buildCategorySidebar(),
            Expanded(child: _buildMenuGrid()),
            if (isWide) _buildOrderPanel(),
          ]),
        ),
        if (!isWide && _cartTotal > 0) _buildCompactCartBar(),
      ]);
    });
  }

  // ── Order info bar: table + customer details ───────────────────────────────
  Widget _buildOrderInfoBar(bool isWide) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Row(children: [
        SizedBox(
          width: isWide ? 260 : double.infinity,
          child: _tableDropdown(),
        ),
        if (isWide) ...[
          const SizedBox(width: 12),
          Expanded(flex: 2, child: _field(_nameCtrl, 'Customer Name *', Icons.person_outline)),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: _field(_phoneCtrl, 'Phone (optional)', Icons.phone_outlined,
            keyboardType: TextInputType.phone)),
        ],
      ]),
    );
  }

  Widget _tableDropdown() {
    return DropdownButtonFormField<String?>(
      initialValue: _selectedTableId,
      decoration: InputDecoration(
        labelText: 'Table',
        labelStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 12),
        prefixIcon: const Icon(Icons.table_restaurant_outlined, size: 18),
        isDense: true,
        filled: true,
        fillColor: AppColors.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      items: [
        const DropdownMenuItem(value: null,
          child: Text('Takeaway', style: TextStyle(fontFamily: 'Poppins', fontSize: 13))),
        ...widget.tables.where((t) => t.status == TableStatus.available).map((t) =>
          DropdownMenuItem(value: t.id,
            child: Text('Table ${t.tableNumber} (${t.capacity} guests)',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)))),
      ],
      onChanged: (v) => setState(() => _selectedTableId = v),
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon,
      {TextInputType? keyboardType}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 12),
        prefixIcon: Icon(icon, size: 16),
        isDense: true,
        filled: true,
        fillColor: AppColors.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
    );
  }

  // ── Category sidebar ───────────────────────────────────────────────────────
  Widget _buildCategorySidebar() {
    return Container(
      width: 90,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border))),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 10),
        children: [
          _catItem(null, 'All', Icons.apps_rounded, _allItems.length),
          ...(_categories.map((c) => _catItem(
            c.id, c.name, _categoryIcon(c.name), _allItems.where((m) => m.categoryId == c.id).length))),
        ],
      ),
    );
  }

  // A best-effort icon per category name — purely decorative, falls back to a
  // generic dish icon for names that don't match a known keyword.
  IconData _categoryIcon(String name) {
    final n = name.toLowerCase();
    if (n.contains('starter')) return Icons.star_outline_rounded;
    if (n.contains('main'))    return Icons.restaurant_outlined;
    if (n.contains('satay') || n.contains('sate')) return Icons.kebab_dining_outlined;
    if (n.contains('rice') || n.contains('nasi'))  return Icons.rice_bowl_outlined;
    if (n.contains('drink') || n.contains('minum')) return Icons.local_cafe_outlined;
    if (n.contains('dessert') || n.contains('sweet')) return Icons.icecream_outlined;
    return Icons.restaurant_menu_outlined;
  }

  Widget _catItem(String? catId, String name, IconData icon, int count) {
    final sel = _selectedCatId == catId;
    return GestureDetector(
      onTap: () => setState(() => _selectedCatId = catId),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          color: sel ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 20, color: sel ? Colors.white : AppColors.textSecondary),
          const SizedBox(height: 6),
          Text(name, style: TextStyle(
            fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700,
            color: sel ? Colors.white : AppColors.textPrimary),
            textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          Text('$count', style: TextStyle(
            fontFamily: 'Poppins', fontSize: 9, fontWeight: FontWeight.w600,
            color: sel ? Colors.white70 : AppColors.textHint)),
        ]),
      ),
    );
  }

  // ── Menu grid (fast-tap) ────────────────────────────────────────────────────
  Widget _buildMenuGrid() {
    final items = _filtered;
    if (items.isEmpty) {
      return const Center(child: Text('No menu items available',
        style: TextStyle(fontFamily: 'Poppins', color: AppColors.textHint)));
    }
    return LayoutBuilder(builder: (context, constraints) {
      final crossAxisCount = (constraints.maxWidth / 230).floor().clamp(1, 5);
      return GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 0.98,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) => _menuItemCard(items[i]),
      );
    });
  }

  Widget _menuItemCard(MenuItem item) {
    final entry   = _cart[item.id];
    final qty     = entry?.qty ?? 0;
    final hasNotes = (entry?.notes ?? '').isNotEmpty;
    final inCart  = qty > 0;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(
          color: inCart ? AppColors.primary : AppColors.border,
          width: inCart ? 1.4 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(height: 3, color: inCart ? AppColors.primary : AppColors.accentOrange),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.name,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14,
                  color: AppColors.textPrimary)),
              if (item.description != null && item.description!.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(item.description!,
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
              ],
              const Spacer(),
              Row(children: [
                const Icon(Icons.timer_outlined, size: 11, color: AppColors.textHint),
                const SizedBox(width: 3),
                Text('${item.preparationTimeMinutes} min', style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 10, color: AppColors.textHint)),
              ]),
              const SizedBox(height: 6),
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Expanded(
                  child: Text('Rp ${_fmtK(item.price)}',
                    style: const TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w800,
                      fontSize: 15, color: AppColors.accent))),
                if (!inCart)
                  GestureDetector(
                    onTap: () => _addToCart(item),
                    child: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.add, size: 18, color: AppColors.textPrimary)))
                else
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.3))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      _qtyBtn(Icons.remove_rounded, () => _removeFromCart(item)),
                      SizedBox(width: 22, child: Center(child: Text('$qty', style: const TextStyle(
                        fontFamily: 'Poppins', fontWeight: FontWeight.w800,
                        fontSize: 13, color: AppColors.primary)))),
                      _qtyBtn(Icons.add_rounded, () => _addToCart(item)),
                    ])),
              ]),
              if (inCart) ...[
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => _showNotesDialog(item),
                  child: Row(children: [
                    Icon(hasNotes ? Icons.edit_note : Icons.note_add_outlined,
                      size: 13, color: hasNotes ? const Color(0xFFB07A0F) : AppColors.textHint),
                    const SizedBox(width: 4),
                    Expanded(child: Text(
                      hasNotes ? entry!.notes : 'Add note',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                        color: hasNotes ? const Color(0xFFB07A0F) : AppColors.textHint,
                        fontStyle: hasNotes ? FontStyle.normal : FontStyle.italic),
                      overflow: TextOverflow.ellipsis, maxLines: 1)),
                  ]),
                ),
              ],
            ]),
          ),
        ),
      ]),
    );
  }

  String _fmtK(double price) => price.toStringAsFixed(0);

  Widget _qtyBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26, height: 26,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(6)),
        child: Icon(icon, size: 14, color: AppColors.primary)),
    );
  }

  // ── Order ticket panel (wide layouts) ───────────────────────────────────────
  Widget _buildOrderPanel() {
    return Container(
      width: 340,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.border))),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          child: Row(children: [
            const Expanded(
              child: Text('Current Order',
                style: TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w800,
                  fontSize: 16, color: AppColors.textPrimary))),
            Text(_isTakeaway ? 'Takeaway' : 'Dine-in',
              style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
          ]),
        ),
        const Divider(height: 1, color: AppColors.border),
        Expanded(
          child: _cart.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No items yet — tap a menu item to add it.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textHint))))
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: _cart.entries.map((e) {
                    final item = _allItems.firstWhere((m) => m.id == e.key,
                        orElse: () => _allItems.first);
                    return _orderTicketRow(item, e.value);
                  }).toList(),
                ),
        ),
        if (_isFetchingEstimate || _estimatedMinutes != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2))),
              child: Row(children: [
                const Icon(Icons.schedule_rounded, size: 15, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isFallbackEstimate ? 'Rough estimate (offline)' : 'Estimated ready to cook',
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary))),
                if (_isFetchingEstimate)
                  const SizedBox(width: 13, height: 13,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                else
                  Text(PrepTimeService.formatEstimate(_estimatedMinutes!),
                    style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 12,
                      fontWeight: FontWeight.w700, color: AppColors.primary)),
              ]),
            ),
          ),
        Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border))),
          child: Column(children: [
            _totalRow('Subtotal', _cartPrice),
            const SizedBox(height: 4),
            _totalRow('Tax (${(AppConfig.defaultTaxRate * 100).toStringAsFixed(0)}%)', _cartTax),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(height: 1, color: AppColors.border)),
            Row(children: [
              const Text('Total', style: TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w800, fontSize: 15,
                color: AppColors.textPrimary)),
              const Spacer(),
              Text('Rp ${_cartGrandTotal.toStringAsFixed(0)}', style: const TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w800, fontSize: 18,
                color: AppColors.accent)),
            ]),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _cart.isEmpty || _isSubmitting ? null : _submitOrder,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent, foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.accent.withValues(alpha: 0.4),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusSm))),
                icon: _isSubmitting
                    ? const SizedBox(width: 15, height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, size: 17),
                label: Text(_isSubmitting ? 'Sending...' : 'Send to Kitchen',
                  style: const TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14))),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _totalRow(String label, double value) {
    return Row(children: [
      Text(label, style: const TextStyle(
        fontFamily: 'Poppins', fontSize: 13, color: AppColors.textSecondary)),
      const Spacer(),
      Text('Rp ${value.toStringAsFixed(0)}', style: const TextStyle(
        fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600,
        color: AppColors.textPrimary)),
    ]);
  }

  Widget _orderTicketRow(MenuItem item, _CartEntry entry) {
    final hasNotes = entry.notes.isNotEmpty;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _qtyBtn(Icons.add_rounded, () => _addToCart(item)),
              SizedBox(height: 22, child: Center(child: Text('${entry.qty}', style: const TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w800,
                fontSize: 12, color: AppColors.primary)))),
              _qtyBtn(Icons.remove_rounded, () => _removeFromCart(item)),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.name,
                style: const TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 13,
                  color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text('Rp ${item.price.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
            ]),
          ),
          Text('Rp ${(item.price * entry.qty).toStringAsFixed(0)}',
            style: const TextStyle(
              fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 13,
              color: AppColors.textPrimary)),
        ]),
        if (hasNotes) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => setState(() => entry.notes = ''),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFF6E3B4).withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(6)),
              child: Row(children: [
                Expanded(child: Text('- ${entry.notes}',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Color(0xFF7A5A12)),
                  overflow: TextOverflow.ellipsis)),
                const Icon(Icons.close, size: 13, color: Color(0xFF7A5A12)),
              ]),
            ),
          ),
        ],
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () => _showNotesDialog(item),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.edit_note, size: 13, color: AppColors.textHint),
            const SizedBox(width: 3),
            Text(hasNotes ? 'Edit Note' : 'Add Note',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textHint)),
          ]),
        ),
      ]),
    );
  }

  // ── Compact cart bar (narrow layouts, replaces the side panel) ─────────────
  Widget _buildCompactCartBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary,
        boxShadow: [BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.3),
          blurRadius: 16, offset: const Offset(0, -4))],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_isFetchingEstimate || _estimatedMinutes != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2))),
              child: Row(children: [
                const Icon(Icons.schedule_rounded, size: 16, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  _isFallbackEstimate ? 'Rough estimate (offline):' : 'Estimated ready to cook:',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.white70)),
                const SizedBox(width: 6),
                if (_isFetchingEstimate)
                  const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                else
                  Text(
                    PrepTimeService.formatEstimate(_estimatedMinutes!),
                    style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 13,
                      fontWeight: FontWeight.w700, color: Colors.white)),
              ]),
            ),
          ),
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(10)),
            child: Center(child: Text('$_cartTotal', style: const TextStyle(
              fontFamily: 'Poppins', fontWeight: FontWeight.w800, color: Colors.white, fontSize: 14)))),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('items selected', style: TextStyle(
              fontFamily: 'Poppins', color: Colors.white60, fontSize: 11)),
            Text('Rp ${_cartPrice.toStringAsFixed(0)}', style: const TextStyle(
              fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white, fontSize: 15)),
          ]),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _isSubmitting ? null : _submitOrder,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            icon: _isSubmitting
                ? const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send_rounded, size: 16),
            label: Text(_isSubmitting ? 'Sending...' : 'Send to Kitchen',
              style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13))),
        ]),
      ]),
    );
  }
}

class _CartEntry {
  int qty;
  String notes;
  _CartEntry({required this.qty, required this.notes});
}
