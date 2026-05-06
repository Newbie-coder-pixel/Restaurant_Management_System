import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/models/staff_model.dart';
import '../../../core/models/staff_role.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/widgets/app_drawer.dart';
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

class _StaffScreenState extends ConsumerState<StaffScreen>
    with SingleTickerProviderStateMixin {
  // ── state ──────────────────────────────────────────────
  List<StaffMember> _staff = [];
  bool _isLoading = true;
  String? _branchId;
  StaffRole? _userRole;
  bool _showArchived = false;
  bool _initialized = false;

  // Branch list untuk superadmin
  List<Map<String, dynamic>> _allBranches = [];

  // Branch filter untuk superadmin (null = semua branch)
  String? _selectedFilterBranchId;

  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  late TabController _tabController;

  // ── lifecycle ──────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
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

  // ── data ───────────────────────────────────────────────
  Future<void> _load() async {
    if (_branchId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    setState(() => _isLoading = true);

    List res;
    if (_userRole != StaffRole.superadmin) {
      res = await Supabase.instance.client
          .from('staff')
          .select()
          .eq('branch_id', _branchId!)
          .eq('is_active', !_showArchived)
          .order('full_name');
    } else if (_selectedFilterBranchId != null) {
      res = await Supabase.instance.client
          .from('staff')
          .select()
          .eq('branch_id', _selectedFilterBranchId!)
          .eq('is_active', !_showArchived)
          .order('full_name');
    } else {
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
    }
  }

  // ── helpers ────────────────────────────────────────────
  Color _roleColor(StaffRole r) {
    switch (r) {
      case StaffRole.superadmin: return const Color(0xFF9C27B0);
      case StaffRole.manager:    return const Color(0xFF2196F3);
      case StaffRole.cashier:    return const Color(0xFF4CAF50);
      case StaffRole.waiter:     return const Color(0xFFFF9800);
      case StaffRole.kitchen:    return const Color(0xFFE94560);
      case StaffRole.host:       return const Color(0xFF00BCD4);
    }
  }

  bool _isValidEmail(String email) =>
      RegExp(r'^[\w.+-]+@[\w-]+\.[a-zA-Z]{2,}$').hasMatch(email);

  List<StaffMember> get _filteredStaff {
    if (_searchQuery.isEmpty) return _staff;
    return _staff.where((s) =>
        s.fullName.toLowerCase().contains(_searchQuery) ||
        s.email.toLowerCase().contains(_searchQuery) ||
        s.role.displayName.toLowerCase().contains(_searchQuery)).toList();
  }

  String _branchName(String? branchId) {
    if (branchId == null) return 'Semua Branch';
    final branch = _allBranches.firstWhere(
      (b) => b['id'] == branchId,
      orElse: () => {'name': 'Unknown'},
    );
    return branch['name'] as String;
  }

  // ── archive / restore ──────────────────────────────────
  Future<void> _setActiveStatus(StaffMember s, bool active) async {
    final action = active ? 'mengaktifkan' : 'mengarsipkan';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(active ? 'Aktifkan Staff' : 'Arsipkan Staff',
            style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: Text(
            'Yakin ingin $action ${s.fullName}?\n\n'
            '${active ? 'Staff akan bisa login kembali.' : 'Staff tidak bisa login, tapi data tetap tersimpan dan bisa diaktifkan kembali kapan saja.'}',
            style: const TextStyle(fontFamily: 'Poppins')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal', style: TextStyle(fontFamily: 'Poppins'))),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: active ? AppColors.available : Colors.orange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(active ? 'Aktifkan' : 'Arsipkan',
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
              ? '✅ ${s.fullName} diaktifkan kembali'
              : '📦 ${s.fullName} diarsipkan'),
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
            'Email reset password akan dikirim ke:\n\n${s.email}\n\nStaff perlu mengecek emailnya.',
            style: const TextStyle(fontFamily: 'Poppins')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal', style: TextStyle(fontFamily: 'Poppins'))),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Kirim Email', style: TextStyle(fontFamily: 'Poppins'))),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(s.email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('📧 Email reset password berhasil dikirim'),
            backgroundColor: const Color(0xFF2196F3),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Gagal kirim email: $e'),
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
                      const Text('Email (tidak bisa diubah)',
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
                    labelText: 'Nama Lengkap *',
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: phoneCtrl,
                decoration: InputDecoration(
                    labelText: 'No. HP',
                    prefixIcon: const Icon(Icons.phone_outlined),
                    hintText: '08xx-xxxx-xxxx',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<StaffRole>(
                initialValue: selectedRole,
                decoration: InputDecoration(
                    labelText: 'Role',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                items: StaffRole.values.map((r) => DropdownMenuItem(
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
                child: const Text('Batal', style: TextStyle(fontFamily: 'Poppins'))),
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
                        ss(() => errorMsg = 'Nama wajib diisi.');
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
                          'updated_at': DateTime.now().toIso8601String(),
                        }).eq('id', s.id);

                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                              content: Text('✅ Data $name berhasil diperbarui'),
                              backgroundColor: const Color(0xFF4CAF50),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
                        }
                        await _load();
                      } catch (e) {
                        ss(() {
                          isLoading = false;
                          errorMsg = 'Gagal menyimpan: $e';
                        });
                      }
                    },
              child: isLoading
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Simpan',
                      style: TextStyle(fontFamily: 'Poppins')),
            ),
          ],
        ),
      ),
    );
  }

  // ── ganti / hapus avatar ───────────────────────────────
  Future<void> _changeAvatar(StaffMember s) async {
    final newUrl = await StaffAvatarService.pickAndUpload(
      context: context,
      staffId: s.id,
      oldAvatarUrl: s.avatarUrl,
    );
    if (newUrl != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('📸 Foto ${s.fullName} berhasil diperbarui'),
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
        title: const Text('Hapus Foto',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: const Text('Yakin ingin menghapus foto profil staff ini?',
            style: TextStyle(fontFamily: 'Poppins')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal', style: TextStyle(fontFamily: 'Poppins'))),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Hapus', style: TextStyle(fontFamily: 'Poppins'))),
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
          content: Text('🗑️ Foto ${s.fullName} dihapus'),
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
                                ? 'Ganti Foto'
                                : 'Tambah Foto',
                            color: _roleColor(s.role),
                            onTap: () {
                              Navigator.pop(ctx);
                              _changeAvatar(s);
                            },
                          ),
                          _MenuGridItem(
                            icon: Icons.edit_outlined,
                            label: 'Edit Data',
                            color: const Color(0xFF2196F3),
                            onTap: () {
                              Navigator.pop(ctx);
                              _showEditStaffDialog(s);
                            },
                          ),
                          _MenuGridItem(
                            icon: Icons.bar_chart_outlined,
                            label: 'Performa',
                            color: const Color(0xFF5C6BC0),
                            onTap: () {
                              Navigator.pop(ctx);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => StaffPerformanceScreen(
                                    branchId: s.branchId ?? _branchId ?? '',
                                  ),
                                ),
                              );
                            },
                          ),
                          _MenuGridItem(
                            icon: Icons.history_outlined,
                            label: 'Riwayat Login',
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
                            label: 'Jadwal Shift',
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
                            label: 'Absensi',
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
                              label: 'Hapus Foto',
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
                      label: 'Arsipkan Staff',
                      subtitle: 'Data tetap tersimpan, bisa diaktifkan kembali',
                      color: Colors.orange,
                      onTap: () {
                        Navigator.pop(ctx);
                        _setActiveStatus(s, false);
                      },
                    )
                  else
                    _ActionTile(
                      icon: Icons.unarchive_outlined,
                      label: 'Aktifkan Kembali',
                      subtitle: 'Staff akan bisa login kembali',
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
          title: const Text('Tambah Staff',
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
                        '💡 Email & password ini akan digunakan staff untuk login ke aplikasi.',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 12)),
                  ),
                ]),
              ),
              const SizedBox(height: 20),
              TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                      labelText: 'Nama Lengkap *',
                      prefixIcon: const Icon(Icons.person_outline),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                  textCapitalization: TextCapitalization.words),
              const SizedBox(height: 16),
              TextField(
                  controller: emailCtrl,
                  decoration: InputDecoration(
                      labelText: 'Email Login *',
                      hintText: 'contoh: budi@resto.com',
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                  keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 16),
              TextField(
                controller: passwordCtrl,
                obscureText: obscure,
                decoration: InputDecoration(
                    labelText: 'Password *',
                    hintText: 'Min. 6 karakter',
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
                      labelText: 'No. HP (opsional)',
                      prefixIcon: const Icon(Icons.phone_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                  keyboardType: TextInputType.phone),
              const SizedBox(height: 16),
              DropdownButtonFormField<StaffRole>(
                initialValue: selectedRole,
                decoration: InputDecoration(
                    labelText: 'Role',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                items: StaffRole.values.map((r) => DropdownMenuItem(
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
                    'Staff ini hanya bisa mengakses data di branch yang dipilih.',
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
                child: const Text('Batal', style: TextStyle(fontFamily: 'Poppins'))),
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
                        ss(() => errorMsg = 'Nama wajib diisi.');
                        return;
                      }
                      if (email.isEmpty) {
                        ss(() => errorMsg = 'Email wajib diisi.');
                        return;
                      }
                      if (!_isValidEmail(email)) {
                        ss(() => errorMsg =
                            'Format email tidak valid.\nContoh: nama@domain.com');
                        return;
                      }
                      if (pass.length < 6) {
                        ss(() => errorMsg = 'Password minimal 6 karakter.');
                        return;
                      }

                      ss(() { isLoading = true; errorMsg = null; });

                      if (isSuperadmin && selectedBranchId == null) {
                        ss(() {
                          isLoading = false;
                          errorMsg = 'Pilih branch untuk staff ini.';
                        });
                        return;
                      }

                      try {
                        final res = await Supabase.instance.client.functions.invoke(
                          'create-staff-user',
                          body: {
                            'email':     email,
                            'password':  pass,
                            'fullName':  name,
                            'phone':     phoneCtrl.text.trim().isEmpty
                                ? null
                                : phoneCtrl.text.trim(),
                            'role':      selectedRole.name,
                            'branchId':  selectedBranchId,
                          },
                        );

                        if (res.status != 200) {
                          final msg = (res.data as Map?)?['error']
                              ?? 'Gagal menambahkan staff.';
                          ss(() { isLoading = false; errorMsg = msg; });
                          return;
                        }

                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                              content: Text('✅ Staff $name berhasil ditambahkan!'),
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
                  : const Text('Simpan',
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

    return Scaffold(
      drawer: const AppDrawer(),
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_showArchived ? 'Staff — Arsip' : 'Staff Management'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        titleTextStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white),
        actions: [
          IconButton(
              icon: const Icon(Icons.bar_chart_outlined),
              tooltip: 'Performa Staff',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StaffPerformanceScreen(
                    branchId: _selectedFilterBranchId ?? _branchId ?? '',
                  ),
                ),
              )),
          TextButton.icon(
              onPressed: () {
                setState(() => _showArchived = !_showArchived);
                _load();
              },
              icon: Icon(
                  _showArchived ? Icons.people : Icons.archive_outlined,
                  color: Colors.white,
                  size: 18),
              label: Text(_showArchived ? 'Aktif' : 'Arsip',
                  style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'Poppins',
                      fontSize: 13))),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(isSuperadmin && _allBranches.isNotEmpty ? 104 : 48),
          child: Column(
            children: [
              if (isSuperadmin && _allBranches.isNotEmpty)
                Container(
                  color: AppColors.primary.withValues(alpha: 0.85),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.store_outlined, color: Colors.white70, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            value: _selectedFilterBranchId,
                            dropdownColor: const Color(0xFF3D2C8D),
                            iconEnabledColor: Colors.white,
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 13,
                                color: Colors.white),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('🏢 Semua Branch',
                                    style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 13,
                                        color: Colors.white)),
                              ),
                              ..._allBranches.map((b) => DropdownMenuItem<String?>(
                                value: b['id'] as String,
                                child: Text('📍 ${b['name']}',
                                    style: const TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 13,
                                        color: Colors.white)),
                              )),
                            ],
                            onChanged: (value) {
                              setState(() => _selectedFilterBranchId = value);
                              _load();
                            },
                          ),
                        ),
                      ),
                      if (!_isLoading)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_staff.length} staff',
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11,
                                color: Colors.white,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                    ],
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TabBar(
                  controller: _tabController,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  indicator: const UnderlineTabIndicator(
                    borderSide: BorderSide(color: Colors.white, width: 2),
                    insets: EdgeInsets.symmetric(horizontal: 16),
                  ),
                  labelStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14),
                  unselectedLabelStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
                  tabs: const [
                    Tab(text: 'Staff', icon: Icon(Icons.people_outline, size: 18)),
                    Tab(text: 'Rekap Shift', icon: Icon(Icons.calendar_today_outlined, size: 18)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: _showArchived
          ? null
          : FloatingActionButton.extended(
              onPressed: _showAddStaffDialog,
              backgroundColor: AppColors.accent,
              elevation: 2,
              icon: const Icon(Icons.person_add, color: Colors.white),
              label: const Text('Tambah Staff',
                  style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600)),
            ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildStaffTab(),
          _buildShiftSummaryTab(),
        ],
      ),
    );
  }

  // ── TAB 1: daftar staff ───────────────────────────────────
  Widget _buildStaffTab() {
    return Column(children: [
      if (_showArchived)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Colors.orange.shade50,
          child: const Row(children: [
            Icon(Icons.archive_outlined, color: Colors.orange, size: 18),
            SizedBox(width: 10),
            Expanded(
                child: Text('Menampilkan staff yang diarsipkan',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.orange))),
          ])),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: TextField(
          controller: _searchCtrl,
          decoration: InputDecoration(
            hintText: 'Cari nama, email, atau role...',
            hintStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textHint),
            prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.textHint),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () => _searchCtrl.clear())
                : null,
            contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            filled: true,
            fillColor: Colors.white,
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.grey.shade200)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.primary)),
          ),
        ),
      ),
      if (!_isLoading && _staff.isNotEmpty) _buildRoleSummaryChips(),
      Expanded(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _filteredStaff.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                            _searchQuery.isNotEmpty
                                ? Icons.search_off
                                : _showArchived
                                    ? Icons.inventory_2_outlined
                                    : Icons.people_outline,
                            size: 72,
                            color: AppColors.textHint),
                        const SizedBox(height: 16),
                        Text(
                            _searchQuery.isNotEmpty
                                ? 'Tidak ada staff dengan kata kunci "$_searchQuery"'
                                : _showArchived
                                    ? 'Tidak ada staff yang diarsipkan'
                                    : 'Belum ada staff',
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 14,
                                color: AppColors.textSecondary),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        if (!_showArchived && _searchQuery.isEmpty)
                          ElevatedButton.icon(
                            onPressed: _showAddStaffDialog,
                            icon: const Icon(Icons.person_add),
                            label: const Text('Tambah Staff Sekarang'),
                            style: ElevatedButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                      ],
                    ))
                : _buildGroupedList(),
      ),
    ]);
  }

  Widget _buildRoleSummaryChips() {
    final counts = <StaffRole, int>{};
    for (final s in _staff) {
      counts[s.role] = (counts[s.role] ?? 0) + 1;
    }
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Chip(
              label: Text('Semua (${_staff.length})',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w500)),
              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
          ),
          ...StaffRole.values
              .where((r) => counts.containsKey(r))
              .map((r) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Chip(
                      avatar: CircleAvatar(
                          backgroundColor: _roleColor(r),
                          radius: 8,
                          child: const SizedBox()),
                      label: Text('${r.displayName} (${counts[r]})',
                          style: const TextStyle(fontFamily: 'Poppins', fontSize: 12)),
                      backgroundColor: _roleColor(r).withValues(alpha: 0.08),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ))),
        ],
      ),
    );
  }

  Widget _buildGroupedList() {
    final grouped = <StaffRole, List<StaffMember>>{};
    for (final s in _filteredStaff) {
      grouped.putIfAbsent(s.role, () => []).add(s);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: StaffRole.values
          .where((r) => grouped.containsKey(r))
          .map((role) {
            final members = grouped[role]!;
            final color = _roleColor(role);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(children: [
                    Container(
                        width: 10, height: 10,
                        decoration: BoxDecoration(
                            color: color, shape: BoxShape.circle)),
                    const SizedBox(width: 10),
                    Text(role.displayName,
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: color)),
                    const SizedBox(width: 8),
                    Text('(${members.length})',
                        style: AppTextStyles.caption),
                  ])),
                ...members.map((s) => Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      child: ListTile(
                        onTap: () => _showStaffOptions(s),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        // ── Avatar: tampilkan foto jika ada, fallback ke inisial ──
                        leading: CircleAvatar(
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
                        title: Text(s.fullName,
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w600,
                                fontSize: 15)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.email, style: AppTextStyles.caption),
                            if (s.phone != null && s.phone!.isNotEmpty)
                              Text(s.phone!,
                                  style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 12,
                                      color: AppColors.textHint)),
                            if (_userRole == StaffRole.superadmin && _selectedFilterBranchId == null)
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '📍 ${_branchName(s.branchId)}',
                                  style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 11,
                                      color: AppColors.primary),
                                ),
                              ),
                          ],
                        ),
                        isThreeLine: true,
                        trailing: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.chevron_right,
                              size: 18, color: AppColors.textSecondary),
                        ),
                      ))),
                const SizedBox(height: 8),
              ],
            );
          }).toList(),
    );
  }

  // ── TAB 2: rekap shift ─────────────────────────────────
  Widget _buildShiftSummaryTab() {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _staff.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.calendar_month_outlined,
                        size: 72, color: AppColors.textHint),
                    const SizedBox(height: 16),
                    const Text('Belum ada staff aktif',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            color: AppColors.textSecondary)),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () => _tabController.animateTo(0),
                      icon: const Icon(Icons.person_add),
                      label: const Text('Tambah Staff Dulu'),
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ))
            : _ShiftSummaryView(
                staff: _staff,
                branchId: _selectedFilterBranchId ?? _branchId ?? '',
                roleColor: _roleColor,
              );
  }
}

// ─────────────────────────────────────────────────────────
// Shift Summary Widget (Tab 2 — rekap semua staff)
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
  static const _days = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

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
              '${_staffOnSelectedDay.length} dari ${widget.staff.length} staff bertugas hari ${_days[_selectedDay]}',
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
                        Text('Tidak ada shift di hari ${_days[_selectedDay]}',
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
                            // Avatar dengan foto jika ada
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