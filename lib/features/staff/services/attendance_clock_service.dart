// lib/features/staff/services/attendance_clock_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import '../presentation/staff_attendance_screen.dart' show AttendanceRecord;

/// Self-service clock-in/out — writes go through the `clock_in`/`clock_out`
/// Postgres RPCs (SECURITY DEFINER), not a direct table insert/update, so the
/// server can enforce ownership + GPS-distance validation atomically. See
/// supabase/migrations/20260803000000_attendance_self_service_clock_in.sql.
class AttendanceClockService {
  final SupabaseClient _client;

  AttendanceClockService(this._client);

  Future<AttendanceRecord?> fetchTodayRecord({required String staffId}) async {
    final today = DateTime.now();
    final dateStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final res = await _client
        .from('attendance')
        .select()
        .eq('staff_id', staffId)
        .eq('date', dateStr)
        .maybeSingle();
    if (res == null) return null;
    return AttendanceRecord.fromJson(res);
  }

  Future<AttendanceRecord> clockIn({
    required double latitude,
    required double longitude,
  }) async {
    final res = await _client.rpc('clock_in', params: {
      'p_lat': latitude,
      'p_lng': longitude,
    });
    return AttendanceRecord.fromJson(res as Map<String, dynamic>);
  }

  Future<AttendanceRecord> clockOut({
    required double latitude,
    required double longitude,
  }) async {
    final res = await _client.rpc('clock_out', params: {
      'p_lat': latitude,
      'p_lng': longitude,
    });
    return AttendanceRecord.fromJson(res as Map<String, dynamic>);
  }
}
