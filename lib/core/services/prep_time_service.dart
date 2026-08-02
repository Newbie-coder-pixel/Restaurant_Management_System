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
  static const String _prodUrl =
      'https://restaurant-ml-api-production.up.railway.app';

  /// Base URL for the ML prediction API.
  ///
  /// ALWAYS use the production server, on all platforms (web, Android, iOS).
  /// Previously non-web builds (APK/App Store) were always directed to
  /// 'http://localhost:8000' — on a real phone that refers to the phone itself, so
  /// predictions always failed with a timeout outside of web/dev emulator. For local
  /// dev, override via: `flutter run --dart-define=ML_API_BASE_URL=http://10.0.2.2:8000`
  /// (Android emulator) or `http://localhost:8000` (iOS simulator/desktop/web dev).
  static String get _baseUrl {
    const override = String.fromEnvironment('ML_API_BASE_URL');
    return override.isNotEmpty ? override : _prodUrl;
  }

  /// Predicts cooking time based on the selected order items.
  ///
  /// [items]     — list of order items along with each menu item's prep time
  /// [branchId]  — used by the server to resolve the per-branch model +
  ///               equipment_factor, and used here to automatically compute
  ///               queue_length from Supabase
  static Future<PrepTimeResult?> predict({
    required List<PrepTimeRequestItem> items,
    required String branchId,
  }) async {
    try {
      // Get the current hour
      final hourOfDay = DateTime.now().hour;

      // Compute the kitchen queue length from Supabase
      final queueLength = await _getQueueLength(branchId);

      // Hit ML API
      final response = await http.post(
        Uri.parse('$_baseUrl/predict'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'items':        items.map((i) => i.toJson()).toList(),
          'hour_of_day':  hourOfDay,
          'queue_length': queueLength,
          // Previously branch_id was NEVER sent, so the server always
          // resolved to the "global" scope — the per-branch model & per-branch
          // equipment_factor were never actually used even after being retrained on the server.
          if (branchId.isNotEmpty) 'branch_id': branchId,
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

  /// Counts the number of orders currently being cooked in the kitchen.
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

  /// Formats the estimate into a user-friendly display string.
  /// Example: 17 → "± 17 min"  |  65 → "± 1 hr 5 min"
  static String formatEstimate(int minutes) {
    if (minutes < 60) return '± $minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '± $h hr' : '± $h hr $m min';
  }

  /// Rough estimate WITHOUT ML — used ONLY as a fallback when [predict]
  /// fails (server unreachable, timeout, etc.), so the customer still
  /// sees an approximate number instead of the estimate card disappearing with no explanation.
  /// The calling screen must mark this as different from a real ML result (e.g. label
  /// "rough estimate") — don't display it as if it were the model's output.
  static int rawFallbackEstimate(List<PrepTimeRequestItem> items) {
    if (items.isEmpty) return 0;
    final total = items.fold<int>(
      0,
      (sum, i) => sum + i.preparationTimeMinutes * i.quantity,
    );
    return total < 1 ? 1 : total;
  }
}