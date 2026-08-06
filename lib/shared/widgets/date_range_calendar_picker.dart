// lib/shared/widgets/date_range_calendar_picker.dart
//
// A "Date is in between X → Y" range picker styled after common admin-panel
// filter UIs: two editable date fields at the top, and two side-by-side
// month calendars below with a single pair of prev/next arrows that shift
// both months together. Selecting a day sets the range start; the next tap
// sets the end (swapping if picked before the start).

import 'package:flutter/material.dart';

const _navy = Color(0xFF1A1A2E);
const _rangeBg = Color(0xFFE8EAF6);

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const _weekdayLabels = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

String _formatDate(DateTime d) => '${_monthNames[d.month - 1].substring(0, 3)} ${d.day}, ${d.year}';

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Parses "MMM d, yyyy" (e.g. "May 25, 2023"); returns null on any mismatch.
DateTime? _parseDate(String text) {
  final m = RegExp(r'^([A-Za-z]{3,})\s+(\d{1,2}),?\s+(\d{4})$').firstMatch(text.trim());
  if (m == null) return null;
  final monthName = m.group(1)!.toLowerCase();
  final monthIndex = _monthNames.indexWhere((n) => n.toLowerCase().startsWith(monthName.substring(0, 3)));
  if (monthIndex == -1) return null;
  final day = int.tryParse(m.group(2)!);
  final year = int.tryParse(m.group(3)!);
  if (day == null || year == null || day < 1 || day > 31) return null;
  return DateTime(year, monthIndex + 1, day);
}

class DateRangeCalendarPicker {
  /// Shows the picker as a centered dialog and resolves to the chosen range,
  /// or null if the user cancelled without applying.
  static Future<DateTimeRange?> show(
    BuildContext context, {
    DateTime? initialStart,
    DateTime? initialEnd,
    DateTime? firstDate,
    DateTime? lastDate,
  }) {
    return showDialog<DateTimeRange>(
      context: context,
      builder: (_) => _DateRangeDialog(
        initialStart: initialStart,
        initialEnd: initialEnd,
        firstDate: firstDate ?? DateTime(DateTime.now().year - 5),
        lastDate: lastDate ?? DateTime.now(),
      ),
    );
  }
}

class _DateRangeDialog extends StatefulWidget {
  final DateTime? initialStart;
  final DateTime? initialEnd;
  final DateTime firstDate;
  final DateTime lastDate;

  const _DateRangeDialog({
    this.initialStart,
    this.initialEnd,
    required this.firstDate,
    required this.lastDate,
  });

  @override
  State<_DateRangeDialog> createState() => _DateRangeDialogState();
}

class _DateRangeDialogState extends State<_DateRangeDialog> {
  DateTime? _start;
  DateTime? _end;
  late DateTime _baseMonth;
  late final TextEditingController _startCtrl;
  late final TextEditingController _endCtrl;

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end = widget.initialEnd;
    final anchor = _start ?? widget.lastDate;
    _baseMonth = DateTime(anchor.year, anchor.month, 1);
    _startCtrl = TextEditingController(text: _start != null ? _formatDate(_start!) : '');
    _endCtrl = TextEditingController(text: _end != null ? _formatDate(_end!) : '');
  }

  @override
  void dispose() {
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  void _selectDay(DateTime day) {
    setState(() {
      if (_start == null || (_start != null && _end != null)) {
        _start = day;
        _end = null;
      } else if (day.isBefore(_start!)) {
        _end = _start;
        _start = day;
      } else {
        _end = day;
      }
      _startCtrl.text = _start != null ? _formatDate(_start!) : '';
      _endCtrl.text = _end != null ? _formatDate(_end!) : '';
    });
  }

  void _submitStartField(String text) {
    final parsed = _parseDate(text);
    if (parsed == null) return;
    setState(() {
      _start = parsed;
      if (_end != null && _end!.isBefore(_start!)) _end = null;
      _baseMonth = DateTime(parsed.year, parsed.month, 1);
    });
  }

  void _submitEndField(String text) {
    final parsed = _parseDate(text);
    if (parsed == null) return;
    setState(() {
      if (_start != null && parsed.isBefore(_start!)) {
        _end = _start;
        _start = parsed;
      } else {
        _end = parsed;
      }
    });
  }

  void _clear() {
    setState(() {
      _start = null;
      _end = null;
      _startCtrl.clear();
      _endCtrl.clear();
    });
  }

  void _shiftMonth(int delta) {
    setState(() => _baseMonth = DateTime(_baseMonth.year, _baseMonth.month + delta, 1));
  }

  @override
  Widget build(BuildContext context) {
    final rightMonth = DateTime(_baseMonth.year, _baseMonth.month + 1, 1);

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Date is in between',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Editable start/end fields
              Row(
                children: [
                  Expanded(child: _dateField(_startCtrl, 'Start date', _submitStartField, allowClear: true)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.grey),
                  ),
                  Expanded(child: _dateField(_endCtrl, 'End date', _submitEndField, allowClear: false)),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // Two-month calendar row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _monthCalendar(
                      _baseMonth,
                      showPrev: true,
                      showNext: false,
                      onPrev: () => _shiftMonth(-1),
                      onNext: null,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: _monthCalendar(
                      rightMonth,
                      showPrev: false,
                      showNext: true,
                      onPrev: null,
                      onNext: () => _shiftMonth(1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: _clear,
                    child: const Text(
                      'Clear',
                      style: TextStyle(fontFamily: 'Poppins', color: Colors.red),
                    ),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel', style: TextStyle(fontFamily: 'Poppins')),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: (_start != null && _end != null)
                            ? () => Navigator.pop(context, DateTimeRange(start: _start!, end: _end!))
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _navy,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Apply', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dateField(TextEditingController ctrl, String hint, ValueChanged<String> onSubmit, {required bool allowClear}) {
    return TextField(
      controller: ctrl,
      onSubmitted: onSubmit,
      style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        suffixIcon: allowClear && ctrl.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close_rounded, size: 16),
                onPressed: _clear,
                visualDensity: VisualDensity.compact,
              )
            : null,
      ),
    );
  }

  Widget _monthCalendar(
    DateTime month, {
    required bool showPrev,
    required bool showNext,
    required VoidCallback? onPrev,
    required VoidCallback? onNext,
  }) {
    final firstOfMonth = DateTime(month.year, month.month, 1);
    final leading = (firstOfMonth.weekday - DateTime.monday) % 7;
    final gridStart = firstOfMonth.subtract(Duration(days: leading));
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final totalCells = leading + daysInMonth;
    final rows = (totalCells / 7).ceil();
    final cells = List.generate(rows * 7, (i) => gridStart.add(Duration(days: i)));

    return Column(
      children: [
        Row(
          children: [
            SizedBox(
              width: 28,
              child: showPrev
                  ? IconButton(
                      icon: const Icon(Icons.chevron_left_rounded, size: 18),
                      onPressed: onPrev,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    )
                  : null,
            ),
            Expanded(
              child: Text(
                '${_monthNames[month.month - 1]} ${month.year}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            SizedBox(
              width: 28,
              child: showNext
                  ? IconButton(
                      icon: const Icon(Icons.chevron_right_rounded, size: 18),
                      onPressed: onNext,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    )
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: _weekdayLabels
              .map((w) => Expanded(
                    child: Text(
                      w,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: Colors.grey[500], fontWeight: FontWeight.w600),
                    ),
                  ))
              .toList(),
        ),
        for (int r = 0; r < rows; r++)
          Row(
            children: List.generate(7, (c) => Expanded(child: _dayCell(cells[r * 7 + c], month, c))),
          ),
      ],
    );
  }

  Widget _dayCell(DateTime day, DateTime displayedMonth, int col) {
    final inMonth = day.month == displayedMonth.month;
    final inRange = day.isAfter(widget.firstDate.subtract(const Duration(days: 1))) &&
        day.isBefore(widget.lastDate.add(const Duration(days: 1)));
    final isStart = _start != null && _sameDay(day, _start!);
    final isEnd = _end != null && _sameDay(day, _end!);
    final isBetween = _start != null && _end != null && day.isAfter(_start!) && day.isBefore(_end!);

    final highlighted = isStart || isEnd || isBetween;
    final isRowEdgeStart = col == 0 || isStart;
    final isRowEdgeEnd = col == 6 || isEnd;

    final enabled = inMonth && inRange;

    return GestureDetector(
      onTap: enabled ? () => _selectDay(day) : null,
      child: Container(
        height: 32,
        margin: const EdgeInsets.symmetric(vertical: 1),
        decoration: BoxDecoration(
          color: highlighted && !isStart && !isEnd ? _rangeBg : null,
          borderRadius: highlighted
              ? BorderRadius.only(
                  topLeft: isRowEdgeStart ? const Radius.circular(16) : Radius.zero,
                  bottomLeft: isRowEdgeStart ? const Radius.circular(16) : Radius.zero,
                  topRight: isRowEdgeEnd ? const Radius.circular(16) : Radius.zero,
                  bottomRight: isRowEdgeEnd ? const Radius.circular(16) : Radius.zero,
                )
              : null,
        ),
        alignment: Alignment.center,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: (isStart || isEnd) ? _navy : null,
          ),
          alignment: Alignment.center,
          child: Text(
            '${day.day}',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              fontWeight: (isStart || isEnd) ? FontWeight.w700 : FontWeight.w400,
              color: (isStart || isEnd)
                  ? Colors.white
                  : !enabled
                      ? Colors.grey[300]
                      : !inMonth
                          ? Colors.grey[400]
                          : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}
