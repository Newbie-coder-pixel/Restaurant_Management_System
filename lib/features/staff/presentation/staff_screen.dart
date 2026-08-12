import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/models/staff_model.dart';
import '../../../core/models/staff_role.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/widgets/app_drawer.dart';
import '../../../shared/widgets/staff_shell.dart';
import '../providers/attendance_clock_provider.dart';
import 'staff_shift_screen.dart';
import 'staff_attendance_screen.dart';
import 'staff_performance_screen.dart';
import 'staff_login_history_screen.dart';
import '../services/staff_avatar_service.dart';

class StaffScreen extends ConsumerStatefulWidget {
  const StaffScreen({super.key});
  @override
  ConsumerState<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends ConsumerState<StaffScreen> {
  // ── state ──────────────────────────────────────────────
  List<StaffMember> _staff = [];
  bool _isLoading = true;
  String? _branchId;
  StaffRole? _userRole;
  bool _showArchived = false;
  bool _initialized = false;

  // Branch list for superadmin
  List<Map<String, dynamic>> _allBranches = [];

  // Branch filter for superadmin (null = all branches)
  String? _selectedFilterBranchId;

  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  // Today's attendance per staff_id (on-duty/off-duty badge + Attendance
  // quick-link sheet) and each staff member's weekly shifts (Shift/Next
  // Shift row on their card) — both sourced from tables already used
  // elsewhere in this file (attendance, staff_shifts), just fetched here
  // too so the redesigned cards can show them without extra taps.
  Map<String, AttendanceRecord> _todayAttendance = {};
  Map<String, List<Map<String, dynamic>>> _shiftsByStaff = {};

  // ── lifecycle ──────────────────────────────────────────
  @override
  void initState() {
    super.initState();
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
      _branchId = staff.branchId;
      _userRole = staff.role;
      _initialized = true;
      if (_userRole == StaffRole.superadmin) _fetchAllBranches();
      _load();
    } else {
      _initialized = true;
      ref.listenManual(currentStaffProvider, (_, next) {
        if (next != null && _branchId == null && mounted) {
          setState(() {
            _branchId = next.branchId;
            _userRole = next.role;
          });
          if (_userRole == StaffRole.superadmin) _fetchAllBranches();
          _load();
        }
      });
    }
  }

  Future<void> _fetchAllBranches() async {
    final res = await Supabase.instance.client
        .from('branches')
        .select('id, name')
        .eq('is_active', true)
        .order('name');
    if (mounted) {
      setState(() {
        _allBranches = (res as List).cast<Map<String, dynamic>>();
      });
    }
  }

  bool get _isAuthorized =>
      _userRole == StaffRole.superadmin || _userRole == StaffRole.manager;

  // ── data ───────────────────────────────────────────────
  Future<void> _load() async {
    if (!_isAuthorized) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    // Non-superadmin must have a branchId
    if (_userRole != StaffRole.superadmin && _branchId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    setState(() => _isLoading = true);

    List res;
    if (_userRole != StaffRole.superadmin) {
      // Regular role: only see their own branch
      res = await Supabase.instance.client
          .from('staff')
          .select()
          .eq('branch_id', _branchId!)
          .eq('is_active', !_showArchived)
          .order('full_name');
    } else if (_selectedFilterBranchId != null) {
      // Superadmin filtering by a specific branch
      res = await Supabase.instance.client
          .from('staff')
          .select()
          .eq('branch_id', _selectedFilterBranchId!)
          .eq('is_active', !_showArchived)
          .order('full_name');
    } else {
      // Superadmin viewing all branches
      res = await Supabase.instance.client
          .from('staff')
          .select()
          .eq('is_active', !_showArchived)
          .order('full_name');
    }

    if (mounted) {
      setState(() {
        _staff = res.map((e) => StaffMember.fromJson(e)).toList();
        _isLoading = false;
      });
      if (!_showArchived) {
        _loadTodayAttendance();
        _loadShiftsForCards();
      }
    }
  }

  Future<void> _loadTodayAttendance() async {
    final ids = _staff.map((s) => s.id).toList();
    final map = await ref
        .read(attendanceClockServiceProvider)
        .fetchTodayRecordsForStaffIds(ids);
    if (mounted) setState(() => _todayAttendance = map);
  }

  Future<void> _loadShiftsForCards() async {
    final ids = _staff.map((s) => s.id).toList();
    if (ids.isEmpty) {
      if (mounted) setState(() => _shiftsByStaff = {});
      return;
    }
    try {
      final res = await Supabase.instance.client
          .from('staff_shifts')
          .select()
          .inFilter('staff_id', ids)
          .order('day_of_week')
          .order('start_time');
      final map = <String, List<Map<String, dynamic>>>{};
      for (final row in (res as List)) {
        final sid = row['staff_id'] as String;
        map.putIfAbsent(sid, () => []).add(row as Map<String, dynamic>);
      }
      if (mounted) setState(() => _shiftsByStaff = map);
    } catch (_) {}
  }

  bool _isOnDuty(StaffMember s) {
    final r = _todayAttendance[s.id];
    return r != null && r.clockIn != null && r.clockOut == null;
  }

  String _formatShiftTime(String? t) {
    if (t == null) return '';
    final parts = t.split(':');
    if (parts.length < 2) return t;
    return '${parts[0]}:${parts[1]}';
  }

  /// Today's shift(s) for [s], formatted "HH:MM - HH:MM" — used on the card
  /// while the staff member is on duty.
  String? _todayShiftLabel(StaffMember s) {
    final today = DateTime.now().weekday - 1;
    final shifts =
        (_shiftsByStaff[s.id] ?? []).where((sh) => sh['day_of_week'] == today).toList();
    if (shifts.isEmpty) return null;
    final sh = shifts.first;
    return '${_formatShiftTime(sh['start_time'])} - ${_formatShiftTime(sh['end_time'])}';
  }

  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// Nearest upcoming shift for [s] (today excluded) — used on the card
  /// while the staff member is off duty.
  String? _nextShiftLabel(StaffMember s) {
    final shifts = _shiftsByStaff[s.id] ?? [];
    if (shifts.isEmpty) return null;
    final today = DateTime.now().weekday - 1;
    Map<String, dynamic>? best;
    int bestOffset = 8;
    for (final sh in shifts) {
      final day = sh['day_of_week'] as int;
      var offset = day - today;
      if (offset <= 0) offset += 7;
      if (offset < bestOffset) {
        bestOffset = offset;
        best = sh;
      }
    }
    if (best == null) return null;
    final dayLabel = bestOffset == 1 ? 'Tomorrow' : _dayNames[best['day_of_week'] as int];
    return '$dayLabel, ${_formatShiftTime(best['start_time'])}';
  }

  // ── helpers ────────────────────────────────────────────
  Color _roleColor(StaffRole r) {
    switch (r) {
      case StaffRole.superadmin: return const Color(0xFF9C27B0);
      case StaffRole.manager:    return const Color(0xFF2196F3);
      case StaffRole.cashier:    return const Color(0xFF4CAF50);
      case StaffRole.waiter:     return const Color(0xFFFF9800);
      case StaffRole.kitchen:    return AppColors.accent;
      case StaffRole.host:       return const Color(0xFF00BCD4);
    }
  }

  bool _isValidEmail(String email) =>
      RegExp(r'^[\w.+-]+@[\w-]+\.[a-zA-Z]{2,}$').hasMatch(email);

  // Validate Indonesian phone number format
  // Valid formats: 08xx-xxxx-xxxx, 08xxxxxxxxxx, +628xx-xxxx-xxxx, +628xxxxxxxxxx
  bool _isValidPhone(String phone) {
    final cleaned = phone.replaceAll(RegExp(r'[\s\-]'), '');
    return RegExp(r'^(\+62|62|0)8[1-9][0-9]{6,10}$').hasMatch(cleaned);
  }

  List<StaffMember> get _filteredStaff {
    if (_searchQuery.isEmpty) return _staff;
    return _staff.where((s) =>
        s.fullName.toLowerCase().contains(_searchQuery) ||
        s.email.toLowerCase().contains(_searchQuery) ||
        s.role.displayName.toLowerCase().contains(_searchQuery)).toList();
  }

  String _branchName(String? branchId) {
    if (branchId == null) return 'All Branches';
    final branch = _allBranches.firstWhere(
      (b) => b['id'] == branchId,
      orElse: () => {'name': 'Unknown'},
    );
    return branch['name'] as String;
  }

  // ── archive / restore ──────────────────────────────────
  Future<void> _setActiveStatus(StaffMember s, bool active) async {
    final action = active ? 'activate' : 'archive';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(active ? 'Activate Staff' : 'Archive Staff',
            style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: Text(
            'Are you sure you want to $action ${s.fullName}?\n\n'
            '${active ? 'The staff member will be able to log in again.' : 'The staff member will not be able to log in, but their data stays saved and can be reactivated anytime.'}',
            style: const TextStyle(fontFamily: 'Poppins')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(fontFamily: 'Poppins'))),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: active ? AppColors.available : Colors.orange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(active ? 'Activate' : 'Archive',
                  style: const TextStyle(fontFamily: 'Poppins'))),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await Supabase.instance.client
        .from('staff')
        .update({'is_active': active, 'updated_at': DateTime.now().toIso8601String()})
        .eq('id', s.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(active
              ? '✅ ${s.fullName} reactivated'
              : '📦 ${s.fullName} archived'),
          backgroundColor: active ? const Color(0xFF4CAF50) : Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
    }
    await _load();
  }

  // ── reset password ─────────────────────────────────────
  Future<void> _sendPasswordReset(StaffMember s) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Reset Password',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: Text(
            'A password reset email will be sent to:\n\n${s.email}\n\nThe staff member needs to check their email.',
            style: const TextStyle(fontFamily: 'Poppins')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(fontFamily: 'Poppins'))),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Send Email', style: TextStyle(fontFamily: 'Poppins'))),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        s.email,
        redirectTo: '${Uri.base.origin}/#/reset-password',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('📧 Password reset email sent successfully'),
            backgroundColor: const Color(0xFF2196F3),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to send email: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
      }
    }
  }

  // ── edit staff ─────────────────────────────────────────
  Future<void> _showEditStaffDialog(StaffMember s) async {
    final nameCtrl  = TextEditingController(text: s.fullName);
    final phoneCtrl = TextEditingController(text: s.phone ?? '');
    StaffRole selectedRole = s.role;
    String? selectedBranchId = s.branchId;
    bool isLoading = false;
    String? errorMsg;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: _roleColor(s.role).withValues(alpha: 0.15),
              backgroundImage: s.avatarUrl != null
                  ? NetworkImage(s.avatarUrl!) as ImageProvider
                  : null,
              child: s.avatarUrl == null
                  ? Text(s.fullName[0].toUpperCase(),
                      style: TextStyle(fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700, color: _roleColor(s.role)))
                  : null,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Edit Staff',
                  style: TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 18))),
          ]),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200)),
                child: Row(children: [
                  const Icon(Icons.email_outlined, size: 18, color: AppColors.textHint),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Email (cannot be changed)',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textHint)),
                      Text(s.email,
                          style: const TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w500)),
                    ])),
                ]),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                    labelText: 'Full Name *',
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: phoneCtrl,
                decoration: InputDecoration(
                    labelText: 'Phone Number',
                    prefixIcon: const Icon(Icons.phone_outlined),
                    hintText: '08xx-xxxx-xxxx',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<StaffRole>(
                // A manager must not be able to assign another staff member the
                // superadmin role via edit — only a superadmin may select
                // superadmin here.
                initialValue: (_userRole != StaffRole.superadmin &&
                        selectedRole == StaffRole.superadmin)
                    ? StaffRole.waiter
                    : selectedRole,
                decoration: InputDecoration(
                    labelText: 'Role',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                items: StaffRole.values
                    .where((r) => _userRole == StaffRole.superadmin || r != StaffRole.superadmin)
                    .map((r) => DropdownMenuItem(
                  value: r,
                  child: Row(children: [
                    Container(width: 12, height: 12,
                        decoration: BoxDecoration(
                            color: _roleColor(r), shape: BoxShape.circle)),
                    const SizedBox(width: 10),
                    Text(r.displayName,
                        style: const TextStyle(fontFamily: 'Poppins')),
                  ]),
                )).toList(),
                onChanged: (v) { if (v != null) ss(() => selectedRole = v); },
              ),
              const SizedBox(height: 16),
              // ── Branch dropdown (superadmin only) ──
              if (_userRole == StaffRole.superadmin && _allBranches.isNotEmpty)
                DropdownButtonFormField<String?>(
                  initialValue: selectedBranchId,
                  decoration: InputDecoration(
                    labelText: 'Branch',
                    prefixIcon: const Icon(Icons.store_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                  items: _allBranches.map((b) => DropdownMenuItem<String?>(
                    value: b['id'] as String,
                    child: Text(b['name'] as String,
                        style: const TextStyle(fontFamily: 'Poppins')),
                  )).toList(),
                  onChanged: (v) => ss(() => selectedBranchId = v),
                ),
              const SizedBox(height: 12),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: _roleColor(selectedRole).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _roleColor(selectedRole).withValues(alpha: 0.3))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.shield_outlined,
                          size: 15, color: _roleColor(selectedRole)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(selectedRole.accessDescription,
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _roleColor(selectedRole))),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: selectedRole.accessFeatures.map((f) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: _roleColor(selectedRole).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20)),
                        child: Text(f,
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11,
                                color: _roleColor(selectedRole))),
                      )).toList(),
                    ),
                  ],
                ),
              ),
              if (errorMsg != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12)),
                  child: Text(errorMsg!,
                      style: const TextStyle(
                          color: Colors.red, fontSize: 13, fontFamily: 'Poppins'))),
              ],
            ]),
          ),
          actions: [
            TextButton(
                onPressed: isLoading ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(fontFamily: 'Poppins'))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: isLoading
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) {
                        ss(() => errorMsg = 'Name is required.');
                        return;
                      }
                      ss(() { isLoading = true; errorMsg = null; });
                      try {
                        await Supabase.instance.client.from('staff').update({
                          'full_name': name,
                          'phone': phoneCtrl.text.trim().isEmpty
                              ? null
                              : phoneCtrl.text.trim(),
                          'role': selectedRole.name,
                          if (_userRole == StaffRole.superadmin && selectedBranchId != null)
                            'branch_id': selectedBranchId,
                          'updated_at': DateTime.now().toIso8601String(),
                        }).eq('id', s.id);

                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                              content: Text('✅ $name\'s data updated successfully'),
                              backgroundColor: const Color(0xFF4CAF50),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
                        }
                        await _load();
                      } catch (e) {
                        ss(() {
                          isLoading = false;
                          errorMsg = 'Failed to save: $e';
                        });
                      }
                    },
              child: isLoading
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Save',
                      style: TextStyle(fontFamily: 'Poppins')),
            ),
          ],
        ),
      ),
    );
  }

  // ── change / remove avatar ──────────────────────────────
  Future<void> _changeAvatar(StaffMember s) async {
    final newUrl = await StaffAvatarService.pickAndUpload(
      context: context,
      staffId: s.id,
      oldAvatarUrl: s.avatarUrl,
    );
    if (newUrl != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('📸 ${s.fullName}\'s photo updated successfully'),
          backgroundColor: const Color(0xFF4CAF50),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
      await _load();
    }
  }

  Future<void> _removeAvatar(StaffMember s) async {
    if (s.avatarUrl == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Remove Photo',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: const Text('Are you sure you want to remove this staff member\'s profile photo?',
            style: TextStyle(fontFamily: 'Poppins')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(fontFamily: 'Poppins'))),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove', style: TextStyle(fontFamily: 'Poppins'))),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final ok = await StaffAvatarService.removeAvatar(
      context: context,
      staffId: s.id,
      avatarUrl: s.avatarUrl!,
    );
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('🗑️ ${s.fullName}\'s photo removed'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
      await _load();
    }
  }

  // ── bottom sheet options ───────────────────────────────
  void _showStaffOptions(StaffMember s) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.4,
        maxChildSize: 0.85,
        expand: false,
        builder: (_, scrollController) => SafeArea(
          child: SingleChildScrollView(
            controller: scrollController,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // drag handle
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  // header
                  Row(children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: _roleColor(s.role).withValues(alpha: 0.15),
                      backgroundImage: s.avatarUrl != null
                          ? NetworkImage(s.avatarUrl!) as ImageProvider
                          : null,
                      child: s.avatarUrl == null
                          ? Text(s.fullName[0].toUpperCase(),
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 20,
                                  color: _roleColor(s.role)))
                          : null),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.fullName,
                              style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 17)),
                          const SizedBox(height: 2),
                          Text(
                              '${s.role.displayName}${s.phone != null ? ' • ${s.phone}' : ''}',
                              style: AppTextStyles.caption),
                        ],
                      ),
                    ),
                  ]),
                  const SizedBox(height: 20),
                  const Divider(height: 1),
                  // grid menu
                  if (s.isActive)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 2.6,
                        children: [
                          _MenuGridItem(
                            icon: s.avatarUrl != null
                                ? Icons.camera_alt_outlined
                                : Icons.add_a_photo_outlined,
                            label: s.avatarUrl != null
                                ? 'Change Photo'
                                : 'Add Photo',
                            color: _roleColor(s.role),
                            onTap: () {
                              Navigator.pop(ctx);
                              _changeAvatar(s);
                            },
                          ),
                          _MenuGridItem(
                            icon: Icons.edit_outlined,
                            label: 'Edit Details',
                            color: const Color(0xFF2196F3),
                            onTap: () {
                              Navigator.pop(ctx);
                              _showEditStaffDialog(s);
                            },
                          ),
                          _MenuGridItem(
                            icon: Icons.bar_chart_outlined,
                            label: 'Performance',
                            color: const Color(0xFF5C6BC0),
                            onTap: () {
                              Navigator.pop(ctx);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => StaffPerformanceScreen(
                                    branchId: _selectedFilterBranchId ?? _branchId ?? '',
                                  ),
                                ),
                              );
                            },
                          ),
                          _MenuGridItem(
                            icon: Icons.history_outlined,
                            label: 'Login History',
                            color: const Color(0xFF00BCD4),
                            onTap: () {
                              Navigator.pop(ctx);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => StaffLoginHistoryScreen(staff: s),
                                ),
                              );
                            },
                          ),
                          _MenuGridItem(
                            icon: Icons.calendar_month_outlined,
                            label: 'Shift Schedule',
                            color: const Color(0xFF9C27B0),
                            onTap: () {
                              Navigator.pop(ctx);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => StaffShiftScreen(staff: s),
                                ),
                              );
                            },
                          ),
                          _MenuGridItem(
                            icon: Icons.fact_check_outlined,
                            label: 'Attendance',
                            color: const Color(0xFF4CAF50),
                            onTap: () {
                              Navigator.pop(ctx);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => StaffAttendanceScreen(
                                    staff: s,
                                    branchId: s.branchId ?? _branchId ?? '',
                                  ),
                                ),
                              );
                            },
                          ),
                          _MenuGridItem(
                            icon: Icons.lock_reset_outlined,
                            label: 'Reset Password',
                            color: const Color(0xFFFF9800),
                            onTap: () {
                              Navigator.pop(ctx);
                              _sendPasswordReset(s);
                            },
                          ),
                          if (s.avatarUrl != null)
                            _MenuGridItem(
                              icon: Icons.no_photography_outlined,
                              label: 'Remove Photo',
                              color: Colors.red,
                              onTap: () {
                                Navigator.pop(ctx);
                                _removeAvatar(s);
                              },
                            ),
                        ],
                      ),
                    ),
                  // archive / restore
                  if (s.isActive)
                    _ActionTile(
                      icon: Icons.archive_outlined,
                      label: 'Archive Staff',
                      subtitle: 'Data stays saved, can be reactivated anytime',
                      color: Colors.orange,
                      onTap: () {
                        Navigator.pop(ctx);
                        _setActiveStatus(s, false);
                      },
                    )
                  else
                    _ActionTile(
                      icon: Icons.unarchive_outlined,
                      label: 'Reactivate',
                      subtitle: 'The staff member will be able to log in again',
                      color: const Color(0xFF4CAF50),
                      onTap: () {
                        Navigator.pop(ctx);
                        _setActiveStatus(s, true);
                      },
                    ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── add staff ──────────────────────────────────────────
  Future<void> _showAddStaffDialog() async {
    final nameCtrl     = TextEditingController();
    final emailCtrl    = TextEditingController();
    final phoneCtrl    = TextEditingController();
    final passwordCtrl = TextEditingController();
    StaffRole selectedRole = StaffRole.waiter;
    bool obscure = true;
    bool isLoading = false;
    String? errorMsg;

    final isSuperadmin = _userRole == StaffRole.superadmin;
    String? selectedBranchId = isSuperadmin
        ? (_allBranches.isNotEmpty ? _allBranches.first['id'] as String : _branchId)
        : _branchId;

    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Add Staff',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 18)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12)),
                child: const Row(children: [
                  Icon(Icons.info_outline, size: 18, color: AppColors.primary),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                        '💡 This email & password will be used by the staff member to log in to the app.',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 12)),
                  ),
                ]),
              ),
              const SizedBox(height: 20),
              TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                      labelText: 'Full Name *',
                      prefixIcon: const Icon(Icons.person_outline),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                  textCapitalization: TextCapitalization.words),
              const SizedBox(height: 16),
              TextField(
                  controller: emailCtrl,
                  decoration: InputDecoration(
                      labelText: 'Login Email *',
                      hintText: 'e.g. budi@resto.com',
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                  keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 16),
              TextField(
                controller: passwordCtrl,
                obscureText: obscure,
                decoration: InputDecoration(
                    labelText: 'Password *',
                    hintText: 'Min. 6 characters',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                        icon: Icon(obscure
                            ? Icons.visibility_off
                            : Icons.visibility),
                        onPressed: () => ss(() => obscure = !obscure)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
              ),
              const SizedBox(height: 16),
              TextField(
                  controller: phoneCtrl,
                  decoration: InputDecoration(
                      labelText: 'Phone Number *',
                      hintText: '08xx-xxxx-xxxx',
                      prefixIcon: const Icon(Icons.phone_outlined),
                      helperText: 'Format: 08xx-xxxx-xxxx or +628xx-xxxx-xxxx',
                      helperStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 11),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                  keyboardType: TextInputType.phone),
              const SizedBox(height: 16),
              DropdownButtonFormField<StaffRole>(
                // A manager (non-superadmin) must not be able to create a superadmin
                // account — previously this dropdown showed every role without
                // restriction, which was a potential privilege-escalation path via
                // creating a new staff member with the superadmin role.
                initialValue: (!isSuperadmin && selectedRole == StaffRole.superadmin)
                    ? StaffRole.waiter
                    : selectedRole,
                decoration: InputDecoration(
                    labelText: 'Role',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                items: StaffRole.values
                    .where((r) => isSuperadmin || r != StaffRole.superadmin)
                    .map((r) => DropdownMenuItem(
                  value: r,
                  child: Row(children: [
                    Container(width: 12, height: 12,
                        decoration: BoxDecoration(
                            color: _roleColor(r), shape: BoxShape.circle)),
                    const SizedBox(width: 10),
                    Text(r.displayName,
                        style: const TextStyle(fontFamily: 'Poppins')),
                  ]),
                )).toList(),
                onChanged: (v) { if (v != null) ss(() => selectedRole = v); },
              ),
              if (isSuperadmin && _allBranches.isNotEmpty) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedBranchId,
                  decoration: InputDecoration(
                    labelText: 'Branch *',
                    prefixIcon: const Icon(Icons.store_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: _allBranches.map((b) => DropdownMenuItem<String>(
                    value: b['id'] as String,
                    child: Text(b['name'] as String,
                        style: const TextStyle(fontFamily: 'Poppins')),
                  )).toList(),
                  onChanged: (v) { if (v != null) ss(() => selectedBranchId = v); },
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    'This staff member can only access data in the selected branch.',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        color: Colors.grey.shade600),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: _roleColor(selectedRole).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _roleColor(selectedRole).withValues(alpha: 0.3))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.shield_outlined,
                          size: 15, color: _roleColor(selectedRole)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(selectedRole.accessDescription,
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _roleColor(selectedRole))),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: selectedRole.accessFeatures.map((f) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: _roleColor(selectedRole).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20)),
                        child: Text(f,
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11,
                                color: _roleColor(selectedRole))),
                      )).toList(),
                    ),
                  ],
                ),
              ),
              if (errorMsg != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12)),
                  child: Text(errorMsg!,
                      style: const TextStyle(
                          color: Colors.red,
                          fontSize: 13,
                          fontFamily: 'Poppins'))),
              ],
            ]),
          ),
          actions: [
            TextButton(
                onPressed: isLoading ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(fontFamily: 'Poppins'))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: isLoading
                  ? null
                  : () async {
                      final name  = nameCtrl.text.trim();
                      final email = emailCtrl.text.trim().toLowerCase();
                      final pass  = passwordCtrl.text;

                      if (name.isEmpty) {
                        ss(() => errorMsg = 'Name is required.');
                        return;
                      }
                      if (email.isEmpty) {
                        ss(() => errorMsg = 'Email is required.');
                        return;
                      }
                      if (!_isValidEmail(email)) {
                        ss(() => errorMsg =
                            'Invalid email format.\nExample: name@domain.com');
                        return;
                      }
                      if (pass.length < 6) {
                        ss(() => errorMsg = 'Password must be at least 6 characters.');
                        return;
                      }
                      final phone = phoneCtrl.text.trim();
                      if (phone.isEmpty) {
                        ss(() => errorMsg = 'Phone number is required.');
                        return;
                      }
                      if (!_isValidPhone(phone)) {
                        ss(() => errorMsg =
                            'Invalid phone number format.\nExample: 0812-3456-7890 or +6281234567890');
                        return;
                      }

                      ss(() { isLoading = true; errorMsg = null; });

                      if (isSuperadmin && selectedBranchId == null) {
                        ss(() {
                          isLoading = false;
                          errorMsg = 'Select a branch for this staff member.';
                        });
                        return;
                      }

                      // ── Check for duplicate email before calling the Edge Function ──
                      try {
                        final existing = await Supabase.instance.client
                            .from('staff')
                            .select('id')
                            .eq('email', email)
                            .maybeSingle();
                        if (existing != null) {
                          ss(() {
                            isLoading = false;
                            errorMsg = 'Email "$email" is already registered.\nUse a different email.';
                          });
                          return;
                        }
                      } catch (_) {
                        // If the check fails, just continue — the Edge Function will handle it
                      }

                      try {
                        final res = await Supabase.instance.client.functions.invoke(
                          'create-staff-user',
                          body: {
                            'email':     email,
                            'password':  pass,
                            'fullName':  name,
                            'phone':     phone,
                            'role':      selectedRole.name,
                            'branchId':  selectedBranchId,
                          },
                        );

                        if (res.status != 200) {
                          // Translate the technical error message into a friendly one
                          final rawMsg = (res.data as Map?)?['error'] as String? ?? '';
                          final String friendlyMsg;
                          if (rawMsg.contains('already been registered') ||
                              rawMsg.contains('already registered') ||
                              rawMsg.contains('already exists')) {
                            friendlyMsg = 'Email "$email" is already registered in the system.\nUse a different email.';
                          } else if (rawMsg.contains('invalid email')) {
                            friendlyMsg = 'Invalid email format.';
                          } else if (rawMsg.contains('weak password') ||
                              rawMsg.contains('password')) {
                            friendlyMsg = 'Password is too weak. Use at least 6 characters.';
                          } else if (rawMsg.isNotEmpty) {
                            friendlyMsg = rawMsg;
                          } else {
                            friendlyMsg = 'Failed to add staff member. Please try again.';
                          }
                          ss(() { isLoading = false; errorMsg = friendlyMsg; });
                          return;
                        }

                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                              content: Text('✅ Staff member $name added successfully!'),
                              backgroundColor: const Color(0xFF4CAF50),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
                        }
                        await _load();
                      } catch (e) {
                        ss(() {
                          isLoading = false;
                          errorMsg = 'Error: $e';
                        });
                      }
                    },
              child: isLoading
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Save',
                      style: TextStyle(fontFamily: 'Poppins')),
            ),
          ],
        ),
      ),
    );
  }

  // ── build ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isSuperadmin = _userRole == StaffRole.superadmin;

    // Screen-side guard — only manager & superadmin may view/modify staff
    // data. The router already blocks navigation to /staff for other roles,
    // but this is re-checked here (not just hiding the drawer menu item)
    // so this widget never renders/queries staff data for an unauthorized
    // role even if mounted through another path.
    if (_userRole != null &&
        _userRole != StaffRole.superadmin &&
        _userRole != StaffRole.manager) {
      return Scaffold(
        drawer: const AppDrawer(),
        appBar: AppBar(title: const Text('Staff Management')),
        body: const Center(
          child: Text('You do not have access to this page.'),
        ),
      );
    }

    return StaffShell(
      pageTitle: _showArchived ? 'Staff — Archive' : 'Staff Management',
      activeRoute: AppRoutes.staff,
      floatingActionButton: _showArchived
          ? null
          : FloatingActionButton.extended(
              onPressed: _showAddStaffDialog,
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('ADD STAFF',
                style: TextStyle(
                  color: Colors.white, fontFamily: 'Poppins',
                  fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.3)),
            ),
      topBarActions: [
        // ── Branch filter dropdown (superadmin only) ──
        if (isSuperadmin && _allBranches.isNotEmpty)
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
                  value: _selectedFilterBranchId,
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
                    ..._allBranches.map((b) => DropdownMenuItem<String?>(
                          value: b['id'] as String,
                          child: Text(b['name'] as String,
                              style: const TextStyle(fontFamily: 'Poppins', fontSize: 12)))),
                  ],
                  onChanged: (val) {
                    setState(() => _selectedFilterBranchId = val);
                    _load();
                  },
                ),
              ),
            ),
          ),
        SizedBox(
          width: 200,
          height: 38,
          child: TextField(
            controller: _searchCtrl,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search staff...',
              hintStyle: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 13, color: AppColors.textHint),
              prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.textSecondary),
              filled: true,
              fillColor: AppColors.surfaceVariant,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Staff Performance',
          icon: const Icon(Icons.bar_chart_outlined, color: AppColors.textSecondary),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StaffPerformanceScreen(
                branchId: isSuperadmin ? _selectedFilterBranchId : (_branchId ?? ''),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: _showArchived ? 'Show active staff' : 'Show archived staff',
          icon: Icon(_showArchived ? Icons.people_outline : Icons.archive_outlined,
              color: AppColors.textSecondary),
          onPressed: () {
            setState(() => _showArchived = !_showArchived);
            _load();
          },
        ),
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
          onPressed: _load,
        ),
      ],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_showArchived)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.accentOrange.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                        border: Border.all(color: AppColors.accentOrange.withValues(alpha: 0.3)),
                      ),
                      child: const Row(children: [
                        Icon(Icons.archive_outlined, color: AppColors.accentOrange, size: 18),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text('Showing archived staff',
                            style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 13,
                              fontWeight: FontWeight.w600, color: AppColors.accentOrange))),
                      ]),
                    ),
                  if (!_showArchived)
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isNarrow = constraints.maxWidth < 700;
                        final cards = [
                          _QuickLinkCard(
                            title: 'Shift Schedule',
                            subtitle: 'Manage weekly rotations',
                            onTap: _showShiftScheduleSheet,
                          ),
                          _QuickLinkCard(
                            title: 'Attendance',
                            subtitle: 'Review clock-ins',
                            onTap: _showTodayAttendanceSheet,
                          ),
                          _QuickLinkCard(
                            title: 'Performance',
                            subtitle: 'Metrics & reviews',
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => StaffPerformanceScreen(
                                  branchId: isSuperadmin ? _selectedFilterBranchId : (_branchId ?? ''),
                                ),
                              ),
                            ),
                          ),
                        ];
                        return isNarrow
                            ? Column(children: [
                                for (final c in cards) ...[c, const SizedBox(height: 12)],
                              ])
                            : Row(children: [
                                for (int i = 0; i < cards.length; i++) ...[
                                  Expanded(child: cards[i]),
                                  if (i != cards.length - 1) const SizedBox(width: 16),
                                ],
                              ]);
                      },
                    ),
                  const SizedBox(height: 24),
                  if (_filteredStaff.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                                _searchQuery.isNotEmpty
                                    ? Icons.search_off
                                    : _showArchived
                                        ? Icons.inventory_2_outlined
                                        : Icons.people_outline,
                                size: 64, color: AppColors.textHint),
                            const SizedBox(height: 16),
                            Text(
                                _searchQuery.isNotEmpty
                                    ? 'No staff found matching "$_searchQuery"'
                                    : _showArchived
                                        ? 'No archived staff'
                                        : 'No staff yet',
                                style: const TextStyle(
                                    fontFamily: 'Poppins', fontSize: 14,
                                    color: AppColors.textSecondary),
                                textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            if (!_showArchived && _searchQuery.isEmpty)
                              FilledButton.icon(
                                onPressed: _showAddStaffDialog,
                                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                                icon: const Icon(Icons.person_add),
                                label: const Text('Add Staff Now'),
                              ),
                          ],
                        ),
                      ),
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final crossAxisCount = constraints.maxWidth >= 1200
                            ? 3
                            : constraints.maxWidth >= 760
                                ? 2
                                : 1;
                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                            childAspectRatio: 2.35,
                          ),
                          itemCount: _filteredStaff.length,
                          itemBuilder: (_, i) {
                            final s = _filteredStaff[i];
                            return _StaffCard(
                              staff: s,
                              isOnDuty: _isOnDuty(s),
                              roleColor: _roleColor(s.role),
                              shiftLabel: _isOnDuty(s) ? _todayShiftLabel(s) : null,
                              nextShiftLabel: _isOnDuty(s) ? null : _nextShiftLabel(s),
                              branchLabel: (_userRole == StaffRole.superadmin && _selectedFilterBranchId == null)
                                  ? _branchName(s.branchId)
                                  : null,
                              onTap: () => _showStaffOptions(s),
                            );
                          },
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }

  // ── Shift Schedule quick link ───────────────────────────
  // Reuses the existing _ShiftSummaryView (day selector + per-day shift
  // list) unchanged — just relocated into a sheet instead of a tab.
  void _showShiftScheduleSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, __) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(children: [
                Text('Shift Schedule',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 18,
                    fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              ]),
            ),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: _staff.isEmpty
                  ? const Center(
                      child: Text('No active staff yet',
                        style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)))
                  : _ShiftSummaryView(
                      staff: _staff,
                      branchId: _selectedFilterBranchId ?? _branchId ?? '',
                      roleColor: _roleColor,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Attendance quick link ───────────────────────────────
  // Shows today's clock-in/out per staff, sourced from the same
  // _todayAttendance map used for the ON DUTY / OFF DUTY card badges.
  void _showTodayAttendanceSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(children: [
                Text("Today's Attendance",
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 18,
                    fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              ]),
            ),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: _staff.isEmpty
                  ? const Center(
                      child: Text('No active staff yet',
                        style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)))
                  : ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                      itemCount: _staff.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
                      itemBuilder: (_, i) {
                        final s = _staff[i];
                        final record = _todayAttendance[s.id];
                        final onDuty = _isOnDuty(s);
                        String statusText;
                        if (record?.clockIn == null) {
                          statusText = 'Not clocked in';
                        } else if (onDuty) {
                          statusText =
                              'Clocked in ${_formatShiftTime('${record!.clockIn!.hour.toString().padLeft(2, '0')}:${record.clockIn!.minute.toString().padLeft(2, '0')}')}';
                        } else {
                          statusText =
                              '${_formatShiftTime('${record!.clockIn!.hour.toString().padLeft(2, '0')}:${record.clockIn!.minute.toString().padLeft(2, '0')}')} — ${_formatShiftTime('${record.clockOut!.hour.toString().padLeft(2, '0')}:${record.clockOut!.minute.toString().padLeft(2, '0')}')}';
                        }
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: _roleColor(s.role).withValues(alpha: 0.15),
                              backgroundImage: s.avatarUrl != null
                                  ? NetworkImage(s.avatarUrl!) as ImageProvider
                                  : null,
                              child: s.avatarUrl == null
                                  ? Text(s.fullName[0].toUpperCase(),
                                      style: TextStyle(
                                        fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                                        fontSize: 13, color: _roleColor(s.role)))
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s.fullName,
                                    style: const TextStyle(
                                      fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14)),
                                  Text(statusText,
                                    style: const TextStyle(
                                      fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary)),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: onDuty
                                    ? AppColors.badgeDark
                                    : AppColors.surfaceVariant,
                                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                                border: onDuty ? null : Border.all(color: AppColors.border),
                              ),
                              child: Text(onDuty ? 'ON DUTY' : 'OFF DUTY',
                                style: TextStyle(
                                  fontFamily: 'Poppins', fontSize: 9, fontWeight: FontWeight.w800,
                                  letterSpacing: 0.3,
                                  color: onDuty ? Colors.white : AppColors.textSecondary)),
                            ),
                          ]),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Quick-link card (Shift Schedule / Attendance / Performance)
// ─────────────────────────────────────────────────────────
class _QuickLinkCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickLinkCard({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                    style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 18,
                      fontWeight: FontWeight.w800, color: AppColors.primary)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                    style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward, color: AppColors.primary, size: 20),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Staff card (avatar, on-duty badge, ID, role, shift/next shift)
// ─────────────────────────────────────────────────────────
class _StaffCard extends StatelessWidget {
  final StaffMember staff;
  final bool isOnDuty;
  final Color roleColor;
  final String? shiftLabel;
  final String? nextShiftLabel;
  final String? branchLabel;
  final VoidCallback onTap;

  const _StaffCard({
    required this.staff,
    required this.isOnDuty,
    required this.roleColor,
    required this.shiftLabel,
    required this.nextShiftLabel,
    this.branchLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final shortId = staff.id.length > 8 ? staff.id.substring(0, 8).toUpperCase() : staff.id.toUpperCase();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant.withValues(alpha: 0.5),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusMd)),
              ),
              child: Row(children: [
                Opacity(
                  opacity: isOnDuty ? 1 : 0.55,
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor: roleColor.withValues(alpha: 0.15),
                    backgroundImage: staff.avatarUrl != null
                        ? NetworkImage(staff.avatarUrl!) as ImageProvider
                        : null,
                    child: staff.avatarUrl == null
                        ? Text(staff.fullName[0].toUpperCase(),
                            style: TextStyle(
                              fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                              fontSize: 16, color: roleColor))
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(staff.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Poppins', fontSize: 16,
                          fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text(
                        branchLabel != null ? 'ID: $shortId • $branchLabel' : 'ID: $shortId',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isOnDuty ? AppColors.badgeDark : AppColors.surface,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    border: isOnDuty ? null : Border.all(color: AppColors.border),
                  ),
                  child: Text(isOnDuty ? 'ON DUTY' : 'OFF DUTY',
                    style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 9, fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                      color: isOnDuty ? Colors.white : AppColors.textSecondary)),
                ),
              ]),
            ),
            const Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('ROLE',
                        style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700,
                          letterSpacing: 0.4, color: AppColors.textSecondary)),
                      Text(staff.role.displayName,
                        style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700,
                          color: isOnDuty ? AppColors.accent : AppColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(isOnDuty ? 'SHIFT' : 'NEXT SHIFT',
                        style: const TextStyle(
                          fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700,
                          letterSpacing: 0.4, color: AppColors.textSecondary)),
                      Text(
                        (isOnDuty ? shiftLabel : nextShiftLabel) ?? '—',
                        style: const TextStyle(
                          fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Shift Summary Widget (used by the Shift Schedule quick-link sheet)
// ─────────────────────────────────────────────────────────
class _ShiftSummaryView extends StatefulWidget {
  final List<StaffMember> staff;
  final String branchId;
  final Color Function(StaffRole) roleColor;

  const _ShiftSummaryView({
    required this.staff,
    required this.branchId,
    required this.roleColor,
  });

  @override
  State<_ShiftSummaryView> createState() => _ShiftSummaryViewState();
}

class _ShiftSummaryViewState extends State<_ShiftSummaryView> {
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  Map<String, List<Map<String, dynamic>>> _shiftsByStaff = {};
  bool _isLoading = true;
  int _selectedDay = DateTime.now().weekday - 1;

  @override
  void initState() {
    super.initState();
    _loadAllShifts();
  }

  Future<void> _loadAllShifts() async {
    setState(() => _isLoading = true);
    final staffIds = widget.staff.map((s) => s.id).toList();
    if (staffIds.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      final res = await Supabase.instance.client
          .from('staff_shifts')
          .select()
          .inFilter('staff_id', staffIds)
          .order('day_of_week')
          .order('start_time');

      final map = <String, List<Map<String, dynamic>>>{};
      for (final row in (res as List)) {
        final sid = row['staff_id'] as String;
        map.putIfAbsent(sid, () => []).add(row as Map<String, dynamic>);
      }
      if (mounted) setState(() { _shiftsByStaff = map; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<StaffMember> get _staffOnSelectedDay {
    return widget.staff.where((s) {
      final shifts = _shiftsByStaff[s.id] ?? [];
      return shifts.any((sh) => sh['day_of_week'] == _selectedDay);
    }).toList();
  }

  String _formatTime(String? t) {
    if (t == null) return '';
    final parts = t.split(':');
    if (parts.length < 2) return t;
    return '${parts[0]}:${parts[1]}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // day selector
      Container(
        color: AppColors.primary.withValues(alpha: 0.05),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(7, (i) {
            final isToday = i == DateTime.now().weekday - 1;
            final isSelected = i == _selectedDay;
            return GestureDetector(
              onTap: () => setState(() => _selectedDay = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary
                      : isToday
                          ? AppColors.primary.withValues(alpha: 0.1)
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: isToday && !isSelected
                      ? Border.all(color: AppColors.primary, width: 1.5)
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_days[i],
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isSelected ? Colors.white : AppColors.textSecondary)),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
      // stats bar
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          const Icon(Icons.people_outline, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Text(
              '${_staffOnSelectedDay.length} of ${widget.staff.length} staff working on ${_days[_selectedDay]}',
              style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 13,
                  color: AppColors.textSecondary)),
        ]),
      ),
      // list
      Expanded(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _staffOnSelectedDay.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.event_busy_outlined,
                            size: 64, color: AppColors.textHint),
                        const SizedBox(height: 12),
                        Text('No shifts on ${_days[_selectedDay]}',
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 14,
                                color: AppColors.textSecondary)),
                      ],
                    ))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                    itemCount: _staffOnSelectedDay.length,
                    itemBuilder: (_, i) {
                      final s = _staffOnSelectedDay[i];
                      final shifts = (_shiftsByStaff[s.id] ?? [])
                          .where((sh) => sh['day_of_week'] == _selectedDay)
                          .toList();
                      final color = widget.roleColor(s.role);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Row(children: [
                            // Avatar with photo if available
                            CircleAvatar(
                                radius: 24,
                                backgroundColor: color.withValues(alpha: 0.15),
                                backgroundImage: s.avatarUrl != null
                                    ? NetworkImage(s.avatarUrl!) as ImageProvider
                                    : null,
                                child: s.avatarUrl == null
                                    ? Text(s.fullName[0].toUpperCase(),
                                        style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontWeight: FontWeight.w700,
                                            fontSize: 16,
                                            color: color))
                                    : null),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s.fullName,
                                      style: const TextStyle(
                                          fontFamily: 'Poppins',
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15)),
                                  const SizedBox(height: 2),
                                  Text(s.role.displayName,
                                      style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: 12,
                                          color: color)),
                                  const SizedBox(height: 6),
                                  ...shifts.map((sh) => Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Row(children: [
                                      const Icon(Icons.access_time, size: 14, color: AppColors.textHint),
                                      const SizedBox(width: 4),
                                      Text(
                                          '${_formatTime(sh['start_time'])} — ${_formatTime(sh['end_time'])}',
                                          style: const TextStyle(
                                              fontFamily: 'Poppins',
                                              fontSize: 13,
                                              color: AppColors.textSecondary)),
                                    ]),
                                  )),
                                ],
                              ),
                            ),
                          ]),
                        ),
                      );
                    }),
      ),
    ]);
  }
}

// ── Grid Menu Item Widget ──────────────────────────────
class _MenuGridItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _MenuGridItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: color.withValues(alpha: 0.9),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Action Tile Widget ─────────────────────────────────
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.15)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: color,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: color.withValues(alpha: 0.5),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}