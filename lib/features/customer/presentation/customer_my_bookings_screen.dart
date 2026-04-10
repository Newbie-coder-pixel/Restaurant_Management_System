import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// ── Provider booking milik user — JOIN branches ───────────────────
final _refreshTriggerProvider = StateProvider<int>((ref) => 0);

final _myBookingsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  ref.watch(_refreshTriggerProvider);

  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return [];

  final res = await Supabase.instance.client
      .from('bookings')
      .select('*, branches(id, name, phone), restaurant_tables!bookings_table_id_fkey(table_number)')
      .eq('customer_user_id', user.id)
      .order('booking_date', ascending: false);

  return (res as List).cast<Map<String, dynamic>>();
});

// ── Provider daftar cabang aktif ──────────────────────────────────
final _branchesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await Supabase.instance.client
      .from('branches')
      .select('id, name, address, phone, opening_time, closing_time')
      .eq('is_active', true)
      .order('name');
  return (res as List).cast<Map<String, dynamic>>();
});

// ── Validasi nomor telepon Indonesia ─────────────────────────────
String? _validatePhone(String phone) {
  final cleaned = phone.replaceAll(RegExp(r'\s|-'), '');
  if (cleaned.isEmpty) return 'Nomor HP wajib diisi';
  if (!RegExp(r'^(\+62|62|0)[0-9]+$').hasMatch(cleaned)) {
    return 'Nomor HP hanya boleh berisi angka';
  }
  String normalized = cleaned;
  if (normalized.startsWith('+62')) normalized = '0${normalized.substring(3)}';
  if (normalized.startsWith('62')) normalized = '0${normalized.substring(2)}';
  if (!normalized.startsWith('08')) {
    return 'Nomor HP harus diawali 08 (contoh: 081234567890)';
  }
  if (normalized.length < 10 || normalized.length > 13) {
    return 'Nomor HP harus 10–13 digit';
  }
  return null;
}

// ─────────────────────────────────────────────────────────────────
// SCREEN UTAMA
// ─────────────────────────────────────────────────────────────────
class CustomerMyBookingsScreen extends ConsumerStatefulWidget {
  const CustomerMyBookingsScreen({super.key});

  @override
  ConsumerState<CustomerMyBookingsScreen> createState() =>
      _CustomerMyBookingsScreenState();
}

class _CustomerMyBookingsScreenState
    extends ConsumerState<CustomerMyBookingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  RealtimeChannel? _bookingChannel;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _listenBookingChanges();
  }

  @override
  void dispose() {
    _bookingChannel?.unsubscribe();
    _tabCtrl.dispose();
    super.dispose();
  }

  void _listenBookingChanges() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    _bookingChannel = Supabase.instance.client
        .channel('booking-changes-${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'bookings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'customer_user_id',
            value: user.id,
          ),
          callback: (payload) {
            if (!mounted) return;
            final newStatus = payload.newRecord['status'] as String?;
            _showStatusNotification(newStatus);
            ref.read(_refreshTriggerProvider.notifier).state++;
          },
        )
        .subscribe();
  }

  void _showStatusNotification(String? status) {
    if (!mounted) return;

    final (String message, Color color, IconData icon) = switch (status) {
      'confirmed' => (
          '🎉 Reservasi kamu dikonfirmasi! Meja sudah disiapkan.',
          const Color(0xFF4CAF50),
          Icons.check_circle,
        ),
      'cancelled' => (
          '❌ Reservasi kamu dibatalkan.',
          const Color(0xFFE94560),
          Icons.cancel,
        ),
      'waitlisted' => (
          '⏳ Semua meja penuh, kamu masuk daftar tunggu.',
          const Color(0xFF7C3AED),
          Icons.hourglass_top,
        ),
      'seated' => (
          '🍽️ Selamat datang! Silakan menuju meja kamu.',
          const Color(0xFF0891B2),
          Icons.restaurant,
        ),
      _ => ('Status reservasi diperbarui.', const Color(0xFF0F3460), Icons.info),
    };

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(message,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w500))),
      ]),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final isDesktop = screenW > 700;

    return Column(children: [
      Container(
        color: Colors.white,
        child: TabBar(
          controller: _tabCtrl,
          labelStyle: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w600),
          unselectedLabelStyle:
              const TextStyle(fontFamily: 'Poppins', fontSize: 13),
          labelColor: const Color(0xFFE94560),
          unselectedLabelColor: const Color(0xFF6B7280),
          indicatorColor: const Color(0xFFE94560),
          indicatorWeight: 2.5,
          tabs: const [
            Tab(
                icon: Icon(Icons.add_circle_outline, size: 18),
                text: 'Buat Reservasi'),
            Tab(
                icon: Icon(Icons.calendar_month_outlined, size: 18),
                text: 'Reservasi Saya'),
          ],
        ),
      ),
      Expanded(
        child: TabBarView(
          controller: _tabCtrl,
          children: [
            _BookingForm(
              isDesktop: isDesktop,
              onSuccess: () {
                ref.read(_refreshTriggerProvider.notifier).state++;
                _tabCtrl.animateTo(1);
              },
            ),
            _BookingHistory(isDesktop: isDesktop),
          ],
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────
// FORM BUAT RESERVASI
// ─────────────────────────────────────────────────────────────────
class _BookingForm extends ConsumerStatefulWidget {
  final bool isDesktop;
  final VoidCallback onSuccess;
  const _BookingForm({required this.isDesktop, required this.onSuccess});

  @override
  ConsumerState<_BookingForm> createState() => _BookingFormState();
}

class _BookingFormState extends ConsumerState<_BookingForm> {
  final _nameCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  String? _phoneError;
  String? _selectedBranchId;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  int _guestCount = 2;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      final name = user.userMetadata?['full_name'] as String? ??
          user.userMetadata?['name'] as String? ?? '';
      _nameCtrl.text = name;
      _phoneCtrl.text = user.phone ?? '';
    }
    _phoneCtrl.addListener(() {
      if (_phoneError != null) {
        setState(() => _phoneError = _validatePhone(_phoneCtrl.text.trim()));
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  String _formatDate(DateTime d) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
    ];
    return '${d.day} ${months[d.month]} ${d.year}';
  }

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 60)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF0F3460),
            onPrimary: Colors.white,
            surface: Colors.white)),
        child: child!));
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime(String open, String close) async {
    final openParts  = open.split(':');
    final closeParts = close.split(':');
    final openHour   = int.tryParse(openParts[0]) ?? 10;
    final closeHour  = int.tryParse(closeParts[0]) ?? 22;

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: openHour, minute: 0),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF0F3460),
            onPrimary: Colors.white)),
        child: child!));

    if (picked == null || !mounted) return;
    if (picked.hour < openHour || picked.hour >= closeHour) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Jam harus antara $open – $close WIB',
            style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: const Color(0xFFE94560),
        behavior: SnackBarBehavior.floating));
      return;
    }
    setState(() => _selectedTime = picked);
  }

  Future<void> _submit(List<Map<String, dynamic>> branches) async {
    if (_selectedBranchId == null) { _err('Pilih cabang dulu'); return; }
    if (_selectedDate == null)     { _err('Pilih tanggal'); return; }
    if (_selectedTime == null)     { _err('Pilih jam kedatangan'); return; }
    if (_nameCtrl.text.trim().isEmpty) { _err('Nama wajib diisi'); return; }

    final phoneErr = _validatePhone(_phoneCtrl.text.trim());
    if (phoneErr != null) {
      setState(() => _phoneError = phoneErr);
      _err(phoneErr);
      return;
    }
    setState(() => _phoneError = null);

    setState(() => _submitting = true);
    try {
      final user    = Supabase.instance.client.auth.currentUser;
      final dateStr = _selectedDate!.toIso8601String().substring(0, 10);
      final timeStr = _formatTime(_selectedTime!);
      final notes   = _notesCtrl.text.trim();

      final rawPhone = _phoneCtrl.text.trim();
      String normalizedPhone = rawPhone.replaceAll(RegExp(r'\s|-'), '');
      if (normalizedPhone.startsWith('+62')) {
        normalizedPhone = '0${normalizedPhone.substring(3)}';
      } else if (normalizedPhone.startsWith('62')) {
        normalizedPhone = '0${normalizedPhone.substring(2)}';
      }

      final bookingRes = await Supabase.instance.client
          .from('bookings')
          .insert({
            'branch_id':        _selectedBranchId,
            'customer_user_id': user?.id,
            'customer_name':    _nameCtrl.text.trim(),
            'customer_phone':   normalizedPhone,
            'guest_count':      _guestCount,
            'booking_date':     dateStr,
            'booking_time':     timeStr,
            'status':           'pending',
            'source':           'app',
            if (notes.isNotEmpty) 'special_requests': notes,
          })
          .select('id')
          .single();

      final bookingId = bookingRes['id'] as String;

      final result = await Supabase.instance.client.rpc(
        'assign_table_to_booking',
        params: {
          'p_booking_id':   bookingId,
          'p_branch_id':    _selectedBranchId,
          'p_guest_count':  _guestCount,
          'p_booking_date': dateStr,
          'p_booking_time': '$timeStr:00',
        },
      ) as Map<String, dynamic>;

      if (!mounted) return;

      final success     = result['success'] as bool;
      final tableNumber = result['table_number'] as String?;

      if (success) {
        _showSuccess(tableNumber: tableNumber);
      } else {
        _showWaitlisted();
      }
    } catch (e) {
      _err('Gagal membuat reservasi: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _err(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
      backgroundColor: const Color(0xFFE94560),
      behavior: SnackBarBehavior.floating));
  }

  void _showSuccess({String? tableNumber}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64, height: 64,
            decoration: const BoxDecoration(
              color: Color(0xFFE8F5E9), shape: BoxShape.circle),
            child: const Icon(Icons.check_circle,
                color: Color(0xFF4CAF50), size: 36)),
          const SizedBox(height: 16),
          const Text('Reservasi Berhasil!',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E))),
          const SizedBox(height: 8),
          if (tableNumber != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF4CAF50).withValues(alpha: 0.3))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.table_restaurant,
                    size: 16, color: Color(0xFF4CAF50)),
                const SizedBox(width: 6),
                Text('Meja $tableNumber sudah disiapkan',
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2E7D32))),
              ])),
          ],
          const Text(
            'Reservasi kamu sudah dikonfirmasi.\nCek tab "Reservasi Saya" untuk detailnya.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: 'Poppins', fontSize: 13, color: Color(0xFF6B7280))),
        ]),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F3460),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 12)),
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                widget.onSuccess();
              },
              child: const Text('OK',
                  style: TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
            )),
        ]));
  }

  void _showWaitlisted() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64, height: 64,
            decoration: const BoxDecoration(
              color: Color(0xFFFFF8E1), shape: BoxShape.circle),
            child: const Icon(Icons.schedule,
                color: Color(0xFFD97706), size: 36)),
          const SizedBox(height: 16),
          const Text('Masuk Waitlist',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E))),
          const SizedBox(height: 8),
          const Text(
            'Semua meja sedang penuh untuk waktu tersebut.\n'
            'Kamu sudah masuk daftar tunggu. Staff akan menghubungi nomor HP kamu jika ada meja tersedia.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: 'Poppins', fontSize: 13, color: Color(0xFF6B7280))),
        ]),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD97706),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 12)),
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                widget.onSuccess();
              },
              child: const Text('Mengerti',
                  style: TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
            )),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final branchesAsync = ref.watch(_branchesProvider);

    return branchesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (branches) {
        if (branches.length == 1 && _selectedBranchId == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _selectedBranchId = branches[0]['id'] as String);
          });
        }

        final selectedBranch = branches
            .where((b) => b['id'] == _selectedBranchId)
            .cast<Map<String, dynamic>?>()
            .firstOrNull;

        final openTime  = (selectedBranch?['opening_time'] as String?)?.substring(0, 5) ?? '10:00';
        final closeTime = (selectedBranch?['closing_time'] as String?)?.substring(0, 5) ?? '22:00';

        Widget formContent = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionLabel('Pilih Cabang'),
            if (branches.length == 1)
              _infoChip(Icons.store, branches[0]['name'] as String)
            else
              _dropdown(
                value: _selectedBranchId,
                hint: 'Pilih cabang',
                items: branches.map((b) => DropdownMenuItem<String>(
                  value: b['id'] as String,
                  child: Text(b['name'] as String,
                      style: const TextStyle(
                          fontFamily: 'Poppins', fontSize: 14)))).toList(),
                onChanged: (v) => setState(() => _selectedBranchId = v)),
            const SizedBox(height: 20),
            if (widget.isDesktop)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _dateField(openTime, closeTime)),
                const SizedBox(width: 16),
                Expanded(child: _timeField(openTime, closeTime)),
              ])
            else ...[
              _dateField(openTime, closeTime),
              const SizedBox(height: 16),
              _timeField(openTime, closeTime),
            ],
            const SizedBox(height: 20),
            _sectionLabel('Jumlah Tamu'),
            _guestPicker(),
            const SizedBox(height: 20),
            if (widget.isDesktop)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _nameField()),
                const SizedBox(width: 16),
                Expanded(child: _phoneField()),
              ])
            else ...[
              _nameField(),
              const SizedBox(height: 12),
              _phoneField(),
            ],
            const SizedBox(height: 20),
            _sectionLabel('Catatan Khusus (opsional)'),
            TextField(
              controller: _notesCtrl,
              maxLines: 3,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
              decoration: _inputDeco(
                  'Contoh: alergi kacang, kursi tinggi untuk bayi...', null)),
            const SizedBox(height: 28),
            GestureDetector(
              onTap: _submitting ? null : () => _submit(branches),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFFE94560), Color(0xFFFF6B6B)]),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(
                    color: const Color(0xFFE94560).withValues(alpha: 0.3),
                    blurRadius: 12, offset: const Offset(0, 4))]),
                child: Center(
                  child: _submitting
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.calendar_today,
                              color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text('Buat Reservasi',
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                        ])))),
            const SizedBox(height: 32),
          ],
        );

        if (widget.isDesktop) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: formContent)));
        }
        return SingleChildScrollView(
            padding: const EdgeInsets.all(20), child: formContent);
      },
    );
  }

  Widget _sectionLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(label,
        style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF374151))));

  Widget _infoChip(IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFF0F3460).withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
          color: const Color(0xFF0F3460).withValues(alpha: 0.2))),
    child: Row(children: [
      Icon(icon, size: 18, color: const Color(0xFF0F3460)),
      const SizedBox(width: 10),
      Text(label,
          style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0F3460))),
    ]));

  Widget _dropdown({
    required String? value,
    required String hint,
    required List<DropdownMenuItem<String>> items,
    required void Function(String?) onChanged,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE5E7EB))),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        isExpanded: true,
        hint: Text(hint,
            style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 14, color: Colors.grey)),
        items: items,
        onChanged: onChanged,
        style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14,
            color: Color(0xFF1A1A2E)))));

  Widget _dateField(String open, String close) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _sectionLabel('Tanggal Kedatangan'),
      GestureDetector(
        onTap: _pickDate,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: _selectedDate != null
                    ? const Color(0xFF0F3460)
                    : const Color(0xFFE5E7EB))),
          child: Row(children: [
            Icon(Icons.calendar_today_outlined,
                size: 18,
                color: _selectedDate != null
                    ? const Color(0xFF0F3460)
                    : const Color(0xFF6B7280)),
            const SizedBox(width: 10),
            Text(
              _selectedDate != null
                  ? _formatDate(_selectedDate!)
                  : 'Pilih tanggal',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  color: _selectedDate != null
                      ? const Color(0xFF1A1A2E)
                      : Colors.grey)),
          ]))),
    ]);

  Widget _timeField(String open, String close) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _sectionLabel('Jam Kedatangan ($open – $close)'),
      GestureDetector(
        onTap: () => _pickTime(open, close),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: _selectedTime != null
                    ? const Color(0xFF0F3460)
                    : const Color(0xFFE5E7EB))),
          child: Row(children: [
            Icon(Icons.access_time_outlined,
                size: 18,
                color: _selectedTime != null
                    ? const Color(0xFF0F3460)
                    : const Color(0xFF6B7280)),
            const SizedBox(width: 10),
            Text(
              _selectedTime != null
                  ? '${_formatTime(_selectedTime!)} WIB'
                  : 'Pilih jam',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  color: _selectedTime != null
                      ? const Color(0xFF1A1A2E)
                      : Colors.grey)),
          ]))),
    ]);

  Widget _guestPicker() => Row(children: [
    _counterBtn(Icons.remove, () {
      if (_guestCount > 1) setState(() => _guestCount--);
    }),
    const SizedBox(width: 16),
    Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB))),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.people_outline, size: 18, color: Color(0xFF6B7280)),
          const SizedBox(width: 8),
          Text('$_guestCount orang',
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A2E))),
        ]))),
    const SizedBox(width: 16),
    _counterBtn(Icons.add, () {
      if (_guestCount < 20) setState(() => _guestCount++);
    }),
  ]);

  Widget _counterBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 44, height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFF0F3460),
        borderRadius: BorderRadius.circular(12)),
      child: Icon(icon, color: Colors.white, size: 20)));

  Widget _nameField() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _sectionLabel('Nama Lengkap'),
      TextField(
        controller: _nameCtrl,
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
        decoration: _inputDeco('Nama sesuai identitas',
            const Icon(Icons.person_outline,
                size: 18, color: Color(0xFF6B7280)))),
    ]);

  Widget _phoneField() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _sectionLabel('Nomor HP'),
      TextField(
        controller: _phoneCtrl,
        keyboardType: TextInputType.phone,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[\d+\s\-]')),
        ],
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
        onChanged: (v) => setState(() => _phoneError = null),
        onEditingComplete: () {
          setState(() =>
            _phoneError = _validatePhone(_phoneCtrl.text.trim()));
        },
        decoration: InputDecoration(
          hintText: '081234567890',
          hintStyle: const TextStyle(
              fontFamily: 'Poppins', fontSize: 13, color: Colors.grey),
          prefixIcon: const Icon(Icons.phone_outlined,
              size: 18, color: Color(0xFF6B7280)),
          errorText: _phoneError,
          errorStyle: const TextStyle(
              fontFamily: 'Poppins', fontSize: 11, color: Color(0xFFE94560)),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: _phoneError != null
                      ? const Color(0xFFE94560)
                      : const Color(0xFFE5E7EB))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: _phoneError != null
                      ? const Color(0xFFE94560)
                      : const Color(0xFF0F3460),
                  width: 1.5)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
      ),
      const Padding(
        padding: EdgeInsets.only(top: 4, left: 4),
        child: Text(
          'Format: 08xxxxxxxxxx (10–13 digit)',
          style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              color: Color(0xFF9CA3AF)))),
    ]);

  InputDecoration _inputDeco(String hint, Widget? prefix) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(
        fontFamily: 'Poppins', fontSize: 13, color: Colors.grey),
    prefixIcon: prefix,
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
    enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
    focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF0F3460), width: 1.5)),
    contentPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 14));
}

// ─────────────────────────────────────────────────────────────────
// RIWAYAT BOOKING
// ─────────────────────────────────────────────────────────────────
class _BookingHistory extends ConsumerWidget {
  final bool isDesktop;
  const _BookingHistory({required this.isDesktop});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingsAsync = ref.watch(_myBookingsProvider);

    return bookingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
          child: Text('Error: $e',
              style: const TextStyle(fontFamily: 'Poppins'))),
      data: (bookings) {
        if (bookings.isEmpty) return _emptyState();

        final content = ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: bookings.length,
          itemBuilder: (_, i) =>
              _BookingCard(booking: bookings[i], isDesktop: isDesktop));

        if (isDesktop) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: content));
        }
        return content;
      },
    );
  }

  Widget _emptyState() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 80, height: 80,
        decoration: BoxDecoration(
          color: const Color(0xFFE94560).withValues(alpha: 0.08),
          shape: BoxShape.circle),
        child: const Icon(Icons.calendar_today_outlined,
            color: Color(0xFFE94560), size: 38)),
      const SizedBox(height: 20),
      const Text('Belum Ada Reservasi',
          style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A2E))),
      const SizedBox(height: 8),
      const Text('Buat reservasi di tab "Buat Reservasi".',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontFamily: 'Poppins', fontSize: 13, color: Color(0xFF6B7280))),
    ]));
}

// ─────────────────────────────────────────────────────────────────
// KARTU BOOKING
// ─────────────────────────────────────────────────────────────────
class _BookingCard extends StatefulWidget {
  final Map<String, dynamic> booking;
  final bool isDesktop;
  const _BookingCard({required this.booking, required this.isDesktop});

  @override
  State<_BookingCard> createState() => _BookingCardState();
}

class _BookingCardState extends State<_BookingCard> {
  bool _uploadingProof = false;

  Map<String, dynamic> get booking => widget.booking;
  bool get isDesktop => widget.isDesktop;

  String get _status => booking['status'] as String? ?? 'pending';

  Color get _color => switch (_status) {
    'confirmed'  => const Color(0xFF4CAF50),
    'cancelled'  => const Color(0xFFE94560),
    'completed'  => const Color(0xFF0F3460),
    'no_show'    => Colors.orange,
    'waitlisted' => const Color(0xFF7C3AED),
    'seated'     => const Color(0xFF0891B2),
    _            => const Color(0xFFFF9800),
  };

  String get _label => switch (_status) {
    'confirmed'  => 'Dikonfirmasi',
    'cancelled'  => 'Dibatalkan',
    'completed'  => 'Selesai',
    'no_show'    => 'Tidak Hadir',
    'waitlisted' => 'Daftar Tunggu',
    'seated'     => 'Sedang Makan',
    _            => 'Menunggu',
  };

  IconData get _icon => switch (_status) {
    'confirmed'  => Icons.check_circle_outline,
    'cancelled'  => Icons.cancel_outlined,
    'completed'  => Icons.done_all,
    'no_show'    => Icons.person_off_outlined,
    'waitlisted' => Icons.hourglass_top_outlined,
    'seated'     => Icons.restaurant_outlined,
    _            => Icons.schedule,
  };

  bool get _isActive =>
      _status == 'pending' || _status == 'confirmed' ||
      _status == 'waitlisted' || _status == 'seated';

  String _fmtDate(String? raw) {
    if (raw == null) return '-';
    try {
      final d = DateTime.parse(raw);
      const months = [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
        'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
      ];
      return '${d.day} ${months[d.month]} ${d.year}';
    } catch (_) { return raw; }
  }

  Future<void> _contactStaff(BuildContext context, String? phone) async {
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Nomor kontak cabang tidak tersedia. Silakan hubungi kami langsung.',
            style: TextStyle(fontFamily: 'Poppins')),
        backgroundColor: Color(0xFF0F3460),
        behavior: SnackBarBehavior.floating));
      return;
    }

    final cleaned = phone
        .replaceAll(RegExp(r'[^\d+]'), '')
        .replaceFirst(RegExp(r'^0'), '62');

    final date   = _fmtDate(booking['booking_date'] as String?);
    final time   = (booking['booking_time'] as String?)?.substring(0, 5) ?? '-';
    final guests = booking['guest_count'] ?? 1;
    final name   = booking['customer_name'] as String? ?? '';

    final msg = Uri.encodeComponent(
        'Halo, saya ingin menghubungi terkait reservasi saya:\n\n'
        '👤 Nama: $name\n'
        '📅 Tanggal: $date\n'
        '🕐 Jam: $time WIB\n'
        '👥 Tamu: $guests orang\n\n'
        'Mohon bantuannya. Terima kasih 🙏');

    final waUrl  = Uri.parse('https://wa.me/$cleaned?text=$msg');
    final telUrl = Uri.parse('tel:$phone');

    if (await canLaunchUrl(waUrl)) {
      await launchUrl(waUrl, mode: LaunchMode.externalApplication);
    } else if (await canLaunchUrl(telUrl)) {
      await launchUrl(telUrl);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Tidak bisa membuka WhatsApp. No: $phone',
              style: const TextStyle(fontFamily: 'Poppins')),
          backgroundColor: const Color(0xFF0F3460),
          behavior: SnackBarBehavior.floating));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final branchData  = booking['branches'] as Map<String, dynamic>?;
    final branchName  = branchData?['name'] as String? ?? 'Restoran';
    final branchPhone = branchData?['phone'] as String?;

    final date    = _fmtDate(booking['booking_date'] as String?);
    final time    = (booking['booking_time'] as String?)?.substring(0, 5) ?? '-';
    final guests  = booking['guest_count'] ?? 1;
    final notes   = booking['special_requests'] as String?;
    final tableId = booking['table_id'] as String?;

    // ── Data DP ──
    final depositAmount = booking['deposit_amount'] as int? ?? 0;
    final depositStatus = booking['deposit_status'] as String? ?? 'not_required';
    final dpPerOrang    = booking['dp_per_orang'] as int? ?? 0;
    final depositNotes  = booking['deposit_notes'] as String?;
    final depositPaidAt = booking['deposit_paid_at'] as String?;
    final hasDeposit    = depositAmount > 0 && depositStatus != 'not_required';
    final isDpPaid      = depositStatus == 'paid' || depositStatus == 'applied';
    final isDpPending   = depositStatus == 'pending';
    final isDpUploaded  = depositStatus == 'uploaded';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 10, offset: const Offset(0, 3))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: _color.withValues(alpha: 0.08),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(16))),
          child: Row(children: [
            Icon(_icon, color: _color, size: 18),
            const SizedBox(width: 8),
            Text(_label,
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: _color)),
            const Spacer(),
            if (_isActive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 6, height: 6,
                      decoration: BoxDecoration(
                          color: _color, shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Text('Live',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _color)),
                ])),
          ])),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(branchName,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E))),
              const SizedBox(height: 12),
              if (isDesktop)
                Row(children: [
                  Expanded(child: Column(children: [
                    _row(Icons.calendar_today_outlined, 'Tanggal', date),
                    const SizedBox(height: 8),
                    _row(Icons.access_time_outlined, 'Jam', '$time WIB'),
                  ])),
                  const SizedBox(width: 24),
                  Expanded(child: Column(children: [
                    _row(Icons.people_outline, 'Tamu', '$guests orang'),
                    if (notes != null && notes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _row(Icons.note_outlined, 'Catatan', notes),
                    ],
                  ])),
                ])
              else ...[
                _row(Icons.calendar_today_outlined, 'Tanggal', date),
                const SizedBox(height: 8),
                _row(Icons.access_time_outlined, 'Jam', '$time WIB'),
                const SizedBox(height: 8),
                _row(Icons.people_outline, 'Tamu', '$guests orang'),
                if (notes != null && notes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _row(Icons.note_outlined, 'Catatan', notes),
                ],
              ],
              if (tableId != null && _status == 'confirmed') ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: const Color(0xFF4CAF50).withValues(alpha: 0.3))),
                  child: Row(children: [
                    const Icon(Icons.table_restaurant,
                        size: 16, color: Color(0xFF4CAF50)),
                    const SizedBox(width: 8),
                    Builder(builder: (_) {
                      final tableData = booking['restaurant_tables']
                          as Map<String, dynamic>?;
                      final num = tableData?['table_number'] as String?;
                      return Text(
                        num != null
                            ? 'Meja $num sudah disiapkan'
                            : 'Meja sudah disiapkan',
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2E7D32)));
                    }),
                  ])),
              ],
              if (_status == 'waitlisted') ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3E8FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: const Color(0xFF7C3AED).withValues(alpha: 0.3))),
                  child: Row(children: [
                    const Icon(Icons.hourglass_top_outlined,
                        size: 16, color: Color(0xFF7C3AED)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Kamu di daftar tunggu. Staff akan menghubungi jika ada meja tersedia.',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                color: Color(0xFF6D28D9))),
                          if (booking['customer_phone'] != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Akan dihubungi via: ${booking['customer_phone']}',
                              style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF7C3AED))),
                          ],
                        ],
                      )),
                  ])),
              ],
              // ── Section DP untuk Customer ──────────────
              if (hasDeposit) ...[
                const SizedBox(height: 12),
                _buildCustomerDpSection(
                  context,
                  depositAmount: depositAmount,
                  depositStatus: depositStatus,
                  dpPerOrang: dpPerOrang,
                  depositNotes: depositNotes,
                  depositPaidAt: depositPaidAt,
                  isDpPaid: isDpPaid,
                  isDpPending: isDpPending,
                  isDpUploaded: isDpUploaded,
                  bookingId: booking['id'] as String? ?? '',
                ),
              ],

              if (_isActive) ...[
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: const Color(0xFFFFCC02).withValues(alpha: 0.4))),
                  child: const Row(children: [
                    Icon(Icons.info_outline, size: 14, color: Color(0xFFD97706)),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Ingin mengubah atau membatalkan? Hubungi staff kami.',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            color: Color(0xFFD97706)))),
                  ])),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _contactStaff(context, branchPhone),
                    icon: const Icon(Icons.chat_rounded,
                        size: 18, color: Color(0xFF25D366)),
                    label: const Text('Hubungi Kami',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1A1A2E))),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10))),
                  )),
              ],
            ])),
      ]));
  }

  // ── Helper: format rupiah ──
  String _formatRupiah(int amount) {
    final str = amount.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buffer.write('.');
      buffer.write(str[i]);
    }
    return 'Rp ${buffer.toString()}';
  }

  String _formatDateTime(String raw) {
    try {
      final dt = DateTime.parse(raw).toLocal();
      const months = [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
        'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
      ];
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '${dt.day} ${months[dt.month]} ${dt.year}, $h:$m';
    } catch (_) {
      return raw;
    }
  }

  // ── Upload bukti transfer ke Supabase Storage ──
  Future<void> _uploadProof(BuildContext context, String bookingId) async {
    try {
      setState(() => _uploadingProof = true);

      // Pilih gambar dari galeri atau kamera
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (_) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            const Text('Pilih Sumber Foto',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 15)),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: Color(0xFF0F3460)),
              title: const Text('Galeri Foto',
                  style: TextStyle(fontFamily: 'Poppins')),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined,
                  color: Color(0xFF0F3460)),
              title: const Text('Kamera',
                  style: TextStyle(fontFamily: 'Poppins')),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      );

      if (source == null || !context.mounted) {
        setState(() => _uploadingProof = false);
        return;
      }

      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (picked == null || !context.mounted) {
        setState(() => _uploadingProof = false);
        return;
      }

      final Uint8List bytes = await picked.readAsBytes();
      final ext = picked.name.split('.').last.toLowerCase();
      final fileName = 'dp_proof_${bookingId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final path = 'booking-proofs/$fileName';

      // Upload ke Supabase Storage bucket 'booking-proofs'
      await Supabase.instance.client.storage
          .from('booking-proofs')
          .uploadBinary(path, bytes,
              fileOptions: FileOptions(contentType: 'image/$ext', upsert: true));

      // Update deposit_status → 'uploaded' dan simpan URL di deposit_notes
      final publicUrl = Supabase.instance.client.storage
          .from('booking-proofs')
          .getPublicUrl(path);

      await Supabase.instance.client
          .from('bookings')
          .update({
            'deposit_status': 'uploaded',
            'deposit_notes': 'Bukti transfer: $publicUrl',
          })
          .eq('id', bookingId);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Row(children: [
          Icon(Icons.check_circle, color: Colors.white, size: 18),
          SizedBox(width: 8),
          Text('Bukti transfer berhasil dikirim! Menunggu konfirmasi staff.',
              style: TextStyle(fontFamily: 'Poppins')),
        ]),
        backgroundColor: Color(0xFF1976D2),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 4),
      ));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Gagal upload bukti: $e',
            style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: const Color(0xFFE94560),
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _uploadingProof = false);
    }
  }

  // ── Widget section DP untuk customer ──
  Widget _buildCustomerDpSection(
    BuildContext context, {
    required int depositAmount,
    required String depositStatus,
    required int dpPerOrang,
    required String? depositNotes,
    required String? depositPaidAt,
    required bool isDpPaid,
    required bool isDpPending,
    required bool isDpUploaded,
    required String bookingId,
  }) {
    final Color bgColor;
    final Color borderColor;
    final Color iconColor;
    final Color labelColor;
    final IconData statusIcon;
    final String statusText;

    if (isDpPaid) {
      bgColor     = const Color(0xFFE8F5E9);
      borderColor = const Color(0xFF4CAF50);
      iconColor   = const Color(0xFF2E7D32);
      labelColor  = const Color(0xFF2E7D32);
      statusIcon  = Icons.check_circle_outline;
      statusText  = 'DP Lunas ✓';
    } else if (isDpUploaded) {
      bgColor     = const Color(0xFFE3F2FD);
      borderColor = const Color(0xFF1976D2);
      iconColor   = const Color(0xFF1565C0);
      labelColor  = const Color(0xFF1565C0);
      statusIcon  = Icons.hourglass_top_outlined;
      statusText  = 'Bukti Dikirim — Menunggu Konfirmasi';
    } else {
      bgColor     = const Color(0xFFFFF3E0);
      borderColor = const Color(0xFFFFB300);
      iconColor   = const Color(0xFFE65100);
      labelColor  = const Color(0xFFE65100);
      statusIcon  = Icons.payments_outlined;
      statusText  = 'DP Belum Dibayar';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // Baris atas: ikon + label + nominal
          Row(children: [
            Icon(statusIcon, size: 16, color: iconColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(statusText,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: labelColor)),
            ),
            Text(
              _formatRupiah(depositAmount),
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: labelColor)),
          ]),

          // Rincian per orang
          if (dpPerOrang > 0) ...[
            const SizedBox(height: 2),
            Text(
              '${_formatRupiah(dpPerOrang)} × ${depositAmount ~/ dpPerOrang} orang',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                color: labelColor.withValues(alpha: 0.7))),
          ],

          // Waktu konfirmasi jika sudah lunas
          if (isDpPaid && depositPaidAt != null) ...[
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.schedule, size: 12, color: labelColor.withValues(alpha: 0.6)),
              const SizedBox(width: 4),
              Text(
                'Dikonfirmasi: ${_formatDateTime(depositPaidAt)}',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: labelColor.withValues(alpha: 0.7))),
            ]),
          ],

          // Catatan dari staff (jika bukan URL bukti)
          if (depositNotes != null &&
              depositNotes.isNotEmpty &&
              !depositNotes.startsWith('Bukti transfer: http')) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(6)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 12, color: labelColor),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(depositNotes,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        color: labelColor))),
                ]),
            ),
          ],

          // Info "bukti sudah dikirim"
          if (isDpUploaded) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(6)),
              child: const Row(children: [
                Icon(Icons.access_time_outlined,
                    size: 13, color: Color(0xFF1565C0)),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Bukti transfer sudah diterima. Staff sedang memverifikasi pembayaranmu.',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: Color(0xFF1565C0)))),
              ]),
            ),
          ],

          // Tombol upload bukti — hanya muncul saat pending (belum upload)
          if (isDpPending) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Cara Bayar DP:',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: Color(0xFFE65100))),
                  const SizedBox(height: 4),
                  const Text(
                    '1. Transfer ke rekening restoran\n'
                    '2. Foto/screenshot bukti transfer\n'
                    '3. Upload di tombol di bawah',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: Color(0xFF6B7280),
                      height: 1.6)),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _uploadingProof
                          ? null
                          : () => _uploadProof(context, bookingId),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE65100),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        textStyle: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                      icon: _uploadingProof
                          ? const SizedBox(
                              width: 14, height: 14,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.upload_file_outlined, size: 16),
                      label: Text(_uploadingProof
                          ? 'Mengupload...'
                          : 'Upload Bukti Transfer'),
                    )),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: const Color(0xFF6B7280)),
        const SizedBox(width: 8),
        Text('$label: ',
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: Color(0xFF6B7280))),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A2E)))),
      ]);
}