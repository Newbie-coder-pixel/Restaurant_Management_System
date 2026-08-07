import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _buildTopBar(),
          Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(bottom: BorderSide(color: AppColors.border)),
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
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
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

  // ── TOP BAR (Pusaka header, shared visual language with other customer screens) ──
  Widget _buildTopBar() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.go('/customer'),
            child: const Text(
              'Pusaka',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 28),
          Expanded(
            child: Row(
              children: [
                _NavLink(label: 'Menu', onTap: () => context.go('/customer')),
                const SizedBox(width: 24),
                _NavLink(
                  label: 'Locations',
                  onTap: () => context.go('/customer'),
                ),
                const SizedBox(width: 24),
                _NavLink(
                  label: 'Our Story',
                  onTap: () => context.go('/customer'),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => context.go('/customer/checkout'),
            child: const Icon(
              Icons.shopping_cart_outlined,
              color: AppColors.textPrimary,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }
}

class _NavLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _NavLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
        ),
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
            primary: AppColors.primary,
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: Color(0xFF1E293B),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
        // A previously chosen time may no longer be valid for the new date
        // (e.g. it was only valid because "today" was further along) — the
        // time slot grid recomputes availability from _selectedDate, so drop
        // a stale selection rather than silently keep an invalid one.
        _selectedTime = null;
      });
    }
  }

  // Hours the branch is open, expanded into whole-hour slots. Handles the
  // closing-past-midnight case (e.g. open 18:00, close 01:00) the same way
  // the old showTimePicker validation did.
  List<int> _availableHours(String open, String close) {
    final openHour = int.tryParse(open.split(':')[0]) ?? 10;
    final closeHour = int.tryParse(close.split(':')[0]) ?? 22;
    final closesAfterMidnight = closeHour < openHour;
    final hours = <int>[];
    if (closesAfterMidnight) {
      for (var h = openHour; h <= 23; h++) {
        hours.add(h);
      }
      for (var h = 0; h <= closeHour; h++) {
        hours.add(h);
      }
    } else {
      for (var h = openHour; h < closeHour; h++) {
        hours.add(h);
      }
    }
    return hours;
  }

  // Earliest bookable hour today (null when a future date is selected, since
  // the "already passed" constraint only applies to today).
  int? _minHourToday() {
    final now = DateTime.now().toLocal();
    final selectedOrToday = _selectedDate ?? now;
    final isToday =
        selectedOrToday.year == now.year &&
        selectedOrToday.month == now.month &&
        selectedOrToday.day == now.day;
    if (!isToday) return null;
    return now.hour + (now.minute > 0 ? 1 : 0);
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
                  backgroundColor: AppColors.primary,
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
        child: CircularProgressIndicator(color: AppColors.primary),
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

        final heroIntro = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Reserve a Table',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 36,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Experience the warmth of Modern Indonesian Heritage. Please '
              'provide your details below to secure your dining experience '
              'at Pusaka.',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15,
                color: AppColors.textSecondary,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 24),
            AspectRatio(
              aspectRatio: 0.95,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.restaurant_outlined,
                  size: 64,
                  color: AppColors.textHint,
                ),
              ),
            ),
          ],
        );

        final formCard = Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionHeader('Location'),
              _branchList(branches),
              const SizedBox(height: 28),
              _sectionHeader('Date'),
              _dateField(),
              const SizedBox(height: 28),
              _sectionHeader('Time'),
              _timeSlotGrid(openTime, closeTime),
              const SizedBox(height: 28),
              _sectionHeader('Party Size'),
              _guestPicker(),
              const SizedBox(height: 28),
              _sectionHeader('Your Details'),
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
              const SizedBox(height: 28),
              _sectionHeader('Special Requests'),
              TextField(
                controller: _notesCtrl,
                maxLines: 3,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Allergies, dietary requirements, or special occasions...',
                  hintStyle: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: AppColors.textHint,
                  ),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.all(14),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : () => _submit(branches),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text('Confirm Reservation'),
                ),
              ),
            ],
          ),
        );

        return Container(
          color: AppColors.background,
          child: SingleChildScrollView(
            padding: EdgeInsets.all(widget.isDesktop ? 40 : 20),
            child: widget.isDesktop
                ? Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1200),
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 5, child: heroIntro),
                            const SizedBox(width: 48),
                            Expanded(flex: 6, child: formCard),
                          ],
                        ),
                      ),
                    ),
                  )
                : formCard,
          ),
        );
      },
    );
  }

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 10),
        const Divider(color: AppColors.border, height: 1),
      ],
    ),
  );

  Widget _radioRow({
    required String label,
    required bool selected,
    required VoidCallback? onTap,
    bool enabled = true,
  }) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
                width: 2,
              ),
            ),
            child: selected
                ? Center(
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: enabled ? AppColors.textPrimary : AppColors.textHint,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _branchList(List<Map<String, dynamic>> branches) => Column(
    children: [
      for (int i = 0; i < branches.length; i++) ...[
        _radioRow(
          label: branches[i]['name'] as String,
          selected: _selectedBranchId == branches[i]['id'],
          onTap: () =>
              setState(() => _selectedBranchId = branches[i]['id'] as String),
        ),
        if (i != branches.length - 1)
          const Divider(color: AppColors.border, height: 1),
      ],
    ],
  );

  Widget _dateField() => GestureDetector(
    onTap: _pickDate,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _selectedDate != null
                  ? _formatDate(_selectedDate!)
                  : 'mm/dd/yyyy',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _selectedDate != null
                    ? AppColors.textPrimary
                    : AppColors.textHint,
              ),
            ),
          ),
          const Icon(
            Icons.calendar_today_outlined,
            size: 18,
            color: AppColors.textSecondary,
          ),
        ],
      ),
    ),
  );

  Widget _timeSlotGrid(String open, String close) {
    final hours = _availableHours(open, close);
    final minHour = _minHourToday();

    Widget slot(int hour) {
      final passed = minHour != null && hour < minHour;
      final label = '${hour.toString().padLeft(2, '0')}:00';
      return _radioRow(
        label: passed ? '$label (Passed)' : label,
        selected: _selectedTime?.hour == hour,
        enabled: !passed,
        onTap: passed
            ? null
            : () => setState(() => _selectedTime = TimeOfDay(hour: hour, minute: 0)),
      );
    }

    final left = <int>[];
    final right = <int>[];
    for (var i = 0; i < hours.length; i++) {
      (i.isEven ? left : right).add(hours[i]);
    }

    Widget column(List<int> col) => Column(
      children: [
        for (int i = 0; i < col.length; i++) ...[
          slot(col[i]),
          if (i != col.length - 1)
            const Divider(color: AppColors.border, height: 1),
        ],
      ],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: column(left)),
        const SizedBox(width: 24),
        Expanded(child: column(right)),
      ],
    );
  }

  Widget _guestPicker() => Row(
    children: [
      _counterBtn(Icons.remove, () {
        if (_guestCount > 1) setState(() => _guestCount--);
      }),
      const SizedBox(width: 20),
      Text(
        '$_guestCount',
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
      ),
      const SizedBox(width: 20),
      _counterBtn(Icons.add, () {
        if (_guestCount < 20) setState(() => _guestCount++);
      }),
      const SizedBox(width: 16),
      const Text(
        'Guests',
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 14,
          color: AppColors.textSecondary,
        ),
      ),
    ],
  );

  Widget _counterBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: AppColors.border),
      ),
      child: Icon(icon, color: AppColors.textPrimary, size: 18),
    ),
  );

  Widget _underlineField({
    required TextEditingController ctrl,
    required String hint,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    ValueChanged<String>? onChanged,
    VoidCallback? onEditingComplete,
    String? errorText,
  }) => TextField(
    controller: ctrl,
    keyboardType: keyboardType,
    inputFormatters: inputFormatters,
    onChanged: onChanged,
    onEditingComplete: onEditingComplete,
    style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        fontFamily: 'Poppins',
        fontSize: 14,
        color: AppColors.textHint,
      ),
      errorText: errorText,
      errorStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 11),
      isDense: true,
      border: const UnderlineInputBorder(
        borderSide: BorderSide(color: AppColors.border),
      ),
      enabledBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: AppColors.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 10),
    ),
  );

  Widget _nameField() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Padding(
        padding: EdgeInsets.only(bottom: 6),
        child: Text(
          'Full name',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
      ),
      _underlineField(ctrl: _nameCtrl, hint: 'Name as on your ID'),
    ],
  );

  Widget _phoneField() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Padding(
        padding: EdgeInsets.only(bottom: 6),
        child: Text(
          'Phone number',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
      ),
      _underlineField(
        ctrl: _phoneCtrl,
        hint: '081234567890',
        keyboardType: TextInputType.phone,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d+\s\-]'))],
        onChanged: (_) => setState(() => _phoneError = null),
        onEditingComplete: () =>
            setState(() => _phoneError = _validatePhone(_phoneCtrl.text.trim())),
        errorText: _phoneError,
      ),
    ],
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
