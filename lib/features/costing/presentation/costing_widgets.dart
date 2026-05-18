// lib/features/costing/presentation/widgets/costing_widgets.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../models/costing_model.dart';

// ─── Formatter IDR ──────────────────────────────────────────────────────────
final _idrFormat = NumberFormat('#,##0', 'id_ID');
final _pctFormat = NumberFormat('0.0', 'id_ID');

String formatIdr(double value) => 'Rp ${_idrFormat.format(value)}';
String formatPct(double value) => '${_pctFormat.format(value)}%';

// ─────────────────────────────────────────────────────────────────────────────
// Widget: Label + TextField untuk input angka
// ─────────────────────────────────────────────────────────────────────────────
class CurrencyInputField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final ValueChanged<double> onChanged;
  final String? helperText;
  final IconData? prefixIcon;
  final Color? accentColor;

  const CurrencyInputField({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
    required this.onChanged,
    this.helperText,
    this.prefixIcon,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = accentColor ?? theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface.withOpacity(0.75),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
          ],
          onChanged: (v) => onChanged(double.tryParse(v) ?? 0),
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: prefixIcon != null
                ? Icon(prefixIcon, size: 18, color: color)
                : const Padding(
                    padding: EdgeInsets.only(left: 12, right: 8),
                    child: Text('Rp',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 0, minHeight: 0),
            helperText: helperText,
            helperStyle: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
            filled: true,
            fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.4),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: color, width: 1.5),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget: Kartu Hasil Kalkulasi (HPP, Margin, Rekomendasi)
// ─────────────────────────────────────────────────────────────────────────────
class CostingResultCard extends StatelessWidget {
  final CostingModel costing;

  const CostingResultCard({super.key, required this.costing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primaryContainer,
            theme.colorScheme.secondaryContainer,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.analytics_rounded,
                    color: theme.colorScheme.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                'Hasil Kalkulasi',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const Spacer(),
              _StatusChip(status: costing.pricingStatus),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // Grid hasil
          Row(
            children: [
              _ResultTile(
                label: 'HPP',
                value: formatIdr(costing.hpp),
                sublabel: 'Harga Pokok Penjualan',
                icon: Icons.receipt_long_rounded,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 12),
              _ResultTile(
                label: 'Rekomendasi Harga',
                value: formatIdr(costing.recommendedSellingPriceRounded),
                sublabel: 'Dengan margin ${costing.targetProfitMarginPercent.toStringAsFixed(0)}%',
                icon: Icons.price_check_rounded,
                color: const Color(0xFF2E7D32),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _ResultTile(
                label: 'Food Cost %',
                value: formatPct(costing.foodCostPercentage),
                sublabel: 'Ideal: 28–35%',
                icon: Icons.restaurant_rounded,
                color: _getFoodCostColor(costing.foodCostPercentage),
              ),
              const SizedBox(width: 12),
              _ResultTile(
                label: 'Margin Aktual',
                value: formatPct(costing.actualProfitMarginPercent),
                sublabel: 'Profit per porsi: ${formatIdr(costing.profitPerPortion)}',
                icon: Icons.trending_up_rounded,
                color: costing.actualProfitMarginPercent >=
                        costing.targetProfitMarginPercent
                    ? const Color(0xFF2E7D32)
                    : theme.colorScheme.error,
              ),
            ],
          ),

          // Health Score Bar
          const SizedBox(height: 16),
          _HealthScoreBar(score: costing.financialHealthScore),
        ],
      ),
    );
  }

  Color _getFoodCostColor(double pct) {
    if (pct >= 28 && pct <= 35) return const Color(0xFF2E7D32);
    if (pct < 28) return const Color(0xFFF9A825);
    if (pct <= 40) return const Color(0xFFE65100);
    return const Color(0xFFB71C1C);
  }
}

class _ResultTile extends StatelessWidget {
  final String label;
  final String value;
  final String sublabel;
  final IconData icon;
  final Color color;

  const _ResultTile({
    required this.label,
    required this.value,
    required this.sublabel,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withOpacity(0.75),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 6),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: color,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
            Text(
              sublabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final CostingStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case CostingStatus.healthy:
        color = const Color(0xFF2E7D32);
        break;
      case CostingStatus.warning:
        color = const Color(0xFFF9A825);
        break;
      case CostingStatus.underpriced:
        color = Theme.of(context).colorScheme.error;
        break;
      default:
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        '${status.emoji} ${status.label}',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _HealthScoreBar extends StatelessWidget {
  final int score;

  const _HealthScoreBar({required this.score});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = score >= 70
        ? const Color(0xFF2E7D32)
        : score >= 40
            ? const Color(0xFFF9A825)
            : theme.colorScheme.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Financial Health Score',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withOpacity(0.75),
              ),
            ),
            Text(
              '$score / 100',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: score / 100,
            minHeight: 6,
            backgroundColor: theme.colorScheme.outline.withOpacity(0.2),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget: Kartu Menu di Daftar
// ─────────────────────────────────────────────────────────────────────────────
class CostingListTile extends StatelessWidget {
  final CostingModel costing;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const CostingListTile({
    super.key,
    required this.costing,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color statusColor;
    switch (costing.pricingStatus) {
      case CostingStatus.healthy:
        statusColor = const Color(0xFF2E7D32);
        break;
      case CostingStatus.warning:
        statusColor = const Color(0xFFF9A825);
        break;
      case CostingStatus.underpriced:
        statusColor = theme.colorScheme.error;
        break;
      default:
        statusColor = Colors.grey;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: statusColor.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              // Status indicator
              Container(
                width: 4,
                height: 44,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      costing.menuItemName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          'HPP: ${formatIdr(costing.hpp)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('·',
                            style: TextStyle(
                                color: theme.colorScheme.outline)),
                        const SizedBox(width: 8),
                        Text(
                          'FC: ${formatPct(costing.foodCostPercentage)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Price & margin
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatIdr(costing.currentSellingPrice),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatPct(costing.actualProfitMarginPercent),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              if (onDelete != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      size: 18, color: theme.colorScheme.error),
                  onPressed: onDelete,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget: Summary Dashboard Card
// ─────────────────────────────────────────────────────────────────────────────
class CostingSummaryCard extends StatelessWidget {
  final CostingSummaryModel summary;

  const CostingSummaryCard({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.inverseSurface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ringkasan Profitabilitas',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onInverseSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _SummaryMetric(
                label: 'Est. Pendapatan/bln',
                value: formatIdr(summary.totalEstimatedMonthlyRevenue),
                color: theme.colorScheme.onInverseSurface,
              ),
              const SizedBox(width: 16),
              _SummaryMetric(
                label: 'Est. Profit/bln',
                value: formatIdr(summary.totalEstimatedMonthlyProfit),
                color: summary.totalEstimatedMonthlyProfit >= 0
                    ? const Color(0xFF81C784)
                    : const Color(0xFFEF9A9A),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _SummaryMetric(
                label: 'Avg Food Cost',
                value: formatPct(summary.averageFoodCostPercent),
                color: theme.colorScheme.onInverseSurface,
              ),
              const SizedBox(width: 16),
              _SummaryMetric(
                label: 'Avg Margin',
                value: formatPct(summary.averageProfitMarginPercent),
                color: theme.colorScheme.onInverseSurface,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Status distribution
          Row(
            children: [
              _StatusBadge(
                  label: '${summary.healthyItems} Sehat',
                  color: const Color(0xFF81C784)),
              const SizedBox(width: 8),
              _StatusBadge(
                  label: '${summary.warningItems} Review',
                  color: const Color(0xFFFFD54F)),
              const SizedBox(width: 8),
              _StatusBadge(
                  label: '${summary.underpricedItems} Rugi',
                  color: const Color(0xFFEF9A9A)),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onInverseSurface.withOpacity(0.6),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget: Section Header
// ─────────────────────────────────────────────────────────────────────────────
class CostingSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color? color;

  const CostingSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.primary;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: c.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: c, size: 18),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
          ],
        ),
      ],
    );
  }
}