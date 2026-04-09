import 'package:supabase_flutter/supabase_flutter.dart';

class TableAssignmentResult {
  final bool success;
  final String status; // 'confirmed' | 'waitlisted' | 'error'
  final String? tableId;
  final String? tableNumber;
  final String? message;

  const TableAssignmentResult({
    required this.success,
    required this.status,
    this.tableId,
    this.tableNumber,
    this.message,
  });

  factory TableAssignmentResult.fromMap(Map<String, dynamic> m) {
    return TableAssignmentResult(
      success:     m['success'] as bool,
      status:      m['status'] as String,
      tableId:     m['table_id'] as String?,
      tableNumber: m['table_number'] as String?,
      message:     m['message'] as String?,
    );
  }

  bool get isConfirmed  => status == 'confirmed';
  bool get isWaitlisted => status == 'waitlisted';
}

class TableAssignmentService {
  final _supabase = Supabase.instance.client;

  /// Buat booking baru lalu auto-assign meja dalam satu flow
  Future<TableAssignmentResult> createAndAssign({
    required String branchId,
    required String customerName,
    required String? customerPhone,
    required String? customerEmail,
    required String? customerUserId,
    required int guestCount,
    required DateTime bookingDateTime,
    String specialRequests = '',
  }) async {
    // Format date dan time sesuai tipe kolom Postgres
    final bookingDate = '${bookingDateTime.year}-'
        '${bookingDateTime.month.toString().padLeft(2, '0')}-'
        '${bookingDateTime.day.toString().padLeft(2, '0')}';
    final bookingTime = '${bookingDateTime.hour.toString().padLeft(2, '0')}:'
        '${bookingDateTime.minute.toString().padLeft(2, '0')}:00';

    // 1. Insert booking dengan status pending
    final booking = await _supabase
        .from('bookings')
        .insert({
          'branch_id':        branchId,
          'customer_name':    customerName,
          'customer_phone':   customerPhone,
          'customer_email':   customerEmail,
          'customer_user_id': customerUserId,
          'guest_count':      guestCount,
          'booking_date':     bookingDate,
          'booking_time':     bookingTime,
          'special_requests': specialRequests,
          'status':           'pending',
        })
        .select('id')
        .single();

    final bookingId = booking['id'] as String;

    // 2. Panggil RPC untuk auto-assign meja
    final response = await _supabase.rpc(
      'assign_table_to_booking',
      params: {
        'p_booking_id':   bookingId,
        'p_branch_id':    branchId,
        'p_guest_count':  guestCount,
        'p_booking_date': bookingDate,
        'p_booking_time': bookingTime,
      },
    );

    return TableAssignmentResult.fromMap(
      Map<String, dynamic>.from(response as Map),
    );
  }

  /// Cancel booking dan bebaskan meja
  Future<void> cancelBooking({
    required String bookingId,
    required String tableId,
  }) async {
    await _supabase.rpc('release_table', params: {
      'p_table_id':   tableId,
      'p_booking_id': bookingId,
      'p_new_status': 'cancelled',
    });
  }

  /// Stream real-time status semua meja di satu branch
  Stream<List<Map<String, dynamic>>> watchTables(String branchId) {
    return _supabase
        .from('restaurant_tables')
        .stream(primaryKey: ['id'])
        .eq('branch_id', branchId)
        .order('table_number');
  }

  /// Stream real-time booking milik customer
  Stream<List<Map<String, dynamic>>> watchMyBookings(String customerUserId) {
    return _supabase
        .from('bookings')
        .stream(primaryKey: ['id'])
        .eq('customer_user_id', customerUserId)
        .order('booking_date', ascending: false);
  }
}