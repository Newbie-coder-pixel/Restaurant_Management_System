import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/models/staff_model.dart';
import '../../../core/models/staff_role.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/widgets/app_drawer.dart';

class StaffScreen extends ConsumerStatefulWidget {
  const StaffScreen({super.key});
  @override
  ConsumerState<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends ConsumerState<StaffScreen> {
  List<StaffMember> _staff = [];
  bool _isLoading = true;
  String? _branchId;
  bool _showArchived = false;
  bool _initialized = false;

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

  bool _isValidEmail(String email) {
    final re = RegExp(r'^[\w.+-]+@[\w-]+\.[a-zA-Z]{2,}$');
    return re.hasMatch(email);
  }

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
        .from('staff').update({'is_active': active}).eq('id', s.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(active ? '✅ ${s.fullName} diaktifkan kembali' : '📦 ${s.fullName} diarsipkan'),
        backgroundColor: active ? const Color(0xFF4CAF50) : Colors.orange));
    }
    await _load();
  }

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
            ListTile(
              leading: CircleAvatar(
                backgroundColor: _roleColor(s.role).withValues(alpha: 0.15),
                child: Text(s.fullName[0].toUpperCase(),
                  style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                    color: _roleColor(s.role)))),
              title: Text(s.fullName,
                style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
              subtitle: Text('${s.role.displayName} • ${s.email}',
                style: AppTextStyles.caption)),
            const Divider(),
            if (s.isActive)
              ListTile(
                leading: const Icon(Icons.archive_outlined, color: Colors.orange),
                title: const Text('Arsipkan Staff',
                  style: TextStyle(fontFamily: 'Poppins', color: Colors.orange, fontWeight: FontWeight.w600)),
                subtitle: const Text('Data tetap tersimpan, bisa diaktifkan kembali',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11)),
                onTap: () { Navigator.pop(ctx); _setActiveStatus(s, false); })
            else
              ListTile(
                leading: const Icon(Icons.unarchive_outlined, color: Color(0xFF4CAF50)),
                title: const Text('Aktifkan Kembali',
                  style: TextStyle(fontFamily: 'Poppins', color: Color(0xFF4CAF50), fontWeight: FontWeight.w600)),
                onTap: () { Navigator.pop(ctx); _setActiveStatus(s, true); }),
          ]),
        ),
      ),
    );
  }

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
      builder: (_) => StatefulBuilder(builder: (ctx, ss) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Tambah Staff',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8)),
            child: const Text(
              '💡 Email & password ini akan digunakan staff untuk login ke aplikasi.',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 12))),
          const SizedBox(height: 14),
          TextField(controller: nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Nama Lengkap *', prefixIcon: Icon(Icons.person_outline))),
          const SizedBox(height: 12),
          TextField(controller: emailCtrl,
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
                icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => ss(() => obscure = !obscure))),
          ),
          const SizedBox(height: 12),
          TextField(controller: phoneCtrl,
            decoration: const InputDecoration(
              labelText: 'No. HP (opsional)', prefixIcon: Icon(Icons.phone_outlined)),
            keyboardType: TextInputType.phone),
          const SizedBox(height: 12),
          DropdownButtonFormField<StaffRole>(
            initialValue: selectedRole,
            decoration: const InputDecoration(labelText: 'Role'),
            items: StaffRole.values.map((r) => DropdownMenuItem(
              value: r,
              child: Row(children: [
                Container(width: 10, height: 10,
                  decoration: BoxDecoration(color: _roleColor(r), shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(r.displayName, style: const TextStyle(fontFamily: 'Poppins')),
              ]),
            )).toList(),
            onChanged: (v) { if (v != null) ss(() => selectedRole = v); },
          ),
          if (errorMsg != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
              child: Text(errorMsg!,
                style: const TextStyle(color: Colors.red, fontSize: 12, fontFamily: 'Poppins'))),
          ],
        ])),
        actions: [
          TextButton(
            onPressed: isLoading ? null : () => Navigator.pop(ctx),
            child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            onPressed: isLoading ? null : () async {
              final name  = nameCtrl.text.trim();
              final email = emailCtrl.text.trim().toLowerCase();
              final pass  = passwordCtrl.text;

              if (name.isEmpty) { ss(() => errorMsg = 'Nama wajib diisi.'); return; }
              if (email.isEmpty) { ss(() => errorMsg = 'Email wajib diisi.'); return; }
              if (!_isValidEmail(email)) {
                ss(() => errorMsg = 'Format email tidak valid.\nContoh: nama@domain.com');
                return;
              }
              if (pass.length < 6) {
                ss(() => errorMsg = 'Password minimal 6 karakter.'); return;
              }

              ss(() { isLoading = true; errorMsg = null; });
              try {
                final existing = await Supabase.instance.client
                    .from('staff').select('id').eq('email', email).maybeSingle();
                if (existing != null) {
                  ss(() { isLoading = false;
                    errorMsg = 'Email sudah terdaftar. Gunakan email lain.'; });
                  return;
                }

                final authRes = await Supabase.instance.client.auth
                    .signUp(email: email, password: pass);
                final userId = authRes.user?.id;
                if (userId == null) throw Exception('Gagal membuat akun.');

                await Supabase.instance.client.from('staff').insert({
                  'user_id':   userId,
                  'branch_id': _branchId,
                  'full_name': name,
                  'email':     email,
                  'phone':     phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
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
                ss(() {
                  isLoading = false;
                  errorMsg = e.toString().contains('already registered') ||
                      e.toString().contains('duplicate key')
                      ? 'Email sudah terdaftar. Gunakan email lain.'
                      : 'Gagal: ${e.toString()}';
                });
              }
            },
            child: isLoading
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Simpan', style: TextStyle(fontFamily: 'Poppins')),
          ),
        ],
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <StaffRole, List<StaffMember>>{};
    for (final s in _staff) {
      grouped.putIfAbsent(s.role, () => []).add(s);
    }

    return Scaffold(
      drawer: const AppDrawer(),
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_showArchived ? 'Staff — Arsip' : 'Staff Management'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        titleTextStyle: const TextStyle(
          fontFamily: 'Poppins', fontSize: 18,
          fontWeight: FontWeight.w600, color: Colors.white),
        actions: [
          TextButton.icon(
            onPressed: () { setState(() => _showArchived = !_showArchived); _load(); },
            icon: Icon(
              _showArchived ? Icons.people : Icons.archive_outlined,
              color: Colors.white, size: 18),
            label: Text(_showArchived ? 'Aktif' : 'Arsip',
              style: const TextStyle(color: Colors.white, fontFamily: 'Poppins', fontSize: 13))),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: _showArchived ? null : FloatingActionButton.extended(
        onPressed: _showAddStaffDialog,
        backgroundColor: AppColors.accent,
        icon: const Icon(Icons.person_add, color: Colors.white),
        label: const Text('Tambah Staff',
          style: TextStyle(color: Colors.white, fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
      ),
      body: Column(children: [
        if (_showArchived)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.orange.shade50,
            child: const Row(children: [
              Icon(Icons.archive_outlined, color: Colors.orange, size: 16),
              SizedBox(width: 8),
              Expanded(child: Text('Menampilkan staff yang diarsipkan',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.orange))),
            ])),
        Expanded(
          child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _staff.isEmpty
                ? Center(child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_showArchived ? Icons.inventory_2_outlined : Icons.people_outline,
                        size: 64, color: AppColors.textHint),
                      const SizedBox(height: 12),
                      Text(
                        _showArchived ? 'Tidak ada staff yang diarsipkan' : 'Belum ada staff',
                        style: const TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)),
                    ]))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
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
                                Container(width: 12, height: 12,
                                  decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                                const SizedBox(width: 8),
                                Text(role.displayName,
                                  style: TextStyle(fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w700, fontSize: 14, color: color)),
                                const SizedBox(width: 8),
                                Text('(${members.length})', style: AppTextStyles.caption),
                              ])),
                            ...members.map((s) => Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                onLongPress: () => _showStaffOptions(s),
                                leading: CircleAvatar(
                                  backgroundColor: color.withValues(alpha: 0.15),
                                  child: Text(s.fullName[0].toUpperCase(),
                                    style: TextStyle(fontFamily: 'Poppins',
                                      fontWeight: FontWeight.w700, color: color))),
                                title: Text(s.fullName,
                                  style: const TextStyle(
                                    fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
                                subtitle: Text(s.email, style: AppTextStyles.caption),
                                trailing: GestureDetector(
                                  onTap: () => _showStaffOptions(s),
                                  child: Icon(
                                    _showArchived ? Icons.unarchive_outlined : Icons.more_vert,
                                    size: 20, color: AppColors.textSecondary)),
                              ))),
                            const SizedBox(height: 8),
                          ],
                        );
                      }).toList()),
        ),
      ]),
    );
  }
}