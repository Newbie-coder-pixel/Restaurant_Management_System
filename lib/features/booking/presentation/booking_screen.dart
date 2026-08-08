import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../shared/models/booking_model.dart';
import '../../../core/models/staff_role.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/widgets/staff_shell.dart';
import '../../../shared/widgets/diamond_pattern_painter.dart';
import 'widgets/booking_card.dart';
import 'widgets/add_booking_dialog.dart';
import 'widgets/edit_booking_dialog.dart';

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

  String? _branchId; // branch belonging to the logged-in staff

  // ── Branch filter (superadmin only) ──
  List<Map<String, dynamic>> _branches = [];
  String? _selectedBranchId; // null = "All" (superadmin only)

  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  String _historyFilter = 'all';

  int _confirmedCount = 0;
  int _pendingCount = 0;
  int _seatedCount = 0;
  int _waitlistedCount = 0;

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
      final isSuperadmin = staff.role == StaffRole.superadmin;
      if (isSuperadmin) {
        _selectedBranchId = null; // default "All"
        _loadBranches();
      } else {
        _selectedBranchId = _branchId;
      }
      _load();
      _loadDatesWithBooking();
      if (_selectedBranchId != null) _setupRealtime(_selectedBranchId!);
    }
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    _tab.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Setup realtime listener for this branch ───────────────
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
              message: '📅 New booking from ${payload.newRecord['customer_name'] ?? 'a customer'}',
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

            _load();
            if (_history.isNotEmpty) _loadHistory();
          },
        )
        .subscribe();
  }

  // ── Load all branches (superadmin only) ───────────────
  Future<void> _loadBranches() async {
    try {
      final res = await Supabase.instance.client
          .from('branches')
          .select('id, name')
          .eq('is_active', true)
          .order('name');
      if (mounted) {
        setState(() => _branches = (res as List).cast<Map<String, dynamic>>());
      }
    } catch (e) {
      debugPrint('error load branches = $e');
    }
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
      var q = Supabase.instance.client
          .from('bookings')
          .select('*, restaurant_tables!bookings_table_id_fkey(table_number, capacity, floor_level)');

      if (_selectedBranchId != null) {
        q = q.eq('branch_id', _selectedBranchId!);
      }
      // if _selectedBranchId is null (All) → don't filter by branch

      final res = await q
          .eq('booking_date', dateStr)
          .order('booking_time');

      if (mounted) {
        final raw = (res as List).cast<Map<String, dynamic>>();
        final models = raw.map((e) => BookingModel.fromJson(e)).toList();
        int confirmed = 0, pending = 0, seated = 0, waitlisted = 0;
        for (final b in models) {
          if (b.status == BookingStatus.confirmed)  confirmed++;
          if (b.status == BookingStatus.pending)    pending++;
          if (b.status == BookingStatus.seated)     seated++;
          if (b.status == BookingStatus.waitlisted) waitlisted++;
        }
        setState(() {
          _bookingsRaw      = raw;
          _bookings         = models;
          _confirmedCount   = confirmed;
          _pendingCount     = pending;
          _seatedCount      = seated;
          _waitlistedCount  = waitlisted;
          _isLoading        = false;
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
      var q = Supabase.instance.client
          .from('bookings')
          .select('booking_date');

      if (_selectedBranchId != null) {
        q = q.eq('branch_id', _selectedBranchId!);
      }

      final res = await q
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
          .select('*, restaurant_tables!bookings_table_id_fkey(table_number)');

      if (_selectedBranchId != null) {
        q = q.eq('branch_id', _selectedBranchId!);
      }

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
      // If staff manually promotes from waitlisted → use the special flow
      // that finds a table first before updating the status
      final raw = _bookingsRaw.firstWhere(
        (r) => r['id'] == id,
        orElse: () => {},
      );
      final currentStatus = raw.isNotEmpty ? raw['status'] as String? : null;

      if (status == BookingStatus.pending && currentStatus == 'waitlisted') {
        await _promoteWaitlistManual(id, raw);
        return;
      }

      await Supabase.instance.client.from('bookings').update({
        'status': status == BookingStatus.noShow ? 'no_show' : status.name,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', id);

      // If the booking is completed/cancelled/no-show → free the table + check the waitlist
      if (status == BookingStatus.completed ||
          status == BookingStatus.cancelled ||
          status == BookingStatus.noShow) {
        // Free the table: set it back to available & clear current_booking_id
        final tableId = raw.isNotEmpty ? raw['table_id'] as String? : null;
        if (tableId != null) {
          await Supabase.instance.client
              .from('restaurant_tables')
              .update({
                'status': 'available',
                'current_booking_id': null,
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('id', tableId);
        }
        if (raw.isNotEmpty) await _promoteWaitlist(raw);
      }

      await _load();
      if (_history.isNotEmpty) _loadHistory();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to update status: $e'),
            backgroundColor: Colors.red));
      }
    }
  }

  // ── Cancellation with a mandatory note ───────────────────
  Future<void> _cancelBooking(String id, String notes) async {
    try {
      final raw = _bookingsRaw.firstWhere(
        (r) => r['id'] == id,
        orElse: () => {},
      );

      await Supabase.instance.client.from('bookings').update({
        'status': 'cancelled',
        'cancellation_notes': notes,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', id);

      // Free the table if there is one
      final tableId = raw.isNotEmpty ? raw['table_id'] as String? : null;
      if (tableId != null) {
        await Supabase.instance.client
            .from('restaurant_tables')
            .update({
              'status': 'available',
              'current_booking_id': null,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', tableId);
      }
      if (raw.isNotEmpty) await _promoteWaitlist(raw);

      await _load();
      if (_history.isNotEmpty) _loadHistory();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('✅ Reservation cancelled successfully'),
            backgroundColor: Color(0xFF4CAF50)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to cancel booking: $e'),
            backgroundColor: Colors.red));
      }
    }
  }

  // ── Manual promote: staff taps "Promote to Pending" on the waitlist card ──
  // Find a table that's genuinely available for this booking slot, then assign it
  Future<void> _promoteWaitlistManual(
      String bookingId, Map<String, dynamic> raw) async {
    if (_branchId == null) return;
    try {
      final bookingDate = raw['booking_date'] as String?;
      final bookingTimeRaw = raw['booking_time'] as String? ?? '00:00:00';
      final duration = (raw['duration_minutes'] as int?) ?? 120;
      final guestCount = (raw['guest_count'] as int?) ?? 1;
      if (bookingDate == null) return;

      final tParts   = bookingTimeRaw.split(':');
      final newStart = int.parse(tParts[0]) * 60 + int.parse(tParts[1]);
      final newEnd   = newStart + duration;

      // Get all tables with sufficient capacity
      final tables = await Supabase.instance.client
          .from('restaurant_tables')
          .select('id, capacity, table_number')
          .eq('branch_id', _branchId!)
          .gte('capacity', guestCount)
          .order('capacity');

      if ((tables as List).isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('No table with sufficient capacity'),
              backgroundColor: Colors.orange));
        }
        return;
      }

      // Get active bookings on the same date to check for overlaps
      final existing = await Supabase.instance.client
          .from('bookings')
          .select('table_id, booking_time, duration_minutes')
          .eq('branch_id', _branchId!)
          .eq('booking_date', bookingDate)
          .inFilter('status', ['pending', 'confirmed', 'seated'])
          .neq('id', bookingId); // exclude this booking itself

      final bookedIds = (existing as List).where((b) {
        final rawT  = b['booking_time'] as String? ?? '00:00:00';
        final parts = rawT.split(':');
        final eStart = int.parse(parts[0]) * 60 + int.parse(parts[1]);
        final eDur   = (b['duration_minutes'] as int?) ?? 120;
        final eEnd   = eStart + eDur;
        return newStart < eEnd && newEnd > eStart;
      }).map((b) => b['table_id'] as String?).where((x) => x != null).toSet();

      final available = tables.where((t) => !bookedIds.contains(t['id'])).toList();

      if (available.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('All tables are full for this slot, can\'t promote yet'),
              backgroundColor: Colors.orange));
        }
        return;
      }

      // Assign the smallest sufficient table + promote to pending
      final chosenTable = available.first;
      await Supabase.instance.client.from('bookings').update({
        'table_id':   chosenTable['id'],
        'status':     'pending',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', bookingId);

      if (mounted) {
        _showRealtimeNotif(
          icon: Icons.arrow_upward_outlined,
          message:
              '✅ Promoted to pending — Table ${chosenTable['table_number']}',
          color: const Color(0xFF7B1FA2),
        );
      }

      await _load();
      if (_history.isNotEmpty) _loadHistory();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to promote waitlist: $e'),
            backgroundColor: Colors.red));
      }
    }
  }

  // ── Promote waitlist: find a waitlisted guest whose slot overlaps the newly freed booking ──
  Future<void> _promoteWaitlist(Map<String, dynamic> freedBooking) async {
    if (_branchId == null) return;

    try {
      final freedTableId = freedBooking['table_id'] as String?;
      final freedDate    = freedBooking['booking_date'] as String?;
      final freedTimeRaw = freedBooking['booking_time'] as String? ?? '00:00:00';
      final freedDur     = (freedBooking['duration_minutes'] as int?) ?? 120;
      if (freedTableId == null || freedDate == null) return;

      // Compute the newly freed slot in minutes
      final tParts     = freedTimeRaw.split(':');
      final freedStart = int.parse(tParts[0]) * 60 + int.parse(tParts[1]);
      final freedEnd   = freedStart + freedDur;

      // Get all waitlisted bookings in the branch + same date, ordered by longest wait
      final waitlistRes = await Supabase.instance.client
          .from('bookings')
          .select('id, booking_time, duration_minutes, guest_count')
          .eq('branch_id', _branchId!)
          .eq('booking_date', freedDate)
          .eq('status', 'waitlisted')
          .order('created_at'); // FIFO — first in, first promoted

      if ((waitlistRes as List).isEmpty) return;

      // Check the capacity of the newly freed table
      final tableRes = await Supabase.instance.client
          .from('restaurant_tables')
          .select('capacity')
          .eq('id', freedTableId)
          .maybeSingle();
      if (tableRes == null) return;
      final tableCapacity = (tableRes['capacity'] as int?) ?? 0;

      // Find the first waitlist candidate whose:
      // 1. Slot overlaps with the newly freed slot
      // 2. Guest count ≤ table capacity
      Map<String, dynamic>? candidate;
      for (final w in waitlistRes) {
        final wTimeRaw = w['booking_time'] as String? ?? '00:00:00';
        final wParts   = wTimeRaw.split(':');
        final wStart   = int.parse(wParts[0]) * 60 + int.parse(wParts[1]);
        final wDur     = (w['duration_minutes'] as int?) ?? 120;
        final wEnd     = wStart + wDur;
        final wGuests  = (w['guest_count'] as int?) ?? 1;

        final overlaps = wStart < freedEnd && wEnd > freedStart;
        if (overlaps && wGuests <= tableCapacity) {
          candidate = w;
          break;
        }
      }

      if (candidate == null) return;

      // Promote: assign the table + change the status to pending
      await Supabase.instance.client.from('bookings').update({
        'table_id':   freedTableId,
        'status':     'pending',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', candidate['id'] as String);

      debugPrint('✅ Waitlist promoted: ${candidate['id']} → table $freedTableId');

      if (mounted) {
        _showRealtimeNotif(
          icon: Icons.queue_outlined,
          message: '🎉 Guest from the waitlist was successfully promoted to pending!',
          color: const Color(0xFF7B1FA2),
          duration: const Duration(seconds: 5),
        );
      }
    } catch (e) {
      debugPrint('⚠️ Promote waitlist failed: $e');
    }
  }

  // ── WhatsApp notification to staff via Edge Function ─────
  Future<void> _notifyStaff(String bookingId) async {
    try {
      await Supabase.instance.client.functions.invoke(
        'notify-staff',
        body: {'booking_id': bookingId},
      );
      debugPrint('✅ Staff notification sent for booking $bookingId');
    } catch (e) {
      // Don't crash the app if the notification fails — just log it
      debugPrint('⚠️ Staff notification failed: $e');
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Color _statusColor(BookingStatus s) {
    switch (s) {
      case BookingStatus.pending:    return AppColors.reserved;
      case BookingStatus.confirmed:  return AppColors.available;
      case BookingStatus.seated:     return AppColors.occupied;
      case BookingStatus.cancelled:  return AppColors.textHint;
      case BookingStatus.noShow:     return AppColors.accent;
      case BookingStatus.completed:  return AppColors.primary;
      case BookingStatus.waitlisted: return const Color(0xFF7B1FA2);
    }
  }

  Color _historyStatusColor(String? s) {
    switch (s) {
      case 'completed': return const Color(0xFF4CAF50);
      case 'cancelled': return AppColors.accent;
      case 'no_show':   return Colors.orange;
      case 'confirmed': return AppColors.available;
      case 'pending':   return AppColors.reserved;
      case 'seated':    return AppColors.occupied;
      default:          return AppColors.textHint;
    }
  }

  String _historyStatusLabel(String? s) {
    switch (s) {
      case 'completed':  return 'Completed';
      case 'cancelled':  return 'Cancelled';
      case 'no_show':    return 'No Show';
      case 'confirmed':  return 'Confirmed';
      case 'pending':    return 'Pending';
      case 'seated':     return 'Seated';
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
    final isSuperadmin = staff != null && staff.role == StaffRole.superadmin;

    if (staff != null && _branchId == null) {
      _branchId = staff.branchId;
      _selectedBranchId = isSuperadmin ? null : _branchId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (isSuperadmin) _loadBranches();
        _load();
        _loadDatesWithBooking();
      });
    }

    final canFilterBranch = isSuperadmin;

    return StaffShell(
      pageTitle: 'Bookings & Reservations',
      activeRoute: AppRoutes.booking,
      floatingActionButton: _tab.index == 0
          ? FloatingActionButton.extended(
              onPressed: _showAddBooking,
              backgroundColor: AppColors.accent,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('New Reservation',
                  style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600)),
            )
          : null,
      topBarActions: [
        // ── BRANCH FILTER DROPDOWN (superadmin only) ──
        if (canFilterBranch)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _selectedBranchId,
                isDense: true,
                icon: const Icon(Icons.keyboard_arrow_down, size: 16, color: AppColors.textSecondary),
                style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 12, color: AppColors.textPrimary),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All Branches',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 12))),
                  ..._branches.map((b) => DropdownMenuItem<String?>(
                        value: b['id'] as String,
                        child: Text(b['name'] as String,
                            style: const TextStyle(fontFamily: 'Poppins', fontSize: 12)))),
                ],
                onChanged: (val) {
                  setState(() {
                    _selectedBranchId = val;
                    _bookings = [];
                    _history = [];
                    _datesWithBooking = {};
                  });
                  _load();
                  _loadDatesWithBooking();
                  if (_history.isNotEmpty) _loadHistory();
                  if (val != null) {
                    _setupRealtime(val);
                  } else {
                    _realtimeChannel?.unsubscribe();
                    _realtimeChannel = null;
                  }
                },
              ),
            ),
          ),
        IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
            onPressed: () {
              _load();
              _loadDatesWithBooking();
            }),
        const SizedBox(width: 4),
      ],
      body: Column(
        children: [
          _buildTabSelector(),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [_buildReservasi(), _buildHistory()],
            ),
          ),
        ],
      ),
    );
  }

  // ── Pill-style tab selector (Reservations / History) ────────────────────
  Widget _buildTabSelector() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm + 2),
        ),
        child: Row(
          children: [
            _tabPill('Reservations', 0),
            _tabPill('History', 1),
          ],
        ),
      ),
    );
  }

  Widget _tabPill(String label, int index) {
    final selected = _tab.index == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab.animateTo(index)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : AppColors.textSecondary)),
        ),
      ),
    );
  }


  Future<void> _showAddBooking() async {
    // For "All" branches, use the staff's own branchId
    final targetBranch = _selectedBranchId ?? _branchId ?? '';
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => AddBookingDialog(branchId: targetBranch),
    );

    if (result != null && _branchId != null) {
      try {
        // Insert the booking into Supabase
        final inserted = await Supabase.instance.client
            .from('bookings')
            .insert({...result, 'branch_id': targetBranch})
            .select()
            .single();

        // ── NEW: Send a WhatsApp notification to staff after the booking is saved ──
        await _notifyStaff(inserted['id'] as String);

        await _load();
        await _loadDatesWithBooking();

        // Show confirmation
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('✅ Booking saved successfully'),
              backgroundColor: Color(0xFF4CAF50)));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Failed to save booking: $e'),
              backgroundColor: Colors.red));
        }
      }
    }
  }

  Map<String, dynamic>? _tableDataFor(BookingModel b) {
    final rawIdx = _bookings.indexOf(b);
    return rawIdx >= 0
        ? _bookingsRaw[rawIdx]['restaurant_tables'] as Map<String, dynamic>?
        : null;
  }

  // Opens the full BookingCard (with edit/cancel/status actions) as a dialog
  // — same widget/logic used before, just presented on demand instead of
  // inline, so the compact grid tiles below can stay lightweight.
  void _openBookingDetail(BookingModel b) {
    final tableData = _tableDataFor(b);
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440, maxHeight: 640),
          child: SingleChildScrollView(
            child: BookingCard(
              booking: b,
              tableData: tableData,
              statusColor: _statusColor(b.status),
              onStatusChange: (s) => _updateStatus(b.id, s),
              onCancel: (notes) => _cancelBooking(b.id, notes),
              onEdit: () {
                Navigator.pop(context);
                _showEditBooking(b, tableData);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReservasi() {
    return Column(children: [
      _buildCalendar(),
      const Divider(height: 1, color: AppColors.border),
      if (!_isLoading && _bookings.isNotEmpty) _buildStatsBar(),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: TextField(
          controller: _searchCtrl,
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Search name, phone, or confirmation code...',
            hintStyle: const TextStyle(
                fontFamily: 'Poppins', fontSize: 13, color: AppColors.textHint),
            prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.textSecondary),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () => _searchCtrl.clear())
                : null,
            contentPadding:
                const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                borderSide: const BorderSide(color: AppColors.border)),
            filled: true,
            fillColor: AppColors.surface,
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(children: [
          Text(
              _searchQuery.isNotEmpty
                  ? '${_filteredBookings.length} of ${_bookings.length} reservations'
                  : '${_bookings.length} reservations',
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
                                ? 'No results found'
                                : 'No reservations yet',
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                color: AppColors.textSecondary)),
                      ],
                    ))
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: _filteredBookings.map((b) => _ReservationTile(
                        booking: b,
                        tableNumber: _tableDataFor(b)?['table_number']?.toString(),
                        statusColor: _statusColor(b.status),
                        statusLabel: _statusLabel(b.status),
                        onTap: () => _openBookingDetail(b),
                      )).toList(),
                    ),
                  ),
      ),
    ]);
  }

  String _statusLabel(BookingStatus s) {
    switch (s) {
      case BookingStatus.pending:    return 'Pending';
      case BookingStatus.confirmed:  return 'Confirmed';
      case BookingStatus.seated:     return 'Seated';
      case BookingStatus.cancelled:  return 'Cancelled';
      case BookingStatus.noShow:     return 'No Show';
      case BookingStatus.completed:  return 'Completed';
      case BookingStatus.waitlisted: return 'Waitlist';
    }
  }

  Widget _buildStatsBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        _statChip('Pending',   _pendingCount,    AppColors.reserved),
        const SizedBox(width: 8),
        _statChip('Confirmed', _confirmedCount,  AppColors.available),
        const SizedBox(width: 8),
        _statChip('Seated',    _seatedCount,     AppColors.occupied),
        if (_waitlistedCount > 0) ...[
          const SizedBox(width: 8),
          _statChip('Waitlist', _waitlistedCount, const Color(0xFF7B1FA2)),
        ],
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
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => EditBookingDialog(
        booking: _bookingsRaw.firstWhere((r) => r['id'] == booking.id, orElse: () => {}),
        branchId: _branchId ?? '',
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
              content: Text('✅ Booking updated successfully'),
              backgroundColor: Color(0xFF4CAF50)));
        }
        await _load();
        await _loadDatesWithBooking();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Failed to update booking: $e'),
              backgroundColor: Colors.red));
        }
      }
    }
  }

  Widget _buildHistory() {
    return Row(children: [
      // ── Left sidebar ──────────────────────────────────
      Container(
        width: 110,
        color: AppColors.primary,
        child: Column(children: [
          const SizedBox(height: 16),
          for (final f in [
            ('all', 'All', Icons.list_alt_rounded),
            ('completed', 'Completed', Icons.check_circle_outline),
            ('cancelled', 'Cancelled', Icons.cancel_outlined),
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

      // ── History list ──────────────────────────────────
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
                        Text('No reservation history yet',
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
                                  '$date • $time • ${b['guest_count'] ?? 1} guests'
                                  '${tableNum != null ? ' • $tableNum' : ''}',
                                  style: AppTextStyles.caption),
                              if (b['confirmation_code'] != null)
                                Text('# ${b['confirmation_code']}',
                                    style: const TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 10,
                                        color: AppColors.textHint)),
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

  // ── Boxed day-strip cell (WED / 12 style), swipeable week-at-a-time via
  // TableCalendar's built-in gestures — header/weekday-row hidden so only
  // the strip of day boxes shows, matching the floor-plan-family design.
  Widget _dayCell(DateTime day, {required bool selected}) {
    final today = isSameDay(day, DateTime.now());
    const weekdayLabels = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    final hasBooking = _datesWithBooking.contains(_fmtDate(day));
    return Container(
      width: 58,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: selected ? AppColors.primary : AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(
            color: selected
                ? AppColors.primary
                : (today ? AppColors.primary.withValues(alpha: 0.5) : AppColors.border),
            width: today && !selected ? 1.5 : 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(weekdayLabels[day.weekday - 1],
              style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700,
                  color: selected ? Colors.white70 : AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text('${day.day}',
              style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : AppColors.textPrimary)),
          const SizedBox(height: 3),
          Container(
            width: 5, height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hasBooking
                  ? (selected ? Colors.white : AppColors.accent)
                  : Colors.transparent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendar() => Container(
        color: AppColors.surface,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: TableCalendar(
          firstDay: DateTime.utc(2024),
          lastDay: DateTime.utc(2030),
          focusedDay: _focusedDay,
          headerVisible: false,
          daysOfWeekVisible: false,
          rowHeight: 78,
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
            defaultBuilder: (ctx, day, focusedDay) => _dayCell(day, selected: false),
            todayBuilder: (ctx, day, focusedDay) => _dayCell(day, selected: false),
            outsideBuilder: (ctx, day, focusedDay) => _dayCell(day, selected: false),
            selectedBuilder: (ctx, day, focusedDay) => _dayCell(day, selected: true),
          ),
          calendarFormat: CalendarFormat.week,
        ),
      );
}

// ── Compact reservation tile for the grid view. Tapping opens the full
// BookingCard (with edit/cancel/status actions) in a dialog — this tile is
// purely a read-only summary, all interaction logic stays in BookingCard.
class _ReservationTile extends StatelessWidget {
  final BookingModel booking;
  final String? tableNumber;
  final Color statusColor;
  final String statusLabel;
  final VoidCallback onTap;

  const _ReservationTile({
    required this.booking,
    required this.tableNumber,
    required this.statusColor,
    required this.statusLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final time = booking.bookingTime.length >= 5
        ? booking.bookingTime.substring(0, 5)
        : booking.bookingTime;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 240,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header: time + status badge, textured background ──
            Stack(
              children: [
                const Positioned.fill(child: CustomPaint(painter: DiamondPatternPainter())),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(time,
                          style: const TextStyle(
                              fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w800,
                              color: AppColors.primary)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(statusLabel,
                            style: const TextStyle(
                                fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700,
                                color: Colors.white)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 1, color: AppColors.border),
            // ── Body: name, guests, table ──
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(booking.customerName,
                      style: const TextStyle(
                          fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),
                  Row(children: [
                    const Icon(Icons.people_alt_outlined, size: 15, color: AppColors.textSecondary),
                    const SizedBox(width: 5),
                    Text('${booking.guestCount} PAX',
                        style: const TextStyle(
                            fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary)),
                    const SizedBox(width: 14),
                    Icon(Icons.chair_alt_outlined, size: 15,
                        color: tableNumber != null ? AppColors.textSecondary : AppColors.textHint),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(tableNumber != null ? 'Table $tableNumber' : 'Unassigned',
                          style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 12,
                              color: tableNumber != null ? AppColors.textSecondary : AppColors.textHint),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}