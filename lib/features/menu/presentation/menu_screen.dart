import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
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
  String? _staffRole;
  bool _isLoading = true;
  bool _initialized = false;

  // Role yang boleh edit/tambah/hapus menu
  bool get _canEdit =>
      _staffRole == 'superadmin' || _staffRole == 'manager';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    final staff = ref.read(currentStaffProvider);
    if (staff != null) {
      _branchId  = staff.branchId;
      _staffRole = staff.role.name;
      _initialized = true;
      _init();
    } else {
      _initialized = true;
      ref.listenManual(currentStaffProvider, (_, next) {
        if (next != null && _branchId == null && mounted) {
          setState(() {
            _branchId  = next.branchId;
            _staffRole = next.role.name;
          });
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

  // ─── Tambah Kategori ────────────────────────────────────────────────────────

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
              if (nameCtrl.text.trim().isEmpty) { return; }
              try {
                await Supabase.instance.client.from('menu_categories').insert({
                  'branch_id': _branchId,
                  'name': nameCtrl.text.trim(),
                  'sort_order': _categories.length + 1,
                  'is_active': true,
                });
                if (ctx.mounted) Navigator.pop(ctx);
                await _load();
              } on PostgrestException catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                    content: Text('Gagal menyimpan: ${e.message}'),
                    backgroundColor: Colors.red,
                  ));
                }
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                    content: Text('Error: $e'),
                    backgroundColor: Colors.red,
                  ));
                }
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  // ─── Hapus Kategori ─────────────────────────────────────────────────────────

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
              try {
                await Supabase.instance.client
                    .from('menu_categories')
                    .delete()
                    .eq('id', cat.id);
                if (ctx.mounted) Navigator.pop(ctx);
                setState(() => _selectedCategoryId = null);
                await _load();
              } on PostgrestException catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                    content: Text('Gagal menghapus: ${e.message}'),
                    backgroundColor: Colors.red,
                  ));
                }
              }
            },
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  // ─── Edit Kategori ──────────────────────────────────────────────────────────

  Future<void> _showEditCategoryDialog(MenuCategory cat) async {
    final nameCtrl = TextEditingController(text: cat.name);
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Kategori',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nama Kategori *',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            onPressed: () async {
              final newName = nameCtrl.text.trim();
              if (newName.isEmpty) return;
              try {
                await Supabase.instance.client
                    .from('menu_categories')
                    .update({'name': newName})
                    .eq('id', cat.id);
                if (ctx.mounted) Navigator.pop(ctx);
                await _load();
              } on PostgrestException catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                    content: Text('Gagal menyimpan: ${e.message}'),
                    backgroundColor: Colors.red,
                  ));
                }
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                    content: Text('Error: $e'),
                    backgroundColor: Colors.red,
                  ));
                }
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    nameCtrl.dispose();
  }

  // ─── Opsi Kategori (Edit / Hapus) ──────────────────────────────────────────

  void _showCategoryOptions(MenuCategory cat) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                cat.name,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: 15),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: AppColors.primary),
              title: const Text('Edit Nama Kategori',
                  style: TextStyle(fontFamily: 'Poppins')),
              onTap: () {
                Navigator.pop(ctx);
                _showEditCategoryDialog(cat);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.accent),
              title: const Text('Hapus Kategori',
                  style: TextStyle(fontFamily: 'Poppins')),
              onTap: () {
                Navigator.pop(ctx);
                _showDeleteCategoryDialog(cat);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ─── Tambah Menu ────────────────────────────────────────────────────────────

  Future<void> _showAddItemDialog() async {
    final nameCtrl    = TextEditingController();
    final priceCtrl   = TextEditingController();
    final descCtrl    = TextEditingController();
    String? selCatId  = _selectedCategoryId;
    String? imageUrlResult;

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          title: const Text('Tambah Menu',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
          content: _MenuItemForm(
            nameCtrl:  nameCtrl,
            priceCtrl: priceCtrl,
            descCtrl:  descCtrl,
            selCatId:  selCatId,
            categories: _categories,
            onCatChanged:      (v) => ss(() => selCatId      = v),
            onImageUrlChanged: (v) => ss(() => imageUrlResult = v),
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
                    priceCtrl.text.trim().isEmpty) { return; }
                try {
                  await Supabase.instance.client.from('menu_items').insert({
                    'branch_id':   _branchId,
                    'category_id': selCatId,
                    'name':        nameCtrl.text.trim(),
                    'price':       double.tryParse(priceCtrl.text.trim()) ?? 0,
                    'description': descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                    'image_url':   imageUrlResult,
                    'is_available': true,
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _load();
                } on PostgrestException catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                      content: Text('Gagal menyimpan: ${e.message}'),
                      backgroundColor: Colors.red,
                    ));
                  }
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Edit Menu ──────────────────────────────────────────────────────────────

  Future<void> _showEditItemDialog(MenuItem item) async {
    final nameCtrl  = TextEditingController(text: item.name);
    final priceCtrl = TextEditingController(text: item.price.toStringAsFixed(0));
    final descCtrl  = TextEditingController(text: item.description ?? '');
    String? selCatId      = item.categoryId;
    String? imageUrlResult = item.imageUrl?.isNotEmpty == true ? item.imageUrl : null;

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          title: const Text('Edit Menu',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
          content: _MenuItemForm(
            nameCtrl:  nameCtrl,
            priceCtrl: priceCtrl,
            descCtrl:  descCtrl,
            selCatId:  selCatId,
            initialImageUrl: item.imageUrl,
            categories: _categories,
            onCatChanged:      (v) => ss(() => selCatId      = v),
            onImageUrlChanged: (v) => ss(() => imageUrlResult = v),
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
                    priceCtrl.text.trim().isEmpty) { return; }
                try {
                  await Supabase.instance.client
                      .from('menu_items')
                      .update({
                        'category_id': selCatId,
                        'name':        nameCtrl.text.trim(),
                        'price':       double.tryParse(priceCtrl.text.trim()) ?? 0,
                        'description': descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                        'image_url':   imageUrlResult,
                      })
                      .eq('id', item.id);
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _load();
                } on PostgrestException catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                      content: Text('Gagal menyimpan: ${e.message}'),
                      backgroundColor: Colors.red,
                    ));
                  }
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Hapus Menu ─────────────────────────────────────────────────────────────

  Future<void> _showDeleteItemDialog(MenuItem item) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Menu?',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
        content: Text(
          'Hapus "${item.name}" dari daftar menu?',
          style: const TextStyle(fontFamily: 'Poppins'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              try {
                await Supabase.instance.client
                    .from('menu_items')
                    .delete()
                    .eq('id', item.id);
                if (ctx.mounted) Navigator.pop(ctx);
                await _load();
              } on PostgrestException catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                    content: Text('Gagal menghapus: ${e.message}'),
                    backgroundColor: Colors.red,
                  ));
                }
              }
            },
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

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
      floatingActionButton: _canEdit
          ? FloatingActionButton.extended(
              onPressed: _showAddItemDialog,
              backgroundColor: AppColors.accent,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('Tambah Menu',
                  style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600)),
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Row(children: [
              // ── Sidebar Kategori ──────────────────────────────────────────
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
                        if (_canEdit)
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
                      onTap: () => setState(() => _selectedCategoryId = null),
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
                        onTap: () => setState(() => _selectedCategoryId = cat.id),
                        onLongPress: _canEdit
                            ? () => _showCategoryOptions(cat)
                            : null,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.fromLTRB(8, 2, 8, 2),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: sel ? AppColors.primary : Colors.transparent,
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

              // ── Grid Menu ─────────────────────────────────────────────────
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
                            item:     item,
                            canEdit:  _canEdit,
                            onToggle: () =>
                                _toggleAvailability(item.id, item.isAvailable),
                            onEdit:   () => _showEditItemDialog(item),
                            onDelete: () => _showDeleteItemDialog(item),
                          );
                        },
                      ),
              ),
            ]),
    );
  }
}

// ─── Reusable Form Widget (dipakai di Add & Edit) ─────────────────────────────

class _MenuItemForm extends StatefulWidget {
  final TextEditingController nameCtrl, priceCtrl, descCtrl;
  final String? selCatId;
  final String? initialImageUrl;
  final List<MenuCategory> categories;
  final ValueChanged<String?> onCatChanged;
  final ValueChanged<String?> onImageUrlChanged;

  const _MenuItemForm({
    required this.nameCtrl,
    required this.priceCtrl,
    required this.descCtrl,
    required this.selCatId,
    required this.categories,
    required this.onCatChanged,
    required this.onImageUrlChanged,
    this.initialImageUrl,
  });

  @override
  State<_MenuItemForm> createState() => _MenuItemFormState();
}

class _MenuItemFormState extends State<_MenuItemForm> {
  // 0 = pilih, 1 = upload file, 2 = url
  int _imageMode = 0;
  final _urlCtrl = TextEditingController();
  String? _previewUrl;
  bool       _isUploading = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialImageUrl != null && widget.initialImageUrl!.isNotEmpty) {
      _previewUrl = widget.initialImageUrl;
      _imageMode  = 2;
      _urlCtrl.text = widget.initialImageUrl!;
      // Beritahu parent URL awal
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onImageUrlChanged(widget.initialImageUrl);
      });
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true, // required for web — loads bytes directly
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Gagal membaca file. Coba lagi.'),
          backgroundColor: Colors.red,
        ));
      }
      return;
    }

    final ext = file.extension ?? 'jpg';
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';

    setState(() => _isUploading = true);

    try {
      await Supabase.instance.client.storage
          .from('menu-images')
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: FileOptions(
              contentType: 'image/$ext',
              upsert: true,
            ),
          );

      final publicUrl = Supabase.instance.client.storage
          .from('menu-images')
          .getPublicUrl(fileName);

      setState(() {
        _previewUrl  = publicUrl;
        _isUploading = false;
      });
      widget.onImageUrlChanged(publicUrl);
    } catch (e) {
      setState(() => _isUploading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal upload: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      width: 400,
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [

          // ── Area Gambar ─────────────────────────────────────────────
          _buildImageSection(cs),
          const SizedBox(height: 16),

          // Nama
          TextField(
            controller: widget.nameCtrl,
            decoration: const InputDecoration(labelText: 'Nama Menu *'),
          ),
          const SizedBox(height: 12),

          // Harga
          TextField(
            controller: widget.priceCtrl,
            decoration: const InputDecoration(
                labelText: 'Harga *', prefixText: 'Rp '),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),

          // Deskripsi
          TextField(
            controller: widget.descCtrl,
            decoration: const InputDecoration(labelText: 'Deskripsi'),
            maxLines: 2,
          ),
          const SizedBox(height: 12),

          // Dropdown Kategori
          DropdownButtonFormField<String>(
            initialValue: widget.selCatId,
            decoration: const InputDecoration(labelText: 'Kategori'),
            items: widget.categories.map((c) => DropdownMenuItem(
              value: c.id,
              child: Text(c.name,
                  style: const TextStyle(fontFamily: 'Poppins')),
            )).toList(),
            onChanged: widget.onCatChanged,
          ),
        ]),
      ),
    );
  }

  Widget _buildImageSection(ColorScheme cs) {
    // Preview jika ada
    Widget preview = _previewUrl != null
        ? ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            child: Stack(children: [
              CachedNetworkImage(
                imageUrl: _previewUrl!,
                height:   150,
                width:    double.infinity,
                fit:      BoxFit.cover,
                errorWidget: (_, __, ___) => _imagePlaceholderBox(cs),
              ),
              // Tombol ganti foto
              Positioned(
                top: 8, right: 8,
                child: GestureDetector(
                  onTap: () => setState(() {
                    _previewUrl = null;
                    _imageMode  = 0;
                    _urlCtrl.clear();
                    widget.onImageUrlChanged(null);
                  }),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                        color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(Icons.close, size: 16, color: Colors.white),
                  ),
                ),
              ),
            ]),
          )
        : const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        border:       Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_previewUrl != null) preview,

        if (_isUploading)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(),
              SizedBox(height: 8),
              Text('Mengupload gambar...', style: TextStyle(fontFamily: 'Poppins', fontSize: 12)),
            ]),
          )
        else if (_imageMode == 0 || _previewUrl == null) ...[
          // Mode pilih: dua tombol
          if (_previewUrl == null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Pilih gambar', style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 10),
                Row(children: [
                  // Tombol Upload
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() => _imageMode = 1);
                        _pickAndUpload();
                      },
                      icon:  const Icon(Icons.upload_file_outlined, size: 18),
                      label: const Text('Upload File',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Tombol URL
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() => _imageMode = 2),
                      icon:  const Icon(Icons.link, size: 18),
                      label: const Text('Pakai URL',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 12)),
                    ),
                  ),
                ]),
              ]),
            ),

          // Mode URL: tampilkan input
          if (_imageMode == 2 && _previewUrl == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _urlCtrl,
                    decoration: const InputDecoration(
                      labelText: 'URL Gambar',
                      hintText:  'Paste URL lalu tekan Enter atau OK',
                      isDense:   true,
                    ),
                    // Auto-apply saat tekan Enter
                    onSubmitted: (url) {
                      url = url.trim();
                      if (url.isEmpty) return;
                      setState(() => _previewUrl = url);
                      widget.onImageUrlChanged(url);
                    },
                    // Auto-apply saat paste (setelah field tidak aktif)
                    onTapOutside: (_) {
                      final url = _urlCtrl.text.trim();
                      if (url.isNotEmpty && _previewUrl == null) {
                        setState(() => _previewUrl = url);
                        widget.onImageUrlChanged(url);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                  onPressed: () {
                    final url = _urlCtrl.text.trim();
                    if (url.isEmpty) return;
                    setState(() => _previewUrl = url);
                    widget.onImageUrlChanged(url);
                  },
                  child: const Text('OK', style: TextStyle(fontFamily: 'Poppins')),
                ),
              ]),
            ),
        ],
      ]),
    );
  }

  Widget _imagePlaceholderBox(ColorScheme cs) => Container(
        height: 150,
        color: cs.surfaceContainerHighest,
        child: Center(
          child: Icon(Icons.broken_image_outlined,
              size: 40, color: cs.onSurfaceVariant),
        ),
      );
}

// ─── Menu Item Card ───────────────────────────────────────────────────────────

class _MenuItemCard extends StatelessWidget {
  final MenuItem item;
  final bool canEdit;
  final VoidCallback onToggle, onEdit, onDelete;

  const _MenuItemCard({
    required this.item,
    required this.canEdit,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Gambar + overlay tombol edit/delete ──────────────────────────
        SizedBox(
          height: 120,
          width: double.infinity,
          child: Stack(fit: StackFit.expand, children: [
            item.imageUrl != null && item.imageUrl!.isNotEmpty
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

            // Tombol edit & delete hanya muncul kalau _canEdit
            if (canEdit)
              Positioned(
                top: 6, right: 6,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _OverlayIconBtn(
                    icon:    Icons.edit_outlined,
                    color:   Colors.blue,
                    tooltip: 'Edit',
                    onTap:   onEdit,
                  ),
                  const SizedBox(width: 4),
                  _OverlayIconBtn(
                    icon:    Icons.delete_outline,
                    color:   Colors.red,
                    tooltip: 'Hapus',
                    onTap:   onDelete,
                  ),
                ]),
              ),
          ]),
        ),

        // ── Konten card ──────────────────────────────────────────────────
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
                        activeThumbColor: AppColors.available,
                        onChanged: canEdit ? (_) => onToggle() : null,
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

// ─── Overlay Icon Button (di atas gambar card) ────────────────────────────────

class _OverlayIconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _OverlayIconBtn({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 30, height: 30,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 4)
            ],
          ),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }
}