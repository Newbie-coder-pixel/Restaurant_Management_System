import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../shared/models/menu_model.dart';
import '../../../../shared/models/table_model.dart';
import '../../../../core/theme/app_theme.dart';

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
  List<MenuItem> _allItems = [];
  String? _selectedCatId;
  String? _selectedTableId;
  final Map<MenuItem, int> _cart = {};
  bool _isLoading = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final catRes = await Supabase.instance.client
        .from('menu_categories')
        .select()
        .eq('branch_id', widget.branchId)
        .order('sort_order');
    final itemRes = await Supabase.instance.client
        .from('menu_items')
        .select()
        .eq('branch_id', widget.branchId)
        .eq('is_available', true)
        .order('name');
    if (mounted) {
      setState(() {
        _categories = (catRes as List).map((e) => MenuCategory.fromJson(e)).toList();
        _allItems = (itemRes as List).map((e) => MenuItem.fromJson(e)).toList();
        _selectedCatId = _categories.isNotEmpty ? _categories.first.id : null;
        _isLoading = false;
      });
    }
  }

  List<MenuItem> get _filtered => _selectedCatId == null
      ? _allItems
      : _allItems.where((m) => m.categoryId == _selectedCatId).toList();

  int get _cartTotal => _cart.values.fold(0, (a, b) => a + b);
  double get _cartPrice =>
      _cart.entries.fold(0, (a, e) => a + e.key.price * e.value);

  void _addToCart(MenuItem item) =>
      setState(() => _cart[item] = (_cart[item] ?? 0) + 1);
  void _removeFromCart(MenuItem item) {
    setState(() {
      if ((_cart[item] ?? 0) <= 1) {
        _cart.remove(item);
      } else {
        _cart[item] = _cart[item]! - 1;
      }
    });
  }

  Future<void> _submitOrder() async {
    if (_cart.isEmpty) return;
    setState(() => _isSubmitting = true);
    final orderNum = 'ORD-${DateTime.now().millisecondsSinceEpoch}';
    final subtotal = _cartPrice;
    final tax = subtotal * 0.11;
    final total = subtotal + tax;
    try {
      final orderRes = await Supabase.instance.client.from('orders').insert({
        'branch_id': widget.branchId,
        'table_id': _selectedTableId,
        'order_number': orderNum,
        'status': 'new',
        'source': 'dineIn',
        'subtotal': subtotal,
        'tax_amount': tax,
        'discount_amount': 0,
        'total_amount': total,
      }).select().single();

      final orderId = orderRes['id'];
      final items = _cart.entries.map((e) => {
        'order_id': orderId,
        'menu_item_id': e.key.id,
        'quantity': e.value,
        'unit_price': e.key.price,
        'subtotal': e.key.price * e.value,
        'status': 'pending',
      }).toList();
      await Supabase.instance.client.from('order_items').insert(items);

      if (_selectedTableId != null) {
        await Supabase.instance.client.from('restaurant_tables')
            .update({'status': 'occupied'}).eq('id', _selectedTableId!);
      }

      if (mounted) {
        setState(() { _cart.clear(); _isSubmitting = false; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Order berhasil dibuat!'),
          backgroundColor: Color(0xFF4CAF50),
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

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : Column(children: [
            // Table selector
            Container(
              color: AppColors.surface,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: DropdownButtonFormField<String>(
                initialValue: _selectedTableId,
                decoration: const InputDecoration(
                  labelText: 'Pilih Meja',
                  prefixIcon: Icon(Icons.table_restaurant),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem(value: null,
                    child: Text('Takeaway', style: TextStyle(fontFamily: 'Poppins'))),
                  ...widget.tables
                    .where((t) => t.status != TableStatus.occupied)
                    .map((t) => DropdownMenuItem(value: t.id,
                      child: Text('Meja ${t.tableNumber} (${t.capacity} org)',
                        style: const TextStyle(fontFamily: 'Poppins')))),
                ],
                onChanged: (v) => setState(() => _selectedTableId = v),
              ),
            ),
            // Category chips
            SizedBox(height: 50, child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: _categories.map((cat) {
                final sel = _selectedCatId == cat.id;
                return GestureDetector(
                  onTap: () => setState(() => _selectedCatId = cat.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: sel ? AppColors.primary : AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: sel ? AppColors.primary : AppColors.border)),
                    child: Text(cat.name,
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 12,
                        fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                        color: sel ? Colors.white : AppColors.textSecondary)),
                  ),
                );
              }).toList(),
            )),
            // Menu grid
            Expanded(child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.9,
              ),
              itemCount: _filtered.length,
              itemBuilder: (_, i) {
                final item = _filtered[i];
                final qty = _cart[item] ?? 0;
                return Card(child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Center(child: Text(item.name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600, fontSize: 13)))),
                    Text('Rp ${item.price.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                        fontSize: 13, color: AppColors.accent)),
                    const SizedBox(height: 6),
                    qty == 0
                        ? SizedBox(width: double.infinity, child: ElevatedButton(
                            onPressed: () => _addToCart(item),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                            child: const Text('+ Tambah',
                              style: TextStyle(fontFamily: 'Poppins', fontSize: 12))))
                        : Row(children: [
                            IconButton(
                              constraints: const BoxConstraints(
                                minWidth: 28, minHeight: 28),
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.remove, size: 16),
                              onPressed: () => _removeFromCart(item)),
                            Expanded(child: Center(child: Text('$qty',
                              style: const TextStyle(
                                fontFamily: 'Poppins', fontWeight: FontWeight.w700)))),
                            IconButton(
                              constraints: const BoxConstraints(
                                minWidth: 28, minHeight: 28),
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.add, size: 16),
                              onPressed: () => _addToCart(item)),
                          ]),
                  ]),
                ));
              },
            )),
            // Cart bar
            if (_cartTotal > 0) Container(
              color: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.accent, borderRadius: BorderRadius.circular(8)),
                  child: Center(child: Text('$_cartTotal',
                    style: const TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                      color: Colors.white, fontSize: 13)))),
                const SizedBox(width: 12),
                const Text('item dipilih',
                  style: TextStyle(fontFamily: 'Poppins', color: Colors.white70)),
                const Spacer(),
                Text('Rp ${_cartPrice.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                    color: Colors.white, fontSize: 16)),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitOrder,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white),
                  child: _isSubmitting
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                      : const Text('Kirim ke Dapur',
                          style: TextStyle(
                            fontFamily: 'Poppins', fontWeight: FontWeight.w600))),
              ]),
            ),
          ]);
  }
}