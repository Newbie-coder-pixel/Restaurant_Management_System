// lib/features/menu/presentation/widgets/add_menu_form.dart

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/menu_model.dart';
import '../../providers/menu_provider.dart';

class AddMenuForm extends ConsumerStatefulWidget {
  /// Jika diisi, form berfungsi sebagai edit mode.
  final Menu? existingMenu;

  const AddMenuForm({super.key, this.existingMenu});

  @override
  ConsumerState<AddMenuForm> createState() => _AddMenuFormState();
}

class _AddMenuFormState extends ConsumerState<AddMenuForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _priceCtrl;

  MenuCategory _selectedCategory = MenuCategory.food;

  // Mobile: gunakan File; Web: gunakan Uint8List
  File? _selectedImageFile;
  Uint8List? _selectedImageBytes;

  bool _isLoading = false;
  String? _imageError;

  bool get _isEdit => widget.existingMenu != null;

  @override
  void initState() {
    super.initState();
    final menu = widget.existingMenu;
    _nameCtrl = TextEditingController(text: menu?.name ?? '');
    _descCtrl = TextEditingController(text: menu?.description ?? '');
    _priceCtrl = TextEditingController(
      text: menu?.price.toStringAsFixed(0) ?? '',
    );
    if (menu != null) _selectedCategory = menu.category;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      if (kIsWeb) {
        // Web: gunakan file_picker
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          withData: true,
        );
        if (result != null && result.files.isNotEmpty) {
          final bytes = result.files.first.bytes;
          if (bytes != null) {
            setState(() {
              _selectedImageBytes = bytes;
              _selectedImageFile = null;
              _imageError = null;
            });
          }
        }
      } else {
        // Mobile: gunakan image_picker
        final picker = ImagePicker();
        final source = await _showImageSourcePicker();
        if (source == null) return;

        final picked = await picker.pickImage(
          source: source,
          imageQuality: 80,
          maxWidth: 1024,
        );
        if (picked != null) {
          setState(() {
            _selectedImageFile = File(picked.path);
            _selectedImageBytes = null;
            _imageError = null;
          });
        }
      }
    } catch (e) {
      setState(() => _imageError = 'Gagal memilih gambar');
    }
  }

  Future<ImageSource?> _showImageSourcePicker() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Pilih Sumber Gambar',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.camera_alt)),
                title: const Text('Kamera'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading:
                    const CircleAvatar(child: Icon(Icons.photo_library)),
                title: const Text('Galeri Foto'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final price = double.tryParse(
          _priceCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''),
        ) ??
        0;

    // Tentukan image yang akan diupload (File atau Uint8List)
    final dynamic imageToUpload =
        _selectedImageFile ?? _selectedImageBytes;

    bool success;

    if (_isEdit) {
      success = await ref.read(menuProvider.notifier).updateMenu(
            menu: widget.existingMenu!.copyWith(
              name: _nameCtrl.text.trim(),
              description: _descCtrl.text.trim(),
              price: price,
              category: _selectedCategory,
            ),
            newImageFile: imageToUpload,
          );
    } else {
      success = await ref.read(menuProvider.notifier).addMenu(
            name: _nameCtrl.text.trim(),
            description: _descCtrl.text.trim(),
            price: price,
            category: _selectedCategory,
            imageFile: imageToUpload,
          );
    }

    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEdit
                ? 'Menu berhasil diperbarui!'
                : 'Menu berhasil ditambahkan!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Terjadi kesalahan, coba lagi.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mq = MediaQuery.of(context);

    return Container(
      height: mq.size.height * 0.92,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.onSurface.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _isEdit ? 'Edit Menu' : 'Tambah Menu Baru',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 24),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                  20, 0, 20, mq.viewInsets.bottom + 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Image Picker
                    _ImagePickerSection(
                      selectedImageFile: _selectedImageFile,
                      selectedImageBytes: _selectedImageBytes,
                      existingImageUrl:
                          _isEdit ? widget.existingMenu?.imageUrl : null,
                      errorText: _imageError,
                      onTap: _pickImage,
                    ),
                    const SizedBox(height: 20),

                    // Name
                    const _FormLabel('Nama Menu'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _nameCtrl,
                      decoration:
                          _inputDecoration('Contoh: Nasi Goreng Spesial'),
                      textCapitalization: TextCapitalization.words,
                      validator: (v) => (v?.trim().isEmpty ?? true)
                          ? 'Nama wajib diisi'
                          : null,
                    ),
                    const SizedBox(height: 16),

                    // Description
                    const _FormLabel('Deskripsi'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _descCtrl,
                      decoration:
                          _inputDecoration('Ceritakan menu ini...'),
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: 16),

                    // Price
                    const _FormLabel('Harga'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _priceCtrl,
                      decoration: _inputDecoration('Contoh: 25000').copyWith(
                        prefixText: 'Rp ',
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Harga wajib diisi';
                        }
                        final num = double.tryParse(
                            v.replaceAll(RegExp(r'[^0-9]'), ''));
                        if (num == null || num <= 0) {
                          return 'Harga tidak valid';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Category
                    const _FormLabel('Kategori'),
                    const SizedBox(height: 8),
                    _CategorySelector(
                      selected: _selectedCategory,
                      onChanged: (c) =>
                          setState(() => _selectedCategory = c),
                    ),
                    const SizedBox(height: 32),

                    // Submit
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: _isLoading ? null : _handleSubmit,
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2.5),
                              )
                            : Text(
                                _isEdit
                                    ? 'Simpan Perubahan'
                                    : 'Tambahkan Menu',
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor:
          Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.primary,
          width: 2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 1.5),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}

// ─── SUB-WIDGETS ──────────────────────────────────────────────────────────────

class _FormLabel extends StatelessWidget {
  final String text;
  const _FormLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context)
          .textTheme
          .labelLarge
          ?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _ImagePickerSection extends StatelessWidget {
  final File? selectedImageFile;
  final Uint8List? selectedImageBytes;
  final String? existingImageUrl;
  final String? errorText;
  final VoidCallback onTap;

  const _ImagePickerSection({
    this.selectedImageFile,
    this.selectedImageBytes,
    this.existingImageUrl,
    this.errorText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget imageContent;

    if (selectedImageBytes != null) {
      // Web preview
      imageContent = Stack(fit: StackFit.expand, children: [
        Image.memory(selectedImageBytes!, fit: BoxFit.cover),
        const Positioned(bottom: 8, right: 8, child: _EditBadge()),
      ]);
    } else if (selectedImageFile != null) {
      // Mobile preview
      imageContent = Stack(fit: StackFit.expand, children: [
        Image.file(selectedImageFile!, fit: BoxFit.cover),
        const Positioned(bottom: 8, right: 8, child: _EditBadge()),
      ]);
    } else if (existingImageUrl != null && existingImageUrl!.isNotEmpty) {
      // Existing image from Supabase
      imageContent = Stack(fit: StackFit.expand, children: [
        Image.network(existingImageUrl!, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const _EmptyImagePlaceholder()),
        const Positioned(bottom: 8, right: 8, child: _EditBadge()),
      ]);
    } else {
      imageContent = const _EmptyImagePlaceholder();
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 160,
        width: double.infinity,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: errorText != null
                ? Colors.red
                : colorScheme.outline.withValues(alpha: 0.3),
            width: errorText != null ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: imageContent,
      ),
    );
  }
}

class _EmptyImagePlaceholder extends StatelessWidget {
  const _EmptyImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.add_photo_alternate_outlined,
          size: 40,
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
        ),
        const SizedBox(height: 8),
        Text(
          'Tambah Foto Menu',
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          kIsWeb ? 'Ketuk untuk memilih file' : 'Ketuk untuk memilih',
          style: TextStyle(
            fontSize: 12,
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}

class _EditBadge extends StatelessWidget {
  const _EditBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.edit, color: Colors.white, size: 12),
          SizedBox(width: 4),
          Text('Ganti',
              style: TextStyle(color: Colors.white, fontSize: 11)),
        ],
      ),
    );
  }
}

class _CategorySelector extends StatelessWidget {
  final MenuCategory selected;
  final ValueChanged<MenuCategory> onChanged;

  const _CategorySelector(
      {required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    const categories = [
      (MenuCategory.food, '🍛', 'Makanan'),
      (MenuCategory.drinks, '🥤', 'Minuman'),
      (MenuCategory.dessert, '🍰', 'Dessert'),
      (MenuCategory.snack, '🍟', 'Snack'),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: categories.map((item) {
        final (category, emoji, label) = item;
        final isSelected = selected == category;
        return GestureDetector(
          onTap: () => onChanged(category),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? colorScheme.onPrimary
                        : colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}