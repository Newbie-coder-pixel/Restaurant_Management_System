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
                  // Catatan penting: "Order Masuk" dihitung dari waktu ORDER
                  // DIBUAT, sedangkan "Pendapatan" dihitung dari waktu
                  // PEMBAYARAN SETTLE (tabel berbeda) — dua populasi yang
                  // legitimately berbeda (order VA/QRIS bisa settle beberapa
                  // menit-jam setelah dibuat), bukan bug — makanya diberi
                  // subtitle eksplisit di sini supaya tidak disangka dua
                  // angka yang seharusnya sama.
                  Row(children: [
                    _kpiCard('Order Masuk', '${s.todayOrders}',
                        Icons.receipt_long, AppColors.primary,
                        subtitle: 'order dibuat hari ini'),
                    const SizedBox(width: 12),
                    _kpiCard(
                        'Pendapatan',
                        _formatRupiahCompact(s.todayRevenue),
                        Icons.monetization_on_outlined,
                        _StatusColors.good,
                        subtitle: 'pembayaran settle hari ini'),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    _kpiCard('Booking Hari Ini', '${s.todayBookings}',
                        Icons.event_available, const Color(0xFF4A3AA7)),
                    const SizedBox(width: 12),
                    _kpiCard(
                        'COGS Hari Ini',
                        _formatRupiahCompact(s.todayCogs),
                        Icons.calculate_outlined,
                        const Color(0xFFEB6834)),
                  ]),
                  const SizedBox(height: 24),

                  // Revenue chart — header + toggle periode
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
                                        'Belum ada transaksi\n${s.period.label.toLowerCase()}',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 12,
                                            color: AppColors.textSecondary)),
                                  ],
                                ),
                              )
                            : _RevenueBarChart(
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
                                // Order yang belum/tidak lunas ditampilkan
                                // dengan tinta netral (bukan warna accent
                                // yang sama seperti order lunas) — sebelumnya
                                // semua order di daftar ini (termasuk yang
                                // dibatalkan/belum bayar) diberi bobot visual
                                // sama seperti order yang benar-benar lunas.
                                color: o.status == OrderStatus.paid
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

// ── Helper: format Rupiah RINGKAS (rb/jt) — SATU-SATUNYA versi ringkas ─────
//
// Sebelumnya ada 3 implementasi pembulatan berbeda tersebar di layar ini
// (_fmtRev di top menu, _fmtRp di margin row, _fmtRp di branch revenue) —
// disatukan supaya angka yang sama selalu tampil dengan format yang sama
// di seluruh dashboard.
String _formatRupiahCompact(num value) {
  final v = value.toDouble();
  if (v.abs() >= 1000000) return 'Rp${(v / 1000000).toStringAsFixed(1)}jt';
  if (v.abs() >= 1000) return 'Rp${(v / 1000).toStringAsFixed(0)}rb';
  return _formatRupiah(v);
}

// ── Status semantik (good/warning/critical) — dipakai konsisten untuk
// margin menu & status order, bukan warna kategori/rank ─────────────────
class _StatusColors {
  static const good = Color(0xFF0CA30C);
  static const warning = Color(0xFFFAB219);
  static const critical = Color(0xFFD03B3B);
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
  const _RevenueBarChart({required this.spots, this.periodDays = 7});

  final List<FlSpot> spots; // x: index 0(n-1 hari lalu)..(n-1)(hari ini), y: ribuan
  final int periodDays;

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
                if (idx < 0 || idx >= periodDays) return const SizedBox();
                final date = today.subtract(Duration(days: periodDays - 1 - idx));
                // Untuk bulan (30 hari): tampilkan label setiap 5 hari agar tidak penuh
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
          final isToday = idx == periodDays - 1;
          return BarChartGroupData(
            x: idx,
            barRods: [
              BarChartRodData(
                toY: spot.y,
                width: periodDays <= 7 ? 22 : 9,
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
  String _selectedCategory = 'Semua';

  List<Map<String, dynamic>> get _filtered {
    final list = _selectedCategory == 'Semua'
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
                child: Text('Belum ada data untuk kategori ini',
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
    // Interval grid: bulatkan ke angka yang enak dibaca
    double gridInterval = (maxQty / 4).ceilToDouble();
    if (gridInterval == 0) gridInterval = 1;
    // Bulatkan ke kelipatan 5, 10, 25, 50, 100 dst supaya lebih rapi
    final nice = [1, 5, 10, 25, 50, 100, 250, 500, 1000];
    for (final n in nice) {
      if (gridInterval <= n) { gridInterval = n.toDouble(); break; }
    }
    final chartMaxY = gridInterval * 5; // selalu 5 baris grid

    // Tinggi chart: min 200, max ~320 — cukup untuk 10 bar
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
              height: chartHeight + 60, // +60 untuk label bawah
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
                          '${item['name']}\n${rod.toY.toInt()} terjual\n${_formatRupiahCompact(item['revenue'] as double)}',
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
                          // Potong nama panjang: maks 2 baris @ 8 karakter
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
                    // SATU warna konsisten untuk semua bar — rank/posisi
                    // top-3 ditunjukkan lewat panjang bar + medali di legend
                    // di bawah chart, BUKAN lewat warna. Sebelumnya top-3
                    // dikasih hue beda (emas/perak/perunggu): kalau filter
                    // kategori berubah dan item lain naik ke top-3, warnanya
                    // ikut "berpindah" ke item itu — warna jadi mengikuti
                    // RANK, bukan identitas menu, yang bikin re-color
                    // membingungkan tiap kali filter diganti.
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
        // Legend singkat: rank 1-3 & total item
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
                  Text('${item['name']} — ${item['qty']} terjual',
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

  Widget _header() => Text('🏆 Menu Terlaris · ${widget.period.label}',
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

  @override
  Widget build(BuildContext context) {
    final name = item['name'] as String;
    final price = item['price'] as double;
    final cogs = item['cogs'] as double;
    final margin = item['margin'] as double;

    // Status good/warning/critical dari palet tervalidasi — dipakai sebagai
    // warna IKON saja, bukan warna teks. Hex warning (#FAB219) kontrasnya
    // cuma ~1.8:1 di atas putih (di bawah ambang baca teks kecil) — teks
    // persentase sengaja tetap warna tinta netral (textPrimary), semantik
    // dibawa oleh ikon + label kata, bukan warna teks itu sendiri.
    final IconData statusIcon;
    final Color statusColor;
    final String statusLabel;
    if (margin >= 50) {
      statusIcon = Icons.check_circle;
      statusColor = _StatusColors.good;
      statusLabel = 'Sehat';
    } else if (margin >= 30) {
      statusIcon = Icons.warning_rounded;
      statusColor = _StatusColors.warning;
      statusLabel = 'Perlu Diawasi';
    } else {
      statusIcon = Icons.error_rounded;
      statusColor = _StatusColors.critical;
      statusLabel = 'Kritis';
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
                  'Jual ${_formatRupiah(price)}  •  COGS ${cogs > 0 ? _formatRupiah(cogs) : "belum diisi"}  •  $statusLabel',
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
// Sebelumnya dirender pakai LinearProgressIndicator bertumpuk — bukan chart
// fl_chart sungguhan, jadi tidak dapat gridline/tooltip/skala yang konsisten
// dengan 2 chart lain di dashboard ini. Diganti BarChart vertikal dengan
// bahasa visual SAMA seperti Revenue Trend & Menu Terlaris (1 warna brand
// konsisten, grid horizontal tipis, tooltip nominal penuh saat disentuh) —
// cabang #1 ditandai lewat mahkota+bold di legend, BUKAN lewat hue berbeda.

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
        // Cabang #1 ditandai lewat label, bukan warna beda di chart.
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Row(
            children: [
              const Text('👑 ', style: TextStyle(fontSize: 13)),
              Flexible(
                child: Text(
                  '${branchRevenue.first['name']} — ${_formatRupiah(branchRevenue.first['revenue'] as double)} bulan ini',
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