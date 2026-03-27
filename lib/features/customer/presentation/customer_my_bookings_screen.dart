// lib/features/customer/presentation/customer_my_bookings_screen.dart
//
// CHANGES v2:
// - _BookingCard: tambah tombol "Hubungi Kami" untuk booking confirmed/pending
//   → buka WhatsApp ke nomor restoran (ambil dari branch.phone di Supabase)
//   → fallback ke tel: jika WhatsApp tidak tersedia
// - Tidak ada cancel langsung — customer harus hubungi staff

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// ── Provider booking milik user yang login ────────────────────────
final _myBookingsProvider =
    StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return const Stream.empty();

  return Supabase.instance.client
      .from('bookings')
      .stream(primaryKey: ['id'])
      .eq('customer_user_id', user.id)
      .order('booking_date', ascending: false)
      .map((rows) => rows.cast<Map<String, dynamic>>());
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

// ── Provider phone per branch (untuk tombol hubungi) ─────────────
final _branchPhoneProvider =
    FutureProvider.autoDispose.family<String?, String>((ref, branchId) async {
  try {
    final res = await Supabase.instance.client
        .from('branches')
        .select('phone')
        .eq('id', branchId)
        .single();
    return (res['phone']) as String?;
  } catch (_) {
    return null;
  }
});

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

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final isDesktop = screenW > 700;

    return Column(children: [
      // Tab bar
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

      // Tab body
      Expanded(
        child: TabBarView(
          controller: _tabCtrl,
          children: [
            _BookingForm(
              isDesktop: isDesktop,
              onSuccess: () => _tabCtrl.animateTo(1),
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
  const _BookingForm(
      {required this.isDesktop, required this.onSuccess});

  @override
  ConsumerState<_BookingForm> createState() => _BookingFormState();
}

class _BookingFormState extends ConsumerState<_BookingForm> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

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
          user.userMetadata?['name'] as String? ??
          '';
      _nameCtrl.text = name;
      _phoneCtrl.text = user.phone ?? '';
    }
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
      '',
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
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
    final openParts = open.split(':');
    final closeParts = close.split(':');
    final openHour = int.tryParse(openParts[0]) ?? 10;
    final closeHour = int.tryParse(closeParts[0]) ?? 22;

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
    if (_selectedBranchId == null) {
      _err('Pilih cabang dulu');
      return;
    }
    if (_selectedDate == null) {
      _err('Pilih tanggal');
      return;
    }
    if (_selectedTime == null) {
      _err('Pilih jam kedatangan');
      return;
    }
    if (_nameCtrl.text.trim().isEmpty) {
      _err('Nama wajib diisi');
      return;
    }
    if (_phoneCtrl.text.trim().isEmpty) {
      _err('Nomor HP wajib diisi');
      return;
    }

    setState(() => _submitting = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      final dateStr =
          _selectedDate!.toIso8601String().substring(0, 10);
      final timeStr = _formatTime(_selectedTime!);
      final notes = _notesCtrl.text.trim();

      await Supabase.instance.client.from('bookings').insert({
        'branch_id': _selectedBranchId,
        'customer_user_id': user?.id,
        'customer_name': _nameCtrl.text.trim(),
        'customer_phone': _phoneCtrl.text.trim(),
        'guest_count': _guestCount,
        'booking_date': dateStr,
        'booking_time': timeStr,
        'status': 'confirmed',
        'source': 'customer_web',
        if (notes.isNotEmpty) 'special_requests': notes,
      });

      if (!mounted) return;
      _showSuccess();
      widget.onSuccess();
    } catch (e) {
      _err('Gagal membuat reservasi: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _err(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(fontFamily: 'Poppins')),
      backgroundColor: const Color(0xFFE94560),
      behavior: SnackBarBehavior.floating));
  }

  void _showSuccess() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
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
          const Text(
            'Reservasi kamu sudah dikonfirmasi.\nCek tab "Reservasi Saya" untuk detailnya.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: Color(0xFF6B7280))),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Color(0xFF0F3460),
                    fontWeight: FontWeight.w600))),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final branchesAsync = ref.watch(_branchesProvider);

    return branchesAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (branches) {
        if (branches.length == 1 && _selectedBranchId == null) {
          _selectedBranchId = branches[0]['id'] as String;
        }

        final selectedBranch = branches.isEmpty
            ? null
            : branches
                .where((b) => b['id'] == _selectedBranchId)
                .cast<Map<String, dynamic>?>()
                .firstOrNull;

        final openTime =
            (selectedBranch?['opening_time'] as String?)
                    ?.substring(0, 5) ??
                '10:00';
        final closeTime =
            (selectedBranch?['closing_time'] as String?)
                    ?.substring(0, 5) ??
                '22:00';

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
                items: branches
                    .map((b) => DropdownMenuItem<String>(
                        value: b['id'] as String,
                        child: Text(b['name'] as String,
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 14))))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _selectedBranchId = v)),
            const SizedBox(height: 20),

            if (widget.isDesktop)
              Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                        child: _dateField(openTime, closeTime)),
                    const SizedBox(width: 16),
                    Expanded(
                        child: _timeField(openTime, closeTime)),
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
              Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
              style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 14),
              decoration: _inputDeco(
                  'Contoh: alergi kacang, kursi tinggi untuk bayi...',
                  null)),
            const SizedBox(height: 28),

            GestureDetector(
              onTap: _submitting
                  ? null
                  : () => _submit(branches),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFE94560),
                      Color(0xFFFF6B6B)
                    ]),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(
                    color: const Color(0xFFE94560)
                        .withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4))]),
                child: Center(
                    child: _submitting
                        ? const SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2))
                        : const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.calendar_today,
                                  color: Colors.white, size: 18),
                              SizedBox(width: 8),
                              Text('Buat Reservasi',
                                  style: TextStyle(
                                      fontFamily: 'Poppins',
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight:
                                          FontWeight.w700)),
                            ])))),
            const SizedBox(height: 32),
          ],
        );

        if (widget.isDesktop) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 680),
                child: formContent)));
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: formContent);
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
    padding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
  }) =>
      Container(
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
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    color: Colors.grey)),
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
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 14),
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
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 14),
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
        child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.people_outline,
                  size: 18, color: Color(0xFF6B7280)),
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

  Widget _counterBtn(IconData icon, VoidCallback onTap) =>
      GestureDetector(
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
        style: const TextStyle(
            fontFamily: 'Poppins', fontSize: 14),
        decoration: _inputDeco(
          'Nama sesuai identitas',
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
        style: const TextStyle(
            fontFamily: 'Poppins', fontSize: 14),
        decoration: _inputDeco(
          '081234567890',
          const Icon(Icons.phone_outlined,
              size: 18, color: Color(0xFF6B7280)))),
    ]);

  InputDecoration _inputDeco(String hint, Widget? prefix) =>
      InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            color: Colors.grey),
        prefixIcon: prefix,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Color(0xFFE5E7EB))),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Color(0xFFE5E7EB))),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
              color: Color(0xFF0F3460), width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 14));
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
      loading: () =>
          const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
          child: Text('Error: $e',
              style: const TextStyle(fontFamily: 'Poppins'))),
      data: (bookings) {
        if (bookings.isEmpty) return _emptyState();

        final content = ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: bookings.length,
          itemBuilder: (_, i) => _BookingCard(
            booking: bookings[i], isDesktop: isDesktop));

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
              fontFamily: 'Poppins',
              fontSize: 13,
              color: Color(0xFF6B7280))),
    ]));
}

// ─────────────────────────────────────────────────────────────────
// KARTU BOOKING
// CHANGES: tambah tombol "Hubungi Kami" untuk status confirmed/pending
// ─────────────────────────────────────────────────────────────────
class _BookingCard extends ConsumerWidget {
  final Map<String, dynamic> booking;
  final bool isDesktop;
  const _BookingCard(
      {required this.booking, required this.isDesktop});

  String get _status => booking['status'] as String? ?? 'pending';
  String? get _branchId => booking['branch_id'] as String?;

  Color get _color => switch (_status) {
    'confirmed' => const Color(0xFF4CAF50),
    'cancelled' => const Color(0xFFE94560),
    'completed' => const Color(0xFF0F3460),
    _ => const Color(0xFFFF9800),
  };

  String get _label => switch (_status) {
    'confirmed' => 'Dikonfirmasi',
    'cancelled' => 'Dibatalkan',
    'completed' => 'Selesai',
    _ => 'Menunggu',
  };

  IconData get _icon => switch (_status) {
    'confirmed' => Icons.check_circle_outline,
    'cancelled' => Icons.cancel_outlined,
    'completed' => Icons.done_all,
    _ => Icons.schedule,
  };

  // Apakah booking masih aktif (bisa hubungi staff)
  bool get _isActive =>
      _status == 'pending' || _status == 'confirmed';

  String _fmtDate(String? raw) {
    if (raw == null) return '-';
    try {
      final d = DateTime.parse(raw);
      const months = [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
        'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
      ];
      return '${d.day} ${months[d.month]} ${d.year}';
    } catch (_) {
      return raw;
    }
  }

  // Buka WhatsApp ke nomor restoran
  // Format pesan sudah include detail booking
  Future<void> _contactStaff(
      BuildContext context, String? phone) async {
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nomor kontak cabang tidak tersedia. '
            'Silakan hubungi kami langsung di lokasi.',
            style: TextStyle(fontFamily: 'Poppins')),
          backgroundColor: Color(0xFF0F3460),
          behavior: SnackBarBehavior.floating));
      return;
    }

    // Bersihkan nomor → format internasional
    final cleaned = phone
        .replaceAll(RegExp(r'[^\d+]'), '')
        .replaceFirst(RegExp(r'^0'), '62');

    final date = _fmtDate(booking['booking_date'] as String?);
    final time = (booking['booking_time'] as String?)
            ?.substring(0, 5) ?? '-';
    final guests = booking['guest_count'] ?? 1;
    final name = booking['customer_name'] as String? ?? '';

    final msg = Uri.encodeComponent(
      'Halo, saya ingin menghubungi terkait reservasi saya:\n\n'
      '👤 Nama: $name\n'
      '📅 Tanggal: $date\n'
      '🕐 Jam: $time WIB\n'
      '👥 Tamu: $guests orang\n\n'
      'Mohon bantuannya. Terima kasih 🙏');

    final waUrl = Uri.parse('https://wa.me/$cleaned?text=$msg');
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
  Widget build(BuildContext context, WidgetRef ref) {
    // Ambil phone dari branch
    final phoneAsync = _branchId != null
        ? ref.watch(_branchPhoneProvider(_branchId!))
        : const AsyncValue<String?>.data(null);
    final branchPhone = phoneAsync.valueOrNull;

    final branchName =
        (booking['branches'] as Map?)?['name'] ?? 'Restoran';
    final date = _fmtDate(booking['booking_date'] as String?);
    final time =
        (booking['booking_time'] as String?)?.substring(0, 5) ?? '-';
    final guests = booking['guest_count'] ?? 1;
    final notes = booking['special_requests'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 10,
          offset: const Offset(0, 3))]),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header status
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                color: _color.withValues(alpha: 0.08),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16))),
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20)),
                    child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6, height: 6,
                            decoration: BoxDecoration(
                              color: _color,
                              shape: BoxShape.circle)),
                          const SizedBox(width: 4),
                          Text('Live',
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: _color)),
                        ])),
              ])),

            // Body
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
                          _row(Icons.calendar_today_outlined,
                              'Tanggal', date),
                          const SizedBox(height: 8),
                          _row(Icons.access_time_outlined,
                              'Jam', '$time WIB'),
                        ])),
                        const SizedBox(width: 24),
                        Expanded(child: Column(children: [
                          _row(Icons.people_outline,
                              'Tamu', '$guests orang'),
                          if (notes != null &&
                              notes.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _row(Icons.note_outlined,
                                'Catatan', notes),
                          ],
                        ])),
                      ])
                    else ...[
                      _row(Icons.calendar_today_outlined,
                          'Tanggal', date),
                      const SizedBox(height: 8),
                      _row(Icons.access_time_outlined,
                          'Jam', '$time WIB'),
                      const SizedBox(height: 8),
                      _row(Icons.people_outline,
                          'Tamu', '$guests orang'),
                      if (notes != null && notes.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _row(Icons.note_outlined,
                            'Catatan', notes),
                      ],
                    ],

                    // ── Tombol Hubungi Kami (hanya untuk booking aktif)
                    if (_isActive) ...[
                      const SizedBox(height: 16),
                      const Divider(height: 1),
                      const SizedBox(height: 12),

                      // Info cancel
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF8E1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: const Color(0xFFFFCC02)
                                  .withValues(alpha: 0.4))),
                        child: const Row(children: [
                          Icon(Icons.info_outline,
                              size: 14,
                              color: Color(0xFFD97706)),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Ingin mengubah atau membatalkan? '
                              'Hubungi staff kami.',
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 11,
                                  color: Color(0xFFD97706)))),
                        ])),
                      const SizedBox(height: 10),

                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _contactStaff(context, branchPhone),
                          icon: const Icon(Icons.chat_rounded,
                              size: 18, color: Color(0xFF25D366)),
                          label: const Text('Hubungi Kami',
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1A1A2E))),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                vertical: 12),
                            side: const BorderSide(
                                color: Color(0xFFE5E7EB)),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(10))),
                        )),
                    ],
                  ])),
          ]));
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