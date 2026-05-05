import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  Map<String, dynamic>? _assignedTable;
  String? _assignError;

  // ── Validasi waktu booking tidak kurang dari 2 jam dari sekarang ──
  String? _validateBookingTime() {
    final bookingDateTime = DateTime(
      _date.year, _date.month, _date.day,
      _time.hour, _time.minute,
    );
    final minAllowed = DateTime.now().add(const Duration(hours: 2));
    if (bookingDateTime.isBefore(minAllowed)) {
      return 'Booking minimal 2 jam sebelum waktu kedatangan.\nPilih waktu minimal ${_formatDateDisplay(minAllowed)} ${minAllowed.hour.toString().padLeft(2, '0')}:${minAllowed.minute.toString().padLeft(2, '0')}.';
    }
    return null;
  }

  Future<void> _findAvailableTable() async {
    // Validasi waktu dulu sebelum cari meja
    final timeError = _validateBookingTime();
    if (timeError != null) {
      setState(() {
        _assignError = timeError;
        _assignedTable = null;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _assignedTable = null;
      _assignError = null;
    });

    try {
      final dateStr = _formatDate(_date);
      final timeStr = _formatTime(_time);

      final tables = await Supabase.instance.client
          .from('restaurant_tables')
          .select()
          .eq('branch_id', widget.branchId)
          .gte('capacity', _guests)
          .eq('status', 'available')
          .order('capacity');

      if ((tables as List).isEmpty) {
        setState(() {
          _assignError = 'Tidak ada meja tersedia untuk $_guests orang';
          _isSearching = false;
        });
        return;
      }

      final existingBookings = await Supabase.instance.client
          .from('bookings')
          .select('table_id')
          .eq('branch_id', widget.branchId)
          .eq('booking_date', dateStr)
          .eq('booking_time', timeStr)
          .inFilter('status', ['pending', 'confirmed', 'seated']);

      final bookedTableIds = (existingBookings as List)
          .map((b) => b['table_id'] as String?)
          .where((id) => id != null)
          .toSet();

      final available = tables
          .where((t) => !bookedTableIds.contains(t['id']))
          .toList();

      if (available.isEmpty) {
        setState(() {
          _assignError =
              'Semua meja untuk $_guests orang sudah penuh di waktu tersebut.\nCoba waktu lain.';
          _isSearching = false;
        });
        return;
      }

      setState(() {
        _assignedTable = available.first;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _assignError = 'Error: $e';
        _isSearching = false;
      });
    }
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
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.event_available,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Reservasi Baru',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 18)),
                Text('Meja akan dipilihkan otomatis',
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
                    // ── Nama ────────────────────────────────
                    TextField(
                      controller: _nameCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                          labelText: 'Nama Tamu *',
                          prefixIcon: Icon(Icons.person_outline)),
                    ),
                    const SizedBox(height: 12),

                    // ── No HP ────────────────────────────────
                    TextField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                          labelText: 'No. HP',
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

                    // ── Jumlah tamu ──────────────────────────
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: const Color(0xFFF8F9FA),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE8EAED))),
                      child: Row(children: [
                        const Icon(Icons.people_outline,
                            color: Color(0xFF1A1A2E), size: 20),
                        const SizedBox(width: 8),
                        const Flexible(
                          child: Text('Jumlah Tamu',
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
                          color: const Color(0xFFE94560),
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
                                color: Color(0xFF1A1A2E))),
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

                    // ── Tanggal & Waktu ──────────────────────
                    Row(children: [
                      Expanded(child: _dateTile()),
                      const SizedBox(width: 8),
                      Expanded(child: _timeTile()),
                    ]),
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
                            'Booking minimal 2 jam sebelum kedatangan. Pembatalan < 2 jam dikenakan biaya.',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11,
                                color: Color(0xFF1565C0)),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 16),

                    // ── Tombol cari meja ─────────────────────
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _nameCtrl.text.trim().isEmpty
                            ? null
                            : _findAvailableTable,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1A1A2E),
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
                              ? 'Mencari meja...'
                              : 'Cek & Pilihkan Meja Otomatis',
                          style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Hasil auto-assign ────────────────────
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
                                  'Meja ${_assignedTable!['table_number']} — Kapasitas ${_assignedTable!['capacity']} orang',
                                  style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF2E7D32)),
                                ),
                                Text(
                                  'Bentuk: ${_assignedTable!['shape']} • Lantai ${_assignedTable!['floor_level']}',
                                  style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 12,
                                      color: Color(0xFF4CAF50)),
                                ),
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
                                Border.all(color: const Color(0xFFE94560))),
                        child: Row(children: [
                          const Icon(Icons.warning_amber_rounded,
                              color: Color(0xFFE94560), size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(_assignError!,
                                style: const TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 13,
                                    color: Color(0xFFE94560))),
                          ),
                        ]),
                      ),

                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 12),

                    // ── Alergi ───────────────────────────────
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
                            Text('Info Alergi & Pantangan Makanan',
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
                                  'Contoh: Alergi kacang, tidak makan babi, vegetarian...',
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

                    // ── Catatan tambahan ─────────────────────
                    TextField(
                      controller: _notesCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                          labelText: 'Catatan Tambahan (opsional)',
                          hintText:
                              'Contoh: Ulang tahun, minta dekorasi bunga...',
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
                child: const Text('Batal',
                    style: TextStyle(fontFamily: 'Poppins')),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed:
                    _assignedTable == null ? null : _submitBooking,
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A2E),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFE0E0E0),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Konfirmasi Reservasi',
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
                    const Text('Tanggal',
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
      specialReq = '🚨 Alergi: $allergy\n📝 Catatan: $notes';
    } else if (allergy.isNotEmpty) {
      specialReq = '🚨 Alergi: $allergy';
    } else if (notes.isNotEmpty) {
      specialReq = notes;
    }

    Navigator.pop(context, {
      'customer_name':    _nameCtrl.text.trim(),
      'customer_phone':   _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      'customer_email':   _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
      'guest_count':      _guests,
      'table_id':         _assignedTable!['id'],
      'booking_date':     _formatDate(_date),
      'booking_time':     _formatTime(_time),
      'special_requests': specialReq,
      'status':           'pending',
      'source':           'app',
    });
  }
}