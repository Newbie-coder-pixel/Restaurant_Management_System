import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/widgets/app_drawer.dart';

class BookingStatsScreen extends ConsumerStatefulWidget {
  const BookingStatsScreen({super.key});

  @override
  ConsumerState<BookingStatsScreen> createState() => _BookingStatsScreenState();
}

class _BookingStatsScreenState extends ConsumerState<BookingStatsScreen> {
  bool _isLoading = true;
  String? _branchId;

  // ── Periode yang dipilih ──────────────────────────────
  _Period _period = _Period.week;

  // ── Data statistik ────────────────────────────────────
  int _totalBookings    = 0;
  int _totalPax         = 0;
  int _confirmedCount   = 0;
  int _cancelledCount   = 0;
  int _noShowCount      = 0;
  int _completedCount   = 0;
  int _waitlistedCount  = 0;

  // Peak hours: key = jam (0-23), value = jumlah booking
  Map<int, int> _peakHours = {};

  // Source breakdown: key = source string, value = count
  Map<String, int> _sourceBreakdown = {};

  // Daily trend: key = 'yyyy-MM-dd', value = count
  Map<String, int> _dailyTrend = {};

  // Avg lead time in days
  double _avgLeadTimeDays = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final staff = ref.read(currentStaffProvider);
    if (staff != null && _branchId == null) {
      _branchId = staff.branchId;
      _loadStats();
    }
  }

  // ── Hitung rentang tanggal berdasarkan periode ────────
  (DateTime, DateTime) _dateRange() {
    final now = DateTime.now();
    switch (_period) {
      case _Period.week:
        return (now.subtract(const Duration(days: 6)), now);
      case _Period.month:
        return (DateTime(now.year, now.month, 1), now);
      case _Period.quarter:
        return (now.subtract(const Duration(days: 89)), now);
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _loadStats() async {
    if (_branchId == null) return;
    setState(() => _isLoading = true);

    try {
      final (start, end) = _dateRange();
      final res = await Supabase.instance.client
          .from('bookings')
          .select(
              'status, guest_count, booking_date, booking_time, source, created_at')
          .eq('branch_id', _branchId!)
          .gte('booking_date', _fmtDate(start))
          .lte('booking_date', _fmtDate(end));

      final rows = (res as List).cast<Map<String, dynamic>>();

      // Reset semua counter
      int total = 0, pax = 0, confirmed = 0, cancelled = 0,
          noShow = 0, completed = 0, waitlisted = 0;
      final hours    = <int, int>{};
      final sources  = <String, int>{};
      final daily    = <String, int>{};
      double leadSum = 0;
      int leadCount  = 0;

      for (final r in rows) {
        total++;
        pax += (r['guest_count'] as int?) ?? 0;

        final status = r['status'] as String? ?? '';
        switch (status) {
          case 'confirmed':  confirmed++;  break;
          case 'cancelled':  cancelled++;  break;
          case 'no_show':    noShow++;     break;
          case 'completed':  completed++;  break;
          case 'waitlisted': waitlisted++; break;
        }

        // Peak hours
        final timeRaw = r['booking_time'] as String? ?? '00:00:00';
        final hour    = int.tryParse(timeRaw.split(':')[0]) ?? 0;
        hours[hour]   = (hours[hour] ?? 0) + 1;

        // Source
        final src   = r['source'] as String? ?? 'app';
        sources[src] = (sources[src] ?? 0) + 1;

        // Daily trend
        final date  = r['booking_date'] as String? ?? '';
        daily[date] = (daily[date] ?? 0) + 1;

        // Lead time: selisih booking_date - created_at dalam hari
        final bookingDate = DateTime.tryParse(date);
        final createdAt   = DateTime.tryParse(r['created_at'] as String? ?? '');
        if (bookingDate != null && createdAt != null) {
          final diff = bookingDate.difference(createdAt).inHours / 24.0;
          if (diff >= 0) {
            leadSum  += diff;
            leadCount++;
          }
        }
      }

      setState(() {
        _totalBookings   = total;
        _totalPax        = pax;
        _confirmedCount  = confirmed;
        _cancelledCount  = cancelled;
        _noShowCount     = noShow;
        _completedCount  = completed;
        _waitlistedCount = waitlisted;
        _peakHours       = hours;
        _sourceBreakdown = sources;
        _dailyTrend      = daily;
        _avgLeadTimeDays = leadCount > 0 ? leadSum / leadCount : 0;
        _isLoading       = false;
      });
    } catch (e) {
      debugPrint('error loadStats = $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Rate kalkulasi ─────────────────────────────────────
  double get _cancellationRate =>
      _totalBookings == 0 ? 0 : _cancelledCount / _totalBookings * 100;
  double get _noShowRate =>
      _totalBookings == 0 ? 0 : _noShowCount / _totalBookings * 100;
  double get _completionRate =>
      _totalBookings == 0 ? 0 : _completedCount / _totalBookings * 100;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Statistik Booking'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        titleTextStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStats,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStats,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildPeriodSelector(),
                  const SizedBox(height: 16),
                  _buildSummaryCards(),
                  const SizedBox(height: 16),
                  _buildRateCards(),
                  const SizedBox(height: 16),
                  _buildPeakHoursChart(),
                  const SizedBox(height: 16),
                  _buildSourceBreakdown(),
                  const SizedBox(height: 16),
                  _buildDailyTrend(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  // ── Period selector ────────────────────────────────────
  Widget _buildPeriodSelector() {
    return Row(children: [
      for (final p in _Period.values)
        Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() => _period = p);
              _loadStats();
            },
            child: Container(
              margin: EdgeInsets.only(right: p != _Period.quarter ? 8 : 0),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: _period == p ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: _period == p
                        ? AppColors.primary
                        : const Color(0xFFE8EAED)),
              ),
              child: Text(p.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _period == p ? Colors.white : AppColors.textSecondary)),
            ),
          ),
        ),
    ]);
  }

  // ── Summary cards: total booking, total pax, lead time ─
  Widget _buildSummaryCards() {
    return Row(children: [
      Expanded(child: _summaryCard(
        label: 'Total Booking',
        value: '$_totalBookings',
        icon: Icons.event_note_outlined,
        color: AppColors.primary,
      )),
      const SizedBox(width: 10),
      Expanded(child: _summaryCard(
        label: 'Total Tamu',
        value: '$_totalPax',
        icon: Icons.people_outline,
        color: AppColors.available,
      )),
      const SizedBox(width: 10),
      Expanded(child: _summaryCard(
        label: 'Avg Lead Time',
        value: '${_avgLeadTimeDays.toStringAsFixed(1)}h',
        icon: Icons.schedule_outlined,
        color: AppColors.reserved,
        subtitle: 'hari sebelum',
      )),
    ]);
  }

  Widget _summaryCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    String? subtitle,
  }) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: color)),
          Text(label,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: AppColors.textSecondary)),
          if (subtitle != null)
            Text(subtitle,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10,
                    color: AppColors.textHint)),
        ]),
      );

  // ── Rate cards: cancellation, no-show, completion ──────
  Widget _buildRateCards() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Breakdown Status',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 14)),
        const SizedBox(height: 14),
        _rateRow('Selesai', _completedCount, _completionRate,
            const Color(0xFF4CAF50)),
        _rateRow('Dibatalkan', _cancelledCount, _cancellationRate,
            AppColors.accent),
        _rateRow('Tidak Hadir', _noShowCount, _noShowRate, Colors.orange),
        _rateRow('Dikonfirmasi', _confirmedCount,
            _totalBookings == 0 ? 0 : _confirmedCount / _totalBookings * 100,
            AppColors.available),
        _rateRow('Waitlist', _waitlistedCount,
            _totalBookings == 0 ? 0 : _waitlistedCount / _totalBookings * 100,
            const Color(0xFF7B1FA2)),
      ]),
    );
  }

  Widget _rateRow(String label, int count, double pct, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 12)),
          ),
          Text('$count  (${pct.toStringAsFixed(1)}%)',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _totalBookings == 0 ? 0 : count / _totalBookings,
            backgroundColor: color.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 6,
          ),
        ),
      ]),
    );
  }

  // ── Peak hours bar chart (manual, tanpa library) ───────
  Widget _buildPeakHoursChart() {
    if (_peakHours.isEmpty) return const SizedBox.shrink();

    final maxVal = _peakHours.values.fold(0, (a, b) => a > b ? a : b);
    // Tampilkan jam operasional: 10:00 - 22:00
    final hours = List.generate(13, (i) => i + 10);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Peak Hours',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 14)),
        const SizedBox(height: 4),
        const Text('Jam tersibuk berdasarkan jumlah booking',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                color: AppColors.textHint)),
        const SizedBox(height: 16),
        SizedBox(
          height: 100,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: hours.map((h) {
              final count  = _peakHours[h] ?? 0;
              final ratio  = maxVal == 0 ? 0.0 : count / maxVal;
              final isPeak = count == maxVal && maxVal > 0;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (count > 0)
                        Text('$count',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: isPeak
                                    ? AppColors.accent
                                    : AppColors.textSecondary)),
                      const SizedBox(height: 2),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        height: ratio * 70 + (count > 0 ? 4 : 0),
                        decoration: BoxDecoration(
                          color: isPeak
                              ? AppColors.accent
                              : AppColors.primary.withValues(alpha: 0.6),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(3)),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(h.toString().padLeft(2, '0'),
                          style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 9,
                              color: AppColors.textHint)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ]),
    );
  }

  // ── Source breakdown ────────────────────────────────────
  Widget _buildSourceBreakdown() {
    if (_sourceBreakdown.isEmpty) return const SizedBox.shrink();

    final sourceLabels = {
      'app':        ('📱', 'App'),
      'website':    ('🌐', 'Website'),
      'ai_chatbot': ('🤖', 'AI Chatbot'),
      'phone':      ('📞', 'Telepon'),
      'walk_in':    ('🚶', 'Walk-in'),
      'whatsapp':   ('💬', 'WhatsApp'),
    };

    // Urut dari terbanyak
    final sorted = _sourceBreakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Channel Booking',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 14)),
        const SizedBox(height: 4),
        const Text('Dari mana tamu melakukan reservasi',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                color: AppColors.textHint)),
        const SizedBox(height: 14),
        ...sorted.map((e) {
          final info  = sourceLabels[e.key] ?? ('📋', e.key);
          final pct   = _totalBookings == 0 ? 0.0 : e.value / _totalBookings;
          final colors = [
            AppColors.primary, AppColors.accent, AppColors.available,
            AppColors.reserved, const Color(0xFF7B1FA2), Colors.teal,
          ];
          final color = colors[sorted.indexOf(e) % colors.length];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Text(info.$1, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    Expanded(
                      child: Text(info.$2,
                          style: const TextStyle(
                              fontFamily: 'Poppins', fontSize: 12)),
                    ),
                    Text('${e.value}  (${(pct * 100).toStringAsFixed(0)}%)',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: color)),
                  ]),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      backgroundColor: color.withValues(alpha: 0.1),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                      minHeight: 6,
                    ),
                  ),
                ]),
              ),
            ]),
          );
        }),
      ]),
    );
  }

  // ── Daily trend: 7/30/90 hari terakhir ─────────────────
  Widget _buildDailyTrend() {
    if (_dailyTrend.isEmpty) return const SizedBox.shrink();

    final (start, end) = _dateRange();
    final days = end.difference(start).inDays + 1;
    final dates = List.generate(
        days, (i) => _fmtDate(start.add(Duration(days: i))));

    final maxVal = dates
        .map((d) => _dailyTrend[d] ?? 0)
        .fold(0, (a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Tren Harian',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 14)),
        const SizedBox(height: 4),
        const Text('Jumlah booking per hari',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                color: AppColors.textHint)),
        const SizedBox(height: 16),
        SizedBox(
          height: 90,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: dates.map((dateStr) {
                final count  = _dailyTrend[dateStr] ?? 0;
                final ratio  = maxVal == 0 ? 0.0 : count / maxVal;
                final parts  = dateStr.split('-');
                final label  = parts.length == 3
                    ? '${parts[2]}/${parts[1]}'
                    : dateStr;
                final isToday = dateStr == _fmtDate(DateTime.now());
                return Container(
                  width: 36,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (count > 0)
                        Text('$count',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: isToday
                                    ? AppColors.accent
                                    : AppColors.primary)),
                      const SizedBox(height: 2),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: ratio * 55 + (count > 0 ? 4 : 2),
                        decoration: BoxDecoration(
                          color: isToday
                              ? AppColors.accent
                              : AppColors.primary.withValues(alpha: 0.5),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(3)),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(label,
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 8,
                              fontWeight: isToday
                                  ? FontWeight.w700
                                  : FontWeight.normal,
                              color: isToday
                                  ? AppColors.accent
                                  : AppColors.textHint)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Period enum ────────────────────────────────────────────
enum _Period {
  week('7 Hari'),
  month('Bulan Ini'),
  quarter('90 Hari');

  final String label;
  const _Period(this.label);
}