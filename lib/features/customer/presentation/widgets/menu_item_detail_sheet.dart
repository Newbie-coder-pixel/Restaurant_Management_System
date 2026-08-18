// Item-detail bottom sheet — lets a customer pick a spice level and/or paid
// add-ons before adding a menu item to the cart. Both sections are omitted
// when the item has none configured (`menu_items.spice_levels`/`add_ons`,
// see migration 20260808020000), which is still the case for every item
// today, so this degrades to a plain image/description/qty/Add-to-Cart view.
import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../providers/cart_provider.dart';

class MenuItemDetailSheet extends StatefulWidget {
  final Map<String, dynamic> item;
  final void Function(CartItem item) onAddToCart;

  const MenuItemDetailSheet({
    super.key,
    required this.item,
    required this.onAddToCart,
  });

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> item,
    required void Function(CartItem item) onAddToCart,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MenuItemDetailSheet(item: item, onAddToCart: onAddToCart),
    );
  }

  @override
  State<MenuItemDetailSheet> createState() => _MenuItemDetailSheetState();
}

class _MenuItemDetailSheetState extends State<MenuItemDetailSheet> {
  int _qty = 1;
  String? _spiceLevel;
  final Set<String> _selectedAddOns = {};

  List<String> get _spiceLevels =>
      List<String>.from(widget.item['spice_levels'] as List? ?? const []);

  List<Map<String, dynamic>> get _addOns => List<Map<String, dynamic>>.from(
    widget.item['add_ons'] as List? ?? const [],
  );

  @override
  void initState() {
    super.initState();
    if (_spiceLevels.isNotEmpty) _spiceLevel = _spiceLevels.first;
  }

  double get _basePrice => (widget.item['price'] as num?)?.toDouble() ?? 0;

  double get _addOnsTotal => _addOns
      .where((a) => _selectedAddOns.contains(a['name'] as String))
      .fold(0.0, (s, a) => s + (a['price'] as num).toDouble());

  double get _unitPrice => _basePrice + _addOnsTotal;

  void _confirmAdd() {
    widget.onAddToCart(
      CartItem(
        menuItemId: widget.item['id'] as String,
        name: widget.item['name'] as String,
        price: _basePrice,
        imageUrl: widget.item['image_url'] as String?,
        quantity: _qty,
        spiceLevel: _spiceLevel,
        addOns: _addOns
            .where((a) => _selectedAddOns.contains(a['name'] as String))
            .map(
              (a) => CartAddOn(
                name: a['name'] as String,
                price: (a['price'] as num).toDouble(),
              ),
            )
            .toList(),
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final name = item['name'] as String? ?? '';
    final desc = item['description'] as String? ?? '';

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: AspectRatio(
                        aspectRatio: 1.1,
                        child: item['image_url'] != null
                            ? Image.network(
                                item['image_url'],
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _placeholder(),
                              )
                            : _placeholder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      name,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (desc.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        desc,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          fontStyle: FontStyle.italic,
                          color: AppColors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Text(
                      'Rp${_fmt(_basePrice)}',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Divider(color: AppColors.border, height: 1),
                    if (_spiceLevels.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _sectionLabel('SPICE LEVEL'),
                      const SizedBox(height: 10),
                      ..._spiceLevels.map(_radioRow),
                    ],
                    if (_addOns.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _sectionLabel('ADD-ONS'),
                      const SizedBox(height: 10),
                      ..._addOns.map(
                        (a) => _checkboxRow(
                          a['name'] as String,
                          (a['price'] as num).toDouble(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _buildBottomBar(),
            ],
          ),
        );
      },
    );
  }

  Widget _placeholder() => Container(
    color: AppColors.surfaceVariant,
    alignment: Alignment.center,
    child: const Icon(
      Icons.restaurant_rounded,
      size: 56,
      color: AppColors.textHint,
    ),
  );

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(
      fontFamily: 'Poppins',
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
      color: AppColors.textSecondary,
    ),
  );

  Widget _radioRow(String label) {
    final selected = _spiceLevel == label;
    return GestureDetector(
      onTap: () => setState(() => _spiceLevel = label),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.border,
                  width: 1.5,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _checkboxRow(String label, double price) {
    final selected = _selectedAddOns.contains(label);
    return GestureDetector(
      onTap: () => setState(() {
        if (selected) {
          _selectedAddOns.remove(label);
        } else {
          _selectedAddOns.add(label);
        }
      }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '+ Rp${_fmt(price)}',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: selected ? AppColors.primary : Colors.transparent,
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.border,
                  width: 1.5,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        16 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_addOnsTotal > 0 || _qty > 1) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  'Rp${_fmt(_unitPrice * _qty)}',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    _stepBtn(
                      Icons.remove,
                      () => setState(() => _qty = _qty > 1 ? _qty - 1 : 1),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Text(
                        '$_qty',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    _stepBtn(Icons.add, () => setState(() => _qty++)),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: GestureDetector(
                  onTap: _confirmAdd,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'ADD TO CART',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            letterSpacing: 0.5,
                          ),
                        ),
                        SizedBox(width: 8),
                        Icon(
                          Icons.arrow_forward,
                          color: Colors.white,
                          size: 15,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      child: Icon(icon, size: 16, color: AppColors.textPrimary),
    ),
  );

  String _fmt(double v) {
    final s = v.toStringAsFixed(0);
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write('.');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }
}
