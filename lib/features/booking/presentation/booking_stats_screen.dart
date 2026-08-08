import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/widgets/staff_shell.dart';

class BookingStatsScreen extends ConsumerStatefulWidget {
  const BookingStatsScreen({super.key});

  @override
  ConsumerState<BookingStatsScreen> createState() => _BookingStatsScreenState();
}

class _BookingStatsScreenState extends ConsumerState<BookingStatsScreen> {
  bool _isLoading = true;
  String? _branchId;

  // ── Branch filter (superadmin only) ──────────────────
  bool _isSuperAdmin = false;
  List<Map<String, dynamic>> _branches = [];
  String? _selectedBranchId; // null = all branches

  // ── Selected period ────────────────────────────────────
  _Period _period = _Period.week;

  // ── Statistics data ────────────────────────────────────
  int _totalBookings    = 0;
  int _totalPax         = 0;
  int _confirmedCount   = 0;
  int _cancelledCount   = 0;
  int _noShowCount      = 0;
  int _completedCount   = 0;
  int _waitlistedCount  = 0;

  // Peak hours: key = hour (0-23), value = booking count
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
      _branchId     = staff.branchId;
      _isSuperAdmin = staff.role.name == 'superadmin';
      if (_isSuperAdmin) {
        _loadBranches();
      }
      _loadStats();
    }
  }

  // ── Load all branches (superadmin only) ───────────────
  Future<void> _loadBranches() async {
    try {
      final res = await Supabase.instance.client
          .from('branches')
          .select('id, name')
          .eq('is_active', true)
          .order('name');
      if (mounted) {
        setState(() =>
            _branches = (res as List).cast<Map<String, dynamic>>());
      }
    } catch (e) {
      debugPrint('_loadBranches error: $e');
    }
  }

  // ── Compute the date range based on the period ────────
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
    if (!_isSuperAdmin && _branchId == null) return;
    setState(() => _isLoading = true);

    // Superadmin: use _selectedBranchId (null = all branches)
    // Other roles: must use their own _branchId
    final effectiveBranchId = _isSuperAdmin ? _selectedBranchId : _branchId;

    try {
      final (start, end) = _dateRange();
      var q = Supabase.instance.client
          .from('bookings')
          .select(
              'status, guest_count, booking_date, booking_time, source, created_at')
          .gte('booking_date', _fmtDate(start))
          .lte('booking_date', _fmtDate(end));

      if (effectiveBranchId != null) {
        q = q.eq('branch_id', effectiveBranchId);
      }

      final res = await q;
      final rows = (res as List).cast<Map<String, dynamic>>();

      // Reset all counters
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

        // Lead time: booking_date - created_at difference in days
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

  // ── Rate calculations ──────────────────────────────────
  double get _cancellationRate =>
      _totalBookings == 0 ? 0 : _cancelledCount / _totalBookings * 100;
  double get _noShowRate =>
      _totalBookings == 0 ? 0 : _noShowCount / _totalBookings * 100;
  double get _completionRate =>
      _totalBookings == 0 ? 0 : _completedCount / _totalBookings * 100;

  @override
  Widget build(BuildContext context) {
    return StaffShell(
      pageTitle: 'Booking Stats',
      activeRoute: AppRoutes.reports,
      topBarActions: [
        // ── BRANCH FILTER DROPDOWN (superadmin only) ──
        if (_isSuperAdmin)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _selectedBranchId,
                isDense: true,
                icon: const Icon(Icons.keyboard_arrow_down,
                    size: 16, color: AppColors.textSecondary),
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: AppColors.textPrimary),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All Branches',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 12))),
                  ..._branches.map((b) => DropdownMenuItem<String?>(
                        value: b['id'] as String,
                        child: Text(b['name'] as String,
                            style: const TextStyle(
                                fontFamily: 'Poppins', fontSize: 12)))),
                ],
                onChanged: (val) {
                  setState(() => _selectedBranchId = val);
                  _loadStats();
                },
              ),
            ),
          ),
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
          onPressed: _loadStats,
        ),
      ],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: _loadStats,
              color: AppColors.primary,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 900;
                  return ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 24),
                      _buildPeriodSelector(),
                      const SizedBox(height: 20),
                      _buildSummaryCards(isWide),
                      const SizedBox(height: 20),
                      if (isWide)
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(flex: 2, child: _buildPeakHoursChart()),
                              const SizedBox(width: 20),
                              Expanded(flex: 1, child: _buildStatusBreakdown()),
                            ],
                          ),
                        )
                      else ...[
                        _buildPeakHoursChart(),
                        const SizedBox(height: 20),
                        _buildStatusBreakdown(),
                      ],
                      const SizedBox(height: 20),
                      _buildSourceBreakdown(),
                      const SizedBox(height: 20),
                      _buildDailyTrend(),
                      const SizedBox(height: 24),
                    ],
                  );
                },
              ),
            ),
    );
  }

  // ── Page header ─────────────────────────────────────────
  Widget _buildHeader() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Booking Stats',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
        SizedBox(height: 4),
        Text('Overview of reservation performance.',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: AppColors.textSecondary)),
      ],
    );
  }

  // ── Period selector ────────────────────────────────────
  Widget _buildPeriodSelector() {
    return Wrap(
      spacing: 10,
      children: [
        for (final p in _Period.values)
          GestureDetector(
            onTap: () {
              setState(() => _period = p);
              _loadStats();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: _period == p ? AppColors.surface : AppColors.surface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border: Border.all(
                    color: _period == p ? AppColors.textPrimary : AppColors.border,
                    width: _period == p ? 1.4 : 1),
              ),
              child: Text(p.label,
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: _period == p
                          ? AppColors.textPrimary
                          : AppColors.textSecondary)),
            ),
          ),
      ],
    );
  }

  // ── Summary cards: total booking, total pax, lead time ─
  Widget _buildSummaryCards(bool isWide) {
    final cards = [
      _summaryCard(
        label: 'Total Booking',
        value: '$_totalBookings',
        icon: Icons.event_note_outlined,
        topColor: AppColors.accent,
      ),
      _summaryCard(
        label: 'Total Guests',
        value: '$_totalPax',
        icon: Icons.people_outline,
        topColor: AppColors.badgeDark,
      ),
      _summaryCard(
        label: 'Avg Lead Time',
        value: '${_avgLeadTimeDays.toStringAsFixed(1)}d',
        icon: Icons.schedule_outlined,
        topColor: AppColors.primary,
        subtitle: 'days in advance',
      ),
    ];

    if (!isWide) {
      return Column(children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          cards[i],
        ],
      ]);
    }

    return Row(children: [
      for (var i = 0; i < cards.length; i++) ...[
        if (i > 0) const SizedBox(width: 16),
        Expanded(child: cards[i]),
      ],
    ]);
  }

  Widget _summaryCard({
    required String label,
    required String value,
    required IconData icon,
    required Color topColor,
    String? subtitle,
  }) =>
      Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 3, color: topColor),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(label.toUpperCase(),
                          style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: AppColors.textSecondary)),
                      const Spacer(),
                      Icon(icon, size: 16, color: AppColors.textHint),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(value,
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            color: AppColors.textHint)),
                  ],
                ],
              ),
            ),
          ],
        ),
      );

  // ── Card shell shared by chart / breakdown panels ──────
  Widget _panel({required String title, required String subtitle, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(subtitle,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }

  // Multi-shade turmeric/clay bar palette, cycling by relative intensity.
  Color _barColor(double ratio, {required bool isPeak}) {
    if (isPeak) return AppColors.accent;
    if (ratio >= 0.6) return AppColors.primary;
    if (ratio >= 0.3) return AppColors.accentOrange;
    return AppColors.primaryLight;
  }

  // ── Peak hours bar chart (manual, no library) ──────────
  Widget _buildPeakHoursChart() {
    if (_peakHours.isEmpty) {
      return _panel(
        title: 'Reservation Volume by Time Slot',
        subtitle: 'Busiest hours by booking count',
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(
              child: Text('No bookings in this period',
                  style: TextStyle(fontFamily: 'Poppins', color: AppColors.textHint))),
        ),
      );
    }

    final maxVal = _peakHours.values.fold(0, (a, b) => a > b ? a : b);
    // Show operating hours: 10:00 - 22:00
    final hours = List.generate(13, (i) => i + 10);

    return _panel(
      title: 'Reservation Volume by Time Slot',
      subtitle: 'Busiest hours by booking count',
      child: SizedBox(
        height: 140,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: hours.map((h) {
            final count  = _peakHours[h] ?? 0;
            final ratio  = maxVal == 0 ? 0.0 : count / maxVal;
            final isPeak = count == maxVal && maxVal > 0;
            final barColor = _barColor(ratio, isPeak: isPeak);
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (count > 0)
                      Text('$count',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: isPeak ? AppColors.accent : AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      height: ratio * 95 + (count > 0 ? 6 : 0),
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(h.toString().padLeft(2, '0'),
                        style: const TextStyle(
                            fontFamily: 'Poppins', fontSize: 10, color: AppColors.textHint)),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── Status breakdown (side panel, "weekly summary"-style list) ─
  Widget _buildStatusBreakdown() {
    final rows = [
      ('Completed', _completedCount, _completionRate, const Color(0xFF4CAF50)),
      ('Confirmed', _confirmedCount,
          _totalBookings == 0 ? 0.0 : _confirmedCount / _totalBookings * 100,
          AppColors.primary),
      ('Waitlist', _waitlistedCount,
          _totalBookings == 0 ? 0.0 : _waitlistedCount / _totalBookings * 100,
          AppColors.accentOrange),
      ('No Show', _noShowCount, _noShowRate, AppColors.badgeDark),
      ('Cancelled', _cancelledCount, _cancellationRate, AppColors.accent),
    ];

    return _panel(
      title: 'Status Breakdown',
      subtitle: 'Bookings by outcome, this period',
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(color: rows[i].$4, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(rows[i].$1,
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
                  ),
                  Text('${rows[i].$2}',
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(width: 8),
                  Text('(${rows[i].$3.toStringAsFixed(1)}%)',
                      style: const TextStyle(
                          fontFamily: 'Poppins', fontSize: 11, color: AppColors.textHint)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Source breakdown ────────────────────────────────────
  Widget _buildSourceBreakdown() {
    if (_sourceBreakdown.isEmpty) return const SizedBox.shrink();

    final sourceLabels = {
      'app':        ('📱', 'App'),
      'website':    ('🌐', 'Website'),
      'ai_chatbot': ('🤖', 'AI Chatbot'),
      'phone':      ('📞', 'Phone'),
      'walk_in':    ('🚶', 'Walk-in'),
      'whatsapp':   ('💬', 'WhatsApp'),
    };

    // Sort from most to least
    final sorted = _sourceBreakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final palette = [
      AppColors.primary, AppColors.accent, AppColors.accentOrange,
      AppColors.primaryLight, AppColors.badgeDark, AppColors.iconAccentBlue,
    ];

    return _panel(
      title: 'Booking Channel',
      subtitle: 'Where guests make their reservations',
      child: Column(children: [
        ...sorted.map((e) {
          final info  = sourceLabels[e.key] ?? ('📋', e.key);
          final pct   = _totalBookings == 0 ? 0.0 : e.value / _totalBookings;
          final color = palette[sorted.indexOf(e) % palette.length];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
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
                      backgroundColor: color.withValues(alpha: 0.12),
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

  // ── Daily trend: last 7/30/90 days ─────────────────────
  Widget _buildDailyTrend() {
    if (_dailyTrend.isEmpty) return const SizedBox.shrink();

    final (start, end) = _dateRange();
    final days = end.difference(start).inDays + 1;
    final dates = List.generate(
        days, (i) => _fmtDate(start.add(Duration(days: i))));

    final maxVal = dates
        .map((d) => _dailyTrend[d] ?? 0)
        .fold(0, (a, b) => a > b ? a : b);

    return _panel(
      title: 'Daily Trend',
      subtitle: 'Number of bookings per day',
      child: SizedBox(
        height: 110,
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
                width: 38,
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
                              color: isToday ? AppColors.accent : AppColors.primary)),
                    const SizedBox(height: 3),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: ratio * 65 + (count > 0 ? 4 : 2),
                      decoration: BoxDecoration(
                        color: isToday
                            ? AppColors.accent
                            : AppColors.primary.withValues(alpha: 0.55),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(label,
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 9,
                            fontWeight: isToday ? FontWeight.w700 : FontWeight.normal,
                            color: isToday ? AppColors.accent : AppColors.textHint)),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

// ── Period enum ────────────────────────────────────────────
enum _Period {
  week('7 Days'),
  month('This Month'),
  quarter('90 Days');

  final String label;
  const _Period(this.label);
}
