import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/heritage_illustrations.dart';

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

  // ── TOP BAR (Cita Rasa header, shared visual language with other customer screens) ──
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
              'Cita Rasa',
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
                  label: 'Reservations',
                  onTap: () {},
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
          .select('id, confirmation_code')
          .single();

      final bookingId = bookingRes['id'] as String;
      final confirmationCode = bookingRes['confirmation_code'] as String?;

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
        final branch = branches
            .where((b) => b['id'] == _selectedBranchId)
            .cast<Map<String, dynamic>?>()
            .firstOrNull;
        _showSuccess(
          tableNumber: tableNumber,
          confirmationCode: confirmationCode,
          branchName: branch?['name'] as String?,
          branchAddress: branch?['address'] as String?,
        );
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

  String _fmtFullDateTime(DateTime date, TimeOfDay time) {
    const weekdays = [
      '',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
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
    final hour12 = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    final minute = time.minute.toString().padLeft(2, '0');
    return '${weekdays[date.weekday]}, ${months[date.month]} '
        '${date.day.toString().padLeft(2, '0')} at $hour12:$minute $period';
  }

  // Booking duration isn't user-selectable in this form (DB defaults to
  // 120 min — see assign_table_to_booking / other booking flows), so the
  // calendar event end time assumes the same default.
  Uri _googleCalendarUrl({
    required String title,
    required String details,
    required String location,
    required DateTime startWib,
  }) {
    final startUtc = startWib.subtract(const Duration(hours: 7));
    final endUtc = startUtc.add(const Duration(minutes: 120));
    String fmt(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}'
        '${d.day.toString().padLeft(2, '0')}T${d.hour.toString().padLeft(2, '0')}'
        '${d.minute.toString().padLeft(2, '0')}00Z';
    return Uri.https('www.google.com', '/calendar/render', {
      'action': 'TEMPLATE',
      'text': title,
      'dates': '${fmt(startUtc)}/${fmt(endUtc)}',
      'details': details,
      if (location.isNotEmpty) 'location': location,
    });
  }

  void _showSuccess({
    String? tableNumber,
    String? confirmationCode,
    String? branchName,
    String? branchAddress,
  }) {
    final date = _selectedDate!;
    final time = _selectedTime!;
    final dateTimeLabel = _fmtFullDateTime(date, time);
    final startWib = DateTime(date.year, date.month, date.day, time.hour, time.minute);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880, maxHeight: 640),
          child: Material(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            clipBehavior: Clip.antiAlias,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 600;

                final content = SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.primary, width: 1.5),
                        ),
                        child: const Icon(Icons.check, color: AppColors.primary, size: 20),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Terima Kasih',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Your reservation is confirmed. We look forward to welcoming you.',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 15,
                          color: AppColors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                        ),
                        child: Column(
                          children: [
                            _successRow(
                              Icons.calendar_today_outlined,
                              'DATE & TIME',
                              dateTimeLabel,
                            ),
                            const Divider(color: AppColors.border, height: 1),
                            _successRow(
                              Icons.people_outline,
                              'PARTY SIZE',
                              '$_guestCount Guests',
                            ),
                            if (tableNumber != null) ...[
                              const Divider(color: AppColors.border, height: 1),
                              _successRow(
                                Icons.table_restaurant_outlined,
                                'TABLE',
                                tableNumber,
                              ),
                            ],
                            if (confirmationCode != null && confirmationCode.isNotEmpty) ...[
                              const Divider(color: AppColors.border, height: 1),
                              _successRow(
                                Icons.tag,
                                'CONFIRMATION NUMBER',
                                confirmationCode,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => launchUrl(
                                _googleCalendarUrl(
                                  title: 'Reservation at Cita Rasa'
                                      '${branchName != null ? ' – $branchName' : ''}',
                                  details: 'Table for $_guestCount guest(s).'
                                      '${confirmationCode != null ? ' Confirmation #$confirmationCode.' : ''}',
                                  location: branchAddress ?? branchName ?? '',
                                  startWib: startWib,
                                ),
                                mode: LaunchMode.externalApplication,
                              ),
                              icon: const Icon(Icons.calendar_today, size: 16),
                              label: const Text('Add to Calendar'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                                ),
                                textStyle: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.of(dialogCtx).pop();
                                ref.read(_refreshTriggerProvider.notifier).state++;
                                context.go('/customer');
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.accent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                                ),
                                textStyle: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              child: const Text('Back to Home'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );

                if (!isWide) return content;

                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Container(
                          color: AppColors.surfaceVariant,
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.restaurant_outlined,
                            size: 64,
                            color: AppColors.textHint,
                          ),
                        ),
                      ),
                      Expanded(flex: 2, child: content),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _successRow(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Row(
      children: [
        Icon(icon, size: 18, color: AppColors.accent),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

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
              'at Cita Rasa.',
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
                padding: const EdgeInsets.all(28),
                child: const TableReservationIllustration(),
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
// BOOKING HISTORY ("My Bookings")
// ─────────────────────────────────────────────────────────────────
class _BookingHistory extends ConsumerStatefulWidget {
  final bool isDesktop;
  const _BookingHistory({required this.isDesktop});

  @override
  ConsumerState<_BookingHistory> createState() => _BookingHistoryState();
}

class _BookingHistoryState extends ConsumerState<_BookingHistory> {
  // 'all' | 'upcoming' | 'past'
  String _filter = 'all';

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

  List<Map<String, dynamic>> _upcomingOf(List<Map<String, dynamic>> all) =>
      all
          .where(_isVisible)
          .where((b) => _activeStatuses.contains(b['status']))
          .toList();

  List<Map<String, dynamic>> _pastOf(List<Map<String, dynamic>> all) => all
      .where(_isVisible)
      .where(
        (b) =>
            _doneStatuses.contains(b['status']) ||
            _cancelledStatuses.contains(b['status']),
      )
      .toList();

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = ref.watch(_myBookingsProvider);

    return bookingsAsync.when(
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
      data: (bookings) {
        final upcoming = _upcomingOf(bookings);
        final past = _pastOf(bookings);

        return Container(
          color: AppColors.background,
          child: SingleChildScrollView(
            padding: EdgeInsets.all(widget.isDesktop ? 40 : 20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _header(),
                    const SizedBox(height: 32),
                    widget.isDesktop
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(width: 200, child: _sidebar()),
                              const SizedBox(width: 40),
                              Expanded(child: _sections(upcoming, past)),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sidebar(),
                              const SizedBox(height: 24),
                              _sections(upcoming, past),
                            ],
                          ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _header() => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'My Bookings',
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 34,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
      ),
      SizedBox(height: 12),
      Text(
        'Review your upcoming culinary journeys and past dining experiences '
        'with us.',
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 15,
          color: AppColors.textSecondary,
          height: 1.6,
        ),
      ),
    ],
  );

  Widget _sidebar() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'STATUS',
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: AppColors.textHint,
        ),
      ),
      const SizedBox(height: 16),
      _sidebarItem('All Bookings', 'all'),
      const SizedBox(height: 12),
      _sidebarItem('Upcoming', 'upcoming'),
      const SizedBox(height: 12),
      _sidebarItem('Past', 'past'),
    ],
  );

  Widget _sidebarItem(String label, String value) {
    final selected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            child: selected
                ? Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sections(
    List<Map<String, dynamic>> upcoming,
    List<Map<String, dynamic>> past,
  ) {
    final showUpcoming = _filter != 'past';
    final showPast = _filter != 'upcoming';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showUpcoming) ...[
          _sectionHeader('Upcoming'),
          if (upcoming.isEmpty)
            _emptySection(
              'No upcoming reservations. Create one in the "New Reservation" tab.',
            )
          else
            ...upcoming.map((b) => _BookingListCard(booking: b)),
          const SizedBox(height: 32),
        ],
        if (showPast) ...[
          _sectionHeader('Past Bookings'),
          if (past.isEmpty)
            _emptySection(
              'Your completed and cancelled bookings will appear here.',
            )
          else
            ...past.map((b) => _BookingListCard(booking: b)),
        ],
      ],
    );
  }

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        const Divider(color: AppColors.border, height: 1),
      ],
    ),
  );

  Widget _emptySection(String msg) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Text(
      msg,
      style: const TextStyle(
        fontFamily: 'Poppins',
        fontSize: 13,
        color: AppColors.textHint,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────
// BOOKING CARD (compact list row + detail sheet)
// ─────────────────────────────────────────────────────────────────
String _fmtBookingDateShort(String? raw) {
  if (raw == null) return '-';
  try {
    final d = DateTime.parse(raw);
    const wd = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
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
    return '${wd[d.weekday]}, ${months[d.month]} ${d.day.toString().padLeft(2, '0')}';
  } catch (_) {
    return raw;
  }
}

String _fmtBookingDateLong(String? raw) {
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

(Color, String) _bookingStatusMeta(String status) => switch (status) {
  'confirmed' => (AppColors.statusConfirmed, 'Confirmed'),
  'pending' => (AppColors.statusWaitlist, 'Pending'),
  'waitlisted' => (AppColors.statusWaitlist, 'Waitlist'),
  'seated' => (AppColors.iconAccentBlue, 'Dining'),
  'completed' => (AppColors.statusCompleted, 'Completed'),
  'cancelled' => (AppColors.statusClosed, 'Cancelled'),
  'no_show' => (AppColors.statusClosed, 'No Show'),
  _ => (AppColors.statusCompleted, status),
};

bool _bookingIsActive(String status) =>
    status == 'pending' ||
    status == 'confirmed' ||
    status == 'waitlisted' ||
    status == 'seated';

Future<void> _contactStaffAbout(
  BuildContext context,
  Map<String, dynamic> booking,
  String? phone,
) async {
  if (phone == null || phone.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Branch contact number not available. Please contact us directly.',
          style: TextStyle(fontFamily: 'Poppins'),
        ),
        backgroundColor: const Color(0xFF3B82F6),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
    return;
  }

  final cleaned = phone
      .replaceAll(RegExp(r'[^\d+]'), '')
      .replaceFirst(RegExp(r'^0'), '62');

  final date = _fmtBookingDateLong(booking['booking_date'] as String?);
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

class _BookingListCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  const _BookingListCard({required this.booking});

  String get _status => booking['status'] as String? ?? 'pending';

  @override
  Widget build(BuildContext context) {
    final branchData = booking['branches'] as Map<String, dynamic>?;
    final branchName = branchData?['name'] as String? ?? 'Restaurant';
    final date = _fmtBookingDateShort(booking['booking_date'] as String?);
    final time = (booking['booking_time'] as String?)?.substring(0, 5) ?? '-';
    final guests = booking['guest_count'] ?? 1;
    final (color, label) = _bookingStatusMeta(_status);
    final isActive = _bookingIsActive(_status);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Stack(
        children: [
          const Positioned(
            top: 0,
            right: 0,
            child: Icon(
              Icons.auto_awesome,
              size: 16,
              color: AppColors.border,
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          label.toUpperCase(),
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      branchName,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 16,
                      runSpacing: 4,
                      children: [
                        _metaItem(Icons.calendar_today_outlined, date),
                        _metaItem(Icons.access_time_outlined, time),
                        _metaItem(Icons.people_outline, 'Table for $guests'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              OutlinedButton(
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  builder: (_) => _BookingDetailSheet(booking: booking),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                child: Text(
                  isActive ? 'Manage' : 'View Details',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metaItem(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: AppColors.textSecondary),
      const SizedBox(width: 5),
      Text(
        text,
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────
// BOOKING DETAIL SHEET
// ─────────────────────────────────────────────────────────────────
class _BookingDetailSheet extends StatelessWidget {
  final Map<String, dynamic> booking;
  const _BookingDetailSheet({required this.booking});

  String get _status => booking['status'] as String? ?? 'pending';

  @override
  Widget build(BuildContext context) {
    final branchData = booking['branches'] as Map<String, dynamic>?;
    final branchName = branchData?['name'] as String? ?? 'Restaurant';
    final branchPhone = branchData?['phone'] as String?;
    final date = _fmtBookingDateLong(booking['booking_date'] as String?);
    final time = (booking['booking_time'] as String?)?.substring(0, 5) ?? '-';
    final guests = booking['guest_count'] ?? 1;
    final tableId = booking['table_id'] as String?;
    final notes = booking['special_requests'] as String?;
    final (color, label) = _bookingStatusMeta(_status);
    final isActive = _bookingIsActive(_status);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              branchName,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            _detailRow(Icons.calendar_today_outlined, 'Date', date),
            const SizedBox(height: 12),
            _detailRow(Icons.access_time_outlined, 'Time', '$time WIB'),
            const SizedBox(height: 12),
            _detailRow(Icons.people_outline, 'Guests', '$guests'),
            if (notes != null && notes.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              _detailRow(Icons.note_outlined, 'Notes', notes),
            ],
            if (tableId != null && _status == 'confirmed') ...[
              const SizedBox(height: 16),
              _detailBanner(
                icon: Icons.table_restaurant,
                text:
                    'Table ${booking['restaurant_tables']?['table_number'] ?? ''} is ready',
                color: AppColors.statusConfirmed,
              ),
            ],
            if (_status == 'waitlisted') ...[
              const SizedBox(height: 16),
              _detailBanner(
                icon: Icons.hourglass_top_outlined,
                text:
                    'You are on the waitlist. Staff will contact you if a table becomes available.\nWill be contacted via: ${booking['customer_phone']}',
                color: AppColors.statusWaitlist,
              ),
            ],
            if (isActive) ...[
              const SizedBox(height: 20),
              const Divider(color: AppColors.border, height: 1),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.statusWaitlist.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: AppColors.statusWaitlist,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Want to change or cancel? Contact our staff.',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.statusWaitlist,
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
                  onPressed: () =>
                      _contactStaffAbout(context, booking, branchPhone),
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
                      color: AppColors.textPrimary,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.border, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: AppColors.textSecondary),
      const SizedBox(width: 12),
      SizedBox(
        width: 60,
        child: Text(
          '$label:',
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
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
            color: AppColors.textPrimary,
          ),
        ),
      ),
    ],
  );

  Widget _detailBanner({
    required IconData icon,
    required String text,
    required Color color,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
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
