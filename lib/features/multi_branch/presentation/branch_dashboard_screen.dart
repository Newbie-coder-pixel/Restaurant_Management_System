import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_drawer.dart';

class BranchDashboardScreen extends ConsumerStatefulWidget {
  const BranchDashboardScreen({super.key});
  @override
  ConsumerState<BranchDashboardScreen> createState() => _BranchDashboardState();
}

class _BranchDashboardState extends ConsumerState<BranchDashboardScreen> {
  List<Map<String, dynamic>> _branches = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final res = await Supabase.instance.client
          .from('branches')
          .select('id, name, address, phone, is_active, opening_time, closing_time')
          .order('created_at');
      setState(() {
        _branches = (res as List).cast<Map<String, dynamic>>();
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  String _fmtTime(String? t) {
    if (t == null) return '-';
    return t.length >= 5 ? t.substring(0, 5) : t;
  }

  Future<TimeOfDay?> _pickTime(BuildContext ctx, TimeOfDay initial) =>
      showTimePicker(context: ctx, initialTime: initial);

  Future<void> _showBranchDialog({Map<String, dynamic>? branch}) async {
    final isEdit = branch != null;
    final nameCtrl    = TextEditingController(text: branch?['name'] ?? '');
    final addressCtrl = TextEditingController(text: branch?['address'] ?? '');
    final phoneCtrl   = TextEditingController(text: branch?['phone'] ?? '');

    // Parse existing times or default
    TimeOfDay openTime  = _parseTime(branch?['opening_time'], const TimeOfDay(hour: 10, minute: 0));
    TimeOfDay closeTime = _parseTime(branch?['closing_time'],  const TimeOfDay(hour: 22, minute: 0));
    bool isLoading = false;
    String? errorMsg;

    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(builder: (ctx, ss) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(isEdit ? 'Edit Cabang' : 'Tambah Cabang',
          style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Nama Cabang *', prefixIcon: Icon(Icons.store_outlined))),
          const SizedBox(height: 12),
          TextField(controller: addressCtrl,
            decoration: const InputDecoration(
              labelText: 'Alamat', prefixIcon: Icon(Icons.location_on_outlined)),
            maxLines: 2),
          const SizedBox(height: 12),
          TextField(controller: phoneCtrl,
            decoration: const InputDecoration(
              labelText: 'No. Telepon', prefixIcon: Icon(Icons.phone_outlined)),
            keyboardType: TextInputType.phone),
          const SizedBox(height: 16),
          // Jam Operasional Section
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('🕐 Jam Operasional',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _TimePickerButton(
                  label: 'Buka',
                  time: openTime,
                  onTap: () async {
                    final t = await _pickTime(ctx, openTime);
                    if (t != null) ss(() => openTime = t);
                  },
                )),
                const SizedBox(width: 10),
                const Text('–', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(width: 10),
                Expanded(child: _TimePickerButton(
                  label: 'Tutup',
                  time: closeTime,
                  onTap: () async {
                    final t = await _pickTime(ctx, closeTime);
                    if (t != null) ss(() => closeTime = t);
                  },
                )),
              ]),
            ]),
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
              if (nameCtrl.text.trim().isEmpty) {
                ss(() => errorMsg = 'Nama cabang wajib diisi.');
                return;
              }
              // Validate close > open
              final openMin  = openTime.hour * 60 + openTime.minute;
              final closeMin = closeTime.hour * 60 + closeTime.minute;
              if (closeMin <= openMin) {
                ss(() => errorMsg = 'Jam tutup harus setelah jam buka.');
                return;
              }
              ss(() { isLoading = true; errorMsg = null; });
              try {
                final data = {
                  'name':         nameCtrl.text.trim(),
                  'address':      addressCtrl.text.trim().isEmpty ? null : addressCtrl.text.trim(),
                  'phone':        phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                  'is_active':    true,
                  'opening_time': '${openTime.hour.toString().padLeft(2,'0')}:${openTime.minute.toString().padLeft(2,'0')}:00',
                  'closing_time': '${closeTime.hour.toString().padLeft(2,'0')}:${closeTime.minute.toString().padLeft(2,'0')}:00',
                };
                if (isEdit) {
                  await Supabase.instance.client
                      .from('branches').update(data).eq('id', branch['id']);
                } else {
                  await Supabase.instance.client.from('branches').insert(data);
                }
                if (ctx.mounted) Navigator.pop(ctx);
                await _load();
              } catch (e) {
                ss(() { isLoading = false; errorMsg = 'Gagal: $e'; });
              }
            },
            child: isLoading
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(isEdit ? 'Simpan' : 'Tambah',
                    style: const TextStyle(fontFamily: 'Poppins')),
          ),
        ],
      )),
    );
  }

  TimeOfDay _parseTime(String? t, TimeOfDay fallback) {
    if (t == null || t.isEmpty) return fallback;
    final parts = t.split(':');
    if (parts.length < 2) return fallback;
    return TimeOfDay(hour: int.tryParse(parts[0]) ?? fallback.hour,
                     minute: int.tryParse(parts[1]) ?? fallback.minute);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Multi-Branch Dashboard'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        titleTextStyle: const TextStyle(
          fontFamily: 'Poppins', fontSize: 18,
          fontWeight: FontWeight.w600, color: Colors.white),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showBranchDialog(),
        backgroundColor: AppColors.accent,
        icon: const Icon(Icons.add_business, color: Colors.white),
        label: const Text('Tambah Cabang',
          style: TextStyle(color: Colors.white, fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _branches.isEmpty
              ? const Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.store_outlined, size: 64, color: AppColors.textHint),
                    SizedBox(height: 12),
                    Text('Belum ada cabang',
                      style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)),
                  ]))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _branches.length,
                  itemBuilder: (_, i) {
                    final b = _branches[i];
                    final isActive = b['is_active'] ?? true;
                    final openStr  = _fmtTime(b['opening_time']);
                    final closeStr = _fmtTime(b['closing_time']);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: Container(
                          width: 50, height: 50,
                          decoration: BoxDecoration(
                            color: isActive
                                ? AppColors.primary.withValues(alpha: 0.1)
                                : AppColors.textHint.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12)),
                          child: Icon(Icons.store,
                            color: isActive ? AppColors.primary : AppColors.textHint,
                            size: 26)),
                        title: Text(b['name'] ?? '',
                          style: const TextStyle(
                            fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (b['address'] != null) ...[
                              const SizedBox(height: 4),
                              Text(b['address'], style: AppTextStyles.caption),
                            ],
                            if (b['phone'] != null) ...[
                              const SizedBox(height: 2),
                              Text(b['phone'], style: AppTextStyles.caption),
                            ],
                            const SizedBox(height: 4),
                            Row(children: [
                              const Icon(Icons.access_time, size: 13, color: AppColors.textHint),
                              const SizedBox(width: 4),
                              Text('$openStr – $closeStr WIB',
                                style: const TextStyle(
                                  fontFamily: 'Poppins', fontSize: 11,
                                  color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                            ]),
                          ],
                        ),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            color: AppColors.primary,
                            tooltip: 'Edit',
                            onPressed: () => _showBranchDialog(branch: b)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: (isActive ? AppColors.available : AppColors.textHint)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isActive ? AppColors.available : AppColors.textHint)),
                            child: Text(isActive ? 'Aktif' : 'Non-Aktif',
                              style: TextStyle(
                                fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w600,
                                color: isActive ? AppColors.available : AppColors.textHint)),
                          ),
                        ]),
                        isThreeLine: true,
                      ),
                    );
                  },
                ),
    );
  }
}

class _TimePickerButton extends StatelessWidget {
  final String label;
  final TimeOfDay time;
  final VoidCallback onTap;
  const _TimePickerButton({required this.label, required this.time, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.4))),
        child: Column(children: [
          Text(label,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          Text('$h:$m',
            style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
        ]),
      ),
    );
  }
}