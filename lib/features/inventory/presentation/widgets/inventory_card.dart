// lib/features/inventory/presentation/widgets/inventory_card.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/inventory_item.dart';
import 'inventory_detail_sheet.dart';

class InventoryCard extends ConsumerWidget {
  final InventoryItem item;
  const InventoryCard({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    if (item.isOutOfStock) {
      statusColor = Colors.red.shade500;
      statusLabel = 'Habis';
      statusIcon = Icons.remove_circle_outline;
    } else if (item.isLowStock) {
      statusColor = Colors.orange.shade600;
      statusLabel = 'Hampir Habis';
      statusIcon = Icons.warning_amber_rounded;
    } else {
      statusColor = Colors.green.shade600;
      statusLabel = 'Tersedia';
      statusIcon = Icons.check_circle_outline;
    }

    final stockPercent = item.minimumStock > 0
        ? (item.availableStock / (item.minimumStock * 3)).clamp(0.0, 1.0)
        : (item.availableStock > 0 ? 1.0 : 0.0);

    return GestureDetector(
      onTap: () => _openDetail(context),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: item.isOutOfStock
                ? Colors.red.withValues(alpha: 0.3)
                : item.isLowStock
                    ? Colors.orange.withValues(alpha: 0.3)
                    : colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.06),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(15)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.category,
                          style: TextStyle(
                            fontSize: 10,
                            color: colorScheme.onSurface.withValues(alpha: 0.5),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Status badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 10, color: statusColor),
                        const SizedBox(width: 3),
                        Text(
                          statusLabel,
                          style: TextStyle(
                            fontSize: 9,
                            color: statusColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Body - stock info
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Available stock (big number)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _formatQty(item.availableStock),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          item.unit,
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurface.withValues(alpha: 0.5),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'Stok Tersedia',
                    style: TextStyle(
                      fontSize: 9,
                      color: colorScheme.onSurface.withValues(alpha: 0.45),
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: stockPercent,
                      minHeight: 5,
                      backgroundColor:
                          colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Awal / Terpakai / Akhir
                  Row(
                    children: [
                      _MiniStat(
                        label: 'Awal',
                        value: _formatQty(item.openingStock),
                        unit: item.unit,
                        color: Colors.blue.shade400,
                      ),
                      const Spacer(),
                      _MiniStat(
                        label: 'Pakai',
                        value: _formatQty(item.usedStock),
                        unit: item.unit,
                        color: Colors.orange.shade500,
                        isNegative: true,
                      ),
                      const Spacer(),
                      _MiniStat(
                        label: 'Akhir',
                        value: _formatQty(item.closingStock),
                        unit: item.unit,
                        color: statusColor,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const Spacer(),

            // Footer - min stock warning
            if (item.minimumStock > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                child: Row(
                  children: [
                    Icon(
                      Icons.flag_outlined,
                      size: 10,
                      color: colorScheme.onSurface.withValues(alpha: 0.35),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      'Min: ${_formatQty(item.minimumStock)} ${item.unit}',
                      style: TextStyle(
                        fontSize: 9,
                        color: colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
              )
            else
              const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  String _formatQty(double qty) {
    if (qty == qty.truncateToDouble()) {
      return qty.toInt().toString();
    }
    return qty.toStringAsFixed(1);
  }

  void _openDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => InventoryDetailSheet(item: item),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;
  final bool isNegative;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    this.isNegative = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 1),
        RichText(
          text: TextSpan(
            children: [
              if (isNegative)
                TextSpan(
                  text: '-',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              TextSpan(
                text: value,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
