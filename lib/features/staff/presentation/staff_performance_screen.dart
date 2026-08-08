import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/staff_role.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';

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
  // --- new fields ---
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
class StaffPerformanceScreen extends ConsumerStatefulWidget {
  // null  = all branches (superadmin "All Branches")
  // ''    = non-superadmin without a branch (edge case, treat as all)
  // id    = specific branch
  final String? branchId;

  const StaffPerformanceScreen({super.key, this.branchId});

  @override
  ConsumerState<StaffPerformanceScreen> createState() => _StaffPerformanceScreenState();
}

class _StaffPerformanceScreenState extends ConsumerState<StaffPerformanceScreen> {
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

  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  // ── Branch filter ──────────────────────────────────────
  List<Map<String, dynamic>> _branches = [];
  String? _selectedBranchId;
  bool _isSuperAdmin = false;

  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    // null or an empty string both mean "all branches"
    _selectedBranchId = (widget.branchId == null || widget.branchId!.isEmpty)
        ? null
        : widget.branchId;
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    final staff = ref.read(currentStaffProvider);
    if (staff != null) {
      _isSuperAdmin = staff.role == StaffRole.superadmin;
      _initialized = true;
      initializeDateFormatting('id_ID', null).then((_) async {
        if (_isSuperAdmin) await _fetchBranches();
        _loadData();
      });
    } else {
      _initialized = true;
      ref.listenManual(currentStaffProvider, (_, next) {
        if (next != null && mounted) {
          setState(() => _isSuperAdmin = next.role == StaffRole.superadmin);
          initializeDateFormatting('id_ID', null).then((_) async {
            if (_isSuperAdmin) await _fetchBranches();
            _loadData();
          });
        }
      });
    }
  }

  Future<void> _fetchBranches() async {
    try {
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
    } catch (e) {
      debugPrint('_fetchBranches error: \$e');
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final monthStart = DateTime(_selectedMonth.year, _selectedMonth.month);
      final monthEnd = DateTime(_selectedMonth.year, _selectedMonth.month + 1);

      // _selectedBranchId == null → all branches (superadmin "All Branches")
      // _selectedBranchId != null → filter to a specific branch
      final response = await Supabase.instance.client.rpc(
        'get_staff_performance',
        params: {
          'p_branch_id': _selectedBranchId, // null is sent as-is to the RPC
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
    var list = _selectedRole == 'all'
        ? _data
        : _data.where((s) => s.role == _selectedRole).toList();
    if (_searchQuery.isNotEmpty) {
      list = list.where((s) =>
          s.fullName.toLowerCase().contains(_searchQuery) ||
          s.role.toLowerCase().contains(_searchQuery)).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: const Text('Staff Performance',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        centerTitle: false,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.border),
        ),
        actions: [
          // ── Branch filter dropdown (superadmin only) ──
          if (_isSuperAdmin && _branches.isNotEmpty)
            DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _selectedBranchId,
                isDense: true,
                dropdownColor: AppColors.surface,
                iconEnabledColor: AppColors.textSecondary,
                icon: const Icon(Icons.keyboard_arrow_down, size: 16),
                style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 11, color: AppColors.textPrimary),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All Branches',
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 11, color: AppColors.textPrimary))),
                  ..._branches.map((b) => DropdownMenuItem<String?>(
                    value: b['id'] as String,
                    child: Text(b['name'] as String,
                      style: const TextStyle(
                        fontFamily: 'Poppins', fontSize: 11, color: AppColors.textPrimary)))),
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
            icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
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
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _error != null
                    ? _buildError()
                    : _filtered.isEmpty
                        ? const Center(
                            child: Text(
                              'No staff data available.',
                              style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary),
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
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Search staff by name or role...',
                      hintStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textHint),
                      prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.textSecondary),
                      filled: true,
                      fillColor: AppColors.surfaceVariant,
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Month picker
              GestureDetector(
                onTap: _pickMonth,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month, size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Text(
                        DateFormat('MMM yyyy', 'id_ID').format(_selectedMonth),
                        style: const TextStyle(fontFamily: 'Poppins', color: AppColors.textPrimary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Role filter
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _roles.map((role) {
                final selected = _selectedRole == role;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(
                      role == 'all' ? 'All Roles' : role,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: selected ? Colors.white : AppColors.textSecondary,
                      ),
                    ),
                    selected: selected,
                    selectedColor: AppColors.primary,
                    backgroundColor: AppColors.surfaceVariant,
                    side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
                    onSelected: (_) => setState(() => _selectedRole = role),
                  ),
                );
              }).toList(),
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
      helpText: 'Select Month',
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
            const Icon(Icons.error_outline, color: AppColors.accent, size: 48),
            const SizedBox(height: 12),
            Text(
              'Failed to load data:\n$_error',
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              onPressed: _loadData,
              child: const Text('Try Again', style: TextStyle(fontFamily: 'Poppins')),
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          iconColor: AppColors.textSecondary,
          collapsedIconColor: AppColors.textSecondary,
          leading: CircleAvatar(
            backgroundColor: _roleColor(staff.role).withValues(alpha: 0.15),
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
              fontFamily: 'Poppins',
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Row(
            children: [
              _RoleBadge(role: staff.role),
              const SizedBox(width: 8),
              Text(
                '${staff.totalOrdersCombined} orders',
                style: const TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
          // Trailing: show grade + final score
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _GradeBadge(grade: staff.grade),
              const SizedBox(height: 2),
              Text(
                '${staff.finalScore.toStringAsFixed(1)} pts',
                style: const TextStyle(fontFamily: 'Poppins', color: AppColors.textHint, fontSize: 11),
              ),
            ],
          ),
          children: [
            const Divider(color: AppColors.border),
            const SizedBox(height: 8),

            // ── Score Summary ──
            _ScoreSummaryRow(staff: staff),
            const SizedBox(height: 12),

            // ── Orders as Waiter ──
            if (staff.role == 'waiter' || staff.totalOrdersAsWaiter > 0) ...[
              const _SectionTitle(title: 'As Waiter', icon: Icons.restaurant),
              const SizedBox(height: 8),
              _MetricsRow(children: [
                _MetricTile(
                  label: 'Total Orders',
                  value: '${staff.totalOrdersAsWaiter}',
                  icon: Icons.receipt_long,
                ),
                _MetricTile(
                  label: 'Completed',
                  value: '${staff.completedOrdersWaiter}',
                  icon: Icons.check_circle_outline,
                  color: const Color(0xFF4CAF50),
                ),
                _MetricTile(
                  label: 'Cancelled',
                  value: '${staff.cancelledOrdersWaiter}',
                  icon: Icons.cancel_outlined,
                  color: AppColors.accent,
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
                label: 'Revenue handled',
                value: currency.format(staff.revenueHandled),
              ),
              const SizedBox(height: 12),
            ],

            // ── Orders as Cashier ──
            if (staff.role == 'cashier' || staff.totalOrdersAsCashier > 0) ...[
              const _SectionTitle(title: 'As Cashier', icon: Icons.point_of_sale),
              const SizedBox(height: 8),
              _MetricsRow(children: [
                _MetricTile(
                  label: 'Total Orders',
                  value: '${staff.totalOrdersAsCashier}',
                  icon: Icons.receipt_long,
                ),
                _MetricTile(
                  label: 'Completed',
                  value: '${staff.completedOrdersCashier}',
                  icon: Icons.check_circle_outline,
                  color: const Color(0xFF4CAF50),
                ),
              ]),
              const SizedBox(height: 4),
              _RevenueTile(
                label: 'Revenue processed',
                value: currency.format(staff.revenueProcessed),
              ),
              const SizedBox(height: 12),
            ],

            // ── Attendance ──
            const _SectionTitle(title: 'Attendance This Month', icon: Icons.calendar_today),
            const SizedBox(height: 8),
            _MetricsRow(children: [
              _MetricTile(
                label: 'Present',
                value: '${staff.daysHadir}',
                icon: Icons.check_circle,
                color: const Color(0xFF4CAF50),
              ),
              _MetricTile(
                label: 'Absent',
                value: '${staff.daysAlpha}',
                icon: Icons.cancel,
                color: AppColors.accent,
              ),
              _MetricTile(
                label: 'Permission',
                value: '${staff.daysIzin}',
                icon: Icons.event_busy_outlined,
                color: const Color(0xFF64B5F6),
              ),
              _MetricTile(
                label: 'Sick',
                value: '${staff.daysSakit}',
                icon: Icons.medical_services_outlined,
                color: const Color(0xFFFFB74D),
              ),
            ]),
            const SizedBox(height: 6),
            _MetricsRow(children: [
              _MetricTile(
                label: 'Leave',
                value: '${staff.daysCuti}',
                icon: Icons.beach_access_outlined,
                color: const Color(0xFFBA68C8),
              ),
              _MetricTile(
                label: 'Avg Hours',
                value: '${staff.avgWorkHours.toStringAsFixed(1)}h',
                icon: Icons.timer_outlined,
              ),
              const Expanded(child: SizedBox()),
              const Expanded(child: SizedBox()),
            ]),
            const SizedBox(height: 8),
            _AttendanceBar(pct: staff.attendanceRatePct),
            const SizedBox(height: 12),

            // ── Punctuality ──
            const _SectionTitle(title: 'Punctuality', icon: Icons.access_time),
            const SizedBox(height: 8),
            _MetricsRow(children: [
              _MetricTile(
                label: 'Total Shifts',
                value: '${staff.totalShiftsScheduled}',
                icon: Icons.calendar_view_week,
              ),
              _MetricTile(
                label: 'On Time',
                value: '${staff.onTimeShifts}',
                icon: Icons.alarm_on,
                color: const Color(0xFF4CAF50),
              ),
              _MetricTile(
                label: 'Late',
                value: '${staff.totalShiftsScheduled - staff.onTimeShifts}',
                icon: Icons.alarm_off,
                color: AppColors.accent,
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
        return AppColors.textSecondary;
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
      'D': AppColors.accent,
    };
    final color = colors[grade] ?? AppColors.textHint;
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
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _ScoreItem(label: 'Attendance', value: staff.attendanceScore, color: const Color(0xFF4CAF50)),
          _Divider(),
          _ScoreItem(label: 'Order', value: staff.orderScore, color: const Color(0xFF2196F3)),
          _Divider(),
          _ScoreItem(label: 'Punctuality', value: staff.punctualityScore, color: const Color(0xFFD97706)),
          _Divider(),
          _ScoreItem(label: 'Final', value: staff.finalScore, color: AppColors.accent, isBold: true),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 32, color: AppColors.border);
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
            fontFamily: 'Poppins',
            color: color,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            fontSize: isBold ? 16 : 14,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontFamily: 'Poppins', color: AppColors.textHint, fontSize: 10),
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
    final color = colors[role] ?? AppColors.textHint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        role,
        style: TextStyle(fontFamily: 'Poppins', color: color, fontSize: 10, fontWeight: FontWeight.w600),
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
        Icon(icon, size: 14, color: AppColors.textHint),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'Poppins',
            color: AppColors.textSecondary,
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
    this.color = AppColors.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Poppins',
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontFamily: 'Poppins', color: AppColors.textHint, fontSize: 10),
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
          Text(label, style: const TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary, fontSize: 12)),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Poppins',
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
            : AppColors.accent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Attendance Rate',
                style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary, fontSize: 12)),
            Text(
              '${pct.toStringAsFixed(1)}%',
              style: TextStyle(fontFamily: 'Poppins', color: color, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (pct / 100).clamp(0.0, 1.0),
            backgroundColor: AppColors.border,
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
            : AppColors.accent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Punctuality Rate',
                style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary, fontSize: 12)),
            Text(
              '${pct.toStringAsFixed(1)}%',
              style: TextStyle(fontFamily: 'Poppins', color: color, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (pct / 100).clamp(0.0, 1.0),
            backgroundColor: AppColors.border,
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}