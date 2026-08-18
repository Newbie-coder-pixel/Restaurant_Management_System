import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../core/models/staff_role.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/auth/providers/auth_provider.dart';

// Simple model for a branch
class _Branch {
  final String id;
  final String name;
  const _Branch({required this.id, required this.name});
}

/// Embedded as the "Closed Days" tab inside BookingScreen (see
/// booking_screen.dart) rather than its own routed screen — no
/// StaffShell/Scaffold of its own, just the content, with a title + refresh
/// header row since it no longer owns a top bar to put a refresh button in.
class RestaurantClosureScreen extends ConsumerStatefulWidget {
  const RestaurantClosureScreen({super.key});

  @override
  ConsumerState<RestaurantClosureScreen> createState() =>
      _RestaurantClosureScreenState();
}

class _RestaurantClosureScreenState
    extends ConsumerState<RestaurantClosureScreen> {
  // The currently displayed active branch
  String? _selectedBranchId;

  // List of branches (only populated for Super Admin)
  List<_Branch> _branches = [];
  bool _isSuperAdmin = false;

  bool _isLoading = true;
  bool _isSaving = false;

  DateTime _focusedDay = DateTime.now();
  Map<String, Map<String, dynamic>> _closures = {};

  // ── "Add Closure" panel state ──────────────────────────────────────────
  // Tapping a calendar day (or picking a date in the panel) selects a day
  // here; the panel then lets the user confirm add/remove via a button
  // press instead of mutating immediately on tap.
  DateTime? _selectedDay;
  final _reasonCtrl = TextEditingController();

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final staff = ref.read(currentStaffProvider);
    if (staff != null && _selectedBranchId == null) {
      _isSuperAdmin = staff.role == StaffRole.superadmin;

      if (_isSuperAdmin) {
        // Super Admin: load all branches first, then pick the first one
        _loadBranches();
      } else {
        // Regular staff: use their own branch directly
        _selectedBranchId = staff.branchId;
        _loadClosures();
      }
    }
  }

  /// Load all branches from Supabase (Super Admin only)
  Future<void> _loadBranches() async {
    setState(() => _isLoading = true);
    try {
      final res = await Supabase.instance.client
          .from('branches')
          .select('id, name')
          .eq('is_active', true)
          .order('name');

      final list = (res as List)
          .cast<Map<String, dynamic>>()
          .map((e) => _Branch(id: e['id'], name: e['name']))
          .toList();

      if (mounted) {
        setState(() {
          _branches = list;
          if (list.isNotEmpty) {
            _selectedBranchId = list.first.id;
          }
        });
        await _loadClosures();
      }
    } catch (e) {
      debugPrint('error load branches: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _loadClosures() async {
    if (_selectedBranchId == null) return;
    setState(() => _isLoading = true);
    try {
      final res = await Supabase.instance.client
          .from('restaurant_closures')
          .select()
          .eq('branch_id', _selectedBranchId!)
          .order('closure_date');

      final map = <String, Map<String, dynamic>>{};
      for (final row in (res as List).cast<Map<String, dynamic>>()) {
        final date = row['closure_date'] as String;
        map[date] = row;
      }

      if (mounted) {
        setState(() {
          _closures = map;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('error load closures: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Select a day (tap on the calendar, or the panel's date picker) ─────
  void _onDaySelected(DateTime day) {
    final dateStr = _fmtDate(day);
    final todayStr = _fmtDate(DateTime.now());
    if (dateStr.compareTo(todayStr) < 0) {
      _showSnack('Cannot change a date that has already passed', AppColors.accentOrange);
      return;
    }
    setState(() {
      _selectedDay = day;
      _focusedDay = day;
      _reasonCtrl.text = _closures[dateStr]?['reason'] as String? ?? '';
    });
  }

  Future<void> _pickDateForPanel() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) _onDaySelected(picked);
  }

  bool get _selectedIsClosed =>
      _selectedDay != null && _closures.containsKey(_fmtDate(_selectedDay!));

  // ── Schedule the closure currently selected in the panel ───────────────
  Future<void> _schedulePanelClosure() async {
    if (_selectedDay == null || _selectedBranchId == null) return;
    final day = _selectedDay!;
    final dateStr = _fmtDate(day);

    final bookings = await Supabase.instance.client
        .from('bookings')
        .select('id')
        .eq('branch_id', _selectedBranchId!)
        .eq('booking_date', dateStr)
        .inFilter('status', ['pending', 'confirmed', 'seated']).limit(1);

    if ((bookings as List).isNotEmpty) {
      if (!mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusLg)),
          title: const Text('Active Bookings Exist',
              style: TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
          content: Text(
            '${_fmtDisplayDate(day)} still has active bookings.\n\n'
            'Do you still want to close the restaurant on this date?',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:
                  const Text('Cancel', style: TextStyle(fontFamily: 'Poppins')),
            ),
            ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Close Anyway',
                  style:
                      TextStyle(fontFamily: 'Poppins', color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() => _isSaving = true);
    try {
      final staff = ref.read(currentStaffProvider);
      final reason = _reasonCtrl.text.trim();
      await Supabase.instance.client.from('restaurant_closures').insert({
        'branch_id': _selectedBranchId,
        'closure_date': dateStr,
        'reason': reason.isEmpty ? null : reason,
        'created_by': staff?.id,
      });
      await _loadClosures();
      _showSnack('✅ ${_fmtDisplayDate(day)} marked as a closed day',
          AppColors.available);
    } catch (e) {
      _showSnack('Failed to save: $e', AppColors.accent);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _removeClosure(String dateStr) async {
    setState(() => _isSaving = true);
    try {
      await Supabase.instance.client
          .from('restaurant_closures')
          .delete()
          .eq('branch_id', _selectedBranchId!)
          .eq('closure_date', dateStr);
      await _loadClosures();
      _showSnack(
          '✅ Closure date removed — restaurant is open again', AppColors.available);
    } catch (e) {
      _showSnack('Failed to delete: $e', AppColors.accent);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  String _fmtDisplayDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

  List<MapEntry<String, Map<String, dynamic>>> get _upcomingClosures {
    final todayStr = _fmtDate(DateTime.now());
    return _closures.entries
        .where((e) => e.key.compareTo(todayStr) >= 0)
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
  }

  String? get _selectedBranchName => _branches
      .where((b) => b.id == _selectedBranchId)
      .map((b) => b.name)
      .firstOrNull;

  // ─────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
        : RefreshIndicator(
            onRefresh: _loadClosures,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 20),
                  LayoutBuilder(builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 980;
                    final left = _buildCalendar();
                    final right = _buildAddClosurePanel();

                    if (isWide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 2, child: left),
                          const SizedBox(width: 20),
                          SizedBox(width: 340, child: right),
                        ],
                      );
                    }
                    return Column(children: [left, const SizedBox(height: 20), right]);
                  }),
                  const SizedBox(height: 24),
                  _buildUpcomingList(),
                ],
              ),
            ),
          );
  }

  // ── Page header — title + refresh/saving indicator ─────────────────────
  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Restaurant Closures',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              SizedBox(height: 4),
              Text('Block dates the restaurant is closed for bookings.',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      color: AppColors.textSecondary)),
            ],
          ),
        ),
        if (_isSaving)
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
            ),
          )
        else
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
            onPressed: _loadClosures,
          ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // CALENDAR (month grid)
  // ─────────────────────────────────────────────────────────────

  Widget _buildCalendar() {
    final monthLabel = _monthLabel(_focusedDay);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Custom header: icon + month/year + prev/next ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              children: [
                const Icon(Icons.calendar_month_rounded, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text(monthLabel,
                  style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 17,
                    fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                const Spacer(),
                if (_isSuperAdmin && _branches.isNotEmpty) ...[
                  _branchChip(),
                  const SizedBox(width: 8),
                ],
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded, color: AppColors.textSecondary),
                  onPressed: () => setState(() =>
                      _focusedDay = DateTime(_focusedDay.year, _focusedDay.month - 1, 1)),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                  onPressed: () => setState(() =>
                      _focusedDay = DateTime(_focusedDay.year, _focusedDay.month + 1, 1)),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: TableCalendar(
              firstDay: DateTime.now().subtract(const Duration(days: 1)),
              lastDay: DateTime.now().add(const Duration(days: 365)),
              focusedDay: _focusedDay,
              headerVisible: false,
              selectedDayPredicate: (d) =>
                  _selectedDay != null && isSameDay(d, _selectedDay!),
              onDaySelected: (selected, focused) => _onDaySelected(selected),
              onPageChanged: (focused) => setState(() => _focusedDay = focused),
              daysOfWeekStyle: const DaysOfWeekStyle(
                weekdayStyle: TextStyle(
                  fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary, letterSpacing: 0.4),
                weekendStyle: TextStyle(
                  fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary, letterSpacing: 0.4),
              ),
              calendarBuilders: CalendarBuilders(
                dowBuilder: (ctx, day) {
                  const labels = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
                  return Center(
                    child: Text(labels[day.weekday - 1],
                      style: const TextStyle(
                        fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary, letterSpacing: 0.4)),
                  );
                },
                defaultBuilder: (ctx, day, focusedDay) => _dayCell(day),
                todayBuilder: (ctx, day, focusedDay) => _dayCell(day, isToday: true),
                outsideBuilder: (ctx, day, focusedDay) => _dayCell(day, isOutside: true),
                selectedBuilder: (ctx, day, focusedDay) => _dayCell(day, isSelected: true),
              ),
              calendarStyle: const CalendarStyle(outsideDaysVisible: true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _branchChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedBranchId,
          isDense: true,
          icon: const Icon(Icons.keyboard_arrow_down, size: 16, color: AppColors.textSecondary),
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textPrimary),
          items: _branches
              .map((b) => DropdownMenuItem<String>(
                    value: b.id,
                    child: Text(b.name, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12))))
              .toList(),
          onChanged: (val) {
            if (val == null || val == _selectedBranchId) return;
            setState(() {
              _selectedBranchId = val;
              _closures = {};
              _focusedDay = DateTime.now();
              _selectedDay = null;
              _reasonCtrl.clear();
            });
            _loadClosures();
          },
        ),
      ),
    );
  }

  String _monthLabel(DateTime d) {
    const months = ['January','February','March','April','May','June',
      'July','August','September','October','November','December'];
    return '${months[d.month - 1]} ${d.year}';
  }

  Widget _dayCell(
    DateTime day, {
    bool isToday = false,
    bool isOutside = false,
    bool isSelected = false,
  }) {
    final dateStr = _fmtDate(day);
    final isClosed = _closures.containsKey(dateStr);
    final isPast = dateStr.compareTo(_fmtDate(DateTime.now())) < 0;

    Color bgColor = Colors.transparent;
    Color textColor = isOutside || isPast
        ? AppColors.textHint
        : AppColors.textPrimary;
    FontWeight fontWeight = FontWeight.normal;
    Border? border;

    if (isClosed) {
      bgColor = AppColors.accent.withValues(alpha: 0.14);
      textColor = AppColors.accent;
      fontWeight = FontWeight.w800;
    }
    if (isToday && !isClosed) {
      textColor = AppColors.primary;
      fontWeight = FontWeight.w800;
      border = Border.all(color: AppColors.primary.withValues(alpha: 0.5));
    }
    if (isSelected) {
      border = Border.all(color: AppColors.primary, width: 2);
    }

    return Container(
      margin: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: border,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('${day.day}',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: fontWeight,
                  color: textColor)),
          if (isClosed) ...[
            const SizedBox(height: 2),
            Icon(
              _closures[dateStr]?['reason'] == null
                  ? Icons.event_busy_rounded
                  : Icons.event_busy_rounded,
              size: 12, color: AppColors.accent),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // ADD CLOSURE PANEL
  // ─────────────────────────────────────────────────────────────

  Widget _buildAddClosurePanel() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              border: const Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(children: [
              Icon(_selectedIsClosed ? Icons.event_available_rounded : Icons.add_circle_outline_rounded,
                color: AppColors.accent, size: 18),
              const SizedBox(width: 8),
              Text(_selectedIsClosed ? 'Manage Closure' : 'Add Closure',
                style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('BRANCH',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w800,
                    letterSpacing: 0.4, color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                _isSuperAdmin
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedBranchId,
                            isExpanded: true,
                            icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: AppColors.textSecondary),
                            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textPrimary),
                            items: _branches
                                .map((b) => DropdownMenuItem<String>(
                                      value: b.id,
                                      child: Text(b.name, style: const TextStyle(fontFamily: 'Poppins', fontSize: 13))))
                                .toList(),
                            onChanged: (val) {
                              if (val == null || val == _selectedBranchId) return;
                              setState(() {
                                _selectedBranchId = val;
                                _closures = {};
                                _selectedDay = null;
                                _reasonCtrl.clear();
                              });
                              _loadClosures();
                            },
                          ),
                        ),
                      )
                    : Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                        ),
                        child: Text(_selectedBranchName ?? 'My Branch',
                          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                      ),
                const SizedBox(height: 16),

                const Text('DATE',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w800,
                    letterSpacing: 0.4, color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                InkWell(
                  onTap: _pickDateForPanel,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(children: [
                      Expanded(
                        child: Text(
                          _selectedDay == null ? 'Tap a date...' : _fmtDisplayDate(_selectedDay!),
                          style: TextStyle(
                            fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700,
                            color: _selectedDay == null ? AppColors.textHint : AppColors.textPrimary)),
                      ),
                      const Icon(Icons.calendar_today_rounded, size: 15, color: AppColors.textSecondary),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),

                const Text('REASON (OPTIONAL)',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w800,
                    letterSpacing: 0.4, color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                TextField(
                  controller: _reasonCtrl,
                  enabled: !_selectedIsClosed,
                  maxLines: 2,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'e.g., Public Holiday, Maintenance...',
                    hintStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textHint),
                    filled: true,
                    fillColor: AppColors.surfaceVariant,
                    contentPadding: const EdgeInsets.all(12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _selectedDay == null || _isSaving
                        ? null
                        : (_selectedIsClosed
                            ? () => _removeClosure(_fmtDate(_selectedDay!))
                            : _schedulePanelClosure),
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Icon(_selectedIsClosed ? Icons.delete_outline_rounded : Icons.save_rounded, size: 18),
                    label: Text(
                      _selectedIsClosed ? 'REMOVE CLOSURE' : 'SCHEDULE CLOSURE',
                      style: const TextStyle(
                        fontFamily: 'Poppins', fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 0.4)),
                    style: FilledButton.styleFrom(
                      backgroundColor: _selectedIsClosed ? AppColors.textHint : AppColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusSm)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // UPCOMING LIST
  // ─────────────────────────────────────────────────────────────

  Widget _buildUpcomingList() {
    final upcoming = _upcomingClosures;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.event_busy_rounded, color: AppColors.accent, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Upcoming Closures${_isSuperAdmin && _selectedBranchName != null ? ' — $_selectedBranchName' : ''} (${upcoming.length})',
            style: const TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      if (upcoming.isEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: AppColors.border),
          ),
          child: const Center(
            child: Column(children: [
              Icon(Icons.store_rounded, size: 40, color: AppColors.textHint),
              SizedBox(height: 8),
              Text('No closure days scheduled yet',
                  style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)),
            ]),
          ),
        )
      else
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // Header row
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: AppColors.surfaceVariant,
                child: const Row(children: [
                  Expanded(flex: 3, child: Text('DATE', style: _kHeaderStyle)),
                  Expanded(flex: 5, child: Text('REASON', style: _kHeaderStyle)),
                  SizedBox(width: 44),
                ]),
              ),
              for (int i = 0; i < upcoming.length; i++) ...[
                if (i != 0) const Divider(height: 1, color: AppColors.border),
                _closureRow(upcoming[i]),
              ],
            ],
          ),
        ),
    ]);
  }

  static const _kHeaderStyle = TextStyle(
    fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w800,
    letterSpacing: 0.4, color: AppColors.textSecondary);

  Widget _closureRow(MapEntry<String, Map<String, dynamic>> e) {
    final dateStr = e.key;
    final row = e.value;
    final reason = row['reason'] as String?;
    final parts = dateStr.split('-');
    final dt = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
    final dayName = _dayName(dt.weekday);
    final isToday = dateStr == _fmtDate(DateTime.now());

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 3,
            child: Row(children: [
              Text('$dayName, ${dt.day}/${dt.month}/${dt.year}',
                  style: const TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 13,
                      color: AppColors.textPrimary)),
              if (isToday) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('Today',
                      style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 9,
                          color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ],
            ]),
          ),
          Expanded(
            flex: 5,
            child: Text(
              reason ?? 'No reason given',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 12,
                  color: reason != null ? AppColors.textSecondary : AppColors.textHint,
                  fontStyle: reason == null ? FontStyle.italic : FontStyle.normal),
            ),
          ),
          SizedBox(
            width: 44,
            child: IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.accent, size: 20),
              tooltip: 'Remove closure day',
              onPressed: () => _removeClosure(dateStr),
            ),
          ),
        ],
      ),
    );
  }

  String _dayName(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[weekday - 1];
  }
}
