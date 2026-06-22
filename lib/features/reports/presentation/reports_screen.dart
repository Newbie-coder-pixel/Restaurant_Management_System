import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_drawer.dart';
import '../../../shared/models/order_model.dart'; // ← tambah ini
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
    // Init provider setelah frame pertama selesai render
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
                    child: Text('Semua Cabang',
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
                  Row(children: [
                    _kpiCard('Order Hari Ini', '${s.todayOrders}',
                        Icons.receipt_long, AppColors.primary),
                    const SizedBox(width: 12),
                    _kpiCard(
                        'Revenue',
                        'Rp ${(s.todayRevenue / 1000).toStringAsFixed(0)}rb',
                        Icons.monetization_on_outlined,
                        AppColors.available),
                    const SizedBox(width: 12),
                    _kpiCard('Booking', '${s.todayBookings}',
                        Icons.event_available, AppColors.reserved),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    _kpiCard(
                        'COGS Hari Ini',
                        'Rp ${(s.todayCogs / 1000).toStringAsFixed(0)}rb',
                        Icons.calculate_outlined,
                        Colors.orange),
                  ]),
                  const SizedBox(height: 24),

                  // Revenue chart
                  const Text('Revenue 7 Hari Terakhir',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 16)),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        height: 220,
                        // Cek total, bukan cuma panjang list — list selalu
                        // berisi 7 entri (nilai 0 kalau memang tak ada
                        // transaksi), jadi .isEmpty tidak pernah true.
                        child: _allZero(s.revenueSpots)
                            ? const Center(
                                child: Column(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.bar_chart_outlined,
                                        size: 36,
                                        color: AppColors.textHint),
                                    SizedBox(height: 8),
                                    Text(
                                        'Belum ada transaksi dalam\n'
                                        '7 hari terakhir',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 12,
                                            color: AppColors.textSecondary)),
                                  ],
                                ),
                              )
                            : _RevenueBarChart(spots: s.revenueSpots),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  _TopMenuSection(topMenus: s.topMenus),
                  const SizedBox(height: 24),
                  _MenuMarginSection(menuMargins: s.menuMargins),
                  const SizedBox(height: 24),

                  if (s.isSuperAdmin)
                    _BranchRevenueSection(branchRevenue: s.branchRevenue),
                  if (s.isSuperAdmin) const SizedBox(height: 24),

                  // Recent orders
                  const Text('Order Terbaru',
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
                                ? 'Meja ${o.tableNumber}'
                                : 'Takeaway',
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${o.items.length} item • ${o.status.label}',
                            style: AppTextStyles.caption,
                          ),
                          trailing: Text(
                            'Rp ${o.totalAmount.toStringAsFixed(0)}',
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w700,
                                color: AppColors.accent),
                          ),
                        ),
                      )),
                ],
              ),
            ),
    );
  }

  Widget _kpiCard(
          String label, String value, IconData icon, Color color) =>
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
              ],
            ),
          ),
        ),
      );
}

// ── Helper: cek apakah semua nilai revenue 7 hari = 0 ──────────────────────
//
// Dipakai untuk empty-state chart. revenueSpots dari provider SELALU
// berisi 7 entri (hari tanpa transaksi diisi 0), jadi tidak bisa pakai
// .isEmpty untuk deteksi "tidak ada data" — harus cek total/jumlahnya.
bool _allZero(List<FlSpot> spots) =>
    spots.isEmpty || spots.every((s) => s.y == 0);

// ── Helper: format Rupiah dengan pemisah ribuan, tanpa perlu intl locale ────
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

// ── Revenue Bar Chart ────────────────────────────────────────────────────────
//
// Dipilih Bar Chart (bukan Line Chart) karena data revenue harian itu
// DISKRIT — tiap hari adalah angka berdiri sendiri, bukan rangkaian
// kontinu. Line chart menyiratkan ada "alur"/interpolasi antar titik yang
// sebenarnya tidak relevan secara analitis untuk perbandingan per-hari.
//
// Perbaikan dibanding versi LineChart sebelumnya:
//   • Grid HANYA horizontal (drawVerticalLine: false) → tidak ada lagi
//     garis-garis vertikal yang membuat chart terlihat penuh & membingungkan
//   • Label sumbu-X pakai TANGGAL ASLI (bukan "Sen/Sel/Rab" generik yang
//     ambigu) + interval:1 supaya tidak dobel/tumpang-tindih
//   • Bar "Hari Ini" diberi warna beda (accent) supaya langsung kelihatan
//     mana performa hari ini vs riwayat 6 hari sebelumnya
//   • Tooltip saat disentuh menampilkan nominal Rupiah ASLI (bukan cuma
//     skala "rb") untuk kebutuhan drill-down analitis
class _RevenueBarChart extends StatelessWidget {
  const _RevenueBarChart({required this.spots});

  final List<FlSpot> spots; // x: index 0(6 hari lalu)..6(hari ini), y: ribuan

  @override
  Widget build(BuildContext context) {
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    // Beri headroom 25% di atas nilai tertinggi supaya bar tidak mepet atap.
    final chartMaxY = maxY <= 0 ? 1.0 : maxY * 1.25;
    final today = DateTime.now();
    const weekdayShort = [
      'Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'
    ]; // index sesuai DateTime.weekday - 1

    return BarChart(
      BarChartData(
        maxY: chartMaxY,
        alignment: BarChartAlignment.spaceAround,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false, // ← hilangkan garis vertikal yang ramai
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
                v == 0 ? '0' : '${v.toStringAsFixed(0)}rb',
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
              interval: 1, // ← fix utama: cegah label dobel/tumpang-tindih
              getTitlesWidget: (v, _) {
                final idx = v.toInt();
                if (idx < 0 || idx > 6) return const SizedBox();
                final date = today.subtract(Duration(days: 6 - idx));
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    children: [
                      Text(weekdayShort[date.weekday - 1],
                          style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 10,
                              fontWeight: FontWeight.w600)),
                      Text('${date.day}/${date.month}',
                          style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 9,
                              color: AppColors.textSecondary)),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => AppColors.primary,
            getTooltipItem: (group, _, rod, __) => BarTooltipItem(
              _formatRupiah(rod.toY * 1000),
              const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  fontSize: 11),
            ),
          ),
        ),
        barGroups: spots.map((spot) {
          final idx = spot.x.toInt();
          final isToday = idx == 6;
          return BarChartGroupData(
            x: idx,
            barRods: [
              BarChartRodData(
                toY: spot.y,
                width: 22,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4)),
                color: isToday ? AppColors.accent : AppColors.primary,
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
    );
  }
}

// ── Top Menu Section ──────────────────────────────────────────────────────────

class _TopMenuSection extends StatelessWidget {
  final List<Map<String, dynamic>> topMenus;
  const _TopMenuSection({required this.topMenus});

  // BUG FIX: hilangkan backslash sebelum $
  String _fmtRev(double v) =>
      'Rp ${(v / 1000).toStringAsFixed(0)}rb';

  @override
  Widget build(BuildContext context) {
    if (topMenus.isEmpty) return const SizedBox.shrink();

    final maxQty = (topMenus.first['qty'] as int).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('🏆 Menu Terlaris',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 16)),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 12),
            child: Column(
              children: topMenus.asMap().entries.map((entry) {
                final rank = entry.key + 1;
                final item = entry.value;
                final name = item['name'] as String;
                final qty = item['qty'] as int;
                final rev = item['revenue'] as double;
                final ratio = maxQty > 0 ? qty / maxQty : 0.0;

                final Color rankColor;
                if (rank == 1) {
                  rankColor = const Color(0xFFFFD700);
                } else if (rank == 2) {
                  rankColor = const Color(0xFFC0C0C0);
                } else if (rank == 3) {
                  rankColor = const Color(0xFFCD7F32);
                } else {
                  rankColor = AppColors.textSecondary;
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 28,
                        child: Text('#$rank',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: rankColor)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(name,
                                      style: const TextStyle(
                                          fontFamily: 'Poppins',
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13),
                                      overflow: TextOverflow.ellipsis),
                                ),
                                const SizedBox(width: 8),
                                Text('$qty terjual',
                                    style: const TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 11,
                                        color: AppColors.textSecondary)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: ratio,
                                minHeight: 6,
                                backgroundColor: AppColors.primary
                                    .withValues(alpha: 0.1),
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(
                                  rank <= 3
                                      ? AppColors.primary
                                      : AppColors.primary
                                          .withValues(alpha: 0.45),
                                ),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(_fmtRev(rev),
                                style: const TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 11,
                                    color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Menu Margin Section ───────────────────────────────────────────────────────
// (tidak ada perubahan logic di sini, hanya subtitle description diupdate)

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
        // Subtitle diupdate: sekarang datanya dari costingProvider
        const Text(
          'Berdasarkan HPP dari modul costing',
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
                const Text('🟢 Margin Tertinggi',
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
                  const Text('🔴 Perlu Perhatian (Margin Rendah)',
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

  String _fmtRp(double v) => 'Rp ${v.toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]}.',
      )}';

  @override
  Widget build(BuildContext context) {
    final name = item['name'] as String;
    final price = item['price'] as double;
    final cogs = item['cogs'] as double;
    final margin = item['margin'] as double;

    final Color marginColor;
    if (margin >= 50) {
      marginColor = Colors.green[700]!;
    } else if (margin >= 30) {
      marginColor = Colors.orange[700]!;
    } else {
      marginColor = Colors.red[700]!;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 54,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: marginColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${margin.toStringAsFixed(0)}%',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: marginColor),
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
                  'Jual ${_fmtRp(price)}  •  COGS ${cogs > 0 ? _fmtRp(cogs) : "belum diisi"}',
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
// (tidak ada perubahan sama sekali di section ini)

class _BranchRevenueSection extends StatelessWidget {
  final List<Map<String, dynamic>> branchRevenue;
  const _BranchRevenueSection({required this.branchRevenue});

  String _fmtRp(double v) {
    if (v >= 1000000) return 'Rp ${(v / 1000000).toStringAsFixed(1)}jt';
    return 'Rp ${(v / 1000).toStringAsFixed(0)}rb';
  }

  @override
  Widget build(BuildContext context) {
    if (branchRevenue.isEmpty) return const SizedBox.shrink();

    final maxRevenue = (branchRevenue.first['revenue'] as double);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('🏪 Perbandingan Cabang',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 16)),
        const SizedBox(height: 4),
        const Text('Revenue bulan ini per cabang',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                color: AppColors.textSecondary)),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: branchRevenue.asMap().entries.map((entry) {
                final rank = entry.key;
                final item = entry.value;
                final name = item['name'] as String;
                final revenue = item['revenue'] as double;
                final ratio =
                    maxRevenue > 0 ? revenue / maxRevenue : 0.0;
                final barColor = rank == 0
                    ? AppColors.primary
                    : AppColors.primary.withValues(alpha: 0.45);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Row(children: [
                            if (rank == 0)
                              const Text('👑 ',
                                  style: TextStyle(fontSize: 12)),
                            Text(name,
                                style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: rank == 0
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    fontSize: 13)),
                          ]),
                          Text(
                            revenue > 0
                                ? _fmtRp(revenue)
                                : 'Belum ada',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: rank == 0
                                    ? AppColors.primary
                                    : AppColors.textSecondary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 8,
                          backgroundColor:
                              AppColors.primary.withValues(alpha: 0.08),
                          valueColor:
                              AlwaysStoppedAnimation<Color>(barColor),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}