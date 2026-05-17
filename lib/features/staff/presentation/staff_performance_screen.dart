import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────
class StaffPerformance {
  final String staffId;
  final String fullName;
  final String role;
  final int totalOrdersAsWaiter;
  final int completedOrdersWaiter;
  final int cancelledOrdersWaiter;
  final double revenueHandled;
  final int totalOrdersAsCashier;
  final int completedOrdersCashier;
  final double revenueProcessed;
  final int totalOrdersCombined;
  final double totalRevenueContribution;
  final int daysHadir;
  final int daysAlpha;
  final int daysIzin;
  final int daysSakit;
  final int daysCuti;
  final double avgWorkHours;
  final double attendanceRatePct;
  final double orderCompletionRatePct;
  // --- field baru ---
  final int totalShiftsScheduled;
  final int onTimeShifts;
  final double punctualityRatePct;
  final double attendanceScore;
  final double orderScore;
  final double punctualityScore;
  final double finalScore;
  final String grade;

  const StaffPerformance({
    required this.staffId,
    required this.fullName,
    required this.role,
    required this.totalOrdersAsWaiter,
    required this.completedOrdersWaiter,
    required this.cancelledOrdersWaiter,
    required this.revenueHandled,
    required this.totalOrdersAsCashier,
    required this.completedOrdersCashier,
    required this.revenueProcessed,
    required this.totalOrdersCombined,
    required this.totalRevenueContribution,
    required this.daysHadir,
    required this.daysAlpha,
    required this.daysIzin,
    required this.daysSakit,
    required this.daysCuti,
    required this.avgWorkHours,
    required this.attendanceRatePct,
    required this.orderCompletionRatePct,
    required this.totalShiftsScheduled,
    required this.onTimeShifts,
    required this.punctualityRatePct,
    required this.attendanceScore,
    required this.orderScore,
    required this.punctualityScore,
    required this.finalScore,
    required this.grade,
  });

  factory StaffPerformance.fromMap(Map<String, dynamic> map) {
    return StaffPerformance(
      staffId: map['staff_id'] ?? '',
      fullName: map['full_name'] ?? '',
      role: map['role'] ?? '',
      totalOrdersAsWaiter: (map['total_orders_as_waiter'] ?? 0) as int,
      completedOrdersWaiter: (map['completed_orders_waiter'] ?? 0) as int,
      cancelledOrdersWaiter: (map['cancelled_orders_waiter'] ?? 0) as int,
      revenueHandled: _toDouble(map['revenue_handled']),
      totalOrdersAsCashier: (map['total_orders_as_cashier'] ?? 0) as int,
      completedOrdersCashier: (map['completed_orders_cashier'] ?? 0) as int,
      revenueProcessed: _toDouble(map['revenue_processed']),
      totalOrdersCombined: (map['total_orders_combined'] ?? 0) as int,
      totalRevenueContribution: _toDouble(map['total_revenue_contribution']),
      daysHadir: (map['days_hadir'] ?? 0) as int,
      daysAlpha: (map['days_alpha'] ?? 0) as int,
      daysIzin: (map['days_izin'] ?? 0) as int,
      daysSakit: (map['days_sakit'] ?? 0) as int,
      daysCuti: (map['days_cuti'] ?? 0) as int,
      avgWorkHours: _toDouble(map['avg_work_hours']),
      attendanceRatePct: _toDouble(map['attendance_rate_pct']),
      orderCompletionRatePct: _toDouble(map['order_completion_rate_pct']),
      totalShiftsScheduled: (map['total_shifts_scheduled'] ?? 0) as int,
      onTimeShifts: (map['on_time_shifts'] ?? 0) as int,
      punctualityRatePct: _toDouble(map['punctuality_rate_pct']),
      attendanceScore: _toDouble(map['attendance_score']),
      orderScore: _toDouble(map['order_score']),
      punctualityScore: _toDouble(map['punctuality_score']),
      finalScore: _toDouble(map['final_score']),
      grade: map['grade'] ?? 'D',
    );
  }

  static double _toDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is double) return val;
    if (val is int) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0.0;
  }
}

// ─────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────
class StaffPerformanceScreen extends StatefulWidget {
  final String branchId;

  const StaffPerformanceScreen({super.key, required this.branchId});

  @override
  State<StaffPerformanceScreen> createState() => _StaffPerformanceScreenState();
}

class _StaffPerformanceScreenState extends State<StaffPerformanceScreen> {
  final _currency = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  List<StaffPerformance> _data = [];
  bool _isLoading = true;
  String? _error;

  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  String _selectedRole = 'all';
  static const _roles = ['all', 'waiter', 'cashier', 'manager', 'kitchen', 'host'];

  // ── Branch filter ──────────────────────────────────────
  List<Map<String, dynamic>> _branches = [];
  String? _selectedBranchId;
  bool _isSuperAdmin = false;

  @override
  void initState() {
    super.initState();
    _selectedBranchId = widget.branchId.isEmpty ? null : widget.branchId;
    initializeDateFormatting('id_ID', null).then((_) async {
      await _checkSuperAdminAndFetchBranches();
      _loadData();
    });
  }

  Future<void> _checkSuperAdminAndFetchBranches() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final res = await Supabase.instance.client
          .from('staff')
          .select('role')
          .eq('user_id', userId)
          .maybeSingle();
      if (res != null && res['role'] == 'superadmin') {
        _isSuperAdmin = true;
        final branches = await Supabase.instance.client
            .from('branches')
            .select('id, name')
            .eq('is_active', true)
            .order('name');
        if (mounted) {
          setState(() {
            _branches = List<Map<String, dynamic>>.from(branches);
          });
        }
      }
    } catch (e) {
      debugPrint('_checkSuperAdminAndFetchBranches error: $e');
    }
  }

  Future<void> _loadData() async {
    final effectiveBranchId = _selectedBranchId ?? (widget.branchId.isNotEmpty ? widget.branchId : null);
    if (effectiveBranchId == null) {
      // Semua Cabang dipilih tapi tidak ada default branch — tampilkan kosong
      setState(() { _data = []; _isLoading = false; });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final monthStart = DateTime(_selectedMonth.year, _selectedMonth.month);
      final monthEnd = DateTime(_selectedMonth.year, _selectedMonth.month + 1);

      final response = await Supabase.instance.client.rpc(
        'get_staff_performance',
        params: {
          'p_branch_id': effectiveBranchId,
          'p_month_start': monthStart.toIso8601String(),
          'p_month_end': monthEnd.toIso8601String(),
        },
      );

      final List<StaffPerformance> result = (response as List)
          .map((e) => StaffPerformance.fromMap(e as Map<String, dynamic>))
          .toList();

      setState(() {
        _data = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  List<StaffPerformance> get _filtered {
    if (_selectedRole == 'all') return _data;
    return _data.where((s) => s.role == _selectedRole).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        title: const Text('Staff Performance'),
        centerTitle: false,
        actions: [
          // ── Branch filter dropdown (superadmin only) ──
          if (_isSuperAdmin && _branches.isNotEmpty)
            DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _selectedBranchId,
                isDense: true,
                dropdownColor: const Color(0xFF1A1A2E),
                iconEnabledColor: Colors.white60,
                icon: const Icon(Icons.keyboard_arrow_down, size: 16),
                style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 11, color: Colors.white70),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Semua Cabang',
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 11, color: Colors.white70))),
                  ..._branches.map((b) => DropdownMenuItem<String?>(
                    value: b['id'] as String,
                    child: Text(b['name'] as String,
                      style: const TextStyle(
                        fontFamily: 'Poppins', fontSize: 11, color: Colors.white)))),
                ],
                onChanged: (val) {
                  setState(() {
                    _selectedBranchId = val;
                    _data = [];
                  });
                  _loadData();
                },
              ),
            ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilters(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildError()
                    : _filtered.isEmpty
                        ? const Center(
                            child: Text(
                              'Tidak ada data staff.',
                              style: TextStyle(color: Colors.white54),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (_, i) =>
                                _StaffCard(staff: _filtered[i], currency: _currency),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      color: const Color(0xFF16213E),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Month picker
          GestureDetector(
            onTap: _pickMonth,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0F3460),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month, size: 16, color: Colors.white70),
                  const SizedBox(width: 6),
                  Text(
                    DateFormat('MMM yyyy', 'id_ID').format(_selectedMonth),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Role filter
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _roles.map((role) {
                  final selected = _selectedRole == role;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(
                        role == 'all' ? 'Semua' : role,
                        style: TextStyle(
                          fontSize: 12,
                          color: selected ? Colors.white : Colors.white60,
                        ),
                      ),
                      selected: selected,
                      selectedColor: const Color(0xFFE94560),
                      backgroundColor: const Color(0xFF0F3460),
                      onSelected: (_) => setState(() => _selectedRole = role),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      helpText: 'Pilih Bulan',
    );
    if (picked != null) {
      setState(() {
        _selectedMonth = DateTime(picked.year, picked.month);
      });
      _loadData();
    }
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFE94560), size: 48),
            const SizedBox(height: 12),
            Text(
              'Gagal memuat data:\n$_error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadData,
              child: const Text('Coba Lagi'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Staff Card Widget
// ─────────────────────────────────────────────
class _StaffCard extends StatelessWidget {
  final StaffPerformance staff;
  final NumberFormat currency;

  const _StaffCard({required this.staff, required this.currency});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: CircleAvatar(
            backgroundColor: _roleColor(staff.role).withValues(alpha: 0.2),
            child: Text(
              staff.fullName.isNotEmpty ? staff.fullName[0].toUpperCase() : '?',
              style: TextStyle(
                color: _roleColor(staff.role),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          title: Text(
            staff.fullName,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Row(
            children: [
              _RoleBadge(role: staff.role),
              const SizedBox(width: 8),
              Text(
                '${staff.totalOrdersCombined} orders',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
          // Trailing: tampilkan grade + final score
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _GradeBadge(grade: staff.grade),
              const SizedBox(height: 2),
              Text(
                '${staff.finalScore.toStringAsFixed(1)} pts',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
          children: [
            const Divider(color: Colors.white10),
            const SizedBox(height: 8),

            // ── Score Summary ──
            _ScoreSummaryRow(staff: staff),
            const SizedBox(height: 12),

            // ── Order sebagai Waiter ──
            if (staff.role == 'waiter' || staff.totalOrdersAsWaiter > 0) ...[
              const _SectionTitle(title: 'Sebagai Waiter', icon: Icons.restaurant),
              const SizedBox(height: 8),
              _MetricsRow(children: [
                _MetricTile(
                  label: 'Total Order',
                  value: '${staff.totalOrdersAsWaiter}',
                  icon: Icons.receipt_long,
                ),
                _MetricTile(
                  label: 'Selesai',
                  value: '${staff.completedOrdersWaiter}',
                  icon: Icons.check_circle_outline,
                  color: const Color(0xFF4CAF50),
                ),
                _MetricTile(
                  label: 'Batal',
                  value: '${staff.cancelledOrdersWaiter}',
                  icon: Icons.cancel_outlined,
                  color: const Color(0xFFE94560),
                ),
                _MetricTile(
                  label: 'Completion',
                  value: '${staff.orderCompletionRatePct.toStringAsFixed(0)}%',
                  icon: Icons.pie_chart_outline,
                  color: const Color(0xFFFFB74D),
                ),
              ]),
              const SizedBox(height: 4),
              _RevenueTile(
                label: 'Revenue ditangani',
                value: currency.format(staff.revenueHandled),
              ),
              const SizedBox(height: 12),
            ],

            // ── Order sebagai Kasir ──
            if (staff.role == 'cashier' || staff.totalOrdersAsCashier > 0) ...[
              const _SectionTitle(title: 'Sebagai Kasir', icon: Icons.point_of_sale),
              const SizedBox(height: 8),
              _MetricsRow(children: [
                _MetricTile(
                  label: 'Total Order',
                  value: '${staff.totalOrdersAsCashier}',
                  icon: Icons.receipt_long,
                ),
                _MetricTile(
                  label: 'Selesai',
                  value: '${staff.completedOrdersCashier}',
                  icon: Icons.check_circle_outline,
                  color: const Color(0xFF4CAF50),
                ),
              ]),
              const SizedBox(height: 4),
              _RevenueTile(
                label: 'Revenue diproses',
                value: currency.format(staff.revenueProcessed),
              ),
              const SizedBox(height: 12),
            ],

            // ── Kehadiran ──
            const _SectionTitle(title: 'Kehadiran Bulan Ini', icon: Icons.calendar_today),
            const SizedBox(height: 8),
            _MetricsRow(children: [
              _MetricTile(
                label: 'Hadir',
                value: '${staff.daysHadir}',
                icon: Icons.check_circle,
                color: const Color(0xFF4CAF50),
              ),
              _MetricTile(
                label: 'Alpha',
                value: '${staff.daysAlpha}',
                icon: Icons.cancel,
                color: const Color(0xFFE94560),
              ),
              _MetricTile(
                label: 'Izin',
                value: '${staff.daysIzin}',
                icon: Icons.event_busy_outlined,
                color: const Color(0xFF64B5F6),
              ),
              _MetricTile(
                label: 'Sakit',
                value: '${staff.daysSakit}',
                icon: Icons.medical_services_outlined,
                color: const Color(0xFFFFB74D),
              ),
            ]),
            const SizedBox(height: 6),
            _MetricsRow(children: [
              _MetricTile(
                label: 'Cuti',
                value: '${staff.daysCuti}',
                icon: Icons.beach_access_outlined,
                color: const Color(0xFFBA68C8),
              ),
              _MetricTile(
                label: 'Rata Jam',
                value: '${staff.avgWorkHours.toStringAsFixed(1)}j',
                icon: Icons.timer_outlined,
              ),
              const Expanded(child: SizedBox()),
              const Expanded(child: SizedBox()),
            ]),
            const SizedBox(height: 8),
            _AttendanceBar(pct: staff.attendanceRatePct),
            const SizedBox(height: 12),

            // ── Ketepatan Waktu (Punctuality) ──
            const _SectionTitle(title: 'Ketepatan Waktu', icon: Icons.access_time),
            const SizedBox(height: 8),
            _MetricsRow(children: [
              _MetricTile(
                label: 'Total Shift',
                value: '${staff.totalShiftsScheduled}',
                icon: Icons.calendar_view_week,
              ),
              _MetricTile(
                label: 'Tepat Waktu',
                value: '${staff.onTimeShifts}',
                icon: Icons.alarm_on,
                color: const Color(0xFF4CAF50),
              ),
              _MetricTile(
                label: 'Terlambat',
                value: '${staff.totalShiftsScheduled - staff.onTimeShifts}',
                icon: Icons.alarm_off,
                color: const Color(0xFFE94560),
              ),
              const Expanded(child: SizedBox()),
            ]),
            const SizedBox(height: 8),
            _PunctualityBar(pct: staff.punctualityRatePct),
          ],
        ),
      ),
    );
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'manager':
        return const Color(0xFFFFB74D);
      case 'cashier':
        return const Color(0xFF64B5F6);
      case 'waiter':
        return const Color(0xFF81C784);
      case 'kitchen':
        return const Color(0xFFFF8A65);
      case 'host':
        return const Color(0xFFBA68C8);
      default:
        return Colors.white54;
    }
  }
}

// ─────────────────────────────────────────────
// Grade Badge
// ─────────────────────────────────────────────
class _GradeBadge extends StatelessWidget {
  final String grade;
  const _GradeBadge({required this.grade});

  @override
  Widget build(BuildContext context) {
    final colors = {
      'A': const Color(0xFF4CAF50),
      'B': const Color(0xFF64B5F6),
      'C': const Color(0xFFFFB74D),
      'D': const Color(0xFFE94560),
    };
    final color = colors[grade] ?? Colors.white38;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Center(
        child: Text(
          grade,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Score Summary Row
// ─────────────────────────────────────────────
class _ScoreSummaryRow extends StatelessWidget {
  final StaffPerformance staff;
  const _ScoreSummaryRow({required this.staff});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _ScoreItem(label: 'Kehadiran', value: staff.attendanceScore, color: const Color(0xFF4CAF50)),
          _Divider(),
          _ScoreItem(label: 'Order', value: staff.orderScore, color: const Color(0xFF64B5F6)),
          _Divider(),
          _ScoreItem(label: 'Tepat Waktu', value: staff.punctualityScore, color: const Color(0xFFFFB74D)),
          _Divider(),
          _ScoreItem(label: 'Final', value: staff.finalScore, color: const Color(0xFFE94560), isBold: true),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 32, color: Colors.white10);
  }
}

class _ScoreItem extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final bool isBold;

  const _ScoreItem({
    required this.label,
    required this.value,
    required this.color,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value.toStringAsFixed(1),
          style: TextStyle(
            color: color,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            fontSize: isBold ? 16 : 14,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Colors.white38, fontSize: 10),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Helper Widgets
// ─────────────────────────────────────────────
class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final colors = {
      'manager': const Color(0xFFFFB74D),
      'cashier': const Color(0xFF64B5F6),
      'waiter': const Color(0xFF81C784),
      'kitchen': const Color(0xFFFF8A65),
      'host': const Color(0xFFBA68C8),
    };
    final color = colors[role] ?? Colors.white38;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        role,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionTitle({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.white38),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

class _MetricsRow extends StatelessWidget {
  final List<Widget> children;
  const _MetricsRow({required this.children});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: children.map((c) => Expanded(child: c)).toList(),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    this.color = Colors.white70,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white38, fontSize: 10),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _RevenueTile extends StatelessWidget {
  final String label;
  final String value;
  const _RevenueTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF4CAF50).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF4CAF50).withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF4CAF50),
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceBar extends StatelessWidget {
  final double pct;
  const _AttendanceBar({required this.pct});

  @override
  Widget build(BuildContext context) {
    final color = pct >= 80
        ? const Color(0xFF4CAF50)
        : pct >= 60
            ? const Color(0xFFFFB74D)
            : const Color(0xFFE94560);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Attendance Rate',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            Text(
              '${pct.toStringAsFixed(1)}%',
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (pct / 100).clamp(0.0, 1.0),
            backgroundColor: Colors.white10,
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}

class _PunctualityBar extends StatelessWidget {
  final double pct;
  const _PunctualityBar({required this.pct});

  @override
  Widget build(BuildContext context) {
    final color = pct >= 80
        ? const Color(0xFF4CAF50)
        : pct >= 60
            ? const Color(0xFFFFB74D)
            : const Color(0xFFE94560);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Punctuality Rate',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            Text(
              '${pct.toStringAsFixed(1)}%',
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (pct / 100).clamp(0.0, 1.0),
            backgroundColor: Colors.white10,
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}