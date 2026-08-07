import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';

// ── User's bookings provider — JOIN branches ───────────────────────
final _refreshTriggerProvider = StateProvider<int>((ref) => 0);

final _myBookingsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((
  ref,
) async {
  ref.watch(_refreshTriggerProvider);

  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return [];

  final res = await Supabase.instance.client
      .from('bookings')
      .select(
        '*, branches(id, name, phone), restaurant_tables!bookings_table_id_fkey(table_number)',
      )
      .eq('customer_user_id', user.id)
      .order('booking_date', ascending: false);

  return (res as List).cast<Map<String, dynamic>>();
});

// ── Active branches list provider ──────────────────────────────────
final _branchesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final res = await Supabase.instance.client
          .from('branches')
          .select('id, name, address, phone, opening_time, closing_time')
          .eq('is_active', true)
          .order('name');
      return (res as List).cast<Map<String, dynamic>>();
    });

// ── Validate Indonesian phone number ─────────────────────────────
String? _validatePhone(String phone) {
  final cleaned = phone.replaceAll(RegExp(r'\s|-'), '');
  if (cleaned.isEmpty) return 'Phone number is required';
  if (!RegExp(r'^(\+62|62|0)[0-9]+$').hasMatch(cleaned)) {
    return 'Phone number can only contain digits';
  }
  String normalized = cleaned;
  if (normalized.startsWith('+62')) normalized = '0${normalized.substring(3)}';
  if (normalized.startsWith('62')) normalized = '0${normalized.substring(2)}';
  if (!normalized.startsWith('08')) {
    return 'Phone number must start with 08 (example: 081234567890)';
  }
  if (normalized.length < 10 || normalized.length > 13) {
    return 'Phone number must be 10–13 digits';
  }
  return null;
}

// ─────────────────────────────────────────────────────────────────
// MAIN SCREEN
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
    _showAnnouncement();
  }

  void _showAnnouncement() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          title: const Row(
            children: [
              Text('⏰', style: TextStyle(fontSize: 28)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Important Notice',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFFB923C).withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: const Text(
                  '📌 Please arrive at least 30 minutes before your chosen reservation time.\n\n'
                  'Arriving more than 15 minutes late may cause the reservation to be automatically cancelled.',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    height: 1.6,
                    color: Color(0xFF92400E),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  child: const Text('I Understand'),
                ),
              ),
            ),
          ],
        ),
      );
    });
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
        '🎉 Your reservation is confirmed! Your table is ready.',
        const Color(0xFF10B981),
        Icons.check_circle,
      ),
      'cancelled' => (
        '❌ Your reservation has been cancelled.',
        const Color(0xFFEF4444),
        Icons.cancel,
      ),
      'waitlisted' => (
        '⏳ All tables are full, you have been added to the waitlist.',
        const Color(0xFF8B5CF6),
        Icons.hourglass_top,
      ),
      'seated' => (
        '🍽️ Welcome! Please head to your table.',
        const Color(0xFF06B6D4),
        Icons.restaurant,
      ),
      _ => (
        'Reservation status updated.',
        const Color(0xFF3B82F6),
        Icons.info,
      ),
    };

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final isDesktop = screenW > 700;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TabBar(
              controller: _tabCtrl,
              labelStyle: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
              ),
              labelColor: AppColors.accent,
              unselectedLabelColor: const Color(0xFF64748B),
              indicatorColor: AppColors.accent,
              indicatorWeight: 3,
              indicatorSize: TabBarIndicatorSize.label,
              tabs: const [
                Tab(
                  icon: Icon(Icons.add_circle_outline, size: 20),
                  text: 'New Reservation',
                ),
                Tab(
                  icon: Icon(Icons.calendar_month_outlined, size: 20),
                  text: 'My Reservations',
                ),
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
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// NEW RESERVATION FORM
// ─────────────────────────────────────────────────────────────────
class _BookingForm extends ConsumerStatefulWidget {
  final bool isDesktop;
  final VoidCallback onSuccess;
  const _BookingForm({required this.isDesktop, required this.onSuccess});

  @override
  ConsumerState<_BookingForm> createState() => _BookingFormState();
}

class _BookingFormState extends ConsumerState<_BookingForm> {
  final _nameCtrl = TextEditingController();
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
      final name =
          user.userMetadata?['full_name'] as String? ??
          user.userMetadata?['name'] as String? ??
          '';
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
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
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
            primary: AppColors.accent,
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: Color(0xFF1E293B),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime(String open, String close) async {
    final openParts = open.split(':');
    final closeParts = close.split(':');
    final openHour = int.tryParse(openParts[0]) ?? 10;
    final closeHour = int.tryParse(closeParts[0]) ?? 22;

    // Use local time (WIB) — not UTC
    final now = DateTime.now().toLocal();
    final selectedOrToday = _selectedDate ?? now;
    final isToday =
        selectedOrToday.year == now.year &&
        selectedOrToday.month == now.month &&
        selectedOrToday.day == now.day;
    final minHour = isToday ? now.hour + (now.minute > 0 ? 1 : 0) : openHour;

    // Handle closing time crossing midnight (e.g. closing at 01:00)
    // A small closeHour (0-4) is treated as past midnight = valid until early morning
    final bool closesAfterMidnight = closeHour < openHour;

    final initialHour =
        (_selectedTime != null && _selectedTime!.hour >= minHour)
        ? _selectedTime!.hour
        : (minHour <= (closesAfterMidnight ? 23 : closeHour - 1) ? minHour : openHour);

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initialHour, minute: 0),
      initialEntryMode: TimePickerEntryMode.dial,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.accent,
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: Color(0xFF1E293B),
          ),
        ),
        child: child!,
      ),
    );

    if (picked == null || !mounted) return;

    // Validation: time cannot be before minHour (today only)
    if (isToday && picked.hour < minHour) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(
                Icons.lock_clock_outlined,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Time ${picked.hour.toString().padLeft(2, '0')}:00 has already passed. Choose ${minHour.toString().padLeft(2, '0')}:00 or later.',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    // Validation: time must be within operating hours
    // If closing past midnight (e.g. 01:00), valid: >= openHour OR <= closeHour
    // If closing before midnight, valid: >= openHour AND < closeHour
    final bool outOfRange = closesAfterMidnight
        ? (picked.hour < openHour && picked.hour > closeHour)
        : (picked.hour < openHour || picked.hour >= closeHour);

    if (outOfRange) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Time must be between $open – $close WIB',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
          ),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    setState(() => _selectedTime = picked);
  }

  Future<void> _submit(List<Map<String, dynamic>> branches) async {
    if (_selectedBranchId == null) {
      _err('Please select a branch first');
      return;
    }
    if (_selectedDate == null) {
      _err('Please select a date');
      return;
    }
    if (_selectedTime == null) {
      _err('Please select an arrival time');
      return;
    }
    if (_nameCtrl.text.trim().isEmpty) {
      _err('Name is required');
      return;
    }

    final phoneErr = _validatePhone(_phoneCtrl.text.trim());
    if (phoneErr != null) {
      setState(() => _phoneError = phoneErr);
      _err(phoneErr);
      return;
    }
    setState(() => _phoneError = null);

    setState(() => _submitting = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      final dateStr = _selectedDate!.toIso8601String().substring(0, 10);
      final timeStr = _formatTime(_selectedTime!);
      final notes = _notesCtrl.text.trim();

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
            'branch_id': _selectedBranchId,
            'customer_user_id': user?.id,
            'customer_name': _nameCtrl.text.trim(),
            'customer_phone': normalizedPhone,
            'guest_count': _guestCount,
            'booking_date': dateStr,
            'booking_time': timeStr,
            'status': 'pending',
            'source': 'app',
            if (notes.isNotEmpty) 'special_requests': notes,
          })
          .select('id')
          .single();

      final bookingId = bookingRes['id'] as String;

      final result =
          await Supabase.instance.client.rpc(
                'assign_table_to_booking',
                params: {
                  'p_booking_id': bookingId,
                  'p_branch_id': _selectedBranchId,
                  'p_guest_count': _guestCount,
                  'p_booking_date': dateStr,
                  'p_booking_time': '$timeStr:00',
                },
              )
              as Map<String, dynamic>;

      if (!mounted) return;

      final success = result['success'] as bool;
      final tableNumber = result['table_number'] as String?;

      if (success) {
        _showSuccess(tableNumber: tableNumber);
      } else {
        _showWaitlisted();
      }
    } catch (e) {
      _err('Failed to create reservation: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _err(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
        ),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showSuccess({String? tableNumber}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFD1FAE5),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF10B981).withValues(alpha: 0.2),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: const Icon(
                Icons.check_circle,
                color: Color(0xFF10B981),
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Reservation Successful!',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 12),
            if (tableNumber != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFD1FAE5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF10B981).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.table_restaurant,
                      size: 20,
                      color: Color(0xFF059669),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Table $tableNumber is ready',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF059669),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const Text(
              'Your reservation has been confirmed.\nCheck the "My Reservations" tab for details.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  Navigator.of(dialogCtx).pop();
                  widget.onSuccess();
                },
                child: const Text(
                  'OK',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showWaitlisted() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: const Icon(
                Icons.schedule,
                color: Color(0xFFD97706),
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Added to Waitlist',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'All tables are currently full for that time.\n'
              'You have been added to the waitlist. Staff will contact your phone number if a table becomes available.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  Navigator.of(dialogCtx).pop();
                  widget.onSuccess();
                },
                child: const Text(
                  'Got It',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final branchesAsync = ref.watch(_branchesProvider);

    return branchesAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      ),
      error: (e, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Error: $e',
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: Color(0xFFEF4444),
              ),
            ),
          ],
        ),
      ),
      data: (branches) {
        if (branches.length == 1 && _selectedBranchId == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _selectedBranchId = branches[0]['id'] as String);
            }
          });
        }

        final selectedBranch = branches
            .where((b) => b['id'] == _selectedBranchId)
            .cast<Map<String, dynamic>?>()
            .firstOrNull;

        final openTime =
            (selectedBranch?['opening_time'] as String?)?.substring(0, 5) ??
            '10:00';
        final closeTime =
            (selectedBranch?['closing_time'] as String?)?.substring(0, 5) ??
            '22:00';

        Widget formContent = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            _sectionLabel('Choose Branch', Icons.store_outlined),
            if (branches.length == 1)
              _infoChip(Icons.store, branches[0]['name'] as String)
            else
              _dropdown(
                value: _selectedBranchId,
                hint: 'Choose a branch',
                items: branches
                    .map(
                      (b) => DropdownMenuItem<String>(
                        value: b['id'] as String,
                        child: Text(
                          b['name'] as String,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _selectedBranchId = v),
              ),
            const SizedBox(height: 24),
            if (widget.isDesktop)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _dateField(openTime, closeTime)),
                  const SizedBox(width: 16),
                  Expanded(child: _timeField(openTime, closeTime)),
                ],
              )
            else ...[
              _dateField(openTime, closeTime),
              const SizedBox(height: 20),
              _timeField(openTime, closeTime),
            ],
            const SizedBox(height: 24),
            _sectionLabel('Number of Guests', Icons.people_outline),
            _guestPicker(),
            const SizedBox(height: 24),
            if (widget.isDesktop)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _nameField()),
                  const SizedBox(width: 16),
                  Expanded(child: _phoneField()),
                ],
              )
            else ...[
              _nameField(),
              const SizedBox(height: 16),
              _phoneField(),
            ],
            const SizedBox(height: 24),
            _sectionLabel('Special Notes', Icons.note_add_outlined),
            TextField(
              controller: _notesCtrl,
              maxLines: 3,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
              decoration: _inputDeco(
                'Example: nut allergy, high chair for baby...',
                null,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _submitting ? null : () => _submit(branches),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.calendar_today, size: 20),
                        SizedBox(width: 10),
                        Text('Create Reservation'),
                      ],
                    ),
            ),
            const SizedBox(height: 32),
          ],
        );

        if (widget.isDesktop) {
          return Container(
            color: const Color(0xFFF8FAFC),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 720),
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 40,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: formContent,
                ),
              ),
            ),
          );
        }
        return Container(
          color: const Color(0xFFF8FAFC),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: formContent,
            ),
          ),
        );
      },
    );
  }

  Widget _sectionLabel(String label, IconData icon) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Icon(icon, size: 18, color: AppColors.accent),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E293B),
          ),
        ),
      ],
    ),
  );

  Widget _infoChip(IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppColors.accent.withValues(alpha: 0.1),
          AppColors.accent.withValues(alpha: 0.05),
        ],
      ),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
    ),
    child: Row(
      children: [
        Icon(icon, size: 20, color: AppColors.accent),
        const SizedBox(width: 12),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.accent,
          ),
        ),
      ],
    ),
  );

  Widget _dropdown({
    required String? value,
    required String hint,
    required List<DropdownMenuItem<String>> items,
    required void Function(String?) onChanged,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        isExpanded: true,
        hint: Text(
          hint,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14,
            color: Color(0xFF94A3B8),
          ),
        ),
        items: items,
        onChanged: onChanged,
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: Color(0xFF1E293B),
        ),
      ),
    ),
  );

  Widget _dateField(String open, String close) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _sectionLabel('Arrival Date', Icons.calendar_today_outlined),
      GestureDetector(
        onTap: _pickDate,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _selectedDate != null
                  ? AppColors.accent
                  : const Color(0xFFE2E8F0),
              width: _selectedDate != null ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 20,
                color: _selectedDate != null
                    ? AppColors.accent
                    : const Color(0xFF94A3B8),
              ),
              const SizedBox(width: 12),
              Text(
                _selectedDate != null
                    ? _formatDate(_selectedDate!)
                    : 'Select date',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _selectedDate != null
                      ? const Color(0xFF1E293B)
                      : const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _timeField(String open, String close) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _sectionLabel('Arrival Time', Icons.access_time_outlined),
      GestureDetector(
        onTap: () => _pickTime(open, close),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _selectedTime != null
                  ? AppColors.accent
                  : const Color(0xFFE2E8F0),
              width: _selectedTime != null ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.access_time_outlined,
                size: 20,
                color: _selectedTime != null
                    ? AppColors.accent
                    : const Color(0xFF94A3B8),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _selectedTime != null
                      ? '${_formatTime(_selectedTime!)} WIB'
                      : 'Select time',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _selectedTime != null
                        ? const Color(0xFF1E293B)
                        : const Color(0xFF94A3B8),
                  ),
                ),
              ),
              Text(
                '$open – $close',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _guestPicker() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    ),
    child: Row(
      children: [
        _counterBtn(Icons.remove, () {
          if (_guestCount > 1) setState(() => _guestCount--);
        }),
        const SizedBox(width: 16),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.people_outline,
                size: 20,
                color: Color(0xFF64748B),
              ),
              const SizedBox(width: 12),
              Text(
                '$_guestCount guest(s)',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        _counterBtn(Icons.add, () {
          if (_guestCount < 20) setState(() => _guestCount++);
        }),
      ],
    ),
  );

  Widget _counterBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: Colors.white, size: 22),
    ),
  );

  Widget _nameField() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _sectionLabel('Full Name', Icons.person_outline),
      TextField(
        controller: _nameCtrl,
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
        decoration: _inputDeco(
          'Name as on your ID',
          const Icon(Icons.person_outline, size: 20, color: Color(0xFF94A3B8)),
        ),
      ),
    ],
  );

  Widget _phoneField() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _sectionLabel('Phone Number', Icons.phone_outlined),
      TextField(
        controller: _phoneCtrl,
        keyboardType: TextInputType.phone,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[\d+\s\-]')),
        ],
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
        onChanged: (v) => setState(() => _phoneError = null),
        onEditingComplete: () {
          setState(() => _phoneError = _validatePhone(_phoneCtrl.text.trim()));
        },
        decoration: InputDecoration(
          hintText: '081234567890',
          hintStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            color: Color(0xFF94A3B8),
          ),
          prefixIcon: const Icon(
            Icons.phone_outlined,
            size: 20,
            color: Color(0xFF94A3B8),
          ),
          errorText: _phoneError,
          errorStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 11,
            color: Color(0xFFEF4444),
          ),
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.accent, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
      ),
      const Padding(
        padding: EdgeInsets.only(top: 8, left: 4),
        child: Text(
          'Format: 08xxxxxxxxxx (10–13 digits)',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 11,
            color: Color(0xFF94A3B8),
          ),
        ),
      ),
    ],
  );

  InputDecoration _inputDeco(String hint, Widget? prefix) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(
      fontFamily: 'Poppins',
      fontSize: 13,
      color: Color(0xFF94A3B8),
    ),
    prefixIcon: prefix,
    filled: true,
    fillColor: const Color(0xFFF8FAFC),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.accent, width: 2),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
  );
}

// ─────────────────────────────────────────────────────────────────
// BOOKING HISTORY
// ─────────────────────────────────────────────────────────────────
class _BookingHistory extends ConsumerStatefulWidget {
  final bool isDesktop;
  const _BookingHistory({required this.isDesktop});

  @override
  ConsumerState<_BookingHistory> createState() => _BookingHistoryState();
}

class _BookingHistoryState extends ConsumerState<_BookingHistory> {
  // 'all' | 'active' | 'done' | 'cancelled'
  String _filter = 'active';

  static const _activeStatuses = {
    'pending',
    'confirmed',
    'waitlisted',
    'seated',
  };
  static const _doneStatuses = {'completed'};
  static const _cancelledStatuses = {'cancelled', 'no_show'};

  /// Old bookings (done/cancelled) > 30 days are hidden automatically
  bool _isVisible(Map<String, dynamic> b) {
    final status = b['status'] as String? ?? 'pending';
    final isFinished =
        _doneStatuses.contains(status) || _cancelledStatuses.contains(status);
    if (!isFinished) return true;
    final raw = b['booking_date'] as String?;
    if (raw == null) return false;
    try {
      final date = DateTime.parse(raw);
      return DateTime.now().difference(date).inDays <= 30;
    } catch (_) {
      return true;
    }
  }

  List<Map<String, dynamic>> _applyFilter(List<Map<String, dynamic>> all) {
    final visible = all.where(_isVisible).toList();
    switch (_filter) {
      case 'active':
        return visible
            .where((b) => _activeStatuses.contains(b['status']))
            .toList();
      case 'done':
        return visible
            .where((b) => _doneStatuses.contains(b['status']))
            .toList();
      case 'cancelled':
        return visible
            .where((b) => _cancelledStatuses.contains(b['status']))
            .toList();
      default:
        return visible;
    }
  }

  int _count(List<Map<String, dynamic>> all, String filter) {
    final visible = all.where(_isVisible).toList();
    switch (filter) {
      case 'active':
        return visible
            .where((b) => _activeStatuses.contains(b['status']))
            .length;
      case 'done':
        return visible.where((b) => _doneStatuses.contains(b['status'])).length;
      case 'cancelled':
        return visible
            .where((b) => _cancelledStatuses.contains(b['status']))
            .length;
      default:
        return visible.length;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = ref.watch(_myBookingsProvider);

    return bookingsAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      ),
      error: (e, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Error: $e',
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: Color(0xFFEF4444),
              ),
            ),
          ],
        ),
      ),
      data: (bookings) {
        final filtered = _applyFilter(bookings);

        return Column(
          children: [
            // ── Filter chips ──────────────────────────────────────
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterChip(
                      label: 'Active',
                      icon: Icons.radio_button_checked,
                      color: const Color(0xFF10B981),
                      count: _count(bookings, 'active'),
                      selected: _filter == 'active',
                      onTap: () => setState(() => _filter = 'active'),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Done',
                      icon: Icons.done_all,
                      color: const Color(0xFF3B82F6),
                      count: _count(bookings, 'done'),
                      selected: _filter == 'done',
                      onTap: () => setState(() => _filter = 'done'),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Cancelled',
                      icon: Icons.cancel_outlined,
                      color: const Color(0xFFEF4444),
                      count: _count(bookings, 'cancelled'),
                      selected: _filter == 'cancelled',
                      onTap: () => setState(() => _filter = 'cancelled'),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'All',
                      icon: Icons.list_alt_outlined,
                      color: const Color(0xFF64748B),
                      count: _count(bookings, 'all'),
                      selected: _filter == 'all',
                      onTap: () => setState(() => _filter = 'all'),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),

            // ── Info banner for done/cancelled filters ─────────────
            if (_filter == 'done' || _filter == 'cancelled' || _filter == 'all')
              Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 14,
                      color: Color(0xFF94A3B8),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'History older than 30 days is hidden automatically',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // ── List ─────────────────────────────────────────────
            Expanded(
              child: filtered.isEmpty
                  ? _emptyState(_filter)
                  : widget.isDesktop
                  ? Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: _buildList(filtered),
                      ),
                    )
                  : _buildList(filtered),
            ),
          ],
        );
      },
    );
  }

  Widget _buildList(List<Map<String, dynamic>> items) => ListView.builder(
    padding: const EdgeInsets.all(16),
    itemCount: items.length,
    itemBuilder: (_, i) =>
        _BookingCard(booking: items[i], isDesktop: widget.isDesktop),
  );

  Widget _emptyState(String filter) {
    final (icon, title, subtitle) = switch (filter) {
      'active' => (
        Icons.calendar_today_outlined,
        'No Active Bookings',
        'Create a new reservation in the "New Reservation" tab.',
      ),
      'done' => (
        Icons.done_all,
        'No Completed History Yet',
        'Completed booking history will appear here.',
      ),
      'cancelled' => (
        Icons.cancel_outlined,
        'Nothing Cancelled',
        'Great, no bookings have been cancelled 😊',
      ),
      _ => (
        Icons.calendar_today_outlined,
        'No Reservations Yet',
        'Create a reservation in the "New Reservation" tab.',
      ),
    };
    final color = switch (filter) {
      'active' => const Color(0xFF10B981),
      'done' => const Color(0xFF3B82F6),
      'cancelled' => const Color(0xFFEF4444),
      _ => AppColors.accent,
    };
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  color.withValues(alpha: 0.12),
                  color.withValues(alpha: 0.05),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 44),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: Color(0xFF64748B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// FILTER CHIP WIDGET
// ─────────────────────────────────────────────────────────────────
class _FilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color : Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: selected ? color : const Color(0xFFE2E8F0),
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: selected ? Colors.white : color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : const Color(0xFF334155),
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.3)
                      : color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : color,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// BOOKING CARD
// ─────────────────────────────────────────────────────────────────
class _BookingCard extends StatefulWidget {
  final Map<String, dynamic> booking;
  final bool isDesktop;
  const _BookingCard({required this.booking, required this.isDesktop});

  @override
  State<_BookingCard> createState() => _BookingCardState();
}

class _BookingCardState extends State<_BookingCard> {
  Map<String, dynamic> get booking => widget.booking;
  bool get isDesktop => widget.isDesktop;

  String get _status => booking['status'] as String? ?? 'pending';

  Color get _color => switch (_status) {
    'confirmed' => const Color(0xFF10B981),
    'cancelled' => const Color(0xFFEF4444),
    'completed' => const Color(0xFF3B82F6),
    'no_show' => const Color(0xFFF59E0B),
    'waitlisted' => const Color(0xFF8B5CF6),
    'seated' => const Color(0xFF06B6D4),
    _ => const Color(0xFFF59E0B),
  };

  String get _label => switch (_status) {
    'confirmed' => 'Confirmed',
    'cancelled' => 'Cancelled',
    'completed' => 'Completed',
    'no_show' => 'No Show',
    'waitlisted' => 'Waitlisted',
    'seated' => 'Dining',
    _ => 'Pending',
  };

  IconData get _icon => switch (_status) {
    'confirmed' => Icons.check_circle_outline,
    'cancelled' => Icons.cancel_outlined,
    'completed' => Icons.done_all,
    'no_show' => Icons.person_off_outlined,
    'waitlisted' => Icons.hourglass_top_outlined,
    'seated' => Icons.restaurant_outlined,
    _ => Icons.schedule,
  };

  bool get _isActive =>
      _status == 'pending' ||
      _status == 'confirmed' ||
      _status == 'waitlisted' ||
      _status == 'seated';

  String _fmtDate(String? raw) {
    if (raw == null) return '-';
    try {
      final d = DateTime.parse(raw);
      const months = [
        '',
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${d.day} ${months[d.month]} ${d.year}';
    } catch (_) {
      return raw;
    }
  }

  Future<void> _contactStaff(BuildContext context, String? phone) async {
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Branch contact number not available. Please contact us directly.',
            style: TextStyle(fontFamily: 'Poppins'),
          ),
          backgroundColor: const Color(0xFF3B82F6),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    final cleaned = phone
        .replaceAll(RegExp(r'[^\d+]'), '')
        .replaceFirst(RegExp(r'^0'), '62');

    final date = _fmtDate(booking['booking_date'] as String?);
    final time = (booking['booking_time'] as String?)?.substring(0, 5) ?? '-';
    final guests = booking['guest_count'] ?? 1;
    final name = booking['customer_name'] as String? ?? '';

    final msg = Uri.encodeComponent(
      'Hello, I would like to reach out about my reservation:\n\n'
      '👤 Name: $name\n'
      '📅 Date: $date\n'
      '🕐 Time: $time WIB\n'
      '👥 Guests: $guests\n\n'
      'Thank you for your help 🙏',
    );

    final waUrl = Uri.parse('https://wa.me/$cleaned?text=$msg');
    final telUrl = Uri.parse('tel:$phone');

    if (await canLaunchUrl(waUrl)) {
      await launchUrl(waUrl, mode: LaunchMode.externalApplication);
    } else if (await canLaunchUrl(telUrl)) {
      await launchUrl(telUrl);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not open WhatsApp. Number: $phone',
              style: const TextStyle(fontFamily: 'Poppins'),
            ),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final branchData = booking['branches'] as Map<String, dynamic>?;
    final branchName = branchData?['name'] as String? ?? 'Restaurant';
    final branchPhone = branchData?['phone'] as String?;

    final tableId = booking['table_id'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            decoration: BoxDecoration(
              color: _color.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Icon(_icon, color: _color, size: 20),
                const SizedBox(width: 10),
                Text(
                  _label,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: _color,
                  ),
                ),
                const Spacer(),
                if (_isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Live',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _color,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.store_outlined,
                        size: 18,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        branchName,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (isDesktop)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _infoGrid()),
                      const SizedBox(width: 24),
                      Expanded(child: _infoGrid2()),
                    ],
                  )
                else
                  _infoGrid(),
                if (tableId != null && _status == 'confirmed') ...[
                  const SizedBox(height: 16),
                  _infoBanner(
                    icon: Icons.table_restaurant,
                    text:
                        'Table ${booking['restaurant_tables']?['table_number'] ?? ''} is ready',
                    color: const Color(0xFF10B981),
                    bgColor: const Color(0xFFD1FAE5),
                  ),
                ],
                if (_status == 'waitlisted') ...[
                  const SizedBox(height: 16),
                  _infoBanner(
                    icon: Icons.hourglass_top_outlined,
                    text:
                        'You are on the waitlist. Staff will contact you if a table becomes available.\nWill be contacted via: ${booking['customer_phone']}',
                    color: const Color(0xFF8B5CF6),
                    bgColor: const Color(0xFFF3E8FF),
                  ),
                ],

                // ──────────────────────────────────────────
                if (_isActive) ...[
                  const SizedBox(height: 20),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Color(0xFFD97706),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Want to change or cancel? Contact our staff.',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFFD97706),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _contactStaff(context, branchPhone),
                      icon: const Icon(
                        Icons.chat_rounded,
                        size: 20,
                        color: Color(0xFF25D366),
                      ),
                      label: const Text(
                        'Contact Us via WhatsApp',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(
                          color: Color(0xFFE2E8F0),
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoGrid() {
    final date = _fmtDate(widget.booking['booking_date'] as String?);
    final time =
        (widget.booking['booking_time'] as String?)?.substring(0, 5) ?? '-';
    final guests = widget.booking['guest_count'] ?? 1;
    return Column(
      children: [
        _infoRow(Icons.calendar_today_outlined, 'Date', date),
        const SizedBox(height: 12),
        _infoRow(Icons.access_time_outlined, 'Time', '$time WIB'),
        const SizedBox(height: 12),
        _infoRow(Icons.people_outline, 'Guests', '$guests'),
      ],
    );
  }

  Widget _infoGrid2() => Column(
    children: [
      if (widget.booking['special_requests'] != null &&
          widget.booking['special_requests'].toString().isNotEmpty) ...[
        _infoRow(
          Icons.note_outlined,
          'Notes',
          widget.booking['special_requests'].toString(),
        ),
      ],
    ],
  );

  Widget _infoRow(IconData icon, String label, String value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: const Color(0xFF94A3B8)),
      const SizedBox(width: 12),
      SizedBox(
        width: 70,
        child: Text(
          '$label:',
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF64748B),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          value,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Color(0xFF1E293B),
          ),
        ),
      ),
    ],
  );

  Widget _infoBanner({
    required IconData icon,
    required String text,
    required Color color,
    required Color bgColor,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    ),
  );
}