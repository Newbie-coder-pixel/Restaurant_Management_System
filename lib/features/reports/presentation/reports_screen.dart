import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_drawer.dart';
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

  @override
  Widget build(BuildContext context) {
    final notifier = ref.watch(reportsProvider);
    final s = notifier.state;

    return Scaffold(
      drawer: const AppDrawer(),
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Reports & Analytics'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        titleTextStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white),
        actions: [
          if (s.isSuperAdmin)
            DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: s.selectedBranchId,
                isDense: true,
                dropdownColor: const Color(0xFF1A1A2E),
                iconEnabledColor: Colors.white60,
                icon: const Icon(Icons.keyboard_arrow_down, size: 16),
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: Colors.white70),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All Branches',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            color: Colors.white70)),
                  ),
                  ...s.branches.map((b) => DropdownMenuItem<String?>(
                        value: b['id'] as String,
                        child: Text(b['name'] as String,
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11,
                                color: Colors.white)),
                      )),
                ],
                onChanged: (val) => notifier.selectBranch(val),
              ),
            ),
          const SizedBox(width: 8),
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: notifier.load),
        ],
      ),
      body: s.isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
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
                  Row(children: [
                    _kpiCard('Orders Received', '${s.todayOrders}',
                        Icons.receipt_long, AppColors.primary,
                        subtitle: 'orders created today'),
                    const SizedBox(width: 12),
                    _kpiCard(
                        'Revenue',
                        _formatRupiahCompact(s.todayRevenue),
                        Icons.monetization_on_outlined,
                        _StatusColors.good,
                        subtitle: 'payments settled today'),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    _kpiCard('Bookings Today', '${s.todayBookings}',
                        Icons.event_available, const Color(0xFF4A3AA7)),
                    const SizedBox(width: 12),
                    _kpiCard(
                        'COGS Today',
                        _formatRupiahCompact(s.todayCogs),
                        Icons.calculate_outlined,
                        const Color(0xFFEB6834)),
                  ]),
                  const SizedBox(height: 24),

                  // Revenue chart — header + period toggle
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Revenue ${s.period.label}',
                          style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w700,
                              fontSize: 16),
                        ),
                      ),
                      _PeriodToggle(
                        current: s.period,
                        onChanged: (p) => notifier.selectPeriod(p),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        height: 220,
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
                    ),
                  ),
                  const SizedBox(height: 24),

                  _TopMenuSection(
                      topMenus: s.topMenus,
                      categories: s.topMenuCategories,
                      period: s.period),
                  const SizedBox(height: 24),
                  _MenuMarginSection(menuMargins: s.menuMargins),
                  const SizedBox(height: 24),

                  if (s.isSuperAdmin)
                    _BranchRevenueSection(branchRevenue: s.branchRevenue),
                  if (s.isSuperAdmin) const SizedBox(height: 24),

                  // Recent orders
                  const Text('Recent Orders',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 16)),
                  const SizedBox(height: 12),
                  ...s.recentOrders.map((o) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: AppColors.primary
                                  .withValues(alpha: 0.08),
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
                          title: Text(
                            o.tableNumber != null
                                ? 'Table ${o.tableNumber}'
                                : 'Takeaway',
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w600),
                          ),
                          subtitle: Row(
                            children: [
                              Text('${o.items.length} item • ',
                                  style: AppTextStyles.caption),
                              _orderStatusChip(o.status),
                            ],
                          ),
                          trailing: Text(
                            _formatRupiah(o.totalAmount),
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w700,
                                // Orders that are unpaid/not settled are shown
                                // in a neutral ink color (not the same accent
                                // color as paid orders) — previously all orders
                                // in this list (including cancelled/unpaid ones)
                                // were given the same visual weight as orders
                                // that were actually paid.
                                color: o.isPaid
                                    ? AppColors.accent
                                    : AppColors.textHint),
                          ),
                        ),
                      )),
                ],
              ),
            ),
    );
  }

  Widget _kpiCard(
          String label, String value, IconData icon, Color color,
          {String? subtitle}) =>
      Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(height: 8),
                Text(value,
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: color)),
                const SizedBox(height: 4),
                Text(label, style: AppTextStyles.caption),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 9.5,
                          color: AppColors.textHint)),
                ],
              ],
            ),
          ),
        ),
      );

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

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: chartMaxY,
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
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.primary,
            getTooltipItems: (touchedSpots) => touchedSpots.map((t) {
              return LineTooltipItem(
                _formatRupiah(t.y * 1000),
                const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    fontSize: 11),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
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
          ),
        ],
      ),
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
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => AppColors.primary,
                      getTooltipItem: (group, _, rod, __) {
                        final item = filtered[group.x];
                        return BarTooltipItem(
                          '${item['name']}\n${rod.toY.toInt()} sold\n${_formatRupiahCompact(item['revenue'] as double)}',
                          const TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
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
                    // ONE consistent color for all bars — top-3 rank/position
                    // is shown via bar length + medals in the legend below the
                    // chart, NOT via color. Previously the top-3 were given
                    // different hues (gold/silver/bronze): if the category filter
                    // changed and a different item rose into the top-3, the
                    // color would "move" to that item — color followed RANK
                    // instead of menu identity, which made the re-coloring
                    // confusing every time the filter changed.
                    return BarChartGroupData(
                      x: idx,
                      barRods: [
                        BarChartRodData(
                          toY: qty,
                          width: (filtered.length <= 5 ? 28 : 18).toDouble(),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4)),
                          color: AppColors.primary,
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: chartMaxY,
                            color: AppColors.primary.withValues(alpha: 0.06),
                          ),
                        ),
                      ],
                      showingTooltipIndicators: [],
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

  Widget _header() => Text('🏆 Best-Selling Menu · ${widget.period.label}',
      style: const TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w700,
          fontSize: 16));

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
        const Text('💡 Margin per Menu',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 16)),
        const SizedBox(height: 4),
        // Subtitle updated: data now comes from costingProvider
        const Text(
          'Based on COGS from the costing module',
          style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🟢 Highest Margin',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Colors.green)),
                const SizedBox(height: 12),
                ...top.map((item) => _MarginRow(item: item)),
              ],
            ),
          ),
        ),
        if (bottom.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🔴 Needs Attention (Low Margin)',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: Colors.red)),
                  const SizedBox(height: 12),
                  ...bottom.map((item) => _MarginRow(item: item)),
                ],
              ),
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
        const Text('🏪 Branch Comparison',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 16)),
        const SizedBox(height: 4),
        const Text('This month\'s revenue per branch',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                color: AppColors.textSecondary)),
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
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => AppColors.primary,
                      getTooltipItem: (group, _, rod, __) {
                        final name = branchRevenue[group.x]['name'] as String;
                        return BarTooltipItem(
                          '$name\n${_formatRupiah(rod.toY)}',
                          const TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
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
              const Text('👑 ', style: TextStyle(fontSize: 13)),
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