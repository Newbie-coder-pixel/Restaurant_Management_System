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

  /// Batched variant of [fetchTodayRecord], keyed by staff_id — used to show
  /// on-duty/off-duty status across a staff list without one query per row.
  Future<Map<String, AttendanceRecord>> fetchTodayRecordsForStaffIds(
      List<String> staffIds) async {
    if (staffIds.isEmpty) return {};
    final today = DateTime.now();
    final dateStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final res = await _client
        .from('attendance')
        .select()
        .inFilter('staff_id', staffIds)
        .eq('date', dateStr);
    final map = <String, AttendanceRecord>{};
    for (final row in (res as List)) {
      final record = AttendanceRecord.fromJson(row as Map<String, dynamic>);
      map[record.staffId] = record;
    }
    return map;
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
