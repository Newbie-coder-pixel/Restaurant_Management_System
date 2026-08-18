import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/models/staff_model.dart';
import '../../../core/theme/app_theme.dart';

// Local model for a shift
class StaffShift {
  final String? id;
  final String staffId;
  final int dayOfWeek; // 0=Monday ... 6=Sunday
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

  // shift duration in hours (for display)
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

class _StaffShiftScreenState extends State<StaffShiftScreen> with SingleTickerProviderStateMixin {
  static const _days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
  ];
  static const _dayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  // Common shift presets for restaurants
  static const _presets = [
    {'label': '🌅 Morning',   'start': '07:00', 'end': '15:00', 'icon': Icons.wb_sunny},
    {'label': '☀️ Midday',    'start': '11:00', 'end': '19:00', 'icon': Icons.sunny},
    {'label': '🌤️ Afternoon', 'start': '15:00', 'end': '23:00', 'icon': Icons.brightness_5},
    {'label': '🌙 Night',     'start': '18:00', 'end': '02:00', 'icon': Icons.nightlight_round},
    {'label': '⭐ Full',      'start': '09:00', 'end': '21:00', 'icon': Icons.star},
  ];

  // shifts[dayIndex] = list of StaffShift
  final Map<int, List<StaffShift>> _shifts = {};
  bool _isLoading = true;
  bool _isSaving = false;
  final Set<int> _dirtyDays = {};
  
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _load();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(parent: _animationController, curve: Curves.easeIn);
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
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
          SnackBar(content: Text('Failed to load shifts: $e'), backgroundColor: Colors.red));
      }
    }
  }

  int _toMinutes(String time) {
    final parts = time.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  // Check whether two shifts overlap, including overnight shifts (e.g. 22:00–02:00).
  // Overnight shifts (end < start) are normalized to end + 1440, then overlap is checked
  // across three scenarios: direct, shift2 shifted back, shift1 shifted back.
  bool _isOverlapping(String start1, String end1, String start2, String end2) {
    final s1 = _toMinutes(start1);
    var e1 = _toMinutes(end1);
    final s2 = _toMinutes(start2);
    var e2 = _toMinutes(end2);

    if (e1 <= s1) e1 += 1440;
    if (e2 <= s2) e2 += 1440;

    if (s1 < e2 && s2 < e1) return true;
    if (s1 < (e2 - 1440) && (s2 - 1440) < e1) return true;
    if ((s1 - 1440) < e2 && s2 < (e1 - 1440)) return true;

    return false;
  }

  Future<void> _addShiftDialog(int day) async {
    String startTime = '08:00';
    String endTime = '16:00';
    String? errorMsg;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.add_alarm, color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Add Shift — ${_days[day]}',
                    style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 18)),
              ),
            ],
          ),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Text('⚡ Quick Presets',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: _presets.map((p) => ActionChip(
                      avatar: Icon(p['icon'] as IconData, size: 16, color: AppColors.primary),
                      label: Text('${p['label']} (${p['start']}–${p['end']})',
                          style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w500)),
                      backgroundColor: AppColors.primary.withValues(alpha: 0.05),
                      onPressed: () => ss(() {
                        startTime = p['start']! as String;
                        endTime = p['end']! as String;
                      }),
                    )).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Text('🕐 Manual',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey)),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: _TimePickerTile(
                      label: 'Start',
                      value: startTime,
                      onChanged: (v) => ss(() => startTime = v),
                    )),
                    const SizedBox(width: 16),
                    Expanded(child: _TimePickerTile(
                      label: 'End',
                      value: endTime,
                      onChanged: (v) => ss(() => endTime = v),
                    )),
                  ]),
                ],
              ),
            ),
            if (errorMsg != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(errorMsg!,
                        style: TextStyle(color: Colors.red.shade700, fontSize: 12, fontFamily: 'Poppins'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(fontFamily: 'Poppins'))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () {
                if (startTime == endTime) {
                  ss(() => errorMsg = 'Start and end time cannot be the same.');
                  return;
                }
                final existing = _shifts[day] ?? [];
                final overlapping = existing.where((s) =>
                    _isOverlapping(startTime, endTime, s.startTime, s.endTime));
                if (overlapping.isNotEmpty) {
                  final conflict = overlapping.first;
                  ss(() => errorMsg =
                      'Conflicts with shift ${conflict.startTime}–${conflict.endTime}.');
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
              child: const Text('Add', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  void _removeShift(int day, StaffShift shift) {
    setState(() {
      _shifts[day]?.remove(shift);
      if (_shifts[day]?.isEmpty ?? false) _shifts.remove(day);
      _dirtyDays.add(day);
    });
  }

  Future<void> _saveAll() async {
    if (_dirtyDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No changes to save.'),
          backgroundColor: Colors.grey));
      return;
    }

    setState(() => _isSaving = true);

    final List<int> savedDays   = [];
    final List<int> failedDays  = [];

    for (final day in _dirtyDays.toList()) {
      try {
        await Supabase.instance.client
            .from('staff_shifts')
            .delete()
            .eq('staff_id', widget.staff.id)
            .eq('day_of_week', day);

        final shifts = _shifts[day] ?? [];
        if (shifts.isNotEmpty) {
          await Supabase.instance.client
              .from('staff_shifts')
              .insert(shifts.map((s) => s.toInsert()).toList());
        }

        savedDays.add(day);
      } catch (_) {
        failedDays.add(day);
      }
    }

    for (final day in savedDays) {
      _dirtyDays.remove(day);
    }

    await _load();

    if (mounted) {
      if (failedDays.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text('✅ Shift schedule saved successfully (${savedDays.length} day(s) updated)')),
              ],
            ),
            backgroundColor: const Color(0xFF4CAF50),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
      } else if (savedDays.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('❌ Failed to save all changes. Check your connection and try again.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4)));
      } else {
        const dayNames = [
          'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
        ];
        final failedNames = failedDays.map((d) => dayNames[d]).join(', ');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '⚠️ ${savedDays.length} day(s) saved successfully.\n'
                'Failed: $failedNames — please try saving again.'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5)));
      }
    }

    if (mounted) setState(() => _isSaving = false);
  }

  Future<void> _copyFromDayDialog(int targetDay) async {
    final sourceDays = List.generate(7, (i) => i)
        .where((d) => d != targetDay && (_shifts[d]?.isNotEmpty ?? false))
        .toList();

    if (sourceDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No other days have a shift schedule yet.'),
          backgroundColor: Colors.orange));
      return;
    }

    final selectedDay = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.copy, color: AppColors.primary, size: 24),
            ),
            const SizedBox(width: 12),
            const Text('Copy from day...',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 18)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: sourceDays.length,
            separatorBuilder: (_, __) => const Divider(height: 0),
            itemBuilder: (_, index) {
              final d = sourceDays[index];
              final shifts = _shifts[d]!;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  child: Text(_dayShort[d], style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                ),
                title: Text(_days[d], style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
                subtitle: Wrap(
                  spacing: 4,
                  children: shifts.map((s) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('${s.startTime}–${s.endTime}',
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 11)),
                  )).toList(),
                ),
                onTap: () => Navigator.pop(ctx, d),
              );
            },
          ),
        ),
      ),
    );

    if (selectedDay == null) return;
    final sourceShifts = _shifts[selectedDay]!;
    final targetExisting = _shifts[targetDay] ?? [];

    final nonOverlapping = sourceShifts.where((s) => !targetExisting.any(
        (e) => _isOverlapping(s.startTime, s.endTime, e.startTime, e.endTime))).toList();
    final skipped = sourceShifts.length - nonOverlapping.length;

    if (nonOverlapping.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('All shifts from that day conflict with existing shifts.'),
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
          content: Text('$skipped shift(s) skipped due to conflicts with the existing schedule.'),
          backgroundColor: Colors.orange));
    }
  }

  // ── slot classification (matches the Morning/Afternoon/Evening legend) ──
  static const int _slotMorning = 0;
  static const int _slotAfternoon = 1;
  static const int _slotEvening = 2;

  int _slotFor(StaffShift s) {
    final start = _toMinutes(s.startTime);
    if (start >= 6 * 60 && start < 14 * 60) return _slotMorning;
    if (start >= 14 * 60 && start < 22 * 60) return _slotAfternoon;
    return _slotEvening;
  }

  List<StaffShift> _shiftsInSlot(int day, int slot) =>
      (_shifts[day] ?? []).where((s) => _slotFor(s) == slot).toList();

  double get _totalWeeklyHours {
    double total = 0;
    for (final dayShifts in _shifts.values) {
      for (final s in dayShifts) {
        total += s.durationHours;
      }
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final totalHours = _totalWeeklyHours;
    final daysWorking = _shifts.values.where((d) => d.isNotEmpty).length;

    const slotColors = [AppColors.primary, AppColors.accent, AppColors.badgeDark];
    const slotLabels = ['Morning (06:00 - 14:00)', 'Afternoon (14:00 - 22:00)', 'Evening (22:00 - 06:00)'];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        title: Text('Shift Schedule — ${widget.staff.fullName}',
            style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        centerTitle: false,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.border),
        ),
        actions: [
          if (_dirtyDays.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Colors.orange,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('${_dirtyDays.length}',
                      style: const TextStyle(
                          fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600, color: Colors.orange)),
                ],
              )),
          _isSaving
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          color: AppColors.primary, strokeWidth: 2)))
              : Container(
                  margin: const EdgeInsets.only(right: 8),
                  child: ElevatedButton.icon(
                    onPressed: _saveAll,
                    icon: const Icon(Icons.save_outlined, color: Colors.white, size: 18),
                    label: const Text('Save',
                        style: TextStyle(
                            color: Colors.white, fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusSm)),
                    ),
                  ),
                ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Legend + weekly totals
                    Wrap(
                      spacing: 20, runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (int i = 0; i < slotLabels.length; i++)
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(width: 12, height: 12,
                                decoration: BoxDecoration(color: slotColors[i], borderRadius: BorderRadius.circular(3))),
                            const SizedBox(width: 6),
                            Text(slotLabels[i],
                                style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary)),
                          ]),
                        Text('$daysWorking active days · ${totalHours.toStringAsFixed(1)} hrs/week',
                            style: const TextStyle(
                                fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Grid
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      ),
                      child: Column(children: [
                        // header row
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.surfaceVariant,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusMd)),
                          ),
                          child: Row(children: [
                            const SizedBox(width: 96, child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              child: Text('DAY', style: AppTextStyles.label))),
                            for (int slot = 0; slot < 3; slot++)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  child: Text(['MORNING', 'AFTERNOON', 'EVENING'][slot], style: AppTextStyles.label),
                                ),
                              ),
                          ]),
                        ),
                        const Divider(height: 1, color: AppColors.border),
                        // day rows
                        for (int day = 0; day < 7; day++) ...[
                          if (day > 0) const Divider(height: 1, color: AppColors.border),
                          _ShiftDayRow(
                            dayShort: _dayShort[day],
                            dayFull: _days[day],
                            isToday: day == DateTime.now().weekday - 1,
                            isDirty: _dirtyDays.contains(day),
                            slotColors: slotColors,
                            slotShifts: [
                              _shiftsInSlot(day, _slotMorning),
                              _shiftsInSlot(day, _slotAfternoon),
                              _shiftsInSlot(day, _slotEvening),
                            ],
                            onAddToSlot: (_) => _addShiftDialog(day),
                            onRemove: (shift) => _removeShift(day, shift),
                            onCopy: () => _copyFromDayDialog(day),
                          ),
                        ],
                      ]),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// One day row of the Morning / Afternoon / Evening grid
// ─────────────────────────────────────────────────────────
class _ShiftDayRow extends StatelessWidget {
  final String dayShort;
  final String dayFull;
  final bool isToday;
  final bool isDirty;
  final List<Color> slotColors;
  final List<List<StaffShift>> slotShifts;
  final ValueChanged<int> onAddToSlot;
  final ValueChanged<StaffShift> onRemove;
  final VoidCallback onCopy;

  const _ShiftDayRow({
    required this.dayShort,
    required this.dayFull,
    required this.isToday,
    required this.isDirty,
    required this.slotColors,
    required this.slotShifts,
    required this.onAddToSlot,
    required this.onRemove,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final isEmpty = slotShifts.every((s) => s.isEmpty);

    return Container(
      color: isToday ? AppColors.primary.withValues(alpha: 0.04) : null,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 96,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(dayShort,
                          style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700,
                              color: isToday ? AppColors.primary : AppColors.textPrimary)),
                      if (isDirty) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.fiber_manual_record, size: 8, color: Colors.orange),
                      ],
                    ]),
                    if (isEmpty)
                      const Text('Closed',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textHint)),
                    const Spacer(),
                    InkWell(
                      onTap: onCopy,
                      child: const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Icon(Icons.copy_outlined, size: 14, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            for (int slot = 0; slot < 3; slot++)
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    border: Border(left: BorderSide(color: AppColors.border)),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: slotShifts[slot].isEmpty
                      ? InkWell(
                          onTap: () => onAddToSlot(slot),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: const Icon(Icons.add, size: 18, color: AppColors.textHint),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 6, runSpacing: 6,
                              children: [
                                ...slotShifts[slot].map((shift) => Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: slotColors[slot].withValues(alpha: 0.4)),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                                        Text('${shift.startTime}-${shift.endTime}',
                                            style: TextStyle(
                                                fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w600,
                                                color: slotColors[slot])),
                                        const SizedBox(width: 4),
                                        InkWell(
                                          onTap: () => onRemove(shift),
                                          child: Icon(Icons.close, size: 12, color: slotColors[slot]),
                                        ),
                                      ]),
                                    )),
                                InkWell(
                                  onTap: () => onAddToSlot(slot),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    child: const Icon(Icons.add, size: 14, color: AppColors.textHint),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Helper widget: time picker tile
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
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade300, width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(children: [
          Text(label,
              style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Icon(Icons.access_time, size: 14, color: Colors.grey.shade600),
        ]),
      ),
    );
  }
}