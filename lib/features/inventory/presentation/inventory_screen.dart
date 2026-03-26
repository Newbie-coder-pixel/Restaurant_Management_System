import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/models/inventory_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/widgets/app_drawer.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});
  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  List<InventoryItem> _items = [];
  bool _isLoading = true;
  String? _branchId;
  bool _showLowOnly = false;

  @override
  void initState() {
    super.initState();
  }

  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    final staff = ref.read(currentStaffProvider);
    if (staff != null) {
      _branchId = staff.branchId;
      _initialized = true;
      _init();
    } else {
      _initialized = true;
      ref.listenManual(currentStaffProvider, (_, next) {
        if (next != null && _branchId == null && mounted) {
          setState(() => _branchId = next.branchId);
          _init();
        }
      });
    }
  }

  Future<void> _init() async {
    await _load();
  }

  Future<void> _load() async {
    if (_branchId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    final res = await Supabase.instance.client
        .from('inventory_items')
        .select()
        .eq('branch_id', _branchId!)
        .order('name');
    if (mounted) {
      setState(() {
        _items = (res as List).map((e) => InventoryItem.fromJson(e)).toList();
        _isLoading = false;
      });
    }
  }

  List<InventoryItem> get _filtered =>
    _showLowOnly ? _items.where((i) => i.isLowStock).toList() : _items;

  int get _lowCount => _items.where((i) => i.isLowStock).length;

  Future<void> _adjustStock(InventoryItem item) async {
    final ctrl = TextEditingController(text: item.currentStock.toString());
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Adjust Stok: ${item.name}',
          style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Stok saat ini: ${item.currentStock} ${item.unit}',
            style: AppTextStyles.bodySecondary),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            decoration: InputDecoration(
              labelText: 'Stok Baru', suffixText: item.unit),
            keyboardType: TextInputType.number),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              final newStock = double.tryParse(ctrl.text);
              if (newStock == null) return;
              final nav = Navigator.of(dialogContext);
              await Supabase.instance.client.from('inventory_items')
                  .update({'current_stock': newStock}).eq('id', item.id);
              await Supabase.instance.client.from('inventory_transactions').insert({
                'branch_id': _branchId,
                'item_id': item.id,
                'transaction_type': 'adjustment',
                'quantity': newStock - item.currentStock,
                'notes': 'Manual adjustment',
              });
              if (mounted) nav.pop();
              if (mounted) await _load();
            },
            child: const Text('Simpan')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Inventory'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        titleTextStyle: const TextStyle(
          fontFamily: 'Poppins', fontSize: 18,
          fontWeight: FontWeight.w600, color: Colors.white),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddItemDialog,
        backgroundColor: AppColors.accent,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Tambah Item',
          style: TextStyle(
            color: Colors.white, fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              // Stats
              Container(
                color: AppColors.primary,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(children: [
                  _statCard('Total Item', '${_items.length}', Colors.white),
                  const SizedBox(width: 10),
                  _statCard('Stok Rendah', '$_lowCount', AppColors.accent),
                ]),
              ),
              // Filter
              Container(
                color: AppColors.surface,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(children: [
                  const Text('Filter:',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 13)),
                  const SizedBox(width: 12),
                  FilterChip(
                    label: Text('Stok Rendah ($_lowCount)',
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 12)),
                    selected: _showLowOnly,
                    onSelected: (v) => setState(() => _showLowOnly = v),
                    selectedColor: AppColors.accent.withValues(alpha: 0.2),
                    checkmarkColor: AppColors.accent,
                  ),
                ]),
              ),
              Expanded(child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _filtered.length,
                itemBuilder: (_, i) {
                  final item = _filtered[i];
                  final isLow = item.isLowStock;
                  final pct = item.minimumStock > 0
                      ? (item.currentStock / item.minimumStock).clamp(0.0, 2.0)
                      : 1.0;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(padding: const EdgeInsets.all(14), child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(child: Text(item.name,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600, fontSize: 15))),
                          if (isLow) Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.accent)),
                            child: const Text('⚠️ Stok Rendah',
                              style: TextStyle(
                                fontFamily: 'Poppins', fontSize: 11,
                                fontWeight: FontWeight.w600, color: AppColors.accent)),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          Text('${item.currentStock} ${item.unit}',
                            style: TextStyle(
                              fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                              fontSize: 18,
                              color: isLow ? AppColors.accent : AppColors.primary)),
                          const Spacer(),
                          Text('Min: ${item.minimumStock} ${item.unit}',
                            style: AppTextStyles.caption),
                        ]),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: pct.clamp(0.0, 1.0),
                            backgroundColor: AppColors.border,
                            valueColor: AlwaysStoppedAnimation(
                              isLow ? AppColors.accent : AppColors.available),
                            minHeight: 6,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                          OutlinedButton.icon(
                            onPressed: () => _adjustStock(item),
                            icon: const Icon(Icons.edit, size: 14),
                            label: const Text('Adjust',
                              style: TextStyle(fontFamily: 'Poppins', fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                          ),
                        ]),
                      ],
                    )),
                  );
                },
              )),
            ]),
    );
  }

  Widget _statCard(String label, String value, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Column(children: [
        Text(value,
          style: TextStyle(
            fontFamily: 'Poppins', fontWeight: FontWeight.w700,
            fontSize: 22, color: color)),
        Text(label,
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.white70)),
      ]),
    ),
  );

  Future<void> _showAddItemDialog() async {
    final nameCtrl  = TextEditingController();
    final unitCtrl  = TextEditingController();
    final stockCtrl = TextEditingController(text: '0');
    final minCtrl   = TextEditingController(text: '0');
    final costCtrl  = TextEditingController(text: '0');

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tambah Item Inventory',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl,
            decoration: const InputDecoration(labelText: 'Nama Item *')),
          const SizedBox(height: 10),
          TextField(controller: unitCtrl,
            decoration: const InputDecoration(labelText: 'Satuan (kg/liter/pcs) *')),
          const SizedBox(height: 10),
          TextField(controller: stockCtrl,
            decoration: const InputDecoration(labelText: 'Stok Awal'),
            keyboardType: TextInputType.number),
          const SizedBox(height: 10),
          TextField(controller: minCtrl,
            decoration: const InputDecoration(labelText: 'Stok Minimum (alert)'),
            keyboardType: TextInputType.number),
          const SizedBox(height: 10),
          TextField(controller: costCtrl,
            decoration: const InputDecoration(
              labelText: 'Harga per Satuan', prefixText: 'Rp '),
            keyboardType: TextInputType.number),
        ])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty || unitCtrl.text.trim().isEmpty) return;
              final nav = Navigator.of(dialogContext);
              await Supabase.instance.client.from('inventory_items').insert({
                'branch_id': _branchId,
                'name': nameCtrl.text.trim(),
                'unit': unitCtrl.text.trim(),
                'current_stock': double.tryParse(stockCtrl.text) ?? 0,
                'minimum_stock': double.tryParse(minCtrl.text) ?? 0,
                'cost_per_unit': double.tryParse(costCtrl.text) ?? 0,
              });
              if (mounted) nav.pop();
              if (mounted) await _load();
            },
            child: const Text('Simpan')),
        ],
      ),
    );
  }
}