import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Request Model ─────────────────────────────────────────────────────────────
class PrepTimeRequestItem {
  final String menuItemName;
  final int quantity;
  final int preparationTimeMinutes;
  final String? specialRequests;

  const PrepTimeRequestItem({
    required this.menuItemName,
    required this.quantity,
    required this.preparationTimeMinutes,
    this.specialRequests,
  });

  Map<String, dynamic> toJson() => {
        'menu_item_name':           menuItemName,
        'quantity':                 quantity,
        'preparation_time_minutes': preparationTimeMinutes,
        'special_requests':         specialRequests,
      };
}

// ── Response Model ────────────────────────────────────────────────────────────
class PrepTimeResult {
  final int estimatedMinutes;
  final Map<String, dynamic> breakdown;

  const PrepTimeResult({
    required this.estimatedMinutes,
    required this.breakdown,
  });

  factory PrepTimeResult.fromJson(Map<String, dynamic> j) => PrepTimeResult(
        estimatedMinutes: j['estimated_minutes'] as int,
        breakdown:        j['breakdown'] as Map<String, dynamic>,
      );
}

// ── Service ───────────────────────────────────────────────────────────────────
class PrepTimeService {
  // Ganti URL ini saat deploy ke production
  static const String _baseUrl = kIsWeb
    ? 'https://restaurant-ml-api-production.up.railway.app'
    : 'http://localhost:8000';

  /// Prediksi waktu masak berdasarkan items order yang dipilih.
  ///
  /// [items]     — list item order beserta prep time masing-masing menu
  /// [branchId]  — untuk hitung queue_length dari Supabase secara otomatis
  static Future<PrepTimeResult?> predict({
    required List<PrepTimeRequestItem> items,
    required String branchId,
  }) async {
    try {
      // Hitung jam sekarang
      final hourOfDay = DateTime.now().hour;

      // Hitung panjang antrian dapur dari Supabase
      final queueLength = await _getQueueLength(branchId);

      // Hit ML API
      final response = await http.post(
        Uri.parse('$_baseUrl/predict'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'items':        items.map((i) => i.toJson()).toList(),
          'hour_of_day':  hourOfDay,
          'queue_length': queueLength,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return PrepTimeResult.fromJson(data);
      } else {
        debugPrint('PrepTimeService error: ${response.statusCode} ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('PrepTimeService exception: $e');
      return null;
    }
  }

  /// Hitung jumlah order yang sedang dimasak di dapur saat ini.
  static Future<int> _getQueueLength(String branchId) async {
    try {
      final res = await Supabase.instance.client
          .from('orders')
          .select('id')
          .eq('branch_id', branchId)
          .eq('status', 'preparing');
      return (res as List).length;
    } catch (e) {
      debugPrint('PrepTimeService queue error: $e');
      return 0;
    }
  }

  /// Format estimasi menjadi string yang ramah ditampilkan ke user.
  /// Contoh: 17 → "± 17 menit"  |  65 → "± 1 jam 5 menit"
  static String formatEstimate(int minutes) {
    if (minutes < 60) return '± $minutes menit';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '± $h jam' : '± $h jam $m menit';
  }
}