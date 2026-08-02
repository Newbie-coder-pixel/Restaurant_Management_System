// lib/features/staff/providers/attendance_clock_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../presentation/staff_attendance_screen.dart' show AttendanceRecord;
import '../services/attendance_clock_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/supabase_client.dart';

final attendanceClockServiceProvider = Provider<AttendanceClockService>((ref) {
  return AttendanceClockService(supabase);
});

/// Today's attendance record for the current staff member, or null if they
/// haven't clocked in yet today. Drives the Clock In/Out control in
/// AppDrawer.
class TodayAttendanceNotifier extends AsyncNotifier<AttendanceRecord?> {
  late AttendanceClockService _service;

  @override
  Future<AttendanceRecord?> build() async {
    _service = ref.watch(attendanceClockServiceProvider);
    final staffId = ref.watch(currentStaffProvider)?.id;
    if (staffId == null) return null;
    return _service.fetchTodayRecord(staffId: staffId);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final staffId = ref.read(currentStaffProvider)?.id;
      if (staffId == null) return null;
      return _service.fetchTodayRecord(staffId: staffId);
    });
  }

  /// Throws on failure (out of range, already recorded, etc) — the caller is
  /// expected to catch and show the message to the user.
  Future<void> clockIn({required double latitude, required double longitude}) async {
    final record = await _service.clockIn(latitude: latitude, longitude: longitude);
    state = AsyncValue.data(record);
  }

  Future<void> clockOut({required double latitude, required double longitude}) async {
    final record = await _service.clockOut(latitude: latitude, longitude: longitude);
    state = AsyncValue.data(record);
  }
}

final todayAttendanceProvider =
    AsyncNotifierProvider<TodayAttendanceNotifier, AttendanceRecord?>(
  TodayAttendanceNotifier.new,
);
