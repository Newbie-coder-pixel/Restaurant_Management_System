import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../shared/models/booking_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/auth/providers/auth_provider.dart';
import 'widgets/booking_card.dart';
import 'widgets/add_booking_dialog.dart';
import 'widgets/edit_booking_dialog.dart';
import '../../../shared/widgets/app_drawer.dart';

class BookingScreen extends ConsumerStatefulWidget {
  const BookingScreen({super.key});
  @override
  ConsumerState<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends ConsumerState<BookingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  List<Map<String, dynamic>> _bookingsRaw = [];
  List<BookingModel> _bookings = [];
  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;
  bool _isHistoryLoading = false;

  Set<String> _datesWithBooking = {};

  String? _branchId;

  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  String _historyFilter = 'all';

  int _confirmedCount = 0;
  int _pendingCount = 0;
  int _seatedCount = 0;

  // ── Realtime ──
  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() {
      if (_tab.index == 1 && _history.isEmpty) _loadHistory();
      setState(() {});
    });
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.toLowerCase());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final staff = ref.read(currentStaffProvider);
    if (staff != null && _branchId == null) {
      _branchId = staff.branchId;
      _load();
      _loadDatesWithBooking();
      _setupRealtime(_branchId!);
    }
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    _tab.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Setup realtime listener untuk branch ini ──────────────
  void _setupRealtime(String branchId) {
    _realtimeChannel?.unsubscribe();

    _realtimeChannel = Supabase.instance.client
        .channel('staff-bookings-$branchId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'bookings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'branch_id',
            value: branchId,
          ),
          callback: (payload) {
            if (!mounted) return;
            _load();
            _loadDatesWithBooking();
            _showRealtimeNotif(
              icon: Icons.event_available,
              message: '📅 Booking baru dari ${payload.newRecord['customer_name'] ?? 'pelanggan'}',
              color: const Color(0xFF4CAF50),
            );
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'bookings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'branch_id',
            value: branchId,
          ),
          callback: (payload) {
            if (!mounted) return;
            final newRecord      = payload.newRecord;
            final oldRecord      = payload.oldRecord;
            final newDepositStatus = newRecord['deposit_status'] as String?;
            final oldDepositStatus = oldRecord['deposit_status'] as String?;
            final customerName   = newRecord['customer_name'] as String? ?? 'Pelanggan';

            _load();
            if (_history.isNotEmpty) _loadHistory();

            // Notif spesifik hanya saat deposit_status berubah
            if (newDepositStatus != oldDepositStatus) {
              if (newDepositStatus == 'uploaded') {
                _showRealtimeNotif(
                  icon: Icons.upload_file_outlined,
                  message: '💳 $customerName mengirim bukti transfer DP. Harap verifikasi.',
                  color: const Color(0xFF1976D2),
                  duration: const Duration(seconds: 6),
                );
              } else if (newDepositStatus == 'paid') {
                _showRealtimeNotif(
                  icon: Icons.check_circle_outline,
                  message: '✅ DP $customerName dikonfirmasi lunas.',
                  color: const Color(0xFF4CAF50),
                );
              }
            }
          },
        )
        .subscribe();
  }

  void _showRealtimeNotif({
    required IconData icon,
    required String message,
    required Color color,
    Duration duration = const Duration(seconds: 4),
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(icon, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(message,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w500))),
      ]),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      duration: duration,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Future<void> _load() async {
    if (_branchId == null) {
      final staff = ref.read(currentStaffProvider);
      _branchId = staff?.branchId;
    }
    if (_branchId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    if (mounted) setState(() => _isLoading = true);
    try {
      final dateStr = _fmtDate(_selectedDay);
      final res = await Supabase.instance.client
          .from('bookings')
          .select('*, restaurant_tables!bookings_table_id_fkey(table_number, capacity, floor_level)')
          .eq('branch_id', _branchId!)
          .eq('booking_date', dateStr)
          .order('booking_time');

      if (mounted) {
        final raw = (res as List).cast<Map<String, dynamic>>();
        final models = raw.map((e) => BookingModel.fromJson(e)).toList();
        int confirmed = 0, pending = 0, seated = 0;
        for (final b in models) {
          if (b.status == BookingStatus.confirmed) confirmed++;
          if (b.status == BookingStatus.pending) pending++;
          if (b.status == BookingStatus.seated) seated++;
        }
        setState(() {
          _bookingsRaw = raw;
          _bookings = models;
          _confirmedCount = confirmed;
          _pendingCount = pending;
          _seatedCount = seated;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('error load = $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadDatesWithBooking() async {
    if (_branchId == null) {
      final staff = ref.read(currentStaffProvider);
      _branchId = staff?.branchId;
    }
    if (_branchId == null) return;
    try {
      final firstDay = DateTime(_focusedDay.year, _focusedDay.month, 1);
      final lastDay = DateTime(_focusedDay.year, _focusedDay.month + 1, 0);
      final res = await Supabase.instance.client
          .from('bookings')
          .select('booking_date')
          .eq('branch_id', _branchId!)
          .gte('booking_date', _fmtDate(firstDay))
          .lte('booking_date', _fmtDate(lastDay))
          .inFilter('status', ['pending', 'confirmed', 'seated', 'waitlisted', 'completed']);
      if (mounted) {
        final dates = (res as List).map((e) => e['booking_date'] as String).toSet();
        setState(() => _datesWithBooking = dates);
      }
    } catch (e) {
      debugPrint('error loadDates = $e');
    }
  }

  Future<void> _loadHistory() async {
    if (_branchId == null) {
      final staff = ref.read(currentStaffProvider);
      _branchId = staff?.branchId;
    }
    if (_branchId == null) return;
    setState(() => _isHistoryLoading = true);
    try {
      final today = _fmtDate(DateTime.now());
      var q = Supabase.instance.client
          .from('bookings')
          .select('*, restaurant_tables!bookings_table_id_fkey(table_number)')
          .eq('branch_id', _branchId!);

      if (_historyFilter == 'completed') {
        q = q.eq('status', 'completed');
      } else if (_historyFilter == 'cancelled') {
        q = q.inFilter('status', ['cancelled', 'no_show']);
      } else {
        q = q.lt('booking_date', today);
      }

      final res = await q
          .order('booking_date', ascending: false)
          .order('booking_time', ascending: false)
          .limit(200);

      if (mounted) {
        setState(() {
          _history = (res as List).cast<Map<String, dynamic>>();
          _isHistoryLoading = false;
        });
      }
    } catch (e) {
      debugPrint('error history = $e');
      if (mounted) setState(() => _isHistoryLoading = false);
    }
  }

  Future<void> _updateStatus(String id, BookingStatus status) async {
    try {
      await Supabase.instance.client.from('bookings').update({
        'status': status == BookingStatus.noShow ? 'no_show' : status.name,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', id);
      await _load();
      if (_history.isNotEmpty) _loadHistory();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Gagal update status: $e'),
            backgroundColor: Colors.red));
      }
    }
  }

  // ── Tandai DP sudah dibayar ─────────────────────────────────
  Future<void> _markDpPaid(String bookingId) async {
    try {
      await Supabase.instance.client.from('bookings').update({
        'deposit_status': 'paid',
        'deposit_paid_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', bookingId);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('✅ DP berhasil ditandai lunas'),
            backgroundColor: Color(0xFF4CAF50)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Gagal update DP: $e'),
            backgroundColor: Colors.red));
      }
    }
  }

  // ── Notif WA ke staff via Edge Function ──────────────────
  Future<void> _notifyStaff(String bookingId) async {
    try {
      await Supabase.instance.client.functions.invoke(
        'notify-staff',
        body: {'booking_id': bookingId},
      );
      debugPrint('✅ Notif staff terkirim untuk booking $bookingId');
    } catch (e) {
      // Jangan crash app kalau notif gagal — cukup log
      debugPrint('⚠️ Notif staff gagal: $e');
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Color _statusColor(BookingStatus s) {
    switch (s) {
      case BookingStatus.pending:   return AppColors.reserved;
      case BookingStatus.confirmed: return AppColors.available;
      case BookingStatus.seated:    return AppColors.occupied;
      case BookingStatus.cancelled: return AppColors.textHint;
      case BookingStatus.noShow:    return AppColors.accent;
      case BookingStatus.completed: return AppColors.primary;
    }
  }

  Color _historyStatusColor(String? s) {
    switch (s) {
      case 'completed': return const Color(0xFF4CAF50);
      case 'cancelled': return const Color(0xFFE94560);
      case 'no_show':   return Colors.orange;
      case 'confirmed': return AppColors.available;
      case 'pending':   return AppColors.reserved;
      case 'seated':    return AppColors.occupied;
      default:          return AppColors.textHint;
    }
  }

  String _historyStatusLabel(String? s) {
    switch (s) {
      case 'completed':  return 'Selesai';
      case 'cancelled':  return 'Dibatalkan';
      case 'no_show':    return 'Tidak Hadir';
      case 'confirmed':  return 'Konfirmasi';
      case 'pending':    return 'Menunggu';
      case 'seated':     return 'Duduk';
      case 'waitlisted': return 'Waitlist';
      default:           return s ?? '-';
    }
  }

  List<BookingModel> get _filteredBookings {
    if (_searchQuery.isEmpty) return _bookings;
    return _bookings.where((b) =>
        b.customerName.toLowerCase().contains(_searchQuery) ||
        (b.customerPhone?.toLowerCase().contains(_searchQuery) ?? false) ||
        (b.confirmationCode.toLowerCase().contains(_searchQuery))).toList();
  }

  @override
  Widget build(BuildContext context) {
    final staff = ref.watch(currentStaffProvider);
    if (staff != null && _branchId == null) {
      _branchId = staff.branchId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _load();
        _loadDatesWithBooking();
      });
    }

    return Scaffold(
      drawer: const AppDrawer(),
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Booking Management'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        titleTextStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                _load();
                _loadDatesWithBooking();
              }),
        ],
        bottom: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: AppColors.accent,
          labelStyle: const TextStyle(
              fontFamily: 'Poppins', fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: 'Reservasi'),
            Tab(text: 'Riwayat'),
          ],
        ),
      ),
      floatingActionButton: _tab.index == 0
          ? FloatingActionButton.extended(
              onPressed: _showAddBooking,
              backgroundColor: AppColors.accent,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('Reservasi Baru',
                  style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600)),
            )
          : null,
      body: TabBarView(
        controller: _tab,
        children: [_buildReservasi(), _buildHistory()],
      ),
    );
  }

  Future<void> _showAddBooking() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => AddBookingDialog(branchId: _branchId ?? ''),
    );

    if (result != null && _branchId != null) {
      try {
        // Insert booking ke Supabase
        final inserted = await Supabase.instance.client
            .from('bookings')
            .insert({...result, 'branch_id': _branchId})
            .select()
            .single();

        // ── BARU: Kirim notif WA ke staff setelah booking berhasil disimpan ──
        await _notifyStaff(inserted['id'] as String);

        await _load();
        await _loadDatesWithBooking();

        // Tampilkan info DP jika ada
        if (mounted) {
          final depositAmount = result['deposit_amount'] as int? ?? 0;
          final depositStatus = result['deposit_status'] as String? ?? 'not_required';

          if (depositAmount > 0 && depositStatus == 'pending') {
            _showDpReminderSnackbar(
              customerName: result['customer_name'] as String? ?? '',
              depositAmount: depositAmount,
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('✅ Booking berhasil disimpan'),
                backgroundColor: Color(0xFF4CAF50)));
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Gagal simpan booking: $e'),
              backgroundColor: Colors.red));
        }
      }
    }
  }

  void _showDpReminderSnackbar({
    required String customerName,
    required int depositAmount,
  }) {
    final formatted = depositAmount.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    );
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.payments_outlined, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '✅ Booking $customerName tersimpan. Tagih DP Rp $formatted sebelum kedatangan.',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
          ),
        ),
      ]),
      backgroundColor: const Color(0xFFE65100),
      duration: const Duration(seconds: 5),
    ));
  }

  Widget _buildReservasi() {
    return Column(children: [
      _buildCalendar(),
      const Divider(height: 1),
      if (!_isLoading && _bookings.isNotEmpty) _buildStatsBar(),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: TextField(
          controller: _searchCtrl,
          decoration: InputDecoration(
            hintText: 'Cari nama, HP, atau kode konfirmasi...',
            hintStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () => _searchCtrl.clear())
                : null,
            contentPadding:
                const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(children: [
          Text(
              _searchQuery.isNotEmpty
                  ? '${_filteredBookings.length} dari ${_bookings.length} reservasi'
                  : '${_bookings.length} reservasi',
              style: AppTextStyles.heading3),
        ])),
      Expanded(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _filteredBookings.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                            _searchQuery.isNotEmpty
                                ? Icons.search_off
                                : Icons.event_available,
                            size: 64,
                            color: AppColors.textHint),
                        const SizedBox(height: 12),
                        Text(
                            _searchQuery.isNotEmpty
                                ? 'Tidak ditemukan'
                                : 'Tidak ada reservasi',
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                color: AppColors.textSecondary)),
                      ],
                    ))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                    itemCount: _filteredBookings.length,
                    itemBuilder: (_, i) {
                      final b = _filteredBookings[i];
                      final rawIdx = _bookings.indexOf(b);
                      final tableData = rawIdx >= 0
                          ? _bookingsRaw[rawIdx]['restaurant_tables']
                              as Map<String, dynamic>?
                          : null;
                      final rawItem = rawIdx >= 0 ? _bookingsRaw[rawIdx] : null;
                      return BookingCard(
                        booking: b,
                        tableData: tableData,
                        rawData: rawItem,
                        statusColor: _statusColor(b.status),
                        onStatusChange: (s) => _updateStatus(b.id, s),
                        onEdit: () => _showEditBooking(b, tableData),
                        onMarkDpPaid: () => _markDpPaid(b.id),
                      );
                    }),
      ),
    ]);
  }

  Widget _buildStatsBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        _statChip('Menunggu', _pendingCount, AppColors.reserved),
        const SizedBox(width: 8),
        _statChip('Konfirmasi', _confirmedCount, AppColors.available),
        const SizedBox(width: 8),
        _statChip('Duduk', _seatedCount, AppColors.occupied),
      ]),
    );
  }

  Widget _statChip(String label, int count, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.4))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text('$count $label',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ]),
      );

  Future<void> _showEditBooking(
      BookingModel booking, Map<String, dynamic>? tableData) async {
    // Cari rawData untuk booking ini
    final rawIdx = _bookings.indexOf(booking);
    final rawItem = rawIdx >= 0 ? _bookingsRaw[rawIdx] : null;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => EditBookingDialog(
        booking: booking,
        branchId: _branchId ?? '',
        rawData: rawItem, // ← pass rawData untuk pre-fill nilai DP
      ),
    );
    if (result != null) {
      try {
        await Supabase.instance.client
            .from('bookings')
            .update(
                {...result, 'updated_at': DateTime.now().toIso8601String()})
            .eq('id', booking.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('✅ Booking berhasil diperbarui'),
              backgroundColor: Color(0xFF4CAF50)));
        }
        await _load();
        await _loadDatesWithBooking();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Gagal update booking: $e'),
              backgroundColor: Colors.red));
        }
      }
    }
  }

  Widget _buildHistory() {
    return Row(children: [
      // ── Sidebar kiri ────────────────────────────────
      Container(
        width: 110,
        color: const Color(0xFF1A1A2E),
        child: Column(children: [
          const SizedBox(height: 16),
          for (final f in [
            ('all', 'Semua', Icons.list_alt_rounded),
            ('completed', 'Lunas', Icons.check_circle_outline),
            ('cancelled', 'Dibatalkan', Icons.cancel_outlined),
          ])
            GestureDetector(
              onTap: () {
                setState(() {
                  _historyFilter = f.$1;
                  _history = [];
                });
                _loadHistory();
              },
              child: Container(
                width: double.infinity,
                margin:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                decoration: BoxDecoration(
                  color: _historyFilter == f.$1
                      ? AppColors.accent.withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: _historyFilter == f.$1
                      ? Border.all(
                          color: AppColors.accent.withValues(alpha: 0.4))
                      : null,
                ),
                child: Column(children: [
                  Icon(f.$3,
                      size: 20,
                      color: _historyFilter == f.$1
                          ? AppColors.accent
                          : Colors.white54),
                  const SizedBox(height: 6),
                  Text(f.$2,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          fontWeight: _historyFilter == f.$1
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: _historyFilter == f.$1
                              ? AppColors.accent
                              : Colors.white54)),
                ]),
              ),
            ),
        ]),
      ),

      // ── List history ─────────────────────────────────
      Expanded(
        child: _isHistoryLoading
            ? const Center(child: CircularProgressIndicator())
            : _history.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.event_busy_outlined,
                            size: 64, color: AppColors.textHint),
                        SizedBox(height: 12),
                        Text('Tidak ada riwayat reservasi',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                color: AppColors.textSecondary)),
                      ],
                    ))
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _history.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final b = _history[i];
                      final status = b['status'] as String?;
                      final date = b['booking_date'] as String? ?? '-';
                      final rawTime = b['booking_time'] as String? ?? '-';
                      final time = rawTime.length >= 5
                          ? rawTime.substring(0, 5)
                          : rawTime;
                      final tableInfo =
                          b['restaurant_tables'] as Map<String, dynamic>?;
                      final tableNum =
                          tableInfo?['table_number']?.toString();

                      // ── Info DP di history ──
                      final depositAmount = b['deposit_amount'] as int? ?? 0;
                      final depositStatus = b['deposit_status'] as String?;
                      final showDpBadge = depositAmount > 0;

                      return Card(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: _historyStatusColor(status)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10)),
                            child: Icon(Icons.event_note,
                                color: _historyStatusColor(status),
                                size: 20)),
                          title: Text(b['customer_name'] ?? '-',
                              style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  '$date • $time • ${b['guest_count'] ?? 1} org'
                                  '${tableNum != null ? ' • $tableNum' : ''}',
                                  style: AppTextStyles.caption),
                              if (b['confirmation_code'] != null)
                                Text('# ${b['confirmation_code']}',
                                    style: const TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 10,
                                        color: AppColors.textHint)),
                              // Badge DP
                              if (showDpBadge) ...[
                                const SizedBox(height: 4),
                                _buildDpBadge(depositAmount, depositStatus),
                              ],
                            ],
                          ),
                          isThreeLine: true,
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _historyStatusColor(status)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: _historyStatusColor(status)
                                      .withValues(alpha: 0.4))),
                            child: Text(_historyStatusLabel(status),
                                style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: _historyStatusColor(status)))),
                        ));
                    }),
      ),
    ]);
  }

  Widget _buildDpBadge(int amount, String? status) {
    final isPaid     = status == 'paid' || status == 'applied';
    final isUploaded = status == 'uploaded';
    final Color color;
    final String label;
    final IconData icon;

    if (isPaid) {
      color = const Color(0xFF4CAF50);
      label = 'DP Lunas';
      icon  = Icons.check_circle_outline;
    } else if (isUploaded) {
      color = const Color(0xFF1976D2);
      label = 'Bukti Dikirim';
      icon  = Icons.hourglass_top_outlined;
    } else {
      color = const Color(0xFFFF9800);
      label = 'DP Belum Bayar';
      icon  = Icons.pending_outlined;
    }

    final formatted = amount.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text('$label • Rp $formatted',
              style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 10,
                  fontWeight: FontWeight.w600, color: color)),
        ]),
      ),
    ]);
  }

  Widget _buildCalendar() => TableCalendar(
        firstDay: DateTime.utc(2024),
        lastDay: DateTime.utc(2030),
        focusedDay: _focusedDay,
        selectedDayPredicate: (d) => isSameDay(d, _selectedDay),
        onDaySelected: (sel, foc) {
          setState(() {
            _selectedDay = sel;
            _focusedDay = foc;
          });
          _load();
        },
        onPageChanged: (focusedDay) {
          setState(() => _focusedDay = focusedDay);
          _loadDatesWithBooking();
        },
        calendarBuilders: CalendarBuilders(
          markerBuilder: (ctx, day, events) {
            final dateStr = _fmtDate(day);
            if (_datesWithBooking.contains(dateStr)) {
              return Positioned(
                bottom: 4,
                child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                        color: AppColors.accent, shape: BoxShape.circle)),
              );
            }
            return null;
          },
        ),
        calendarStyle: const CalendarStyle(
          selectedDecoration: BoxDecoration(
              color: AppColors.primary, shape: BoxShape.circle),
          todayDecoration: BoxDecoration(
              color: Color(0x99E94560), shape: BoxShape.circle),
          defaultTextStyle: TextStyle(fontFamily: 'Poppins'),
          weekendTextStyle:
              TextStyle(fontFamily: 'Poppins', color: AppColors.accent)),
        headerStyle: const HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
          titleTextStyle: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: 16)),
        calendarFormat: CalendarFormat.week,
      );
}