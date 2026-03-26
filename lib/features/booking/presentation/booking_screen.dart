import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../shared/models/booking_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/auth/providers/auth_provider.dart';
import 'widgets/booking_card.dart';
import 'widgets/add_booking_dialog.dart';
import '../../../shared/widgets/app_drawer.dart';

class BookingScreen extends ConsumerStatefulWidget {
  const BookingScreen({super.key});
  @override
  ConsumerState<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends ConsumerState<BookingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<BookingModel> _bookings = [];
  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;
  bool _isHistoryLoading = false;
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  String? _branchId;
  String _historyFilter = 'all';

  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() {
      if (_tab.index == 1 && _history.isEmpty) { _loadHistory(); }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    final staff = ref.read(currentStaffProvider);
    if (staff != null) {
      _branchId = staff.branchId; _initialized = true; _init();
    } else {
      _initialized = true;
      ref.listenManual(currentStaffProvider, (_, next) {
        if (next != null && _branchId == null && mounted) {
          setState(() => _branchId = next.branchId); _init();
        }
      });
    }
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _init() async { await _load(); }

  Future<void> _load() async {
    if (_branchId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    if (mounted) setState(() => _isLoading = true);
    try {
      final dateStr = "${_selectedDay.year}-"
          "${_selectedDay.month.toString().padLeft(2,'0')}-"
          "${_selectedDay.day.toString().padLeft(2,'0')}";
      final res = await Supabase.instance.client
          .from('bookings').select()
          .eq('branch_id', _branchId!).eq('booking_date', dateStr)
          .order('booking_time');
      if (mounted) {
        setState(() {
          _bookings = (res as List).map((e) => BookingModel.fromJson(e)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) { setState(() => _isLoading = false); }
    }
  }

  Future<void> _loadHistory() async {
    if (_branchId == null) return;
    setState(() => _isHistoryLoading = true);
    try {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      var q = Supabase.instance.client.from('bookings').select()
          .eq('branch_id', _branchId!);
      if (_historyFilter == 'completed') {
        q = q.eq('status', 'completed');
      } else if (_historyFilter == 'cancelled') {
        q = q.inFilter('status', ['cancelled', 'no_show']);
      } else {
        q = q.lt('booking_date', today);
      }
      final res = await q.order('booking_date', ascending: false).limit(200);
      if (mounted) {
        setState(() {
          _history = (res as List).cast<Map<String, dynamic>>();
          _isHistoryLoading = false;
        });
      }
    } catch (_) {
      if (mounted) { setState(() => _isHistoryLoading = false); }
    }
  }

  Future<void> _updateStatus(String id, BookingStatus status) async {
    await Supabase.instance.client
        .from('bookings').update({'status': status.name}).eq('id', id);
    await _load();
  }

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
      default:          return AppColors.textHint;
    }
  }

  String _historyStatusLabel(String? s) {
    switch (s) {
      case 'completed': return 'Selesai';
      case 'cancelled': return 'Dibatalkan';
      case 'no_show':   return 'Tidak Hadir';
      case 'confirmed': return 'Konfirmasi';
      default:          return s ?? '-';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Booking Management'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        titleTextStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 18,
          fontWeight: FontWeight.w600, color: Colors.white),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
        bottom: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: AppColors.accent,
          labelStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: 'Reservasi'),
            Tab(text: 'Riwayat'),
          ],
        ),
      ),
      floatingActionButton: _tab.index == 0 ? FloatingActionButton.extended(
        onPressed: () async {
          final result = await showDialog<Map<String, dynamic>>(
            context: context,
            builder: (_) => AddBookingDialog(branchId: _branchId ?? ''),
          );
          if (result != null && _branchId != null) {
            await Supabase.instance.client.from('bookings')
                .insert({...result, 'branch_id': _branchId});
            await _load();
          }
        },
        backgroundColor: AppColors.accent,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Reservasi Baru',
          style: TextStyle(color: Colors.white, fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
      ) : null,
      body: TabBarView(controller: _tab, children: [
        _buildReservasi(),
        _buildHistory(),
      ]),
    );
  }

  Widget _buildReservasi() {
    return Column(children: [
      _buildCalendar(),
      const Divider(height: 1),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Text('${_bookings.length} reservasi hari ini', style: AppTextStyles.heading3),
        ])),
      Expanded(
        child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _bookings.isEmpty
              ? const Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.event_available, size: 64, color: AppColors.textHint),
                    SizedBox(height: 12),
                    Text('Tidak ada reservasi',
                      style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)),
                  ]))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  itemCount: _bookings.length,
                  itemBuilder: (_, i) => BookingCard(
                    booking: _bookings[i],
                    statusColor: _statusColor(_bookings[i].status),
                    onStatusChange: (s) => _updateStatus(_bookings[i].id, s),
                  ))),
    ]);
  }

  Widget _buildHistory() {
    return Column(children: [
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final f in [('all','Semua Lalu'), ('completed','Selesai'), ('cancelled','Dibatalkan')])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(f.$2, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12)),
                  selected: _historyFilter == f.$1,
                  onSelected: (_) { setState(() { _historyFilter = f.$1; _history = []; }); _loadHistory(); },
                  selectedColor: AppColors.accent.withValues(alpha: 0.15),
                  checkmarkColor: AppColors.accent)),
          ]))),
      Expanded(
        child: _isHistoryLoading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
              ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.event_busy_outlined, size: 64, color: AppColors.textHint),
                  SizedBox(height: 12),
                  Text('Tidak ada riwayat reservasi',
                    style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary))]))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _history.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final b = _history[i];
                    final status = b['status'] as String?;
                    final date = b['booking_date'] as String? ?? '-';
                    final rawTime = b['booking_time'] as String? ?? '-';
                    final time = rawTime.length >= 5 ? rawTime.substring(0, 5) : rawTime;
                    return Card(
                      child: ListTile(
                        leading: Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: _historyStatusColor(status).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10)),
                          child: Icon(Icons.event_note,
                            color: _historyStatusColor(status), size: 22)),
                        title: Text(b['customer_name'] ?? '-',
                          style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
                        subtitle: Text('$date • $time • ${b['guest_count'] ?? 1} orang',
                          style: AppTextStyles.caption),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _historyStatusColor(status).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _historyStatusColor(status).withValues(alpha: 0.4))),
                          child: Text(_historyStatusLabel(status),
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                              fontWeight: FontWeight.w600, color: _historyStatusColor(status))))));
                  })),
    ]);
  }

  Widget _buildCalendar() => TableCalendar(
    firstDay: DateTime.utc(2024),
    lastDay: DateTime.utc(2030),
    focusedDay: _focusedDay,
    selectedDayPredicate: (d) => isSameDay(d, _selectedDay),
    onDaySelected: (sel, foc) {
      setState(() { _selectedDay = sel; _focusedDay = foc; });
      _load();
    },
    calendarStyle: const CalendarStyle(
      selectedDecoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
      todayDecoration: BoxDecoration(color: Color(0x99E94560), shape: BoxShape.circle),
      defaultTextStyle: TextStyle(fontFamily: 'Poppins'),
      weekendTextStyle: TextStyle(fontFamily: 'Poppins', color: AppColors.accent)),
    headerStyle: const HeaderStyle(
      formatButtonVisible: false, titleCentered: true,
      titleTextStyle: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 16)),
    calendarFormat: CalendarFormat.week,
  );
}