import 'dart:math';
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

  final Map<String, _CartEntry> _cart = {};

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  bool _isLoading = true;
  bool _isSubmitting = false;

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

  int get _cartTotal => _cart.values.fold(0, (a, b) => a + b.qty);

  double get _cartPrice => _cart.entries.fold(0, (a, e) {
        final item = _allItems.firstWhere(
          (m) => m.id == e.key,
          orElse: () => _allItems.first,
        );
        return a + item.price * e.value.qty;
      });

  bool get _isTakeaway => _selectedTableId == null;

  void _addToCart(MenuItem item) {
    setState(() {
      if (_cart.containsKey(item.id)) {
        _cart[item.id]!.qty++;
      } else {
        _cart[item.id] = _CartEntry(qty: 1, notes: '');
      }
    });
  }

  void _removeFromCart(MenuItem item) {
    setState(() {
      if (!_cart.containsKey(item.id)) return;
      if (_cart[item.id]!.qty <= 1) {
        _cart.remove(item.id);
      } else {
        _cart[item.id]!.qty--;
      }
    });
  }

  Future<void> _showNotesDialog(MenuItem item) async {
    final ctrl = TextEditingController(text: _cart[item.id]?.notes ?? '');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.edit_note, color: AppColors.primary, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.name,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          autofocus: true,
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Contoh: tidak pedas, tanpa bawang, extra saus...',
            hintStyle: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: AppColors.textHint,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
            contentPadding: const EdgeInsets.all(12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                if (_cart.containsKey(item.id)) {
                  _cart[item.id]!.notes = '';
                }
              });
              Navigator.pop(ctx);
            },
            child: const Text(
              'Hapus Catatan',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                if (_cart.containsKey(item.id)) {
                  _cart[item.id]!.notes = ctrl.text.trim();
                }
              });
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Simpan',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  String _generateOrderNumber() {
    final now = DateTime.now();
    final date =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final rand = Random().nextInt(9000) + 1000;
    return 'ORD-$date-$rand';
  }

  Future<void> _submitOrder() async {
    if (_cart.isEmpty) return;

    if (_isTakeaway && _nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nama pelanggan wajib diisi untuk takeaway.'),
          backgroundColor: AppColors.accent,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // ✅ FIX: hapus subtotal, tax_amount, total_amount dari orders insert
      // karena kemungkinan juga generated. Hanya insert field yang diperlukan.
      final orderRes = await Supabase.instance.client
          .from('orders')
          .insert({
            'branch_id': widget.branchId,
            'table_id': _selectedTableId,
            'order_number': _generateOrderNumber(),
            'status': 'new',
            'source': _isTakeaway ? 'takeaway' : 'dine_in', // ✅ FIX: dine_in bukan dineIn
            'order_type': 'staff_order',
            'customer_name': _isTakeaway ? _nameCtrl.text.trim() : null,
            'customer_phone': _isTakeaway && _phoneCtrl.text.trim().isNotEmpty
                ? _phoneCtrl.text.trim()
                : null,
            'discount_amount': 0,
          })
          .select()
          .single();

      final orderId = orderRes['id'];

      // ✅ FIX: hapus 'subtotal' dari order_items insert — GENERATED column
      final items = _cart.entries.map((e) {
        final menuItem = _allItems.firstWhere((m) => m.id == e.key);
        return {
          'order_id': orderId,
          'menu_item_id': menuItem.id,
          'menu_item_name': menuItem.name,
          'quantity': e.value.qty,
          'unit_price': menuItem.price,
          // ❌ DIHAPUS: 'subtotal' → generated column, otomatis dihitung DB
          'status': 'pending',
          if (e.value.notes.isNotEmpty) 'special_requests': e.value.notes,
        };
      }).toList();

      await Supabase.instance.client.from('order_items').insert(items);

      if (_selectedTableId != null) {
        await Supabase.instance.client
            .from('restaurant_tables')
            .update({'status': 'occupied'})
            .eq('id', _selectedTableId!);
      }

      if (mounted) {
        setState(() {
          _cart.clear();
          _nameCtrl.clear();
          _phoneCtrl.clear();
          _isSubmitting = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order berhasil dibuat!'),
            backgroundColor: Color(0xFF4CAF50),
          ),
        );
        widget.onOrderCreated();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.accent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              _buildOrderHeader(),

              SizedBox(
                height: 50,
                child: ListView(
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
                            color: sel ? AppColors.primary : AppColors.border,
                          ),
                        ),
                        child: Text(
                          cat.name,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                            color: sel ? Colors.white : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) {
                    final item = _filtered[i];
                    final entry = _cart[item.id];
                    final qty = entry?.qty ?? 0;
                    final hasNotes = (entry?.notes ?? '').isNotEmpty;

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Center(
                                child: Text(
                                  item.name,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                            Text(
                              'Rp ${item.price.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: AppColors.accent,
                              ),
                            ),
                            const SizedBox(height: 6),
                            if (qty == 0)
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: () => _addToCart(item),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 6),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text(
                                    '+ Tambah',
                                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12),
                                  ),
                                ),
                              )
                            else
                              Column(
                                children: [
                                  Row(
                                    children: [
                                      IconButton(
                                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                        padding: EdgeInsets.zero,
                                        icon: const Icon(Icons.remove, size: 16),
                                        onPressed: () => _removeFromCart(item),
                                      ),
                                      Expanded(
                                        child: Center(
                                          child: Text(
                                            '$qty',
                                            style: const TextStyle(
                                              fontFamily: 'Poppins',
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                        padding: EdgeInsets.zero,
                                        icon: const Icon(Icons.add, size: 16),
                                        onPressed: () => _addToCart(item),
                                      ),
                                    ],
                                  ),
                                  GestureDetector(
                                    onTap: () => _showNotesDialog(item),
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: hasNotes
                                            ? AppColors.primary.withValues(alpha: 0.08)
                                            : AppColors.border.withValues(alpha: 0.3),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            hasNotes ? Icons.edit_note : Icons.note_add_outlined,
                                            size: 12,
                                            color: hasNotes ? AppColors.primary : AppColors.textHint,
                                          ),
                                          const SizedBox(width: 3),
                                          Flexible(
                                            child: Text(
                                              hasNotes ? entry!.notes : 'Tambah catatan',
                                              style: TextStyle(
                                                fontFamily: 'Poppins',
                                                fontSize: 10,
                                                color: hasNotes ? AppColors.primary : AppColors.textHint,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              if (_cartTotal > 0)
                Container(
                  color: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            '$_cartTotal',
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'item dipilih',
                        style: TextStyle(fontFamily: 'Poppins', color: Colors.white70),
                      ),
                      const Spacer(),
                      Text(
                        'Rp ${_cartPrice.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: _isSubmitting ? null : _submitOrder,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text(
                                'Kirim ke Dapur',
                                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600),
                              ),
                      ),
                    ],
                  ),
                ),
            ],
          );
  }

  Widget _buildOrderHeader() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String?>(
            initialValue: _selectedTableId,
            decoration: const InputDecoration(
              labelText: 'Pilih Meja',
              prefixIcon: Icon(Icons.table_restaurant),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('Takeaway', style: TextStyle(fontFamily: 'Poppins')),
              ),
              ...widget.tables.map((t) => DropdownMenuItem(
                    value: t.id,
                    child: Text(
                      'Meja ${t.tableNumber} (${t.capacity} org) • ${t.status.label}',
                      style: const TextStyle(fontFamily: 'Poppins'),
                    ),
                  )),
            ],
            onChanged: (v) => setState(() {
              _selectedTableId = v;
              if (!_isTakeaway) {
                _nameCtrl.clear();
                _phoneCtrl.clear();
              }
            }),
          ),

          if (_isTakeaway) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _nameCtrl,
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Nama Pelanggan *',
                      labelStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
                      prefixIcon: const Icon(Icons.person_outline, size: 18),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.primary, width: 2),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'No. HP (opsional)',
                      labelStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
                      prefixIcon: const Icon(Icons.phone_outlined, size: 18),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.primary, width: 2),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CartEntry {
  int qty;
  String notes;
  _CartEntry({required this.qty, required this.notes});
}