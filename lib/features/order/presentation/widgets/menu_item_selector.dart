import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../shared/models/menu_model.dart';
import '../../../../shared/models/table_model.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/prep_time_service.dart'; // ← ML Service

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
  int?  _estimatedMinutes;   // hasil prediksi ML
  bool  _isFetchingEstimate  = false;

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
    final catRes  = await Supabase.instance.client
        .from('menu_categories').select()
        .eq('branch_id', widget.branchId).order('sort_order');
    final itemRes = await Supabase.instance.client
        .from('menu_items').select()
        .eq('branch_id', widget.branchId).eq('is_available', true).order('name');
    if (mounted) {
      setState(() {
        _categories    = (catRes  as List).map((e) => MenuCategory.fromJson(e)).toList();
        _allItems      = (itemRes as List).map((e) => MenuItem.fromJson(e)).toList();
        _selectedCatId = null;
        _isLoading     = false;
      });
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

  void _addToCart(MenuItem item) {
    setState(() {
      if (_cart.containsKey(item.id)) { _cart[item.id]!.qty++; }
      else { _cart[item.id] = _CartEntry(qty: 1, notes: ''); }
    });
    _fetchEstimate(); // ← update estimasi setiap cart berubah
  }

  void _removeFromCart(MenuItem item) {
    setState(() {
      if (!_cart.containsKey(item.id)) return;
      if (_cart[item.id]!.qty <= 1) { _cart.remove(item.id); }
      else { _cart[item.id]!.qty--; }
    });
    _fetchEstimate(); // ← update estimasi setiap cart berubah
  }

  // ── ML: Fetch estimasi waktu ───────────────────────────────────────────────
  Future<void> _fetchEstimate() async {
    if (_cart.isEmpty) {
      setState(() => _estimatedMinutes = null);
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
        _estimatedMinutes  = result?.estimatedMinutes;
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
            const Text('Catatan khusus untuk item ini',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textHint)),
          ])),
        ]),
        content: TextField(
          controller: ctrl, maxLines: 3, autofocus: true,
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Contoh: tidak pedas, tanpa bawang, extra saus...',
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
            child: const Text('Hapus Catatan',
              style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary, fontSize: 12))),
          ElevatedButton(
            onPressed: () {
              setState(() { if (_cart.containsKey(item.id)) _cart[item.id]!.notes = ctrl.text.trim(); });
              Navigator.pop(ctx);
              _fetchEstimate(); // ← update estimasi setelah notes berubah
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('Simpan', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  // ── Submit ─────────────────────────────────────────────────────────────────
  Future<void> _submitOrder() async {
    if (_cart.isEmpty) return;
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Nama pelanggan wajib diisi.'),
        backgroundColor: AppColors.accent));
      return;
    }
    if (_phoneCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Nomor telepon wajib diisi.'),
        backgroundColor: AppColors.accent));
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final now  = DateTime.now();
      final date = '${now.year}${now.month.toString().padLeft(2,'0')}${now.day.toString().padLeft(2,'0')}';
      final orderNumber = 'ORD-$date-${Random().nextInt(9000) + 1000}';

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
      }).select().single();

      final orderId = orderRes['id'] as String;

      await Supabase.instance.client.from('order_items').insert(
        _cart.entries.map((e) {
          final m = _allItems.firstWhere((x) => x.id == e.key);
          return {
            'order_id':       orderId,
            'menu_item_id':   m.id,
            'menu_item_name': m.name,
            'quantity':       e.value.qty,
            'unit_price':     m.price,
            'status':         'pending',
            if (e.value.notes.isNotEmpty) 'special_requests': e.value.notes,
          };
        }).toList(),
      );

      if (_selectedTableId != null) {
        await Supabase.instance.client
            .from('restaurant_tables').update({'status': 'occupied'}).eq('id', _selectedTableId!);
      }

      if (mounted) {
        // Tampilkan snackbar dengan estimasi waktu jika tersedia
        final estimasiText = _estimatedMinutes != null
            ? ' Estimasi siap: ${PrepTimeService.formatEstimate(_estimatedMinutes!)}'
            : '';
        setState(() {
          _cart.clear();
          _nameCtrl.clear();
          _phoneCtrl.clear();
          _estimatedMinutes = null;
          _isSubmitting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ Order berhasil dikirim ke dapur!$estimasiText'),
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
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      _buildHeader(),
      Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildCategorySidebar(),
        Expanded(child: _buildMenuList()),
      ])),
      if (_cartTotal > 0) _buildCartBar(),
    ]);
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Column(children: [
        DropdownButtonFormField<String?>(
          initialValue: _selectedTableId,
          decoration: const InputDecoration(
            labelText: 'Pilih Meja',
            labelStyle: TextStyle(fontFamily: 'Poppins'),
            prefixIcon: Icon(Icons.table_restaurant_outlined, size: 18),
            isDense: true,
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          items: [
            const DropdownMenuItem(value: null,
              child: Text('Takeaway', style: TextStyle(fontFamily: 'Poppins'))),
            ...widget.tables.where((t) => t.status == TableStatus.available).map((t) =>
              DropdownMenuItem(value: t.id,
                child: Text('Meja ${t.tableNumber} (${t.capacity} org)',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)))),
          ],
          onChanged: (v) => setState(() => _selectedTableId = v),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(flex: 3, child: _field(_nameCtrl, 'Nama Pelanggan *', Icons.person_outline)),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: _field(_phoneCtrl, 'No. HP *', Icons.phone_outlined,
            keyboardType: TextInputType.phone)),
        ]),
      ]),
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
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 2)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
    );
  }

  // ── Category sidebar ───────────────────────────────────────────────────────
  Widget _buildCategorySidebar() {
    return Container(
      width: 86,
      color: const Color(0xFFF7F8FA),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _catItem(null, 'Semua', Icons.apps_rounded, _allItems.length),
          ...(_categories.map((c) => _catItem(
            c.id, c.name, Icons.restaurant_outlined,
            _allItems.where((m) => m.categoryId == c.id).length))),
        ],
      ),
    );
  }

  Widget _catItem(String? catId, String name, IconData icon, int count) {
    final sel = _selectedCatId == catId;
    return GestureDetector(
      onTap: () => setState(() => _selectedCatId = catId),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: sel ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: sel ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 6, offset: const Offset(0, 2))] : null,
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 20, color: sel ? Colors.white : AppColors.textSecondary),
          const SizedBox(height: 5),
          Text(name, style: TextStyle(
            fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w600,
            color: sel ? Colors.white : AppColors.textSecondary),
            textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: sel ? Colors.white.withValues(alpha: 0.2) : AppColors.border.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8)),
            child: Text('$count', style: TextStyle(
              fontFamily: 'Poppins', fontSize: 9, fontWeight: FontWeight.w700,
              color: sel ? Colors.white : AppColors.textHint))),
        ]),
      ),
    );
  }

  // ── Menu list ──────────────────────────────────────────────────────────────
  Widget _buildMenuList() {
    final items = _filtered;
    if (items.isEmpty) {
      return const Center(child: Text('Tidak ada menu tersedia',
        style: TextStyle(fontFamily: 'Poppins', color: AppColors.textHint)));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      itemCount: items.length,
      itemBuilder: (_, i) => _menuItemCard(items[i]),
    );
  }

  Widget _menuItemCard(MenuItem item) {
    final entry   = _cart[item.id];
    final qty     = entry?.qty ?? 0;
    final hasNotes = (entry?.notes ?? '').isNotEmpty;
    final inCart  = qty > 0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: inCart ? AppColors.primary.withValues(alpha: 0.03) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: inCart ? AppColors.primary.withValues(alpha: 0.25) : AppColors.border.withValues(alpha: 0.5),
          width: inCart ? 1.5 : 1),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.name, style: const TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 2),
              Row(children: [
                Text('Rp ${item.price.toStringAsFixed(0)}', style: const TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                  fontSize: 13, color: AppColors.accent)),
                // ── Badge prep time ──────────────────────────────────────
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.timer_outlined, size: 11, color: Colors.orange.shade700),
                    const SizedBox(width: 3),
                    Text('${item.preparationTimeMinutes} mnt', style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 10,
                      color: Colors.orange.shade700, fontWeight: FontWeight.w600)),
                  ])),
                if (inCart) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6)),
                    child: Text('= Rp ${(item.price * qty).toStringAsFixed(0)}',
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                        fontWeight: FontWeight.w600, color: AppColors.primary))),
                ],
              ]),
            ])),
            const SizedBox(width: 12),
            if (!inCart)
              ElevatedButton.icon(
                onPressed: () => _addToCart(item),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Tambah',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600)))
            else
              Container(
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.2))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _qtyBtn(Icons.remove_rounded, () => _removeFromCart(item)),
                  SizedBox(width: 32, child: Center(child: Text('$qty', style: const TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w800,
                    fontSize: 15, color: AppColors.primary)))),
                  _qtyBtn(Icons.add_rounded, () => _addToCart(item)),
                ])),
          ]),
          if (inCart) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _showNotesDialog(item),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: hasNotes ? Colors.amber.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: hasNotes ? Colors.amber.withValues(alpha: 0.35) : Colors.grey.withValues(alpha: 0.2))),
                child: Row(children: [
                  Icon(hasNotes ? Icons.edit_note : Icons.note_add_outlined,
                    size: 15, color: hasNotes ? Colors.amber.shade700 : AppColors.textHint),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    hasNotes ? entry!.notes : 'Tambah catatan (tidak pedas, tanpa bawang...)',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                      color: hasNotes ? Colors.amber.shade800 : AppColors.textHint,
                      fontStyle: hasNotes ? FontStyle.normal : FontStyle.italic),
                    overflow: TextOverflow.ellipsis, maxLines: 2)),
                  if (hasNotes) ...[
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => setState(() => _cart[item.id]?.notes = ''),
                      child: Icon(Icons.close, size: 14, color: Colors.amber.shade600)),
                  ],
                ]),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 16, color: AppColors.primary)),
    );
  }

  // ── Cart bar (dengan estimasi ML) ──────────────────────────────────────────
  Widget _buildCartBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary,
        boxShadow: [BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.3),
          blurRadius: 16, offset: const Offset(0, -4))],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(mainAxisSize: MainAxisSize.min, children: [

        // ── Baris estimasi ML ──────────────────────────────────────────────
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
                const Text('Estimasi siap masak:',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.white70)),
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

        // ── Baris cart utama ───────────────────────────────────────────────
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(10)),
            child: Center(child: Text('$_cartTotal', style: const TextStyle(
              fontFamily: 'Poppins', fontWeight: FontWeight.w800, color: Colors.white, fontSize: 14)))),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('item dipilih', style: TextStyle(
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
            label: Text(_isSubmitting ? 'Mengirim...' : 'Kirim ke Dapur',
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