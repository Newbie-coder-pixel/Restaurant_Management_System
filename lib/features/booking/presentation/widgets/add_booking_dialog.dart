import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math';
import '../../../../core/theme/app_theme.dart';

class AddBookingDialog extends StatefulWidget {
  final String branchId;
  const AddBookingDialog({super.key, required this.branchId});

  @override
  State<AddBookingDialog> createState() => _AddBookingDialogState();
}

class _AddBookingDialogState extends State<AddBookingDialog> {
  final _nameCtrl    = TextEditingController();
  final _phoneCtrl   = TextEditingController();
  final _emailCtrl   = TextEditingController();
  final _allergyCtrl = TextEditingController();
  final _notesCtrl   = TextEditingController();

  int _guests = 2;
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _time = const TimeOfDay(hour: 19, minute: 0);

  bool _isSearching = false;
  int _duration = 120; // default 2 hours
  Map<String, dynamic>? _assignedTable;
  String? _assignError;
  String? _confirmationCode; // generated once a table is successfully found

  // ── Validate that the booking time is at least 2 hours from now ──
  String? _validateBookingTime() {
    final bookingDateTime = DateTime(
      _date.year, _date.month, _date.day,
      _time.hour, _time.minute,
    );
    final minAllowed = DateTime.now().add(const Duration(hours: 2));
    if (bookingDateTime.isBefore(minAllowed)) {
      return 'Bookings must be made at least 2 hours before arrival.\nPlease choose a time no earlier than ${_formatDateDisplay(minAllowed)} ${minAllowed.hour.toString().padLeft(2, '0')}:${minAllowed.minute.toString().padLeft(2, '0')}.';
    }
    return null;
  }

  Future<void> _findAvailableTable() async {
    // Validate the time first before searching for a table
    final timeError = _validateBookingTime();
    if (timeError != null) {
      setState(() {
        _assignError = timeError;
        _assignedTable = null;
      });
      return;
    }

    setState(() {
      _isSearching     = true;
      _assignedTable   = null;
      _assignError     = null;
      _confirmationCode = null;
    });

    try {
      final dateStr = _formatDate(_date);

      // ── Check whether this date is a restaurant closure day ──
      final closureRes = await Supabase.instance.client
          .from('restaurant_closures')
          .select('reason')
          .eq('branch_id', widget.branchId)
          .eq('closure_date', dateStr)
          .maybeSingle();

      if (closureRes != null) {
        final reason = closureRes['reason'] as String?;
        setState(() {
          _assignError = reason != null && reason.isNotEmpty
              ? '🚫 The restaurant is closed on this date.\nReason: $reason\n\nPlease choose another date.'
              : '🚫 The restaurant is closed on this date.\nPlease choose another date.';
          _isSearching = false;
        });
        return;
      }

      final tables = await Supabase.instance.client
          .from('restaurant_tables')
          .select()
          .eq('branch_id', widget.branchId)
          .gte('capacity', _guests)
          .eq('status', 'available')
          .order('capacity');

      if ((tables as List).isEmpty) {
        setState(() {
          _assignError = 'No table available for $_guests guests';
          _isSearching = false;
        });
        return;
      }

      // Get all active bookings on the same date, then filter by duration overlap
      final existingBookings = await Supabase.instance.client
          .from('bookings')
          .select('table_id, booking_time, duration_minutes')
          .eq('branch_id', widget.branchId)
          .eq('booking_date', dateStr)
          .inFilter('status', ['pending', 'confirmed', 'seated']);

      // Compute the new booking interval: [newStart, newEnd) in minutes
      final newStart = _time.hour * 60 + _time.minute;
      final newEnd = newStart + _duration;

      final bookedTableIds = (existingBookings as List).where((b) {
        final rawTime    = b['booking_time'] as String? ?? '00:00:00';
        final parts      = rawTime.split(':');
        final existStart = int.parse(parts[0]) * 60 + int.parse(parts[1]);
        final existDur   = (b['duration_minutes'] as int?) ?? 120;
        final existEnd   = existStart + existDur;
        // Overlaps if the two intervals intersect
        return newStart < existEnd && newEnd > existStart;
      }).map((b) => b['table_id'] as String?).where((id) => id != null).toSet();

      final available = tables
          .where((t) => !bookedTableIds.contains(t['id']))
          .toList();

      if (available.isEmpty) {
        setState(() {
          _assignError =
              'All tables for $_guests guests are fully booked at that time.\nTry a different time.';
          _isSearching = false;
        });
        return;
      }

      setState(() {
        _assignedTable = available.first;
        _confirmationCode = _generateConfirmationCode();
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _assignError = 'Error: $e';
        _isSearching = false;
      });
    }
  }

  String _generateConfirmationCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // avoid 0/O, 1/I to prevent ambiguity
    final rng = Random();
    final suffix = List.generate(4, (_) => chars[rng.nextInt(chars.length)]).join();
    final d = _date;
    final dateTag =
        '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
    return 'BK-$dateTag-$suffix';
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  String _formatDateDisplay(DateTime d) =>
      '${d.day}/${d.month}/${d.year}';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _allergyCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // ── Header ─────────────────────────────────
            Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.event_available,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('New Reservation',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 18)),
                Text('A table will be assigned automatically',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: Color(0xFF6B7280))),
              ]),
            ]),
            const SizedBox(height: 20),

            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Name ─────────────────────────────────
                    TextField(
                      controller: _nameCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                          labelText: 'Guest Name *',
                          prefixIcon: Icon(Icons.person_outline)),
                    ),
                    const SizedBox(height: 12),

                    // ── Phone Number ─────────────────────────
                    TextField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                          labelText: 'Phone Number',
                          prefixIcon: Icon(Icons.phone_outlined)),
                    ),
                    const SizedBox(height: 12),

                    // ── Email ────────────────────────────────
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined)),
                    ),
                    const SizedBox(height: 16),

                    // ── Guest Count ───────────────────────────
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: const Color(0xFFF8F9FA),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE8EAED))),
                      child: Row(children: [
                        const Icon(Icons.people_outline,
                            color: AppColors.primary, size: 20),
                        const SizedBox(width: 8),
                        const Flexible(
                          child: Text('Guest Count',
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis),
                        ),
                        const Spacer(),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.remove_circle_outline, size: 26),
                          color: AppColors.accent,
                          onPressed: () {
                            if (_guests > 1) {
                              setState(() {
                                _guests--;
                                _assignedTable = null;
                                _assignError = null;
                              });
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        Text('$_guests',
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w700,
                                fontSize: 22,
                                color: AppColors.primary)),
                        const SizedBox(width: 8),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.add_circle_outline, size: 26),
                          color: const Color(0xFF4CAF50),
                          onPressed: () => setState(() {
                            _guests++;
                            _assignedTable = null;
                            _assignError = null;
                          }),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 12),

                    // ── Date & Time ───────────────────────────
                    Row(children: [
                      Expanded(child: _dateTile()),
                      const SizedBox(width: 8),
                      Expanded(child: _timeTile()),
                    ]),
                    const SizedBox(height: 8),

                    // ── Duration ──────────────────────────────
                    DropdownButtonFormField<int>(
                      initialValue: _duration,
                      decoration: const InputDecoration(
                          labelText: 'Duration',
                          prefixIcon: Icon(Icons.timer_outlined)),
                      items: const [
                        DropdownMenuItem(value: 60,  child: Text('1 hour (60 min)',   style: TextStyle(fontFamily: 'Poppins'))),
                        DropdownMenuItem(value: 90,  child: Text('1.5 hours (90 min)', style: TextStyle(fontFamily: 'Poppins'))),
                        DropdownMenuItem(value: 120, child: Text('2 hours (120 min)',  style: TextStyle(fontFamily: 'Poppins'))),
                        DropdownMenuItem(value: 180, child: Text('3 hours (180 min)',  style: TextStyle(fontFamily: 'Poppins'))),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() {
                            _duration = v;
                            _assignedTable = null;
                            _assignError = null;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 8),

                    // ── Info cancellation rule ───────────────
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                          color: const Color(0xFFE3F2FD),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: const Color(0xFF1976D2)
                                  .withValues(alpha: 0.3))),
                      child: const Row(children: [
                        Icon(Icons.info_outline,
                            size: 14, color: Color(0xFF1976D2)),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Bookings must be made at least 2 hours before arrival. Cancellations < 2 hours are subject to a fee.',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11,
                                color: Color(0xFF1565C0)),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 16),

                    // ── Find table button ────────────────────
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _nameCtrl.text.trim().isEmpty
                            ? null
                            : _findAvailableTable,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12))),
                        icon: _isSearching
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.search, size: 18),
                        label: Text(
                          _isSearching
                              ? 'Searching for a table...'
                              : 'Check & Auto-Assign Table',
                          style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Auto-assign result ────────────────────
                    if (_assignedTable != null)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: const Color(0xFF4CAF50))),
                        child: Row(children: [
                          const Icon(Icons.check_circle,
                              color: Color(0xFF4CAF50), size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Table ${_assignedTable!['table_number']} — Capacity ${_assignedTable!['capacity']} guests',
                                  style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF2E7D32)),
                                ),
                                Text(
                                  'Shape: ${_assignedTable!['shape']} • Floor ${_assignedTable!['floor_level']}',
                                  style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 12,
                                      color: Color(0xFF4CAF50)),
                                ),
                                if (_confirmationCode != null) ...[
                                  const SizedBox(height: 6),
                                  Row(children: [
                                    const Icon(Icons.confirmation_number_outlined,
                                        size: 13, color: Color(0xFF1565C0)),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Code: $_confirmationCode',
                                      style: const TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF1565C0),
                                          letterSpacing: 1.2),
                                    ),
                                  ]),
                                ],
                              ],
                            ),
                          ),
                        ]),
                      ),

                    if (_assignError != null)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: const Color(0xFFFFEBEE),
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: AppColors.accent)),
                        child: Row(children: [
                          const Icon(Icons.warning_amber_rounded,
                              color: AppColors.accent, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(_assignError!,
                                style: const TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 13,
                                    color: AppColors.accent)),
                          ),
                        ]),
                      ),

                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 12),

                    // ── Allergies ─────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: const Color(0xFFFFF3E0),
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: const Color(0xFFFF9800))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(children: [
                            Icon(Icons.warning_amber_rounded,
                                color: Color(0xFFE65100), size: 18),
                            SizedBox(width: 6),
                            Text('Allergy & Dietary Restriction Info',
                                style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: Color(0xFFE65100))),
                          ]),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _allergyCtrl,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              hintText:
                                  'Example: Peanut allergy, no pork, vegetarian...',
                              hintStyle: TextStyle(
                                  fontFamily: 'Poppins', fontSize: 12),
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                              isDense: true,
                              contentPadding: EdgeInsets.all(10),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Additional notes ──────────────────────
                    TextField(
                      controller: _notesCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                          labelText: 'Additional Notes (optional)',
                          hintText:
                              'Example: Birthday, request flower decoration...',
                          prefixIcon: Icon(Icons.notes_outlined)),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Action buttons ──────────────────────────
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel',
                    style: TextStyle(fontFamily: 'Poppins')),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed:
                    _assignedTable == null ? null : _submitBooking,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFE0E0E0),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Confirm Reservation',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600)),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _dateTile() => GestureDetector(
        onTap: () async {
          final d = await showDatePicker(
            context: context,
            initialDate: _date,
            firstDate: DateTime.now(),
            lastDate: DateTime.now().add(const Duration(days: 365)),
          );
          if (d != null) {
            setState(() {
              _date = d;
              _assignedTable = null;
              _assignError = null;
            });
          }
        },
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE8EAED)),
              borderRadius: BorderRadius.circular(8),
              color: const Color(0xFFF8F9FA)),
          child: Row(children: [
            const Icon(Icons.calendar_today,
                size: 16, color: Color(0xFF6B7280)),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Date',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 10,
                            color: Color(0xFF6B7280))),
                    Text(_formatDateDisplay(_date),
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                  ]),
            ),
          ]),
        ),
      );

  Widget _timeTile() => GestureDetector(
        onTap: () async {
          final t =
              await showTimePicker(context: context, initialTime: _time);
          if (t != null) {
            setState(() {
              _time = t;
              _assignedTable = null;
              _assignError = null;
            });
          }
        },
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE8EAED)),
              borderRadius: BorderRadius.circular(8),
              color: const Color(0xFFF8F9FA)),
          child: Row(children: [
            const Icon(Icons.access_time,
                size: 16, color: Color(0xFF6B7280)),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Time',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 10,
                            color: Color(0xFF6B7280))),
                    Text(_time.format(context),
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                  ]),
            ),
          ]),
        ),
      );

  void _submitBooking() {
    if (_assignedTable == null || _nameCtrl.text.trim().isEmpty) return;

    final allergy = _allergyCtrl.text.trim();
    final notes   = _notesCtrl.text.trim();
    String? specialReq;
    if (allergy.isNotEmpty && notes.isNotEmpty) {
      specialReq = '🚨 Allergy: $allergy\n📝 Notes: $notes';
    } else if (allergy.isNotEmpty) {
      specialReq = '🚨 Allergy: $allergy';
    } else if (notes.isNotEmpty) {
      specialReq = notes;
    }

    Navigator.pop(context, {
      'customer_name':      _nameCtrl.text.trim(),
      'customer_phone':     _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      'customer_email':     _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
      'guest_count':        _guests,
      'table_id':           _assignedTable!['id'],
      'booking_date':       _formatDate(_date),
      'booking_time':       _formatTime(_time),
      'duration_minutes':   _duration,
      'special_requests':   specialReq,
      'confirmation_code':  _confirmationCode,
      'status':             'pending',
      'source':             'app',
    });
  }
}