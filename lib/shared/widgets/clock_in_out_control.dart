// lib/shared/widgets/clock_in_out_control.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../../core/services/location_service.dart';
import '../../core/theme/app_theme.dart';
import '../../features/customer/presentation/widgets/location_permission_sheet.dart';
import '../../features/staff/presentation/staff_attendance_screen.dart' show AttendanceRecord;
import '../../features/staff/providers/attendance_clock_provider.dart';

/// Self-service Clock In/Out control, shown in AppDrawer's header — the one
/// screen element common to every staff role. Explicit action (tap to clock
/// in/out), not automatic on login; verified server-side against the
/// branch's GPS location by the clock_in/clock_out RPCs.
class ClockInOutControl extends ConsumerWidget {
  const ClockInOutControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayAsync = ref.watch(todayAttendanceProvider);

    return todayAsync.when(
      loading: () => const _ControlShell(
        child: SizedBox(
          height: 16,
          width: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
        ),
      ),
      error: (_, __) => const _ControlShell(
        child: Text('Attendance unavailable',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.white54)),
      ),
      data: (today) => _ClockButton(today: today),
    );
  }
}

class _ControlShell extends StatelessWidget {
  final Widget child;
  const _ControlShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(child: child),
    );
  }
}

class _ClockButton extends ConsumerStatefulWidget {
  final AttendanceRecord? today;
  const _ClockButton({required this.today});

  @override
  ConsumerState<_ClockButton> createState() => _ClockButtonState();
}

class _ClockButtonState extends ConsumerState<_ClockButton> {
  bool _busy = false;

  bool get _isClockedIn =>
      widget.today != null &&
      widget.today!.isSelfService &&
      widget.today!.clockIn != null &&
      widget.today!.clockOut == null;

  bool get _isDoneForToday =>
      widget.today != null &&
      (widget.today!.clockOut != null || !widget.today!.isSelfService);

  String _time(DateTime? dt) {
    if (dt == null) return '—';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _handleTap() async {
    if (_busy || _isDoneForToday) return;
    setState(() => _busy = true);
    try {
      final locationService = LocationService();
      final ready = await locationService.isLocationReady();
      if (!ready) {
        if (!mounted) return;
        // LocationPermissionSheet's Future resolves as soon as the sheet is
        // popped (before its own async permission-request logic finishes),
        // so we can't await it directly for the result — use a Completer
        // fed by the onGranted/onDenied callbacks instead.
        final completer = Completer<bool>();
        unawaited(LocationPermissionSheet.show(
          context,
          onGranted: () => completer.complete(true),
          onDenied: () => completer.complete(false),
        ));
        final granted = await completer.future;
        if (!granted) {
          setState(() => _busy = false);
          return;
        }
      }

      final position = await locationService.getCurrentPosition();
      if (position == null) {
        _showMessage('Could not get your location. Please try again.', isError: true);
        return;
      }

      final notifier = ref.read(todayAttendanceProvider.notifier);
      if (_isClockedIn) {
        await notifier.clockOut(
            latitude: position.latitude, longitude: position.longitude);
        _showMessage('Clocked out successfully');
      } else {
        await notifier.clockIn(
            latitude: position.latitude, longitude: position.longitude);
        _showMessage('Clocked in successfully');
      }
    } on PostgrestException catch (e) {
      _showMessage(e.message, isError: true);
    } catch (e) {
      _showMessage('Failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : AppColors.available,
    ));
  }

  @override
  Widget build(BuildContext context) {
    String statusLine;
    IconData icon;
    if (widget.today == null) {
      statusLine = 'Not clocked in';
      icon = Icons.login_rounded;
    } else if (_isClockedIn) {
      statusLine = 'Clocked in since ${_time(widget.today!.clockIn)}';
      icon = Icons.logout_rounded;
    } else if (widget.today!.clockOut != null) {
      statusLine =
          'Worked ${_time(widget.today!.clockIn)} – ${_time(widget.today!.clockOut)}';
      icon = Icons.check_circle_outline_rounded;
    } else {
      statusLine = 'Recorded by manager: ${widget.today!.status.label}';
      icon = Icons.info_outline_rounded;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _isDoneForToday || _busy ? null : _handleTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          if (_busy)
            const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
            )
          else
            Icon(icon, size: 18, color: Colors.white70),
          const SizedBox(width: 10),
          Expanded(
            child: Text(statusLine,
                style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 11, color: Colors.white70),
                overflow: TextOverflow.ellipsis),
          ),
          if (!_isDoneForToday && !_busy)
            Text(_isClockedIn ? 'Clock Out' : 'Clock In',
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
        ]),
      ),
    );
  }
}
