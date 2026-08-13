import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/staff_shell.dart';
import '../../../shared/models/order_model.dart'; // ← added this
import '../providers/reports_provider.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});
  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  @override
  void initState() {
    super.initState();
    // Init the provider after the first frame finishes rendering
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(reportsProvider).init();
    });
  }

  final _topMenuSectionKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final notifier = ref.watch(reportsProvider);
    final s = notifier.state;

    return StaffShell(
      pageTitle: 'Reports',
      activeRoute: AppRoutes.reports,
      topBarActions: [
        if (s.isSuperAdmin)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border: Border.all(color: AppColors.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: s.selectedBranchId,
                  isDense: true,
                  icon: const Icon(Icons.keyboard_arrow_down,
                      size: 16, color: AppColors.textSecondary),
                  style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 12, color: AppColors.textPrimary),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All Branches',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 12))),
                    ...s.branches.map((b) => DropdownMenuItem<String?>(
                          value: b['id'] as String,
                          child: Text(b['name'] as String,
                              style: const TextStyle(fontFamily: 'Poppins', fontSize: 12)))),
                  ],
                  onChanged: (val) => notifier.selectBranch(val),
                ),
              ),
            ),
          ),
        _PeriodToggle(
          current: s.period,
          onChanged: (p) => notifier.selectPeriod(p),
        ),
        const SizedBox(width: 8),
        IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
            onPressed: notifier.load),
      ],
      body: s.isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // KPI row
                  // Important note: "Orders Received" is calculated from the time the
                  // ORDER WAS CREATED, while "Revenue" is calculated from the time the
                  // PAYMENT SETTLED (a different table) — two legitimately different
                  // populations (VA/QRIS orders can settle several minutes to hours after
                  // being created), not a bug — hence the explicit subtitle here so it's
                  // not mistaken for two numbers that should match.
                  LayoutBuilder(builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 760;
                    final cards = [
                      _kpiCard('Gross Revenue', _formatRupiahCompact(s.todayRevenue),
                          subtitle: 'payments settled today'),
                      _kpiCard('Orders Received', '${s.todayOrders}',
                          subtitle: 'orders created today'),
                      _kpiCard('Bookings Today', '${s.todayBookings}'),
                      _kpiCard('COGS Today', _formatRupiahCompact(s.todayCogs)),
                    ];
                    if (isWide) {
                      return Row(children: [
                        for (int i = 0; i < cards.length; i++) ...[
                          Expanded(child: cards[i]),
                          if (i != cards.length - 1) const SizedBox(width: 12),
                        ],
                      ]);
                    }
                    return Column(children: [
                      Row(children: [Expanded(child: cards[0]), const SizedBox(width: 12), Expanded(child: cards[1])]),
                      const SizedBox(height: 12),
                      Row(children: [Expanded(child: cards[2]), const SizedBox(width: 12), Expanded(child: cards[3])]),
                    ]);
                  }),
                  const SizedBox(height: 24),

                  // Revenue chart + Top Sellers panel
                  LayoutBuilder(builder: (context, constraints) {
                    final chart = _SectionCard(
                      title: 'Revenue Trend',
                      subtitle: 'Daily gross sales · ${s.period.label}',
                      child: SizedBox(
                        height: 260,
                        child: _allZero(s.revenueSpots)
                            ? Center(
                                child: Column(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.bar_chart_outlined,
                                        size: 36,
                                        color: AppColors.textHint),
                                    const SizedBox(height: 8),
                                    Text(
                                        'No transactions yet\n${s.period.label.toLowerCase()}',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 12,
                                            color: AppColors.textSecondary)),
                                  ],
                                ),
                              )
                            : _RevenueLineChart(
                                spots: s.revenueSpots,
                                periodDays: s.period.days,
                              ),
                      ),
                    );
                    final topSellers = _TopSellersPanel(
                      topMenus: s.topMenus,
                      onViewFullReport: () {
                        final ctx = _topMenuSectionKey.currentContext;
                        if (ctx != null) {
                          Scrollable.ensureVisible(ctx,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut);
                        }
                      },
                    );
                    final isWide = constraints.maxWidth >= 900;
                    if (isWide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 2, child: chart),
                          const SizedBox(width: 16),
                          SizedBox(width: 320, child: topSellers),
                        ],
                      );
                    }
                    return Column(children: [chart, const SizedBox(height: 16), topSellers]);
                  }),
                  const SizedBox(height: 24),

                  KeyedSubtree(
                    key: _topMenuSectionKey,
                    child: _TopMenuSection(
                        topMenus: s.topMenus,
                        categories: s.topMenuCategories,
                        period: s.period),
                  ),
                  const SizedBox(height: 24),
                  _MenuMarginSection(menuMargins: s.menuMargins),
                  const SizedBox(height: 24),

                  if (s.isSuperAdmin)
                    _BranchRevenueSection(branchRevenue: s.branchRevenue),
                  if (s.isSuperAdmin) const SizedBox(height: 24),

                  // Recent orders
                  const _SectionHeader(title: 'Recent Orders'),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: Column(children: [
                      for (int i = 0; i < s.recentOrders.length; i++) ...[
                        if (i > 0) const Divider(height: 1, color: AppColors.border),
                        _RecentOrderRow(order: s.recentOrders[i], statusChip: _orderStatusChip),
                      ],
                      if (s.recentOrders.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: Text('No orders yet',
                                style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)),
                          ),
                        ),
                    ]),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _kpiCard(String label, String value, {String? subtitle}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          Text(value,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                  color: AppColors.textPrimary)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10.5,
                    color: AppColors.textHint)),
          ],
        ],
      ),
    );
  }

  Widget _orderStatusChip(OrderStatus status) {
    final Color color;
    switch (status) {
      case OrderStatus.paid:
        color = _StatusColors.good;
        break;
      case OrderStatus.cancelled:
        color = _StatusColors.critical;
        break;
      default:
        color = AppColors.textHint;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(status.label,
          style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: status == OrderStatus.paid
                  ? Colors.green[800]
                  : status == OrderStatus.cancelled
                      ? Colors.red[800]
                      : AppColors.textSecondary)),
    );
  }
}

// ── Helper: check whether all 7-day revenue values are 0 ──────────────────
//
// Used for the chart's empty state. revenueSpots from the provider ALWAYS
// contains 7 entries (days without transactions are filled with 0), so
// .isEmpty can't be used to detect "no data" — the total/sum must be checked.
bool _allZero(List<FlSpot> spots) =>
    spots.isEmpty || spots.every((s) => s.y == 0);

// ── Helper: format Rupiah with thousands separators, no intl locale needed ──
String _formatRupiah(num value) {
  final rounded = value.round();
  final isNegative = rounded < 0;
  final digits = rounded.abs().toString();
  final buffer = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return '${isNegative ? '-' : ''}Rp$buffer';
}

// ── Helper: format Rupiah COMPACTLY (K/M) — THE ONLY compact version ──────
//
// Previously there were 3 different rounding implementations scattered
// across this screen (_fmtRev in top menu, _fmtRp in margin row, _fmtRp in
// branch revenue) — unified so the same number always shows in the same
// format across the whole dashboard.
String _formatRupiahCompact(num value) {
  final v = value.toDouble();
  if (v.abs() >= 1000000) return 'Rp${(v / 1000000).toStringAsFixed(1)}M';
  if (v.abs() >= 1000) return 'Rp${(v / 1000).toStringAsFixed(0)}K';
  return _formatRupiah(v);
}

// ── Semantic status (good/warning/critical) — used consistently for
// menu margin & order status, not category/rank color ─────────────────
class _StatusColors {
  static const good = Color(0xFF0CA30C);
  static const warning = Color(0xFFFAB219);
  static const critical = Color(0xFFD03B3B);
}

// ── Revenue Line Chart ───────────────────────────────────────────────────────
//
// Was a BarChart with a full-height "track" behind every bar
// (BackgroundBarChartRodData toY: chartMaxY on every single bar). With mostly
// low/zero-revenue days in the period (e.g. viewing "This Month" before the
// month has much history), that track dominated the chart as a wall of
// near-full-height grey columns with only the odd real value poking through
// — the actual trend was unreadable. A single trend line with a shaded area
// underneath doesn't have that artifact: zero-revenue days just sit on the
// baseline instead of drawing a misleading full-height block, so the actual
// shape of the trend (and the one standout day) reads immediately.
class _RevenueLineChart extends StatelessWidget {
  const _RevenueLineChart({required this.spots, this.periodDays = 7});

  final List<FlSpot> spots; // x: index 0(n-1 days ago)..(n-1)(today), y: thousands
  final int periodDays;

  @override
  Widget build(BuildContext context) {
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    // Give 25% headroom above the highest value so the line doesn't touch the top.
    final chartMaxY = maxY <= 0 ? 1.0 : maxY * 1.25;
    final today = DateTime.now();
    const weekdayShort = [
      'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
    ]; // index matches DateTime.weekday - 1

    // Which points get a permanent value label above the dot: all of them
    // for a 7-day view, but only first/peak/today for a 30-day view — labeling
    // all 30 points would overlap into an unreadable smear, defeating the
    // "read it without hovering" goal instead of serving it.
    final peakIndex = () {
      var best = 0;
      for (var i = 1; i < spots.length; i++) {
        if (spots[i].y > spots[best].y) best = i;
      }
      return best;
    }();
    final labeledIndices = periodDays <= 7
        ? List.generate(spots.length, (i) => i).toSet()
        : {0, peakIndex, spots.length - 1};

    final lineBarData = LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.2,
      color: AppColors.primary,
      barWidth: 3,
      isStrokeCapRound: true,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, bar, index) {
          final isToday = spot.x.toInt() == periodDays - 1;
          return FlDotCirclePainter(
            radius: isToday ? 5 : (periodDays <= 7 ? 3.5 : 2),
            color: isToday ? AppColors.accent : AppColors.primary,
            strokeWidth: 2,
            strokeColor: Colors.white,
          );
        },
      ),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.primary.withValues(alpha: 0.18),
            AppColors.primary.withValues(alpha: 0.0),
          ],
        ),
      ),
    );

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: chartMaxY,
        showingTooltipIndicators: labeledIndices
            .where((i) => i >= 0 && i < spots.length)
            .map((i) => ShowingTooltipIndicators(
                [LineBarSpot(lineBarData, 0, spots[i])]))
            .toList(),
        lineTouchData: LineTouchData(
          enabled: false,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => Colors.transparent,
            tooltipPadding: EdgeInsets.zero,
            tooltipMargin: 10,
            fitInsideVertically: true,
            fitInsideHorizontally: true,
            getTooltipItems: (touchedSpots) => touchedSpots.map((t) {
              final isToday = t.x.toInt() == periodDays - 1;
              return LineTooltipItem(
                _formatRupiahCompact(t.y * 1000),
                TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    color: isToday ? AppColors.accent : AppColors.primary,
                    fontSize: 10),
              );
            }).toList(),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false, // keep the grid uncluttered
          horizontalInterval: chartMaxY / 4,
          getDrawingHorizontalLine: (_) => const FlLine(
            color: AppColors.border,
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: chartMaxY / 4 == 0 ? 1 : chartMaxY / 4,
              getTitlesWidget: (v, _) => Text(
                v == 0 ? '0' : '${v.toStringAsFixed(0)}K',
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10,
                    color: AppColors.textSecondary),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1, // prevent double/overlapping labels
              getTitlesWidget: (v, _) {
                final idx = v.toInt();
                if (idx < 0 || idx >= periodDays) return const SizedBox();
                final date = today.subtract(Duration(days: periodDays - 1 - idx));
                // For monthly view (30 days): show a label every 5 days so it isn't crowded
                if (periodDays > 7 && idx % 5 != 0 && idx != periodDays - 1) {
                  return const SizedBox();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    children: [
                      if (periodDays <= 7)
                        Text(weekdayShort[date.weekday - 1],
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 10,
                                fontWeight: FontWeight.w600)),
                      Text('${date.day}/${date.month}',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: periodDays <= 7 ? 9 : 10,
                              color: AppColors.textSecondary)),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [lineBarData],
      ),
    );
  }
}

// ── Section Header (icon-in-box + title, no emoji) ─────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  const _SectionHeader({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: AppColors.textPrimary)),
              if (subtitle != null)
                Text(subtitle!,
                    style: const TextStyle(
                        fontFamily: 'Poppins', fontSize: 11.5, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Bordered card wrapper used for the Revenue Trend chart ─────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  const _SectionCard({required this.title, required this.child, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(title: title, subtitle: subtitle),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

// ── Top Sellers side panel ──────────────────────────────────────────────────

class _TopSellersPanel extends StatelessWidget {
  final List<Map<String, dynamic>> topMenus;
  final VoidCallback onViewFullReport;
  const _TopSellersPanel({required this.topMenus, required this.onViewFullReport});

  @override
  Widget build(BuildContext context) {
    final top = topMenus.take(4).toList();
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: _SectionHeader(title: 'Top Sellers'),
          ),
          if (top.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Text('No sales data yet',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary)),
            )
          else ...[
            const Divider(height: 1, color: AppColors.border),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Row(children: [
                SizedBox(width: 20, child: Text('#', style: AppTextStyles.label)),
                Expanded(child: Text('ITEM NAME', style: AppTextStyles.label)),
                Text('QTY', style: AppTextStyles.label),
                SizedBox(width: 12),
                Text('REV', style: AppTextStyles.label),
              ]),
            ),
            for (int i = 0; i < top.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: AppColors.border, indent: 16, endIndent: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 20,
                      child: Text('${i + 1}',
                          style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: AppColors.primary)),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(top[i]['name'] as String,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13)),
                          Text(top[i]['category'] as String? ?? '',
                              style: const TextStyle(
                                  fontFamily: 'Poppins', fontSize: 10.5, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    Text('${top[i]['qty']}',
                        style: const TextStyle(
                            fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 12)),
                    const SizedBox(width: 12),
                    Text(_formatRupiahCompact(top[i]['revenue'] as double),
                        style: const TextStyle(
                            fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.primary)),
                  ],
                ),
              ),
            ],
            const Divider(height: 1, color: AppColors.border),
            InkWell(
              onTap: onViewFullReport,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                color: AppColors.surfaceVariant,
                child: const Center(
                  child: Text('VIEW FULL MENU REPORT',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                          color: AppColors.accent)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Recent order row ─────────────────────────────────────────────────────────

class _RecentOrderRow extends StatelessWidget {
  final OrderModel order;
  final Widget Function(OrderStatus) statusChip;
  const _RecentOrderRow({required this.order, required this.statusChip});

  @override
  Widget build(BuildContext context) {
    final o = order;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              o.orderNumber.split('-').last,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  color: AppColors.primary),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                o.tableNumber != null ? 'Table ${o.tableNumber}' : 'Takeaway',
                style: const TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 2),
              Row(children: [
                Text('${o.items.length} item • ', style: AppTextStyles.caption),
                statusChip(o.status),
              ]),
            ],
          ),
        ),
        Text(
          _formatRupiah(o.totalAmount),
          style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              // Orders that are unpaid/not settled are shown in a neutral ink
              // color (not the same accent color as paid orders) — previously
              // all orders in this list (including cancelled/unpaid ones)
              // were given the same visual weight as orders that were
              // actually paid.
              color: o.isPaid ? AppColors.accent : AppColors.textHint),
        ),
      ]),
    );
  }
}

// ── Period Toggle Widget ──────────────────────────────────────────────────────

class _PeriodToggle extends StatelessWidget {
  final ReportPeriod current;
  final ValueChanged<ReportPeriod> onChanged;

  const _PeriodToggle({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: ReportPeriod.values.map((p) {
          final isSelected = current == p;
          return GestureDetector(
            onTap: () => onChanged(p),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                p.label,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Top Menu Section ──────────────────────────────────────────────────────────

class _TopMenuSection extends StatefulWidget {
  final List<Map<String, dynamic>> topMenus;
  final List<String> categories;
  final ReportPeriod period;
  const _TopMenuSection({
    required this.topMenus,
    required this.categories,
    required this.period,
  });

  @override
  State<_TopMenuSection> createState() => _TopMenuSectionState();
}

class _TopMenuSectionState extends State<_TopMenuSection> {
  String _selectedCategory = 'All';

  List<Map<String, dynamic>> get _filtered {
    final list = _selectedCategory == 'All'
        ? widget.topMenus
        : widget.topMenus
            .where((m) => m['category'] == _selectedCategory)
            .toList();
    return list.take(10).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.topMenus.isEmpty) return const SizedBox.shrink();

    final filtered = _filtered;
    if (filtered.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(),
          const SizedBox(height: 8),
          _categoryChips(),
          const SizedBox(height: 12),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text('No data yet for this category',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: AppColors.textSecondary)),
              ),
            ),
          ),
        ],
      );
    }

    final maxQty = (filtered.first['qty'] as int).toDouble();
    // Grid interval: round to a nice, readable number
    double gridInterval = (maxQty / 4).ceilToDouble();
    if (gridInterval == 0) gridInterval = 1;
    // Round to a multiple of 5, 10, 25, 50, 100 etc. for tidiness
    final nice = [1, 5, 10, 25, 50, 100, 250, 500, 1000];
    for (final n in nice) {
      if (gridInterval <= n) { gridInterval = n.toDouble(); break; }
    }
    final chartMaxY = gridInterval * 5; // always 5 grid rows

    // Chart height: min 200, max ~320 — enough for 10 bars
    final chartHeight = (filtered.length * 38.0).clamp(200.0, 320.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(),
        const SizedBox(height: 8),
        _categoryChips(),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
            child: SizedBox(
              height: chartHeight + 60, // +60 for the bottom label
              child: BarChart(
                BarChartData(
                  maxY: chartMaxY,
                  alignment: BarChartAlignment.spaceAround,
                  // Value labels are permanent (showingTooltipIndicators on every
                  // group, touch disabled) rather than shown on hover/tap — the
                  // whole point of this redesign is that the exact qty sold is
                  // readable in one glance, not after moving a cursor onto the bar.
                  barTouchData: BarTouchData(
                    enabled: false,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => Colors.transparent,
                      tooltipPadding: EdgeInsets.zero,
                      tooltipMargin: 6,
                      fitInsideVertically: true,
                      getTooltipItem: (group, _, rod, __) {
                        return BarTooltipItem(
                          rod.toY.toInt().toString(),
                          const TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                              fontSize: 11),
                        );
                      },
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: gridInterval,
                    getDrawingHorizontalLine: (_) => const FlLine(
                      color: AppColors.border,
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        interval: gridInterval,
                        getTitlesWidget: (v, _) {
                          if (v == 0) return const SizedBox();
                          final label = v >= 1000
                              ? '${(v / 1000).toStringAsFixed(0)}k'
                              : v.toInt().toString();
                          return Text(label,
                              style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 10,
                                  color: AppColors.textSecondary));
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 52,
                        getTitlesWidget: (v, _) {
                          final idx = v.toInt();
                          if (idx < 0 || idx >= filtered.length) {
                            return const SizedBox();
                          }
                          final name = filtered[idx]['name'] as String;
                          // Truncate long names: max 2 lines @ 8 characters
                          final words = name.split(' ');
                          final lines = <String>[];
                          var line = '';
                          for (final w in words) {
                            if ((line.isEmpty ? w : '$line $w').length > 9) {
                              if (line.isNotEmpty) lines.add(line);
                              line = w.length > 9 ? '${w.substring(0, 8)}..' : w;
                            } else {
                              line = line.isEmpty ? w : '$line $w';
                            }
                          }
                          if (line.isNotEmpty) lines.add(line);
                          final display = lines.take(2).join('\n');

                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              display,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 9,
                                  color: AppColors.textSecondary),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: filtered.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final item = entry.value;
                    final qty = (item['qty'] as int).toDouble();
                    // Each bar gets its own color so items are distinguishable
                    // at a glance, not just by their (small) axis label. Color
                    // is keyed to the item NAME's hash, not to `idx` — so it
                    // stays fixed to that menu item across re-renders even if
                    // the category filter changes which items are shown/in
                    // what order (the earlier single-color version deliberately
                    // avoided coloring by rank/position for the same reason:
                    // color following position instead of identity was
                    // confusing whenever the filter changed).
                    final itemName = item['name'] as String;
                    final barColor = AppColors
                        .chartPalette[itemName.hashCode.abs() % AppColors.chartPalette.length];
                    return BarChartGroupData(
                      x: idx,
                      barRods: [
                        BarChartRodData(
                          toY: qty,
                          width: (filtered.length <= 5 ? 28 : 18).toDouble(),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4)),
                          color: barColor,
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: chartMaxY,
                            color: barColor.withValues(alpha: 0.06),
                          ),
                        ),
                      ],
                      showingTooltipIndicators: [0],
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
        // Short legend: rank 1-3 & item totals
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Wrap(
            spacing: 12,
            runSpacing: 4,
            children: filtered.take(3).toList().asMap().entries.map((e) {
              final medals = ['🥇', '🥈', '🥉'];
              final item = e.value;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(medals[e.key],
                      style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 4),
                  Text('${item['name']} — ${item['qty']} sold',
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          color: AppColors.textSecondary)),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _header() => _SectionHeader(
      title: 'Best-Selling Menu · ${widget.period.label}');

  Widget _categoryChips() {
    if (widget.categories.length <= 1) return const SizedBox.shrink();
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: widget.categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final cat = widget.categories[i];
          final isSelected = cat == _selectedCategory;
          return GestureDetector(
            onTap: () => setState(() => _selectedCategory = cat),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary
                    : AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.primary.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: Text(
                cat,
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : AppColors.primary),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Menu Margin Section ───────────────────────────────────────────────────────
// (no logic changes here, only the subtitle description was updated)

class _MenuMarginSection extends StatelessWidget {
  final List<Map<String, dynamic>> menuMargins;
  const _MenuMarginSection({required this.menuMargins});

  @override
  Widget build(BuildContext context) {
    if (menuMargins.isEmpty) return const SizedBox.shrink();

    final top = menuMargins.take(5).toList();
    final bottom = menuMargins.length > 5
        ? menuMargins.reversed.take(3).toList()
        : <Map<String, dynamic>>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Subtitle updated: data now comes from costingProvider
        const _SectionHeader(
          title: 'Margin per Menu',
          subtitle: 'Based on COGS from the costing module',
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Icon(Icons.trending_up_rounded, size: 15, color: _StatusColors.good),
                SizedBox(width: 6),
                Text('Highest Margin',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: _StatusColors.good)),
              ]),
              const SizedBox(height: 12),
              ...top.map((item) => _MarginRow(item: item)),
            ],
          ),
        ),
        if (bottom.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.trending_down_rounded, size: 15, color: _StatusColors.critical),
                  SizedBox(width: 6),
                  Text('Needs Attention (Low Margin)',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: _StatusColors.critical)),
                ]),
                const SizedBox(height: 12),
                ...bottom.map((item) => _MarginRow(item: item)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _MarginRow extends StatelessWidget {
  final Map<String, dynamic> item;
  const _MarginRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final name = item['name'] as String;
    final price = item['price'] as double;
    final cogs = item['cogs'] as double;
    final margin = item['margin'] as double;

    // good/warning/critical status from the validated palette — used as the
    // ICON color only, not the text color. The warning hex (#FAB219) has a
    // contrast of only ~1.8:1 on white (below the readability threshold for
    // small text) — the percentage text intentionally stays a neutral ink
    // color (textPrimary); the semantics are carried by the icon + word
    // label, not the text color itself.
    final IconData statusIcon;
    final Color statusColor;
    final String statusLabel;
    if (margin >= 50) {
      statusIcon = Icons.check_circle;
      statusColor = _StatusColors.good;
      statusLabel = 'Healthy';
    } else if (margin >= 30) {
      statusIcon = Icons.warning_rounded;
      statusColor = _StatusColors.warning;
      statusLabel = 'Needs Monitoring';
    } else {
      statusIcon = Icons.error_rounded;
      statusColor = _StatusColors.critical;
      statusLabel = 'Critical';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 58,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(statusIcon, color: statusColor, size: 14),
                const SizedBox(height: 2),
                Text(
                  '${margin.toStringAsFixed(0)}%',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppColors.textPrimary,
                      fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: 13),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  'Sell ${_formatRupiah(price)}  •  COGS ${cogs > 0 ? _formatRupiah(cogs) : "not set"}  •  $statusLabel',
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Branch Revenue Section ────────────────────────────────────────────────────
//
// Previously rendered with stacked LinearProgressIndicators — not a real
// fl_chart chart, so it lacked the gridlines/tooltip/scale consistent with
// the other 2 charts on this dashboard. Replaced with a vertical BarChart
// using the SAME visual language as Revenue Trend & Best-Selling Menu (1
// consistent brand color, thin horizontal grid, full nominal tooltip on
// touch) — branch #1 is marked via a crown+bold in the legend, NOT via a
// different hue.

class _BranchRevenueSection extends StatelessWidget {
  final List<Map<String, dynamic>> branchRevenue;
  const _BranchRevenueSection({required this.branchRevenue});

  @override
  Widget build(BuildContext context) {
    if (branchRevenue.isEmpty) return const SizedBox.shrink();

    final maxRevenue =
        branchRevenue.map((b) => b['revenue'] as double).reduce((a, b) => a > b ? a : b);
    final chartMaxY = maxRevenue <= 0 ? 1.0 : maxRevenue * 1.25;
    final gridInterval = chartMaxY / 4 == 0 ? 1.0 : chartMaxY / 4;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          title: 'Branch Comparison',
          subtitle: 'This month\'s revenue per branch',
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
            child: SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  maxY: chartMaxY,
                  alignment: BarChartAlignment.spaceAround,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: gridInterval,
                    getDrawingHorizontalLine: (_) => const FlLine(
                      color: AppColors.border,
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  // Same permanent-label technique as the other charts on this
                  // screen: the revenue figure sits above the bar at all times
                  // instead of only appearing on hover/tap.
                  barTouchData: BarTouchData(
                    enabled: false,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => Colors.transparent,
                      tooltipPadding: EdgeInsets.zero,
                      tooltipMargin: 6,
                      fitInsideVertically: true,
                      getTooltipItem: (group, _, rod, __) {
                        return BarTooltipItem(
                          _formatRupiahCompact(rod.toY),
                          const TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                              fontSize: 11),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 44,
                        interval: gridInterval,
                        getTitlesWidget: (v, _) => Text(
                          v == 0 ? '0' : _formatRupiahCompact(v),
                          style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 9,
                              color: AppColors.textSecondary),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        getTitlesWidget: (v, _) {
                          final idx = v.toInt();
                          if (idx < 0 || idx >= branchRevenue.length) {
                            return const SizedBox();
                          }
                          final name = branchRevenue[idx]['name'] as String;
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              name.length > 10 ? '${name.substring(0, 9)}…' : name,
                              style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 9.5,
                                  color: AppColors.textSecondary),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: branchRevenue.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final revenue = entry.value['revenue'] as double;
                    return BarChartGroupData(
                      x: idx,
                      barRods: [
                        BarChartRodData(
                          toY: revenue,
                          width: 26,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4)),
                          color: AppColors.primary,
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: chartMaxY,
                            color: AppColors.surfaceVariant,
                          ),
                        ),
                      ],
                      showingTooltipIndicators: [0],
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
        // Branch #1 is marked via a label, not a different color in the chart.
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Row(
            children: [
              const Icon(Icons.emoji_events_rounded, size: 15, color: AppColors.primary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '${branchRevenue.first['name']} — ${_formatRupiah(branchRevenue.first['revenue'] as double)} this month',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                      color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}