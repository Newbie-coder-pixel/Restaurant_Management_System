import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/models/staff_model.dart';
import '../../../core/models/staff_role.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/widgets/app_drawer.dart';
import 'staff_shift_screen.dart'; // <-- import shift screen

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
  bool _showArchived = false;
  bool _initialized = false;

  // search
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  // tab
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
      _initialized = true;
      _load();
    } else {
      _initialized = true;
      ref.listenManual(currentStaffProvider, (_, next) {
        if (next != null && _branchId == null && mounted) {
          setState(() => _branchId = next.branchId);
          _load();
        }
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
    final res = await Supabase.instance.client
        .from('staff')
        .select()
        .eq('branch_id', _branchId!)
        .eq('is_active', !_showArchived)
        .order('full_name');
    if (mounted) {
      setState(() {
        _staff = (res as List).map((e) => StaffMember.fromJson(e)).toList();
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

  // ── archive / restore ──────────────────────────────────
  Future<void> _setActiveStatus(StaffMember s, bool active) async {
    final action = active ? 'mengaktifkan' : 'mengarsipkan';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(active ? 'Aktifkan Staff' : 'Arsipkan Staff',
            style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: Text(
            'Yakin ingin $action ${s.fullName}?\n\n'
            '${active ? 'Staff akan bisa login kembali.' : 'Staff tidak bisa login, tapi data tetap tersimpan dan bisa diaktifkan kembali kapan saja.'}',
            style: const TextStyle(fontFamily: 'Poppins')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: active ? AppColors.available : Colors.orange,
                  foregroundColor: Colors.white),
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
          backgroundColor: active ? const Color(0xFF4CAF50) : Colors.orange));
    }
    await _load();
  }

  // ── reset password ─────────────────────────────────────
  Future<void> _sendPasswordReset(StaffMember s) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reset Password',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: Text(
            'Email reset password akan dikirim ke:\n\n${s.email}\n\nStaff perlu mengecek emailnya.',
            style: const TextStyle(fontFamily: 'Poppins')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Kirim Email', style: TextStyle(fontFamily: 'Poppins'))),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(s.email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('📧 Email reset password berhasil dikirim'),
            backgroundColor: Color(0xFF2196F3)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Gagal kirim email: $e'),
            backgroundColor: Colors.red));
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: _roleColor(s.role).withValues(alpha: 0.15),
              child: Text(s.fullName[0].toUpperCase(),
                  style: TextStyle(fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700, color: _roleColor(s.role)))),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Edit Staff',
                  style: const TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w700))),
          ]),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // email (read-only info)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300)),
                child: Row(children: [
                  const Icon(Icons.email_outlined, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Email (tidak bisa diubah)',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: Colors.grey)),
                      Text(s.email,
                          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
                    ])),
                ])),
              const SizedBox(height: 14),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                    labelText: 'Nama Lengkap *',
                    prefixIcon: Icon(Icons.person_outline)),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(
                    labelText: 'No. HP',
                    prefixIcon: Icon(Icons.phone_outlined),
                    hintText: '08xx-xxxx-xxxx'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<StaffRole>(
                value: selectedRole,
                decoration: const InputDecoration(labelText: 'Role'),
                items: StaffRole.values.map((r) => DropdownMenuItem(
                  value: r,
                  child: Row(children: [
                    Container(width: 10, height: 10,
                        decoration: BoxDecoration(
                            color: _roleColor(r), shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Text(r.displayName,
                        style: const TextStyle(fontFamily: 'Poppins')),
                  ]),
                )).toList(),
                onChanged: (v) { if (v != null) ss(() => selectedRole = v); },
              ),
              if (errorMsg != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(errorMsg!,
                      style: const TextStyle(
                          color: Colors.red, fontSize: 12, fontFamily: 'Poppins'))),
              ],
            ]),
          ),
          actions: [
            TextButton(
                onPressed: isLoading ? null : () => Navigator.pop(ctx),
                child: const Text('Batal')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary, foregroundColor: Colors.white),
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
                              content: Text('✅ Data ${name} berhasil diperbarui'),
                              backgroundColor: const Color(0xFF4CAF50)));
                        }
                        await _load();
                      } catch (e) {
                        ss(() {
                          isLoading = false;
                          errorMsg = 'Gagal menyimpan: ${e.toString()}';
                        });
                      }
                    },
              child: isLoading
                  ? const SizedBox(
                      width: 18, height: 18,
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

  // ── bottom sheet options ───────────────────────────────
  void _showStaffOptions(StaffMember s) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2))),
            // header
            ListTile(
              leading: CircleAvatar(
                  backgroundColor: _roleColor(s.role).withValues(alpha: 0.15),
                  child: Text(s.fullName[0].toUpperCase(),
                      style: TextStyle(fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          color: _roleColor(s.role)))),
              title: Text(s.fullName,
                  style: const TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
              subtitle: Text(
                  '${s.role.displayName}${s.phone != null ? ' • ${s.phone}' : ''}',
                  style: AppTextStyles.caption)),
            const Divider(),
            // edit — hanya saat active
            if (s.isActive)
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: Color(0xFF2196F3)),
                title: const Text('Edit Data Staff',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Color(0xFF2196F3),
                        fontWeight: FontWeight.w600)),
                subtitle: const Text('Ubah nama, no. HP, atau role',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showEditStaffDialog(s);
                }),
            // lihat shift
            if (s.isActive)
              ListTile(
                leading: const Icon(Icons.calendar_month_outlined,
                    color: Color(0xFF9C27B0)),
                title: const Text('Jadwal Shift',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Color(0xFF9C27B0),
                        fontWeight: FontWeight.w600)),
                subtitle: const Text('Atur jadwal kerja mingguan',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StaffShiftScreen(staff: s),
                    ),
                  );
                }),
            // reset password
            if (s.isActive)
              ListTile(
                leading: const Icon(Icons.lock_reset_outlined,
                    color: Color(0xFF607D8B)),
                title: const Text('Reset Password',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Color(0xFF607D8B),
                        fontWeight: FontWeight.w600)),
                subtitle: const Text('Kirim email reset ke staff',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  _sendPasswordReset(s);
                }),
            const Divider(),
            // archive / restore
            if (s.isActive)
              ListTile(
                leading: const Icon(Icons.archive_outlined, color: Colors.orange),
                title: const Text('Arsipkan Staff',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.orange,
                        fontWeight: FontWeight.w600)),
                subtitle: const Text('Data tetap tersimpan, bisa diaktifkan kembali',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  _setActiveStatus(s, false);
                })
            else
              ListTile(
                leading: const Icon(Icons.unarchive_outlined,
                    color: Color(0xFF4CAF50)),
                title: const Text('Aktifkan Kembali',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Color(0xFF4CAF50),
                        fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(ctx);
                  _setActiveStatus(s, true);
                }),
          ]),
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

    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Tambah Staff',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8)),
                child: const Text(
                    '💡 Email & password ini akan digunakan staff untuk login ke aplikasi.',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12))),
              const SizedBox(height: 14),
              TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Nama Lengkap *',
                      prefixIcon: Icon(Icons.person_outline)),
                  textCapitalization: TextCapitalization.words),
              const SizedBox(height: 12),
              TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Email Login *',
                      hintText: 'contoh: budi@resto.com',
                      prefixIcon: Icon(Icons.email_outlined)),
                  keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 12),
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
                        onPressed: () => ss(() => obscure = !obscure))),
              ),
              const SizedBox(height: 12),
              TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(
                      labelText: 'No. HP (opsional)',
                      prefixIcon: Icon(Icons.phone_outlined)),
                  keyboardType: TextInputType.phone),
              const SizedBox(height: 12),
              DropdownButtonFormField<StaffRole>(
                value: selectedRole,
                decoration: const InputDecoration(labelText: 'Role'),
                items: StaffRole.values.map((r) => DropdownMenuItem(
                  value: r,
                  child: Row(children: [
                    Container(width: 10, height: 10,
                        decoration: BoxDecoration(
                            color: _roleColor(r), shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Text(r.displayName,
                        style: const TextStyle(fontFamily: 'Poppins')),
                  ]),
                )).toList(),
                onChanged: (v) { if (v != null) ss(() => selectedRole = v); },
              ),
              if (errorMsg != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(errorMsg!,
                      style: const TextStyle(
                          color: Colors.red,
                          fontSize: 12,
                          fontFamily: 'Poppins'))),
              ],
            ]),
          ),
          actions: [
            TextButton(
                onPressed: isLoading ? null : () => Navigator.pop(ctx),
                child: const Text('Batal')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white),
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

                      // ── step 1: cek duplikat ──
                      try {
                        final existing = await Supabase.instance.client
                            .from('staff')
                            .select('id')
                            .eq('email', email)
                            .maybeSingle();
                        if (existing != null) {
                          ss(() {
                            isLoading = false;
                            errorMsg = 'Email sudah terdaftar. Gunakan email lain.';
                          });
                          return;
                        }
                      } catch (e) {
                        ss(() {
                          isLoading = false;
                          errorMsg = 'Gagal memeriksa email: $e';
                        });
                        return;
                      }

                      // ── step 2: buat auth user ──
                      String? userId;
                      try {
                        final authRes = await Supabase.instance.client.auth
                            .signUp(email: email, password: pass);
                        userId = authRes.user?.id;
                        if (userId == null) throw Exception('Gagal membuat akun auth.');
                      } catch (e) {
                        ss(() {
                          isLoading = false;
                          errorMsg = e.toString().contains('already registered')
                              ? 'Email sudah terdaftar di sistem auth. Gunakan email lain.'
                              : 'Gagal buat akun: $e';
                        });
                        return;
                      }

                      // ── step 3: insert staff row ──
                      // Jika step ini gagal, auth user sudah terbuat.
                      // Log error & tampilkan pesan yang jelas ke manager.
                      try {
                        await Supabase.instance.client.from('staff').insert({
                          'user_id':   userId,
                          'branch_id': _branchId,
                          'full_name': name,
                          'email':     email,
                          'phone': phoneCtrl.text.trim().isEmpty
                              ? null
                              : phoneCtrl.text.trim(),
                          'role':      selectedRole.name,
                          'is_active': true,
                        });

                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                              content: Text('✅ Staff $name berhasil ditambahkan!'),
                              backgroundColor: const Color(0xFF4CAF50)));
                        }
                        await _load();
                      } catch (e) {
                        // Auth user sudah terbuat tapi data staff gagal disimpan.
                        // Tampilkan pesan khusus supaya manager tahu harus hubungi admin.
                        ss(() {
                          isLoading = false;
                          errorMsg =
                              'Akun berhasil dibuat tapi gagal simpan data staff.\n'
                              'Hubungi admin untuk menyelesaikan pendaftaran.\n\n'
                              'Detail: $e';
                        });
                      }
                    },
              child: isLoading
                  ? const SizedBox(
                      width: 18, height: 18,
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

  // ── build ──────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_showArchived ? 'Staff — Arsip' : 'Staff Management'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        titleTextStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white),
        actions: [
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
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          labelStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: 'Staff', icon: Icon(Icons.people_outline, size: 18)),
            Tab(text: 'Rekap Shift', icon: Icon(Icons.calendar_today_outlined, size: 18)),
          ],
        ),
      ),
      floatingActionButton: _showArchived
          ? null
          : FloatingActionButton.extended(
              onPressed: _showAddStaffDialog,
              backgroundColor: AppColors.accent,
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

  // ── TAB 1: daftar staff ────────────────────────────────
  Widget _buildStaffTab() {
    return Column(children: [
      // archived banner
      if (_showArchived)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.orange.shade50,
          child: const Row(children: [
            Icon(Icons.archive_outlined, color: Colors.orange, size: 16),
            SizedBox(width: 8),
            Expanded(
                child: Text('Menampilkan staff yang diarsipkan',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: Colors.orange))),
          ])),
      // search bar
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: TextField(
          controller: _searchCtrl,
          decoration: InputDecoration(
            hintText: 'Cari nama, email, atau role...',
            hintStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () => _searchCtrl.clear())
                : null,
            contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
      ),
      // summary chips
      if (!_isLoading && _staff.isNotEmpty) _buildRoleSummaryChips(),
      // list
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
                            size: 64,
                            color: AppColors.textHint),
                        const SizedBox(height: 12),
                        Text(
                            _searchQuery.isNotEmpty
                                ? 'Tidak ada staff dengan kata kunci "$_searchQuery"'
                                : _showArchived
                                    ? 'Tidak ada staff yang diarsipkan'
                                    : 'Belum ada staff',
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                color: AppColors.textSecondary),
                            textAlign: TextAlign.center),
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
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          // "Semua" chip
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Chip(
              label: Text('Semua (${_staff.length})',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 11)),
              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
            )),
          ...StaffRole.values
              .where((r) => counts.containsKey(r))
              .map((r) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Chip(
                      avatar: CircleAvatar(
                          backgroundColor: _roleColor(r),
                          radius: 6,
                          child: const SizedBox()),
                      label: Text('${r.displayName} (${counts[r]})',
                          style: const TextStyle(
                              fontFamily: 'Poppins', fontSize: 11)),
                      backgroundColor: _roleColor(r).withValues(alpha: 0.08),
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
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(children: [
                    Container(
                        width: 12, height: 12,
                        decoration: BoxDecoration(
                            color: color, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Text(role.displayName,
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: color)),
                    const SizedBox(width: 8),
                    Text('(${members.length})',
                        style: AppTextStyles.caption),
                  ])),
                ...members.map((s) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        onTap: () => _showStaffOptions(s),
                        leading: CircleAvatar(
                            backgroundColor:
                                color.withValues(alpha: 0.15),
                            child: Text(s.fullName[0].toUpperCase(),
                                style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w700,
                                    color: color))),
                        title: Text(s.fullName,
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w600)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.email, style: AppTextStyles.caption),
                            if (s.phone != null && s.phone!.isNotEmpty)
                              Text(s.phone!,
                                  style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 11,
                                      color: AppColors.textHint)),
                          ],
                        ),
                        isThreeLine:
                            s.phone != null && s.phone!.isNotEmpty,
                        trailing: Icon(Icons.chevron_right,
                            size: 20, color: AppColors.textSecondary),
                      ))),
                const SizedBox(height: 8),
              ],
            );
          }).toList(),
    );
  }

  // ── TAB 2: rekap shift minggu ini ─────────────────────
  Widget _buildShiftSummaryTab() {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _staff.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.calendar_month_outlined,
                        size: 64, color: AppColors.textHint),
                    const SizedBox(height: 12),
                    const Text('Belum ada staff aktif',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            color: AppColors.textSecondary)),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () => _tabController.animateTo(0),
                      child: const Text('Tambah Staff Dulu'),
                    ),
                  ],
                ))
            : _ShiftSummaryView(
                staff: _staff,
                branchId: _branchId ?? '',
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
  // day_of_week: 0=Mon ... 6=Sun
  static const _days = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

  Map<String, List<Map<String, dynamic>>> _shiftsByStaff = {};
  bool _isLoading = true;
  int _selectedDay = DateTime.now().weekday - 1; // 0-based Mon

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
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(7, (i) {
            final isToday = i == DateTime.now().weekday - 1;
            final isSelected = i == _selectedDay;
            return GestureDetector(
              onTap: () => setState(() => _selectedDay = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary
                      : isToday
                          ? AppColors.primary.withValues(alpha: 0.1)
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
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
                            fontSize: 11,
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          const Icon(Icons.people_outline, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(
              '${_staffOnSelectedDay.length} dari ${widget.staff.length} staff bertugas hari ${_days[_selectedDay]}',
              style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 12,
                  color: AppColors.textSecondary)),
        ])),
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
                            size: 56, color: AppColors.textHint),
                        const SizedBox(height: 8),
                        Text('Tidak ada shift di hari ${_days[_selectedDay]}',
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                color: AppColors.textSecondary)),
                      ],
                    ))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                    itemCount: _staffOnSelectedDay.length,
                    itemBuilder: (_, i) {
                      final s = _staffOnSelectedDay[i];
                      final shifts = (_shiftsByStaff[s.id] ?? [])
                          .where((sh) => sh['day_of_week'] == _selectedDay)
                          .toList();
                      final color = widget.roleColor(s.role);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          child: Row(children: [
                            CircleAvatar(
                                backgroundColor: color.withValues(alpha: 0.15),
                                child: Text(s.fullName[0].toUpperCase(),
                                    style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontWeight: FontWeight.w700,
                                        color: color))),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s.fullName,
                                      style: const TextStyle(
                                          fontFamily: 'Poppins',
                                          fontWeight: FontWeight.w600)),
                                  Text(s.role.displayName,
                                      style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: 11,
                                          color: color)),
                                  ...shifts.map((sh) => Text(
                                      '🕐 ${_formatTime(sh['start_time'])} — ${_formatTime(sh['end_time'])}',
                                      style: const TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: 12,
                                          color: AppColors.textSecondary))),
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