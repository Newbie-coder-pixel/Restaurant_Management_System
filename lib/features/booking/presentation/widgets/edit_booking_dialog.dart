import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../shared/models/booking_model.dart';
import '../../../../core/theme/app_theme.dart';

class EditBookingDialog extends StatefulWidget {
  final BookingModel booking;
  final String branchId;

  const EditBookingDialog({
    super.key,
    required this.booking,
    required this.branchId,
  });

  @override
  State<EditBookingDialog> createState() => _EditBookingDialogState();
}

class _EditBookingDialogState extends State<EditBookingDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _notesCtrl;

  late int _guests;
  late DateTime _date;
  late TimeOfDay _time;
  late int _duration;

  bool _isSearching = false;
  final bool _isSaving = false;
  Map<String, dynamic>? _assignedTable;
  String? _assignError;
  bool _tableChanged = false; // apakah meja perlu di-assign ulang

  @override
  void initState() {
    super.initState();
    final b = widget.booking;
    _nameCtrl  = TextEditingController(text: b.customerName);
    _phoneCtrl = TextEditingController(text: b.customerPhone ?? '');
    _emailCtrl = TextEditingController(text: b.customerEmail ?? '');

    // Parse special_requests kembali jadi notes saja
    // (alergi sudah tersimpan di dalam teks yang sama)
    _notesCtrl = TextEditingController(text: b.specialRequests ?? '');

    _guests   = b.guestCount;
    _duration = b.durationMinutes;

    // Parse booking date
    _date = b.bookingDate;

    // Parse booking time "HH:mm:ss" → TimeOfDay
    final timeParts = b.bookingTime.split(':');
    _time = TimeOfDay(
      hour:   int.tryParse(timeParts[0]) ?? 19,
      minute: int.tryParse(timeParts.length > 1 ? timeParts[1] : '0') ?? 0,
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fmtDateDisplay(DateTime d) =>
      '${d.day}/${d.month}/${d.year}';

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  // ── Re-assign meja jika jumlah tamu atau waktu berubah ─
  Future<void> _reassignTable() async {
    setState(() {
      _isSearching = true;
      _assignedTable = null;
      _assignError = null;
    });

    try {
      final dateStr = _fmtDate(_date);
      final timeStr = _fmtTime(_time);

      // Ambil meja dengan kapasitas cukup
      final tables = await Supabase.instance.client
          .from('restaurant_tables')
          .select()
          .eq('branch_id', widget.branchId)
          .gte('capacity', _guests)
          .order('capacity');

      if ((tables as List).isEmpty) {
        setState(() {
          _assignError = 'Tidak ada meja untuk $_guests orang';
          _isSearching = false;
        });
        return;
      }

      // Cek booking lain di slot yang sama, kecuali booking ini sendiri
      final existingBookings = await Supabase.instance.client
          .from('bookings')
          .select('table_id')
          .eq('branch_id', widget.branchId)
          .eq('booking_date', dateStr)
          .eq('booking_time', timeStr)
          .neq('id', widget.booking.id) // exclude booking ini sendiri
          .inFilter('status', ['pending', 'confirmed', 'seated']);

      final bookedTableIds = (existingBookings as List)
          .map((b) => b['table_id'] as String?)
          .where((id) => id != null)
          .toSet();

      final available =
          tables.where((t) => !bookedTableIds.contains(t['id'])).toList();

      if (available.isEmpty) {
        setState(() {
          _assignError =
              'Semua meja untuk $_guests orang sudah penuh di waktu ini.\nCoba waktu lain.';
          _isSearching = false;
        });
        return;
      }

      setState(() {
        _assignedTable = available.first;
        _isSearching = false;
        _tableChanged = true;
      });
    } catch (e) {
      setState(() {
        _assignError = 'Error: $e';
        _isSearching = false;
      });
    }
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    final notes = _notesCtrl.text.trim();

    final payload = <String, dynamic>{
      'customer_name':  name,
      'customer_phone': _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      'customer_email': _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
      'guest_count':    _guests,
      'booking_date':   _fmtDate(_date),
      'booking_time':   _fmtTime(_time),
      'duration_minutes': _duration,
      'special_requests': notes.isEmpty ? null : notes,
    };

    // Kalau meja di-assign ulang, update juga table_id
    if (_tableChanged && _assignedTable != null) {
      payload['table_id'] = _assignedTable!['id'];
    }

    Navigator.pop(context, payload);
  }

  @override
  Widget build(BuildContext context) {
    final guestOrTimeChanged =
        _guests != widget.booking.guestCount ||
        _fmtDate(_date) != _fmtDate(widget.booking.bookingDate) ||
        _fmtTime(_time) != widget.booking.bookingTime;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Header
            Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.edit_calendar_outlined,
                    color: Colors.white, size: 20)),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Edit Booking',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 18)),
                  Text('# ${widget.booking.confirmationCode}',
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          color: AppColors.textSecondary)),
                ],
              )),
              IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context)),
            ]),
            const SizedBox(height: 20),

            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nama
                    TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Nama Tamu *',
                          prefixIcon: Icon(Icons.person_outline)),
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 12),

                    // HP & Email
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                              labelText: 'No. HP',
                              prefixIcon: Icon(Icons.phone_outlined)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.email_outlined)),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 16),

                    // Jumlah tamu
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: const Color(0xFFF8F9FA),
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: const Color(0xFFE8EAED))),
                      child: Row(children: [
                        const Icon(Icons.people_outline,
                            color: Color(0xFF1A1A2E), size: 20),
                        const SizedBox(width: 8),
                        const Text('Jumlah Tamu',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w500)),
                        const Spacer(),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.remove_circle_outline,
                              size: 26),
                          color: const Color(0xFFE94560),
                          onPressed: _guests > 1
                              ? () => setState(() {
                                    _guests--;
                                    _assignedTable = null;
                                    _assignError = null;
                                    _tableChanged = false;
                                  })
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Text('$_guests',
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w700,
                                fontSize: 22,
                                color: Color(0xFF1A1A2E))),
                        const SizedBox(width: 8),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.add_circle_outline,
                              size: 26),
                          color: const Color(0xFF4CAF50),
                          onPressed: () => setState(() {
                            _guests++;
                            _assignedTable = null;
                            _assignError = null;
                            _tableChanged = false;
                          }),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 12),

                    // Tanggal & Waktu
                    Row(children: [
                      Expanded(child: _dateTile()),
                      const SizedBox(width: 8),
                      Expanded(child: _timeTile()),
                    ]),
                    const SizedBox(height: 12),

                    // Durasi
                    DropdownButtonFormField<int>(
                      // ignore: deprecated_member_use
                      value: _duration,
                      decoration: const InputDecoration(
                          labelText: 'Durasi',
                          prefixIcon: Icon(Icons.timer_outlined)),
                      items: const [
                        DropdownMenuItem(value: 60,  child: Text('1 jam (60 menit)', style: TextStyle(fontFamily: 'Poppins'))),
                        DropdownMenuItem(value: 90,  child: Text('1.5 jam (90 menit)', style: TextStyle(fontFamily: 'Poppins'))),
                        DropdownMenuItem(value: 120, child: Text('2 jam (120 menit)', style: TextStyle(fontFamily: 'Poppins'))),
                        DropdownMenuItem(value: 180, child: Text('3 jam (180 menit)', style: TextStyle(fontFamily: 'Poppins'))),
                      ],
                      onChanged: (v) { if (v != null) setState(() => _duration = v); },
                    ),
                    const SizedBox(height: 16),

                    // Re-assign meja (hanya kalau tamu/waktu berubah)
                    if (guestOrTimeChanged) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: Colors.blue.shade200)),
                        child: Row(children: [
                          Icon(Icons.info_outline,
                              color: Colors.blue.shade700, size: 16),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                                'Jumlah tamu atau waktu berubah — klik tombol di bawah untuk cari meja ulang.',
                                style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 12)),
                          ),
                        ])),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isSearching ? null : _reassignTable,
                          style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1A1A2E),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(10))),
                          icon: _isSearching
                              ? const SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white))
                              : const Icon(Icons.search, size: 18),
                          label: Text(
                              _isSearching
                                  ? 'Mencari...'
                                  : 'Cari Meja Ulang',
                              style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

                    // Hasil assign
                    if (_assignedTable != null)
                      _resultCard(
                          '✅ Meja ${_assignedTable!['table_number']} — '
                          'Kapasitas ${_assignedTable!['capacity']} orang',
                          const Color(0xFF4CAF50)),
                    if (_assignError != null)
                      _resultCard(_assignError!, const Color(0xFFE94560)),

                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 8),

                    // Catatan / special requests
                    TextField(
                      controller: _notesCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Alergi & Catatan Khusus',
                        hintText:
                            'Contoh: Alergi kacang, ulang tahun, minta dekorasi...',
                        prefixIcon: Icon(Icons.notes_outlined),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Buttons
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Batal',
                      style: TextStyle(fontFamily: 'Poppins'))),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                // Kalau waktu/tamu berubah, meja harus di-assign ulang dulu
                onPressed: (guestOrTimeChanged && !_tableChanged)
                    ? null
                    : _isSaving
                        ? null
                        : _submit,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                icon: _isSaving
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_outlined, size: 16),
                label: Text(
                    guestOrTimeChanged && !_tableChanged
                        ? 'Cari meja dulu'
                        : 'Simpan Perubahan',
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600)),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _resultCard(String message, Color color) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(children: [
          Icon(
              color == const Color(0xFF4CAF50)
                  ? Icons.check_circle_outline
                  : Icons.warning_amber_rounded,
              color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Text(message,
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      color: color))),
        ]),
      );

  Widget _dateTile() => GestureDetector(
        onTap: () async {
          final d = await showDatePicker(
              context: context,
              initialDate: _date,
              firstDate: DateTime.now(),
              lastDate:
                  DateTime.now().add(const Duration(days: 365)));
          if (d != null) {
            setState(() {
              _date = d;
              _assignedTable = null;
              _assignError = null;
              _tableChanged = false;
            });
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                  const Text('Tanggal',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10,
                          color: Color(0xFF6B7280))),
                  Text(_fmtDateDisplay(_date),
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                ],
              ),
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
              _tableChanged = false;
            });
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                  const Text('Waktu',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10,
                          color: Color(0xFF6B7280))),
                  Text(_time.format(context),
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                ],
              ),
            ),
          ]),
        ),
      );
}