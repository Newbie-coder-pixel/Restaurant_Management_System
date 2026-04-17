import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/models/staff_model.dart';
import '../../../core/models/staff_role.dart';
import '../../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────
// Enum status absensi (sesuai kolom DB: status varchar(20))
// ─────────────────────────────────────────────────────────
enum AttendanceStatus {
  hadir,
  izin,
  sakit,
  alpha,
  cuti;

  String get label {
    switch (this) {
      case AttendanceStatus.hadir:  return 'Hadir';
      case AttendanceStatus.izin:   return 'Izin';
      case AttendanceStatus.sakit:  return 'Sakit';
      case AttendanceStatus.alpha:  return 'Alpha';
      case AttendanceStatus.cuti:   return 'Cuti';
    }
  }

  String get value => name; // 'hadir', 'izin', dst — cocok dengan DB

  Color get color {
    switch (this) {
      case AttendanceStatus.hadir:  return const Color(0xFF4CAF50);
      case AttendanceStatus.izin:   return const Color(0xFF2196F3);
      case AttendanceStatus.sakit:  return const Color(0xFFFF9800);
      case AttendanceStatus.alpha:  return const Color(0xFFF44336);
      case AttendanceStatus.cuti:   return const Color(0xFF9C27B0);
    }
  }

  static AttendanceStatus fromString(String? s) {
    switch (s) {
      case 'izin':   return AttendanceStatus.izin;
      case 'sakit':  return AttendanceStatus.sakit;
      case 'alpha':  return AttendanceStatus.alpha;
      case 'cuti':   return AttendanceStatus.cuti;
      default:       return AttendanceStatus.hadir;
    }
  }
}

// ─────────────────────────────────────────────────────────
// Model lokal untuk attendance
// ─────────────────────────────────────────────────────────
class AttendanceRecord {
  final String id;
  final String staffId;
  final String branchId;
  final DateTime? clockIn;
  final DateTime? clockOut;
  final DateTime date;
  final AttendanceStatus status;
  final String? notes;

  AttendanceRecord({
    required this.id,
    required this.staffId,
    required this.branchId,
    this.clockIn,
    this.clockOut,
    required this.date,
    required this.status,
    this.notes,
  });

  factory AttendanceRecord.fromJson(Map<String, dynamic> j) => AttendanceRecord(
        id: j['id'] as String,
        staffId: j['staff_id'] as String,
        branchId: j['branch_id'] as String,
        clockIn: j['clock_in'] != null
            ? DateTime.parse(j['clock_in'] as String).toLocal()
            : null,
        clockOut: j['clock_out'] != null
            ? DateTime.parse(j['clock_out'] as String).toLocal()
            : null,
        date: DateTime.parse(j['date'] as String),
        status: AttendanceStatus.fromString(j['status'] as String?),
        notes: j['notes'] as String?,
      );

  // Durasi kerja dalam menit (null jika belum clock out)
  int? get durationMinutes {
    if (clockIn == null || clockOut == null) return null;
    return clockOut!.difference(clockIn!).inMinutes;
  }

  String get durationText {
    final mins = durationMinutes;
    if (mins == null) return '—';
    final h = mins ~/ 60;
    final m = mins % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}j';
    return '${h}j ${m}m';
  }

  bool get isComplete => clockIn != null && clockOut != null;
  bool get needsClock => status == AttendanceStatus.hadir;
}

// ─────────────────────────────────────────────────────────
// Screen utama
// ─────────────────────────────────────────────────────────
class StaffAttendanceScreen extends StatefulWidget {
  final StaffMember staff;
  final String branchId;

  const StaffAttendanceScreen({
    super.key,
    required this.staff,
    required this.branchId,
  });

  @override
  State<StaffAttendanceScreen> createState() => _StaffAttendanceScreenState();
}

class _StaffAttendanceScreenState extends State<StaffAttendanceScreen> {
  List<AttendanceRecord> _records = [];
  bool _isLoading = true;

  late DateTime _selectedMonth;

  @override
  void initState() {
    super.initState();
    _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
    _load();
  }

  // ── load data attendance ────────────────────────────────
  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final firstDay = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
      final lastDay =
          DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);

      final res = await Supabase.instance.client
          .from('attendance')
          .select()
          .eq('staff_id', widget.staff.id)
          .gte('date', _formatDate(firstDay))
          .lte('date', _formatDate(lastDay))
          .order('date', ascending: false);

      if (mounted) {
        setState(() {
          _records = (res as List)
              .map((e) => AttendanceRecord.fromJson(e as Map<String, dynamic>))
              .toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Gagal memuat data absensi: $e'),
            backgroundColor: Colors.red));
      }
    }
  }

  // ── dialog tambah attendance ───────────────────────────
  Future<void> _showAddAttendanceDialog() async {
    DateTime selectedDate = DateTime.now();
    TimeOfDay? clockInTime;
    TimeOfDay? clockOutTime;
    AttendanceStatus selectedStatus = AttendanceStatus.hadir;
    final notesController = TextEditingController();
    String? errorMsg;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Tambah Catatan Absensi',
              style: TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Info banner
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8)),
                child: const Text(
                    '📋 Input manual oleh manager. Gunakan untuk koreksi atau lupa absen.',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12)),
              ),
              const SizedBox(height: 16),

              // Pilih tanggal
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: selectedDate,
                    firstDate: DateTime(DateTime.now().year - 1),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) ss(() => selectedDate = picked);
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: 12, horizontal: 14),
                  decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    const Icon(Icons.calendar_today_outlined,
                        size: 18, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Tanggal',
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 11,
                                  color: Colors.grey)),
                          Text(_formatDateDisplay(selectedDate),
                              style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w600)),
                        ]),
                  ]),
                ),
              ),
              const SizedBox(height: 12),

              // Status dropdown
              DropdownButtonFormField<AttendanceStatus>(
                initialValue: selectedStatus,
                decoration: InputDecoration(
                  labelText: 'Status Kehadiran',
                  labelStyle: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 13),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
                items: AttendanceStatus.values
                    .map((s) => DropdownMenuItem(
                          value: s,
                          child: Row(children: [
                            Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                    color: s.color, shape: BoxShape.circle)),
                            const SizedBox(width: 8),
                            Text(s.label,
                                style: const TextStyle(
                                    fontFamily: 'Poppins', fontSize: 13)),
                          ]),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) ss(() => selectedStatus = v);
                },
              ),
              const SizedBox(height: 12),

              // Jam masuk & keluar (hanya tampil kalau status = hadir)
              if (selectedStatus == AttendanceStatus.hadir) ...[
                Row(children: [
                  Expanded(
                      child: _TimePickerButton(
                    label: 'Jam Masuk',
                    icon: Icons.login_outlined,
                    value: clockInTime,
                    onTap: () async {
                      final t = await showTimePicker(
                          context: ctx,
                          initialTime: clockInTime ??
                              const TimeOfDay(hour: 8, minute: 0));
                      if (t != null) ss(() => clockInTime = t);
                    },
                  )),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _TimePickerButton(
                    label: 'Jam Keluar',
                    icon: Icons.logout_outlined,
                    value: clockOutTime,
                    onTap: () async {
                      final t = await showTimePicker(
                          context: ctx,
                          initialTime: clockOutTime ??
                              const TimeOfDay(hour: 17, minute: 0));
                      if (t != null) ss(() => clockOutTime = t);
                    },
                  )),
                ]),
                const SizedBox(height: 12),
              ],

              // Notes
              TextField(
                controller: notesController,
                maxLines: 2,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Catatan (opsional)',
                  labelStyle: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 13),
                  hintText: 'Misal: izin acara keluarga, sakit demam...',
                  hintStyle: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 12, color: Colors.grey),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
              ),

              if (errorMsg != null) ...[
                const SizedBox(height: 10),
                Text(errorMsg!,
                    style: const TextStyle(
                        color: Colors.red,
                        fontSize: 12,
                        fontFamily: 'Poppins')),
              ],
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Batal')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white),
              onPressed: () async {
                // Validasi jam jika status hadir
                if (selectedStatus == AttendanceStatus.hadir) {
                  if (clockInTime == null) {
                    ss(() => errorMsg = 'Jam masuk wajib diisi untuk status Hadir.');
                    return;
                  }
                  if (clockOutTime != null) {
                    final inMins =
                        clockInTime!.hour * 60 + clockInTime!.minute;
                    final outMins =
                        clockOutTime!.hour * 60 + clockOutTime!.minute;
                    if (outMins <= inMins) {
                      ss(() => errorMsg =
                          'Jam keluar harus setelah jam masuk.');
                      return;
                    }
                  }
                }
                // Cek duplikat
                final dateStr = _formatDate(selectedDate);
                final existing =
                    _records.any((r) => _formatDate(r.date) == dateStr);
                if (existing) {
                  ss(() =>
                      errorMsg = 'Sudah ada catatan absensi di tanggal ini.');
                  return;
                }

                Navigator.pop(ctx);
                await _insertAttendance(
                  date: selectedDate,
                  clockIn: selectedStatus == AttendanceStatus.hadir
                      ? clockInTime
                      : null,
                  clockOut: selectedStatus == AttendanceStatus.hadir
                      ? clockOutTime
                      : null,
                  status: selectedStatus,
                  notes: notesController.text.trim().isEmpty
                      ? null
                      : notesController.text.trim(),
                );
              },
              child:
                  const Text('Simpan', style: TextStyle(fontFamily: 'Poppins')),
            ),
          ],
        ),
      ),
    );

    notesController.dispose();
  }

  Future<void> _insertAttendance({
    required DateTime date,
    TimeOfDay? clockIn,
    TimeOfDay? clockOut,
    required AttendanceStatus status,
    String? notes,
  }) async {
    try {
      final clockInDt = clockIn != null
          ? DateTime(date.year, date.month, date.day, clockIn.hour,
                  clockIn.minute)
              .toUtc()
              .toIso8601String()
          : null;
      final clockOutDt = clockOut != null
          ? DateTime(date.year, date.month, date.day, clockOut.hour,
                  clockOut.minute)
              .toUtc()
              .toIso8601String()
          : null;

      await Supabase.instance.client.from('attendance').insert({
        'staff_id': widget.staff.id,
        'branch_id': widget.branchId,
        'date': _formatDate(date),
        'status': status.value,
        if (clockInDt != null) 'clock_in': clockInDt,
        if (clockOutDt != null) 'clock_out': clockOutDt,
        if (notes != null) 'notes': notes,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('✅ Catatan absensi berhasil disimpan'),
            backgroundColor: Color(0xFF4CAF50)));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Gagal menyimpan: $e'),
            backgroundColor: Colors.red));
      }
    }
  }

  // ── dialog edit attendance ─────────────────────────────
  Future<void> _showEditDialog(AttendanceRecord record) async {
    TimeOfDay? clockInTime = record.clockIn != null
        ? TimeOfDay.fromDateTime(record.clockIn!)
        : null;
    TimeOfDay? clockOutTime = record.clockOut != null
        ? TimeOfDay.fromDateTime(record.clockOut!)
        : null;
    AttendanceStatus selectedStatus = record.status;
    final notesController =
        TextEditingController(text: record.notes ?? '');
    String? errorMsg;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
              'Edit Absensi — ${_formatDateDisplay(record.date)}',
              style: const TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Status dropdown
              DropdownButtonFormField<AttendanceStatus>(
                initialValue: selectedStatus,
                decoration: InputDecoration(
                  labelText: 'Status Kehadiran',
                  labelStyle: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 13),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
                items: AttendanceStatus.values
                    .map((s) => DropdownMenuItem(
                          value: s,
                          child: Row(children: [
                            Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                    color: s.color, shape: BoxShape.circle)),
                            const SizedBox(width: 8),
                            Text(s.label,
                                style: const TextStyle(
                                    fontFamily: 'Poppins', fontSize: 13)),
                          ]),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    ss(() {
                      selectedStatus = v;
                      // Reset jam kalau ganti ke non-hadir
                      if (v != AttendanceStatus.hadir) {
                        clockInTime = null;
                        clockOutTime = null;
                      }
                    });
                  }
                },
              ),
              const SizedBox(height: 12),

              // Jam (hanya kalau status hadir)
              if (selectedStatus == AttendanceStatus.hadir) ...[
                Row(children: [
                  Expanded(
                      child: _TimePickerButton(
                    label: 'Jam Masuk',
                    icon: Icons.login_outlined,
                    value: clockInTime,
                    onTap: () async {
                      final t = await showTimePicker(
                          context: ctx,
                          initialTime: clockInTime ??
                              const TimeOfDay(hour: 8, minute: 0));
                      if (t != null) ss(() => clockInTime = t);
                    },
                  )),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _TimePickerButton(
                    label: 'Jam Keluar',
                    icon: Icons.logout_outlined,
                    value: clockOutTime,
                    onTap: () async {
                      final t = await showTimePicker(
                          context: ctx,
                          initialTime: clockOutTime ??
                              const TimeOfDay(hour: 17, minute: 0));
                      if (t != null) ss(() => clockOutTime = t);
                    },
                  )),
                ]),
                const SizedBox(height: 12),
              ],

              // Notes
              TextField(
                controller: notesController,
                maxLines: 2,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Catatan (opsional)',
                  labelStyle: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 13),
                  hintText: 'Misal: izin acara keluarga, sakit demam...',
                  hintStyle: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 12, color: Colors.grey),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
              ),

              if (errorMsg != null) ...[
                const SizedBox(height: 10),
                Text(errorMsg!,
                    style: const TextStyle(
                        color: Colors.red,
                        fontSize: 12,
                        fontFamily: 'Poppins')),
              ],
            ]),
          ),
          actions: [
            // Hapus
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _deleteAttendance(record);
              },
              child:
                  const Text('Hapus', style: TextStyle(color: Colors.red)),
            ),
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Batal')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white),
              onPressed: () async {
                if (selectedStatus == AttendanceStatus.hadir &&
                    clockInTime == null) {
                  ss(() => errorMsg =
                      'Jam masuk wajib diisi untuk status Hadir.');
                  return;
                }
                if (clockInTime != null && clockOutTime != null) {
                  final inMins =
                      clockInTime!.hour * 60 + clockInTime!.minute;
                  final outMins =
                      clockOutTime!.hour * 60 + clockOutTime!.minute;
                  if (outMins <= inMins) {
                    ss(() =>
                        errorMsg = 'Jam keluar harus setelah jam masuk.');
                    return;
                  }
                }
                Navigator.pop(ctx);
                await _updateAttendance(
                  record: record,
                  clockIn: selectedStatus == AttendanceStatus.hadir
                      ? clockInTime
                      : null,
                  clockOut: selectedStatus == AttendanceStatus.hadir
                      ? clockOutTime
                      : null,
                  status: selectedStatus,
                  notes: notesController.text.trim().isEmpty
                      ? null
                      : notesController.text.trim(),
                );
              },
              child:
                  const Text('Simpan', style: TextStyle(fontFamily: 'Poppins')),
            ),
          ],
        ),
      ),
    );

    notesController.dispose();
  }

  Future<void> _updateAttendance({
    required AttendanceRecord record,
    TimeOfDay? clockIn,
    TimeOfDay? clockOut,
    required AttendanceStatus status,
    String? notes,
  }) async {
    try {
      final base = record.date;
      final clockInDt = clockIn != null
          ? DateTime(base.year, base.month, base.day, clockIn.hour,
                  clockIn.minute)
              .toUtc()
              .toIso8601String()
          : null;
      final clockOutDt = clockOut != null
          ? DateTime(base.year, base.month, base.day, clockOut.hour,
                  clockOut.minute)
              .toUtc()
              .toIso8601String()
          : null;

      await Supabase.instance.client.from('attendance').update({
        'status': status.value,
        'clock_in': clockInDt,   // null akan clear kolom
        'clock_out': clockOutDt, // null akan clear kolom
        'notes': notes,
      }).eq('id', record.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('✅ Absensi berhasil diperbarui'),
            backgroundColor: Color(0xFF4CAF50)));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Gagal memperbarui: $e'),
            backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _deleteAttendance(AttendanceRecord record) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Catatan',
            style: TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: Text(
            'Yakin ingin menghapus catatan absensi ${_formatDateDisplay(record.date)}?',
            style: const TextStyle(fontFamily: 'Poppins')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus', style: TextStyle(fontFamily: 'Poppins')),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await Supabase.instance.client
          .from('attendance')
          .delete()
          .eq('id', record.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('🗑️ Catatan absensi dihapus'),
            backgroundColor: Colors.orange));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Gagal menghapus: $e'),
            backgroundColor: Colors.red));
      }
    }
  }

  // ── helpers ────────────────────────────────────────────
  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _formatDateDisplay(DateTime d) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
    ];
    const days = ['Min', 'Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab'];
    return '${days[d.weekday % 7]}, ${d.day} ${months[d.month]} ${d.year}';
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return '—';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _monthLabel(DateTime d) {
    const months = [
      '', 'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
      'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
    ];
    return '${months[d.month]} ${d.year}';
  }

  // ── summary stats ──────────────────────────────────────
  _AttendanceStats get _stats {
    final hadirRecords =
        _records.where((r) => r.status == AttendanceStatus.hadir).toList();
    final complete = hadirRecords.where((r) => r.isComplete).toList();
    final totalMins =
        complete.fold<int>(0, (s, r) => s + (r.durationMinutes ?? 0));
    final avgMins =
        complete.isEmpty ? 0 : totalMins ~/ complete.length;
    return _AttendanceStats(
      totalDays: _records.length,
      hadirDays: hadirRecords.length,
      notHadirDays: _records
          .where((r) => r.status != AttendanceStatus.hadir)
          .length,
      totalMinutes: totalMins,
      avgMinutes: avgMins,
    );
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

  // ── build ──────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final roleColor = _roleColor(widget.staff.role);
    final stats = _stats;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Absensi — ${widget.staff.fullName}',
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 16,
                fontWeight: FontWeight.w600)),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddAttendanceDialog,
        backgroundColor: AppColors.accent,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Tambah Catatan',
            style: TextStyle(color: Colors.white, fontFamily: 'Poppins')),
      ),
      body: Column(children: [
        // ── Staff header ──
        Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Row(children: [
            CircleAvatar(
                radius: 22,
                backgroundColor: roleColor.withValues(alpha: 0.15),
                child: Text(widget.staff.fullName[0].toUpperCase(),
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: roleColor))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.staff.fullName,
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700)),
                    Text(widget.staff.role.displayName,
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            color: roleColor)),
                  ]),
            ),
          ]),
        ),

        // ── Month selector ──
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () {
                setState(() => _selectedMonth = DateTime(
                    _selectedMonth.year, _selectedMonth.month - 1));
                _load();
              },
            ),
            Expanded(
              child: Text(_monthLabel(_selectedMonth),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: _selectedMonth.month == DateTime.now().month &&
                      _selectedMonth.year == DateTime.now().year
                  ? null
                  : () {
                      setState(() => _selectedMonth = DateTime(
                          _selectedMonth.year, _selectedMonth.month + 1));
                      _load();
                    },
            ),
          ]),
        ),

        // ── Stats summary ──
        if (!_isLoading && _records.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(children: [
              _StatChip(
                  label: 'Total',
                  value: '${stats.totalDays}x',
                  color: AppColors.primary),
              const SizedBox(width: 8),
              _StatChip(
                  label: 'Hadir',
                  value: '${stats.hadirDays}x',
                  color: const Color(0xFF4CAF50)),
              const SizedBox(width: 8),
              _StatChip(
                  label: 'Total Jam',
                  value:
                      '${(stats.totalMinutes / 60).toStringAsFixed(1)}j',
                  color: const Color(0xFF9C27B0)),
              const SizedBox(width: 8),
              _StatChip(
                  label: 'Rata-rata',
                  value:
                      '${(stats.avgMinutes / 60).toStringAsFixed(1)}j',
                  color: const Color(0xFFFF9800)),
            ]),
          ),

        // ── List ──
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _records.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.event_busy_outlined,
                              size: 56, color: AppColors.textHint),
                          const SizedBox(height: 8),
                          Text(
                              'Belum ada catatan absensi di ${_monthLabel(_selectedMonth)}',
                              style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  color: AppColors.textSecondary),
                              textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _showAddAttendanceDialog,
                            icon: const Icon(Icons.add),
                            label: const Text('Tambah Catatan'),
                          ),
                        ],
                      ))
                  : ListView.builder(
                      padding:
                          const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      itemCount: _records.length,
                      itemBuilder: (_, i) => _AttendanceCard(
                        record: _records[i],
                        formatDateDisplay: _formatDateDisplay,
                        formatTime: _formatTime,
                        onEdit: () => _showEditDialog(_records[i]),
                      ),
                    ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Card per record
// ─────────────────────────────────────────────────────────
class _AttendanceCard extends StatelessWidget {
  final AttendanceRecord record;
  final String Function(DateTime) formatDateDisplay;
  final String Function(DateTime?) formatTime;
  final VoidCallback onEdit;

  const _AttendanceCard({
    required this.record,
    required this.formatDateDisplay,
    required this.formatTime,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final status = record.status;
    final statusColor = status.color;
    final statusLabel = status.label;
    final showClock = status == AttendanceStatus.hadir;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            // Status bar
            Container(
              width: 4,
              height: 52,
              decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 12),
            // Date + jam
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(formatDateDisplay(record.date),
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                    const SizedBox(height: 4),
                    if (showClock)
                      Row(children: [
                        const Icon(Icons.login_outlined,
                            size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(formatTime(record.clockIn),
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                color: AppColors.textSecondary)),
                        const SizedBox(width: 12),
                        const Icon(Icons.logout_outlined,
                            size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(formatTime(record.clockOut),
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                color: AppColors.textSecondary)),
                      ]),
                    // Notes preview
                    if (record.notes != null &&
                        record.notes!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        record.notes!,
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            fontStyle: FontStyle.italic),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ]),
            ),
            // Duration + status badge
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (showClock)
                Text(record.durationText,
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(statusLabel,
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10,
                        color: statusColor,
                        fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(width: 4),
            const Icon(Icons.edit_outlined,
                size: 16, color: AppColors.textHint),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Helper widgets
// ─────────────────────────────────────────────────────────
class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding:
            const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10)),
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: color)),
          Text(label,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 10,
                  color: AppColors.textSecondary)),
        ]),
      ),
    );
  }
}

class _TimePickerButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final TimeOfDay? value;
  final VoidCallback onTap;

  const _TimePickerButton({
    required this.label,
    required this.icon,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
            border: Border.all(
                color: value != null
                    ? AppColors.primary
                    : Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8)),
        child: Column(children: [
          Icon(icon,
              size: 16,
              color: value != null ? AppColors.primary : Colors.grey),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 10, color: Colors.grey)),
          const SizedBox(height: 2),
          Text(
            value != null
                ? '${value!.hour.toString().padLeft(2, '0')}:${value!.minute.toString().padLeft(2, '0')}'
                : '—',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: value != null
                    ? AppColors.textPrimary
                    : Colors.grey),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Data class untuk stats
// ─────────────────────────────────────────────────────────
class _AttendanceStats {
  final int totalDays;
  final int hadirDays;
  final int notHadirDays;
  final int totalMinutes;
  final int avgMinutes;

  const _AttendanceStats({
    required this.totalDays,
    required this.hadirDays,
    required this.notHadirDays,
    required this.totalMinutes,
    required this.avgMinutes,
  });
}