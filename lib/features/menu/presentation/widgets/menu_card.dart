// lib/features/menu/presentation/widgets/menu_card.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/menu_model.dart';
import '../../providers/menu_provider.dart';
import 'add_menu_form.dart';

class MenuCard extends ConsumerStatefulWidget {
  final Menu menu;

  const MenuCard({super.key, required this.menu});

  @override
  ConsumerState<MenuCard> createState() => _MenuCardState();
}

class _MenuCardState extends ConsumerState<MenuCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isToggling = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      lowerBound: 0.95,
      upperBound: 1.0,
      value: 1.0,
    );
    _scaleAnimation = _controller;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(_) => _controller.reverse();
  void _onTapUp(_) => _controller.forward();
  void _onTapCancel() => _controller.forward();

  Future<void> _handleToggle() async {
    if (_isToggling) return;
    setState(() => _isToggling = true);

    final success = await ref
        .read(menuProvider.notifier)
        .toggleAvailability(widget.menu.id, widget.menu.isAvailable);

    if (mounted) {
      setState(() => _isToggling = false);
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gagal mengubah status menu'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _handleEdit() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddMenuForm(existingMenu: widget.menu),
    );
  }

  void _handleDelete() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Menu?'),
        content: Text('Menu "${widget.menu.name}" akan dihapus permanen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () async {
              Navigator.pop(context);
              await ref
                  .read(menuProvider.notifier)
                  .deleteMenu(widget.menu.id);
            },
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  Color get _statusColor {
    return switch (widget.menu.status) {
      MenuStatus.available => Colors.green,
      MenuStatus.outOfStock => Colors.red,
      MenuStatus.seasonal => Colors.orange,
    };
  }

  String get _statusLabel {
    return switch (widget.menu.status) {
      MenuStatus.available => 'Tersedia',
      MenuStatus.outOfStock => 'Habis',
      MenuStatus.seasonal => 'Musiman',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final menu = widget.menu;

    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) => Transform.scale(
          scale: _scaleAnimation.value,
          child: child,
        ),
        child: Card(
          elevation: 2,
          shadowColor: colorScheme.shadow.withOpacity(0.15),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: menu.isAvailable
                  ? Colors.transparent
                  : Colors.red.shade200,
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Image ──
              _MenuImage(imageUrl: menu.imageUrl, isAvailable: menu.isAvailable),

              // ── Content ──
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Status Badge
                      _StatusBadge(
                        label: _statusLabel,
                        color: _statusColor,
                      ),
                      const SizedBox(height: 4),

                      // Name
                      Text(
                        menu.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),

                      // Description
                      Expanded(
                        child: Text(
                          menu.description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurface.withOpacity(0.6),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                      // Price + Actions
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            'Rp ${_formatPrice(menu.price)}',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Row(
                            children: [
                              _IconBtn(
                                icon: Icons.edit_outlined,
                                color: colorScheme.secondary,
                                onTap: _handleEdit,
                                tooltip: 'Edit',
                              ),
                              const SizedBox(width: 4),
                              _IconBtn(
                                icon: Icons.delete_outline,
                                color: Colors.red.shade400,
                                onTap: _handleDelete,
                                tooltip: 'Hapus',
                              ),
                            ],
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      // Toggle Availability
                      _AvailabilityToggle(
                        isAvailable: menu.isAvailable,
                        isLoading: _isToggling,
                        onToggle: _handleToggle,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatPrice(double price) {
    return price.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
        );
  }
}

// ─── SUB-WIDGETS ──────────────────────────────────────────────────────────────

class _MenuImage extends StatelessWidget {
  final String? imageUrl;
  final bool isAvailable;

  const _MenuImage({this.imageUrl, required this.isAvailable});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          imageUrl != null && imageUrl!.isNotEmpty
              ? Image.network(
                  imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _PlaceholderImage(),
                )
              : _PlaceholderImage(),
          if (!isAvailable)
            Container(
              color: Colors.black.withOpacity(0.45),
              child: const Center(
                child: Icon(Icons.block, color: Colors.white54, size: 32),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlaceholderImage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceVariant,
      child: Icon(
        Icons.restaurant,
        size: 36,
        color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.4),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color.withOpacity(0.9),
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;

  const _IconBtn({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}

class _AvailabilityToggle extends StatelessWidget {
  final bool isAvailable;
  final bool isLoading;
  final VoidCallback onToggle;

  const _AvailabilityToggle({
    required this.isAvailable,
    required this.isLoading,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isAvailable
              ? Colors.green.withOpacity(0.1)
              : Colors.red.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                isAvailable ? Icons.check_circle : Icons.cancel_outlined,
                size: 14,
                color: isAvailable ? Colors.green : Colors.red,
              ),
            const SizedBox(width: 4),
            Text(
              isAvailable ? 'Aktif' : 'Nonaktif',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isAvailable ? Colors.green.shade700 : Colors.red.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
