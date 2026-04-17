import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/models/staff_model.dart';
import '../../../core/models/staff_role.dart';
import '../../../core/theme/app_theme.dart';

// Model lokal untuk shift
class StaffShift {
  final String? id;
  final String staffId;
  final int dayOfWeek; // 0=Senin ... 6=Minggu
  final String startTime; // format "HH:mm"
  final String endTime;

  StaffShift({
    this.id,
    required this.staffId,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
  });

  factory StaffShift.fromJson(Map<String, dynamic> j) => StaffShift(
        id: j['id'] as String?,
        staffId: j['staff_id'] as String,
        dayOfWeek: j['day_of_week'] as int,
        startTime: j['start_time'] as String,
        endTime: j['end_time'] as String,
      );

  Map<String, dynamic> toInsert() => {
        'staff_id': staffId,
        'day_of_week': dayOfWeek,
        'start_time': startTime,
        'end_time': endTime,
      };

  // durasi shift dalam jam (untuk display)
  double get durationHours {
    final s = startTime.split(':');
    final e = endTime.split(':');
    final startMin = int.parse(s[0]) * 60 + int.parse(s[1]);
    final endMin = int.parse(e[0]) * 60 + int.parse(e[1]);
    final diff = endMin > startMin ? endMin - startMin : (24 * 60 - startMin + endMin);
    return diff / 60;
  }
}

class StaffShiftScreen extends StatefulWidget {
  final StaffMember staff;
  const StaffShiftScreen({super.key, required this.staff});

  @override
  State<StaffShiftScreen> createState() => _StaffShiftScreenState();
}

class _StaffShiftScreenState extends State<StaffShiftScreen> {
  static const _days = [
    'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'
  ];
  static const _dayShort = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

  // Preset shift umum untuk restoran
  static const _presets = [
    {'label': 'Pagi',  'start': '07:00', 'end': '15:00'},
    {'label': 'Siang', 'start': '11:00', 'end': '19:00'},
    {'label': 'Sore',  'start': '15:00', 'end': '23:00'},
    {'label': 'Malam', 'start': '18:00', 'end': '02:00'},
    {'label': 'Full',  'start': '09:00', 'end': '21:00'},
  ];

  // shifts[dayIndex] = list of StaffShift
  final Map<int, List<StaffShift>> _shifts = {};
  bool _isLoading = true;
  bool _isSaving = false;

  // track perubahan belum disimpan
  final Set<int> _dirtyDays = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final res = await Supabase.instance.client
          .from('staff_shifts')
          .select()
          .eq('staff_id', widget.staff.id)
          .order('day_of_week')
          .order('start_time');

      final map = <int, List<StaffShift>>{};
      for (final row in (res as List)) {
        final shift = StaffShift.fromJson(row as Map<String, dynamic>);
        map.putIfAbsent(shift.dayOfWeek, () => []).add(shift);
      }
      if (mounted) setState(() { _shifts.clear(); _shifts.addAll(map); _isLoading = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat shift: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // ── helper: konversi "HH:mm" ke menit dari tengah malam ─
  int _toMinutes(String time) {
    final parts = time.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  // ── helper: cek apakah dua shift overlap (support overnight) ─
  // Overnight shift: endTime < startTime (misal 22:00 – 02:00)
  bool _isOverlapping(String start1, String end1, String start2, String end2) {
    final s1 = _toMinutes(start1);
    final e1 = _toMinutes(end1);
    final s2 = _toMinutes(start2);
    final e2 = _toMinutes(end2);

    // Normalisasi ke range [start, end) — overnight dikonversi ke end + 1440
    final e1Norm = e1 <= s1 ? e1 + 1440 : e1; // overnight shift 1
    final e2Norm = e2 <= s2 ? e2 + 1440 : e2; // overnight shift 2

    // Cek overlap dengan mengecek kedua arah (shift 2 bisa mulai sebelum tengah malam)
    // Cek normal
    final overlap1 = s1 < e2Norm && s2 < e1Norm;
    // Cek shift 2 yang mungkin overnight (geser s2 +1440 untuk cek wraparound)
    final overlap2 = s1 < (e2Norm - 1440 + 1440) && (s2 + 1440) < e1Norm;

    return overlap1 || (e2 <= s2 && overlap2);
  }

  // ── tambah shift di hari tertentu ─────────────────────
  Future<void> _addShiftDialog(int day) async {
    String startTime = '08:00';
    String endTime = '16:00';
    String? errorMsg;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Tambah Shift — ${_days[day]}',
              style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            // Preset buttons
            const Text('Preset cepat:',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8, runSpacing: 6,
              children: _presets.map((p) => ActionChip(
                label: Text('${p['label']} (${p['start']}–${p['end']})',
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 11)),
                onPressed: () => ss(() {
                  startTime = p['start']!;
                  endTime = p['end']!;
                }),
              )).toList(),
            ),
            const Divider(height: 24),
            // Manual time picker
            Row(children: [
              Expanded(child: _TimePickerTile(
                label: 'Mulai',
                value: startTime,
                onChanged: (v) => ss(() => startTime = v),
              )),
              const SizedBox(width: 16),
              Expanded(child: _TimePickerTile(
                label: 'Selesai',
                value: endTime,
                onChanged: (v) => ss(() => endTime = v),
              )),
            ]),
            if (errorMsg != null) ...[
              const SizedBox(height: 8),
              Text(errorMsg!, style: const TextStyle(color: Colors.red, fontSize: 12, fontFamily: 'Poppins')),
            ],
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Batal')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              onPressed: () {
                // Validasi 1: start == end tidak boleh
                if (startTime == endTime) {
                  ss(() => errorMsg = 'Jam mulai dan selesai tidak boleh sama.');
                  return;
                }
                // Validasi 2: cek overlap dengan shift yang sudah ada di hari ini
                final existing = _shifts[day] ?? [];
                final overlapping = existing.where((s) =>
                    _isOverlapping(startTime, endTime, s.startTime, s.endTime));
                if (overlapping.isNotEmpty) {
                  final conflict = overlapping.first;
                  ss(() => errorMsg =
                      'Bertabrakan dengan shift ${conflict.startTime}–${conflict.endTime}.');
                  return;
                }
                Navigator.pop(ctx);
                setState(() {
                  _shifts.putIfAbsent(day, () => []).add(StaffShift(
                    staffId: widget.staff.id,
                    dayOfWeek: day,
                    startTime: startTime,
                    endTime: endTime,
                  ));
                  _dirtyDays.add(day);
                });
              },
              child: const Text('Tambah', style: TextStyle(fontFamily: 'Poppins')),
            ),
          ],
        ),
      ),
    );
  }

  // ── hapus shift ────────────────────────────────────────
  void _removeShift(int day, StaffShift shift) {
    setState(() {
      _shifts[day]?.remove(shift);
      if (_shifts[day]?.isEmpty ?? false) _shifts.remove(day);
      _dirtyDays.add(day);
    });
  }

  // ── simpan semua perubahan ke Supabase ─────────────────
  Future<void> _saveAll() async {
    if (_dirtyDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Tidak ada perubahan untuk disimpan.'),
          backgroundColor: Colors.grey));
      return;
    }

    setState(() => _isSaving = true);

    final List<int> savedDays   = [];
    final List<int> failedDays  = [];

    for (final day in _dirtyDays.toList()) {
      try {
        // 1. Hapus shift lama di hari ini
        await Supabase.instance.client
            .from('staff_shifts')
            .delete()
            .eq('staff_id', widget.staff.id)
            .eq('day_of_week', day);

        // 2. Insert shift baru (kalau ada)
        final shifts = _shifts[day] ?? [];
        if (shifts.isNotEmpty) {
          await Supabase.instance.client
              .from('staff_shifts')
              .insert(shifts.map((s) => s.toInsert()).toList());
        }

        savedDays.add(day);
      } catch (_) {
        // Hari ini gagal — tandai tapi lanjut ke hari berikutnya
        failedDays.add(day);
      }
    }

    // Hapus hanya hari yang berhasil dari _dirtyDays
    for (final day in savedDays) {
      _dirtyDays.remove(day);
    }

    // Reload supaya ID dari DB masuk ke state
    await _load();

    if (mounted) {
      if (failedDays.isEmpty) {
        // Semua berhasil
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '✅ Jadwal shift berhasil disimpan (${savedDays.length} hari diperbarui)'),
            backgroundColor: const Color(0xFF4CAF50)));
      } else if (savedDays.isEmpty) {
        // Semua gagal
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                '❌ Gagal menyimpan semua perubahan. Cek koneksi dan coba lagi.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4)));
      } else {
        // Sebagian berhasil, sebagian gagal
        const dayNames = [
          'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'
        ];
        final failedNames = failedDays.map((d) => dayNames[d]).join(', ');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '⚠️ ${savedDays.length} hari berhasil disimpan.\n'
                'Gagal: $failedNames — coba simpan ulang.'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5)));
      }
    }

    if (mounted) setState(() => _isSaving = false);
  }

  // ── copy shift dari hari lain ──────────────────────────
  Future<void> _copyFromDayDialog(int targetDay) async {
    final sourceDays = List.generate(7, (i) => i)
        .where((d) => d != targetDay && (_shifts[d]?.isNotEmpty ?? false))
        .toList();

    if (sourceDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Belum ada hari lain yang punya jadwal shift.'),
          backgroundColor: Colors.orange));
      return;
    }

    final selectedDay = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Copy dari hari...',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: sourceDays.map((d) {
            final shifts = _shifts[d]!;
            return ListTile(
              title: Text(_days[d], style: const TextStyle(fontFamily: 'Poppins')),
              subtitle: Text(
                  shifts.map((s) => '${s.startTime}–${s.endTime}').join(', '),
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 12)),
              onTap: () => Navigator.pop(ctx, d),
            );
          }).toList(),
        ),
      ),
    );

    if (selectedDay == null) return;
    final sourceShifts = _shifts[selectedDay]!;
    final targetExisting = _shifts[targetDay] ?? [];

    // Filter hanya shift yang tidak overlap dengan yang sudah ada di hari target
    final nonOverlapping = sourceShifts.where((s) => !targetExisting.any(
        (e) => _isOverlapping(s.startTime, s.endTime, e.startTime, e.endTime))).toList();
    final skipped = sourceShifts.length - nonOverlapping.length;

    if (nonOverlapping.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Semua shift dari hari itu bertabrakan dengan shift yang sudah ada.'),
            backgroundColor: Colors.orange));
      }
      return;
    }

    setState(() {
      _shifts.putIfAbsent(targetDay, () => []).addAll(nonOverlapping.map((s) => StaffShift(
        staffId: widget.staff.id,
        dayOfWeek: targetDay,
        startTime: s.startTime,
        endTime: s.endTime,
      )));
      _dirtyDays.add(targetDay);
    });

    if (mounted && skipped > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$skipped shift dilewati karena bertabrakan dengan jadwal yang ada.'),
          backgroundColor: Colors.orange));
    }
  }

  // ── hitung total jam per minggu ────────────────────────
  double get _totalWeeklyHours {
    double total = 0;
    for (final dayShifts in _shifts.values) {
      for (final s in dayShifts) {
        total += s.durationHours;
      }
    }
    return total;
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

  @override
  Widget build(BuildContext context) {
    final roleColor = _roleColor(widget.staff.role);
    final totalHours = _totalWeeklyHours;
    final daysWorking = _shifts.values.where((d) => d.isNotEmpty).length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Jadwal Shift — ${widget.staff.fullName}',
            style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w600)),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          if (_dirtyDays.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange, borderRadius: BorderRadius.circular(10)),
              child: Text('${_dirtyDays.length} belum disimpan',
                  style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 11, color: Colors.white))),
          _isSaving
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2)))
              : TextButton.icon(
                  onPressed: _saveAll,
                  icon: const Icon(Icons.save_outlined, color: Colors.white, size: 18),
                  label: const Text('Simpan',
                      style: TextStyle(
                          color: Colors.white, fontFamily: 'Poppins', fontSize: 13))),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              // Staff header card
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 8, offset: const Offset(0, 2))
                  ],
                ),
                child: Row(children: [
                  CircleAvatar(
                      radius: 24,
                      backgroundColor: roleColor.withValues(alpha: 0.15),
                      child: Text(widget.staff.fullName[0].toUpperCase(),
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w700,
                              fontSize: 20,
                              color: roleColor))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(widget.staff.fullName,
                          style: const TextStyle(
                              fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
                      Text(widget.staff.role.displayName,
                          style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 12, color: roleColor)),
                    ]),
                  ),
                  // stats
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('$daysWorking hari/minggu',
                        style: const TextStyle(
                            fontFamily: 'Poppins', fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    Text('${totalHours.toStringAsFixed(1)} jam total',
                        style: const TextStyle(
                            fontFamily: 'Poppins', fontSize: 11,
                            color: AppColors.textSecondary)),
                  ]),
                ]),
              ),

              // Weekly grid
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                  itemCount: 7,
                  itemBuilder: (_, day) {
                    final dayShifts = _shifts[day] ?? [];
                    final isToday = day == DateTime.now().weekday - 1;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: isToday
                            ? Border.all(color: AppColors.primary, width: 1.5)
                            : null,
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 6, offset: const Offset(0, 2))
                        ],
                      ),
                      child: Column(children: [
                        // day header
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          child: Row(children: [
                            // hari badge
                            Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(
                                color: isToday
                                    ? AppColors.primary
                                    : dayShifts.isNotEmpty
                                        ? AppColors.primary.withValues(alpha: 0.1)
                                        : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(_dayShort[day],
                                      style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: isToday
                                              ? Colors.white
                                              : dayShifts.isNotEmpty
                                                  ? AppColors.primary
                                                  : Colors.grey)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_days[day],
                                      style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontWeight: FontWeight.w600,
                                          color: isToday
                                              ? AppColors.primary
                                              : AppColors.textPrimary)),
                                  if (dayShifts.isNotEmpty)
                                    Text(
                                      '${dayShifts.length} shift · '
                                      '${dayShifts.fold(0.0, (s, sh) => s + sh.durationHours).toStringAsFixed(1)} jam',
                                      style: const TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: 11,
                                          color: AppColors.textSecondary))
                                  else
                                    const Text('Libur',
                                        style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 11,
                                            color: AppColors.textHint)),
                                ],
                              ),
                            ),
                            // action buttons
                            if (_dirtyDays.contains(day))
                              const Padding(
                                padding: EdgeInsets.only(right: 4),
                                child: Icon(Icons.circle, size: 8, color: Colors.orange)),
                            // copy dari hari lain
                            IconButton(
                              icon: const Icon(Icons.copy_outlined,
                                  size: 18, color: AppColors.textSecondary),
                              tooltip: 'Copy dari hari lain',
                              onPressed: () => _copyFromDayDialog(day),
                            ),
                            // tambah shift
                            IconButton(
                              icon: Icon(Icons.add_circle_outline,
                                  size: 20,
                                  color: dayShifts.isNotEmpty
                                      ? AppColors.primary
                                      : Colors.grey),
                              tooltip: 'Tambah shift',
                              onPressed: () => _addShiftDialog(day),
                            ),
                          ]),
                        ),
                        // shift chips
                        if (dayShifts.isNotEmpty) ...[
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            child: Wrap(
                              spacing: 8, runSpacing: 6,
                              children: dayShifts.map((shift) {
                                return Chip(
                                  label: Text(
                                      '${shift.startTime} – ${shift.endTime}',
                                      style: const TextStyle(
                                          fontFamily: 'Poppins', fontSize: 12)),
                                  backgroundColor:
                                      AppColors.primary.withValues(alpha: 0.08),
                                  deleteIcon: const Icon(Icons.close, size: 14),
                                  deleteIconColor: Colors.red,
                                  onDeleted: () => _removeShift(day, shift),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ]),
                    );
                  },
                ),
              ),
            ]),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Helper widget: time picker tile
// ─────────────────────────────────────────────────────────
class _TimePickerTile extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  const _TimePickerTile({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final parts = value.split(':');
        final initial = TimeOfDay(
            hour: int.parse(parts[0]), minute: int.parse(parts[1]));
        final picked = await showTimePicker(
            context: context, initialTime: initial);
        if (picked != null) {
          onChanged(
              '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(children: [
          Text(label,
              style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 16)),
          const SizedBox(height: 2),
          const Icon(Icons.access_time, size: 14, color: Colors.grey),
        ]),
      ),
    );
  }
}