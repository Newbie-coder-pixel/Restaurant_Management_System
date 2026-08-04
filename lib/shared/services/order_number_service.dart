import 'package:supabase_flutter/supabase_flutter.dart';

/// One shared, atomic, per-(branch, day) sequence behind every order-number
/// scheme in the app (QR "A001" queue numbers, customer app "WEB-...", staff
/// cashier "ORD-..."). Each display format differs, but the underlying
/// integer is reserved from the SAME counter — so order numbers read as one
/// continuous, chronological sequence per branch regardless of which app
/// created the order. See
/// supabase/migrations/20260805000000_shared_daily_order_sequence.sql for the
/// atomic Postgres side of this (a client-side "read last, increment" would
/// race under concurrent callers across three separate apps).
class OrderNumberService {
  /// Reserves the next sequence number for [branchId]'s current day (day
  /// boundary is Asia/Jakarta local time, decided server-side — NOT this
  /// device's clock, so every app agrees on when "today" resets regardless of
  /// device timezone).
  static Future<({int seq, DateTime orderDate})> nextSequence(
    String branchId,
  ) async {
    final rows = await Supabase.instance.client.rpc(
      'next_daily_order_number',
      params: {'p_branch_id': branchId},
    ) as List<dynamic>;
    final row = rows.first as Map<String, dynamic>;
    return (
      seq: row['seq_number'] as int,
      orderDate: DateTime.parse(row['order_date'] as String),
    );
  }

  /// "A001".."A999", then "B001".."B999", etc — same look QR queue numbers
  /// have always had, just driven by the shared sequence instead of a
  /// per-branch "read the last one" query.
  static String formatQrQueueNumber(int seq) {
    final letterIndex = (seq - 1) ~/ 999;
    final withinLetter = ((seq - 1) % 999) + 1;
    final letter = String.fromCharCode('A'.codeUnitAt(0) + letterIndex);
    return '$letter${withinLetter.toString().padLeft(3, '0')}';
  }

  static String formatWebOrderNumber(int seq, DateTime orderDate) =>
      'WEB-${_yyyymmdd(orderDate)}-${seq.toString().padLeft(3, '0')}';

  static String formatStaffOrderNumber(int seq, DateTime orderDate) =>
      'ORD-${_yyyymmdd(orderDate)}-${seq.toString().padLeft(3, '0')}';

  static String _yyyymmdd(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
}
