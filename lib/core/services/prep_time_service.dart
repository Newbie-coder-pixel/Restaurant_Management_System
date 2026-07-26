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

  /// Base URL API prediksi ML.
  ///
  /// SELALU pakai server production, di semua platform (web, Android, iOS).
  /// Sebelumnya build non-web (APK/App Store) selalu diarahkan ke
  /// 'http://localhost:8000' — di HP asli itu merujuk ke HP itu sendiri, jadi
  /// prediksi selalu gagal timeout di luar web/emulator dev. Untuk dev lokal,
  /// override lewat: `flutter run --dart-define=ML_API_BASE_URL=http://10.0.2.2:8000`
  /// (emulator Android) atau `http://localhost:8000` (simulator iOS/desktop/web dev).
  static String get _baseUrl {
    const override = String.fromEnvironment('ML_API_BASE_URL');
    return override.isNotEmpty ? override : _prodUrl;
  }

  /// Prediksi waktu masak berdasarkan items order yang dipilih.
  ///
  /// [items]     — list item order beserta prep time masing-masing menu
  /// [branchId]  — dipakai server untuk resolve model per-branch +
  ///               equipment_factor, dan dipakai di sini untuk hitung
  ///               queue_length dari Supabase secara otomatis
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
          // Sebelumnya branch_id TIDAK PERNAH dikirim, jadi server selalu
          // resolve ke scope "global" — model per-branch & equipment_factor
          // per-branch tidak pernah kepakai walau sudah di-retrain di server.
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

  /// Estimasi kasar TANPA ML — dipakai HANYA sebagai fallback saat [predict]
  /// gagal (server tidak terjangkau, timeout, dll), supaya customer tetap
  /// lihat angka kira-kira daripada kartu estimasi hilang tanpa keterangan.
  /// Layar pemanggil wajib menandai ini berbeda dari hasil ML asli (mis. label
  /// "estimasi kasar") — jangan tampilkan seolah-olah hasil model.
  static int rawFallbackEstimate(List<PrepTimeRequestItem> items) {
    if (items.isEmpty) return 0;
    final total = items.fold<int>(
      0,
      (sum, i) => sum + i.preparationTimeMinutes * i.quantity,
    );
    return total < 1 ? 1 : total;
  }
}