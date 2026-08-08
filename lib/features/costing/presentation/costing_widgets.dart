// lib/features/costing/presentation/widgets/costing_widgets.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/costing_model.dart';
import '../../../core/theme/app_theme.dart';

// ─── IDR Formatter ──────────────────────────────────────────────────────────
final _idrFormat = NumberFormat('#,##0', 'id_ID');
final _pctFormat = NumberFormat('0.0', 'id_ID');

String formatIdr(double value) => 'Rp ${_idrFormat.format(value)}';
String formatPct(double value) => '${_pctFormat.format(value)}%';

// ─────────────────────────────────────────────────────────────────────────────
// Widget: Label + TextField for numeric input
// ─────────────────────────────────────────────────────────────────────────────
class CurrencyInputField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final ValueChanged<double> onChanged;
  final String? helperText;
  final IconData? prefixIcon;
  final Color? accentColor;
  final String? Function(String?)? validator;
  final bool isRequired;

  const CurrencyInputField({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
    required this.onChanged,
    this.helperText,
    this.prefixIcon,
    this.accentColor,
    this.validator,
    this.isRequired = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? AppColors.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            style: const TextStyle(
              fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
            children: [
              TextSpan(text: label),
              if (isRequired)
                const TextSpan(
                  text: ' *',
                  style: TextStyle(
                      color: AppColors.accent, fontWeight: FontWeight.w800),
                ),
            ],
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
          validator: validator,
          // The red warning is visible immediately when the screen opens, no
          // need to wait for the user to start typing.
          autovalidateMode: AutovalidateMode.always,
          style: const TextStyle(
            fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 15,
            color: AppColors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontFamily: 'Poppins', color: AppColors.textHint),
            prefixIcon: prefixIcon != null
                ? Icon(prefixIcon, size: 18, color: color)
                : const Padding(
                    padding: EdgeInsets.only(left: 12, right: 8),
                    child: Text('Rp',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700, fontSize: 13,
                            color: AppColors.textSecondary)),
                  ),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 0, minHeight: 0),
            helperText: helperText,
            helperStyle: const TextStyle(
              fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary),
            filled: true,
            fillColor: AppColors.surfaceVariant,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              borderSide: BorderSide(color: color, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              borderSide: const BorderSide(color: AppColors.accent, width: 1.3),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              borderSide: const BorderSide(color: AppColors.accent, width: 1.6),
            ),
            errorStyle: const TextStyle(
              fontFamily: 'Poppins',
              color: AppColors.accent,
              fontWeight: FontWeight.w600,
              fontSize: 12,
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
// Widget: Calculation Result Card (COGS, Margin, Recommendation)
// ─────────────────────────────────────────────────────────────────────────────
class CostingResultCard extends StatelessWidget {
  final CostingModel costing;

  const CostingResultCard({super.key, required this.costing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
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
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: const Icon(Icons.analytics_rounded,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 10),
              const Text(
                'Calculation Result',
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              _StatusChip(status: costing.pricingStatus),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 16),

          // Result grid
          Row(
            children: [
              _ResultTile(
                label: 'COGS',
                value: formatIdr(costing.hpp),
                sublabel: 'Cost of Goods Sold',
                icon: Icons.receipt_long_rounded,
                color: AppColors.accent,
              ),
              const SizedBox(width: 12),
              _ResultTile(
                label: 'Recommended Price',
                value: formatIdr(costing.recommendedSellingPriceRounded),
                sublabel: 'With ${costing.targetProfitMarginPercent.toStringAsFixed(0)}% margin',
                icon: Icons.price_check_rounded,
                color: AppColors.available,
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
                label: 'Actual Margin',
                value: formatPct(costing.actualProfitMarginPercent),
                sublabel: 'Profit per portion: ${formatIdr(costing.profitPerPortion)}',
                icon: Icons.trending_up_rounded,
                color: costing.actualProfitMarginPercent >=
                        costing.targetProfitMarginPercent
                    ? AppColors.available
                    : AppColors.accent,
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
    if (pct >= 28 && pct <= 35) return AppColors.available;
    if (pct < 28) return AppColors.accentOrange;
    if (pct <= 40) return const Color(0xFFE65100);
    return AppColors.accent;
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
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w800,
                color: color, fontSize: 15,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              sublabel,
              style: const TextStyle(
                fontFamily: 'Poppins', color: AppColors.textSecondary, fontSize: 10,
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
        color = AppColors.available;
        break;
      case CostingStatus.warning:
        color = AppColors.accentOrange;
        break;
      case CostingStatus.underpriced:
        color = AppColors.accent;
        break;
      default:
        color = AppColors.textHint;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        '${status.emoji} ${status.label}',
        style: TextStyle(
          fontFamily: 'Poppins', color: color, fontSize: 11, fontWeight: FontWeight.w700,
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
    final color = score >= 70
        ? AppColors.available
        : score >= 40
            ? AppColors.accentOrange
            : AppColors.accent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Financial Health Score',
              style: TextStyle(
                fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            Text(
              '$score / 100',
              style: TextStyle(
                fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w800,
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
            backgroundColor: AppColors.border,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget: Menu Card in the List
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
    Color statusColor;
    switch (costing.pricingStatus) {
      case CostingStatus.healthy:
        statusColor = AppColors.available;
        break;
      case CostingStatus.warning:
        statusColor = AppColors.accentOrange;
        break;
      case CostingStatus.underpriced:
        statusColor = AppColors.accent;
        break;
      default:
        statusColor = AppColors.textHint;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(
              color: statusColor.withValues(alpha: 0.35),
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
                      style: const TextStyle(
                        fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          'COGS: ${formatIdr(costing.hpp)}',
                          style: const TextStyle(
                            fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text('·', style: TextStyle(color: AppColors.textSecondary)),
                        const SizedBox(width: 8),
                        Text(
                          'FC: ${formatPct(costing.foodCostPercentage)}',
                          style: const TextStyle(
                            fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary,
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
                    style: const TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w800, fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatPct(costing.actualProfitMarginPercent),
                    style: TextStyle(
                      fontFamily: 'Poppins', color: statusColor, fontSize: 11, fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              if (onDelete != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.accent),
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.textPrimary,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Profitability Summary',
            style: TextStyle(
              fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _SummaryMetric(
                label: 'Est. Revenue/mo',
                value: formatIdr(summary.totalEstimatedMonthlyRevenue),
                color: Colors.white,
              ),
              const SizedBox(width: 16),
              _SummaryMetric(
                label: 'Est. Profit/mo',
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
                color: Colors.white,
              ),
              const SizedBox(width: 16),
              _SummaryMetric(
                label: 'Avg Margin',
                value: formatPct(summary.averageProfitMarginPercent),
                color: Colors.white,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Status distribution
          Row(
            children: [
              _StatusBadge(
                  label: '${summary.healthyItems} Healthy',
                  color: const Color(0xFF81C784)),
              const SizedBox(width: 8),
              _StatusBadge(
                  label: '${summary.warningItems} Review',
                  color: const Color(0xFFFFD54F)),
              const SizedBox(width: 8),
              _StatusBadge(
                  label: '${summary.underpricedItems} Loss',
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
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins', fontSize: 11, color: Colors.white.withValues(alpha: 0.65),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Poppins', fontWeight: FontWeight.w800, fontSize: 16, color: color,
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
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Poppins', color: color, fontSize: 11, fontWeight: FontWeight.w700,
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
    final c = color ?? AppColors.primary;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Icon(icon, color: c, size: 18),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
