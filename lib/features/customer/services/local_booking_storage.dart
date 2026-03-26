// lib/features/customer/services/local_booking_storage.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Model booking yang disimpan secara lokal di device customer
class LocalBooking {
  final String id;
  final String branchId;
  final String branchName;
  final String customerName;
  final String customerPhone;
  final int guestCount;
  final String bookingDate;   // format: YYYY-MM-DD
  final String bookingTime;   // format: HH:MM
  final String status;
  final String? specialRequests;
  final DateTime createdAt;

  const LocalBooking({
    required this.id,
    required this.branchId,
    required this.branchName,
    required this.customerName,
    required this.customerPhone,
    required this.guestCount,
    required this.bookingDate,
    required this.bookingTime,
    required this.status,
    this.specialRequests,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id':              id,
    'branch_id':       branchId,
    'branch_name':     branchName,
    'customer_name':   customerName,
    'customer_phone':  customerPhone,
    'guest_count':     guestCount,
    'booking_date':    bookingDate,
    'booking_time':    bookingTime,
    'status':          status,
    'special_requests': specialRequests,
    'created_at':      createdAt.toIso8601String(),
  };

  factory LocalBooking.fromJson(Map<String, dynamic> json) => LocalBooking(
    id:              json['id'] as String,
    branchId:        json['branch_id'] as String,
    branchName:      json['branch_name'] as String? ?? '',
    customerName:    json['customer_name'] as String,
    customerPhone:   json['customer_phone'] as String,
    guestCount:      json['guest_count'] as int,
    bookingDate:     json['booking_date'] as String,
    bookingTime:     json['booking_time'] as String,
    status:          json['status'] as String? ?? 'confirmed',
    specialRequests: json['special_requests'] as String?,
    createdAt:       DateTime.parse(json['created_at'] as String),
  );
}

class LocalBookingStorage {
  static const _key = 'customer_bookings';

  /// Ambil semua booking dari local storage
  static Future<List<LocalBooking>> getAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return [];
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => LocalBooking.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)); // terbaru di atas
    } catch (_) {
      return [];
    }
  }

  /// Simpan booking baru ke local storage
  static Future<void> save(LocalBooking booking) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = await getAll();

      // Hindari duplikat berdasarkan id
      final filtered = existing.where((b) => b.id != booking.id).toList();
      filtered.insert(0, booking); // terbaru di depan

      // Batasi maksimal 50 booking tersimpan
      final limited = filtered.take(50).toList();
      await prefs.setString(_key, jsonEncode(limited.map((b) => b.toJson()).toList()));
    } catch (_) {}
  }

  /// Update status booking (misal setelah sync dari server)
  static Future<void> updateStatus(String bookingId, String newStatus) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = await getAll();
      final updated = existing.map((b) {
        if (b.id == bookingId) {
          return LocalBooking(
            id: b.id, branchId: b.branchId, branchName: b.branchName,
            customerName: b.customerName, customerPhone: b.customerPhone,
            guestCount: b.guestCount, bookingDate: b.bookingDate,
            bookingTime: b.bookingTime, status: newStatus,
            specialRequests: b.specialRequests, createdAt: b.createdAt,
          );
        }
        return b;
      }).toList();
      await prefs.setString(_key, jsonEncode(updated.map((b) => b.toJson()).toList()));
    } catch (_) {}
  }

  /// Hapus semua (untuk testing / clear data)
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}