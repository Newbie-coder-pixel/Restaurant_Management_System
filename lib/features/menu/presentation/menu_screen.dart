import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../shared/models/menu_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/widgets/app_drawer.dart';

class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({super.key});
  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> {
  List<MenuCategory> _categories = [];
  List<MenuItem> _items = [];
  String? _selectedCategoryId;
  String? _branchId;
  bool _isLoading = true;
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

  Future<void> _init() async => _load();

  Future<void> _load() async {
    if (_branchId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    final catRes = await Supabase.instance.client
        .from('menu_categories')
        .select()
        .eq('branch_id', _branchId!)
        .order('sort_order');
    final itemRes = await Supabase.instance.client
        .from('menu_items')
        .select()
        .eq('branch_id', _branchId!)
        .order('name');
    if (mounted) {
      setState(() {
        _categories = (catRes as List).map((e) => MenuCategory.fromJson(e)).toList();
        _items = (itemRes as List).map((e) => MenuItem.fromJson(e)).toList();
        _selectedCategoryId ??= _categories.isNotEmpty ? _categories.first.id : null;
        _isLoading = false;
      });
    }
  }

  List<MenuItem> get _filtered => _selectedCategoryId == null
      ? _items
      : _items.where((m) => m.categoryId == _selectedCategoryId).toList();

  Future<void> _toggleAvailability(String itemId, bool current) async {
    await Supabase.instance.client
        .from('menu_items')
        .update({'is_available': !current})
        .eq('id', itemId);
    await _load();
  }

  Future<void> _showAddCategoryDialog() async {
    final nameCtrl = TextEditingController();
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tambah Kategori',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nama Kategori *',
            hintText: 'Contoh: Minuman, Makanan Berat...',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              await Supabase.instance.client.from('menu_categories').insert({
                'branch_id': _branchId,
                'name': nameCtrl.text.trim(),
                'sort_order': _categories.length + 1,
                'is_active': true,
              });
              if (ctx.mounted) Navigator.pop(ctx);
              await _load();
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeleteCategoryDialog(MenuCategory cat) async {
    final count = _items.where((m) => m.categoryId == cat.id).length;
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Kategori?',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
        content: Text(
          count > 0
              ? 'Kategori "${cat.name}" memiliki $count menu. Semua menu di kategori ini akan ikut terhapus.'
              : 'Hapus kategori "${cat.name}"?',
          style: const TextStyle(fontFamily: 'Poppins'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent, foregroundColor: Colors.white),
            onPressed: () async {
              await Supabase.instance.client
                  .from('menu_categories')
                  .delete()
                  .eq('id', cat.id);
              if (ctx.mounted) Navigator.pop(ctx);
              setState(() => _selectedCategoryId = null);
              await _load();
            },
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddItemDialog() async {
    final nameCtrl  = TextEditingController();
    final priceCtrl = TextEditingController();
    final descCtrl  = TextEditingController();
    final imageCtrl = TextEditingController();
    String? selCatId = _selectedCategoryId;
    String? previewUrl;

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          title: const Text('Tambah Menu',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (previewUrl != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: CachedNetworkImage(
                      imageUrl: previewUrl!,
                      height: 140,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        height: 140,
                        color: Colors.grey[200],
                        child: const Center(
                          child: Icon(Icons.broken_image_outlined,
                              color: Colors.grey, size: 40)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                TextField(
                  controller: imageCtrl,
                  decoration: InputDecoration(
                    labelText: 'URL Gambar',
                    hintText: 'https://...',
                    prefixIcon: const Icon(Icons.image_outlined),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.visibility_outlined),
                      tooltip: 'Preview',
                      onPressed: () {
                        final url = imageCtrl.text.trim();
                        ss(() => previewUrl = url.isNotEmpty ? url : null);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nama Menu *'),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: priceCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Harga *', prefixText: 'Rp '),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'Deskripsi'),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),

                // FIX 1: 'value' → 'initialValue' (deprecated after v3.33.0-1.0.pre)
                DropdownButtonFormField<String>(
                  initialValue: selCatId,
                  decoration: const InputDecoration(labelText: 'Kategori'),
                  items: _categories.map((c) => DropdownMenuItem(
                    value: c.id,
                    child: Text(c.name,
                        style: const TextStyle(fontFamily: 'Poppins')),
                  )).toList(),
                  onChanged: (v) => ss(() => selCatId = v),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white),
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty ||
                    priceCtrl.text.trim().isEmpty) {
                  return; // FIX 2: wrap single-statement if body in braces
                }
                final imageUrl = imageCtrl.text.trim();
                await Supabase.instance.client.from('menu_items').insert({
                  'branch_id': _branchId,
                  'category_id': selCatId,
                  'name': nameCtrl.text.trim(),
                  'price': double.tryParse(priceCtrl.text.trim()) ?? 0,
                  'description': descCtrl.text.trim().isEmpty
                      ? null
                      : descCtrl.text.trim(),
                  'image_url': imageUrl.isEmpty ? null : imageUrl,
                  'is_available': true,
                });
                if (ctx.mounted) Navigator.pop(ctx);
                await _load();
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Menu Management'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        titleTextStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load)
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddItemDialog,
        backgroundColor: AppColors.accent,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Tambah Menu',
            style: TextStyle(
                color: Colors.white,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Row(children: [
              Container(
                width: 160,
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: const Offset(2, 0))
                  ],
                ),
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 4, 8),
                      child: Row(children: [
                        Expanded(
                          child: Text('KATEGORI',
                              style: AppTextStyles.label.copyWith(
                                  color: AppColors.textSecondary,
                                  letterSpacing: 1)),
                        ),
                        InkWell(
                          onTap: _showAddCategoryDialog,
                          borderRadius: BorderRadius.circular(8),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.add_circle_outline,
                                size: 18, color: AppColors.primary),
                          ),
                        ),
                      ]),
                    ),
                    GestureDetector(
                      onTap: () =>
                          setState(() => _selectedCategoryId = null),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.fromLTRB(8, 2, 8, 2),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: _selectedCategoryId == null
                              ? AppColors.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('Semua',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 13,
                                fontWeight: _selectedCategoryId == null
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: _selectedCategoryId == null
                                    ? Colors.white
                                    : AppColors.textSecondary)),
                      ),
                    ),
                    ..._categories.map((cat) {
                      final sel = _selectedCategoryId == cat.id;
                      return GestureDetector(
                        onTap: () =>
                            setState(() => _selectedCategoryId = cat.id),
                        onLongPress: () => _showDeleteCategoryDialog(cat),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.fromLTRB(8, 2, 8, 2),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: sel
                                ? AppColors.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(cat.name,
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 13,
                                  fontWeight: sel
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: sel
                                      ? Colors.white
                                      : AppColors.textSecondary)),
                        ),
                      );
                    }),
                  ],
                ),
              ),

              const VerticalDivider(width: 1),

              Expanded(
                child: _filtered.isEmpty
                    ? const Center(
                        child: Text('Belum ada menu di kategori ini',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                color: AppColors.textSecondary)))
                    : GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 220,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.68,
                        ),
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) {
                          final item = _filtered[i];
                          return _MenuItemCard(
                            item: item,
                            onToggle: () =>
                                _toggleAvailability(item.id, item.isAvailable),
                          );
                        },
                      ),
              ),
            ]),
    );
  }
}

class _MenuItemCard extends StatelessWidget {
  final MenuItem item;
  final VoidCallback onToggle;

  const _MenuItemCard({required this.item, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          height: 120,
          width: double.infinity,
          child: item.imageUrl != null && item.imageUrl!.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: item.imageUrl!,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    color: Colors.grey[200],
                    child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  errorWidget: (_, __, ___) => _imagePlaceholder(),
                )
              : _imagePlaceholder(),
        ),

        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(item.name,
                          style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                              fontSize: 13),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ),
                    Transform.scale(
                      scale: 0.8,
                      child: Switch(
                        value: item.isAvailable,
                        // FIX 3: 'activeColor' → 'activeThumbColor' (deprecated after v3.31.0-2.0.pre)
                        activeThumbColor: AppColors.available,
                        onChanged: (_) => onToggle(),
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ]),
                  if (item.description != null &&
                      item.description!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(item.description!,
                        style: AppTextStyles.caption,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                  const Spacer(),
                  Text(
                    'Rp ${_formatPrice(item.price)}',
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.accent),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: (item.isAvailable
                              ? AppColors.available
                              : AppColors.textHint)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      item.isAvailable ? 'Tersedia' : 'Habis',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: item.isAvailable
                              ? AppColors.available
                              : AppColors.textHint),
                    ),
                  ),
                ]),
          ),
        ),
      ]),
    );
  }

  Widget _imagePlaceholder() => Container(
        color: Colors.grey[100],
        child: Center(
          child: Icon(Icons.fastfood_outlined,
              size: 40, color: Colors.grey[400]),
        ),
      );

  String _formatPrice(double price) => price
      .toStringAsFixed(0)
      .replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
}