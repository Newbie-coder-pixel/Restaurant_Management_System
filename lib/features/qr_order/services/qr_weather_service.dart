// lib/features/qr_order/services/qr_weather_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

/// Best-effort weather lookup for the QR menu-recommendation chatbot, so a
/// "recommend me something" request can factor in whether it's hot or cold
/// at the customer's table instead of guessing. Every step here is wrapped
/// so a failure (permission denied, GPS off, API down) degrades to `null`
/// rather than throwing — the caller falls back to just asking the customer
/// directly in chat instead.
class QrWeatherInfo {
  final double tempC;
  final bool isHot;
  final bool isCold;
  final bool isRaining;

  const QrWeatherInfo({
    required this.tempC,
    required this.isHot,
    required this.isCold,
    required this.isRaining,
  });

  /// Short factual line fed into the AI system prompt as real, verified data.
  String toPromptLine() {
    final cond = isRaining
        ? 'rainy'
        : isHot
            ? 'hot'
            : isCold
                ? 'cool/cold'
                : 'mild';
    return "Customer's current local weather (from device GPS + live weather "
        "API): ${tempC.toStringAsFixed(0)}°C, $cond.";
  }
}

class QrWeatherService {
  QrWeatherService._();

  static const _timeout = Duration(seconds: 6);

  /// Returns null if location permission isn't granted, GPS is off, or the
  /// weather lookup fails for any reason — never throws.
  static Future<QrWeatherInfo?> tryFetch() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 8),
        ),
      ).timeout(_timeout);

      return await _fetchWeather(position.latitude, position.longitude);
    } catch (e) {
      debugPrint('QrWeatherService.tryFetch error: $e');
      return null;
    }
  }

  // Open-Meteo: free, no API key, CORS-enabled — safe to call directly from
  // the browser/app with no server-side proxy (unlike Groq, which needs
  // api/chat.js to keep its key secret).
  static Future<QrWeatherInfo?> _fetchWeather(double lat, double lon) async {
    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$lat&longitude=$lon&current_weather=true',
      );
      final res = await http.get(uri).timeout(_timeout);
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final current = data['current_weather'] as Map<String, dynamic>?;
      if (current == null) return null;

      final temp = (current['temperature'] as num?)?.toDouble();
      final weatherCode = (current['weathercode'] as num?)?.toInt() ?? 0;
      if (temp == null) return null;

      // WMO weather codes: 51-67/80-82 = drizzle/rain/showers, 95-99 = storms
      final isRaining = (weatherCode >= 51 && weatherCode <= 82) ||
          (weatherCode >= 95 && weatherCode <= 99);

      return QrWeatherInfo(
        tempC: temp,
        isHot: temp >= 30,
        isCold: temp <= 22,
        isRaining: isRaining,
      );
    } catch (e) {
      debugPrint('QrWeatherService._fetchWeather error: $e');
      return null;
    }
  }
}
