// lib/features/customer/services/sentiment_escalation_service.dart
//
// Alur:
// 1. CustomerChatbotScreen panggil SentimentEscalationService.analyze(text)
// 2. Jika sentiment == negative/urgent → escalate()
// 3. escalate() → query manager tokens → kirim FCM via Vercel proxy → log ke Supabase
// 4. notifyCustomerBooking() → query customer token → kirim FCM konfirmasi booking

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Hasil analisis sentiment ───────────────────────────────────────────
enum SentimentLevel { neutral, negative, urgent }

class SentimentResult {
  final SentimentLevel level;
  final String reason;

  const SentimentResult({required this.level, required this.reason});

  bool get shouldEscalate => level != SentimentLevel.neutral;
}

// ── Service ────────────────────────────────────────────────────────────
class SentimentEscalationService {
  // ── Keyword-based detection ────────────────────────────────────────
  static const _urgentKeywords = [
    'darurat', 'urgent', 'bahaya', 'kecelakaan', 'sakit', 'mati',
    'tolong segera', 'minta tolong', 'tidak bisa bernapas',
  ];

  static const _negativeKeywords = [
    'kecewa', 'sangat kecewa', 'tidak puas', 'ga puas', 'mengecewakan',
    'buruk', 'jelek', 'parah', 'basi', 'kotor', 'jorok', 'tidak enak',
    'ga enak', 'dingin', 'lambat sekali', 'lama banget', 'tidak profesional',
    'komplain', 'keluhan', 'minta refund', 'kembalikan uang', 'tipu',
    'bohong', 'marah', 'kesal banget', 'nyebelin', 'mengecewakan banget',
    'tidak akan kembali', 'ga akan balik', 'lapor', 'review jelek',
  ];

  /// Analisis sentiment dari teks customer.
  static SentimentResult analyze(String text) {
    final lower = text.toLowerCase();

    for (final kw in _urgentKeywords) {
      if (lower.contains(kw)) {
        return SentimentResult(
          level: SentimentLevel.urgent,
          reason: 'Keyword urgent: "$kw"',
        );
      }
    }

    int negativeHits = 0;
    String matchedKw = '';
    for (final kw in _negativeKeywords) {
      if (lower.contains(kw)) {
        negativeHits++;
        if (matchedKw.isEmpty) matchedKw = kw;
      }
    }

    if (negativeHits >= 1) {
      return SentimentResult(
        level: SentimentLevel.negative,
        reason: 'Keyword negatif: "$matchedKw" (+${negativeHits - 1} lainnya)',
      );
    }

    return const SentimentResult(level: SentimentLevel.neutral, reason: 'OK');
  }

  // ── Notifikasi konfirmasi booking ke customer ──────────────────────
  /// Dipanggil setelah booking berhasil dibuat & meja ter-assign.
  /// Mengirim push notification ke device customer sebagai konfirmasi.
  static Future<void> notifyCustomerBooking({
    required String customerUserId,
    required String customerName,
    required String bookingDate,
    required String bookingTime,
    required int guestCount,
    required String tableNumber,
    bool isWaitlisted = false,
  }) async {
    try {
      // 1. Ambil FCM token customer
      final tokens = await _getCustomerTokens(customerUserId);
      if (tokens.isEmpty) {
        debugPrint('[Notify] Tidak ada token untuk customer $customerUserId');
        return;
      }

      // 2. Susun pesan sesuai status booking
      final String title;
      final String body;

      if (isWaitlisted) {
        title = '📋 Reservasi Masuk Daftar Tunggu';
        body = 'Hi $customerName! Reservasi $bookingDate pukul $bookingTime '
            'untuk $guestCount orang masuk daftar tunggu. '
            'Kami akan hubungi Anda jika ada meja tersedia.';
      } else {
        title = '✅ Reservasi Dikonfirmasi!';
        body = 'Hi $customerName! Meja $tableNumber sudah disiapkan untuk '
            '$guestCount orang pada $bookingDate pukul $bookingTime. '
            'Sampai jumpa! 😊';
      }

      // 3. Kirim push notification
      await _sendPushNotifications(
        tokens: tokens,
        title: title,
        body: body,
        data: {
          'type': 'booking_confirmation',
          'booking_date': bookingDate,
          'booking_time': bookingTime,
          'table_number': tableNumber,
          'is_waitlisted': isWaitlisted.toString(),
          'screen': 'my_bookings', // Deep link ke halaman booking customer
        },
      );

      debugPrint('[Notify] Booking confirmation sent to customer $customerUserId');
    } catch (e) {
      debugPrint('[Notify] notifyCustomerBooking error: $e');
      // Jangan throw — gagal notif tidak boleh crash alur booking
    }
  }

  // ── Eskalasi ke manager ────────────────────────────────────────────
  /// Dipanggil hanya jika [result.shouldEscalate] == true.
  static Future<void> escalate({
    required String branchId,
    required String customerMessage,
    required SentimentResult result,
    String? customerName,
    String? sessionId,
  }) async {
    try {
      final tokens = await _getManagerTokens(branchId);
      if (tokens.isEmpty) {
        debugPrint('[Sentiment] Tidak ada manager token untuk branch $branchId');
        return;
      }

      final isUrgent = result.level == SentimentLevel.urgent;
      await _sendPushNotifications(
        tokens: tokens,
        title: isUrgent
            ? '🚨 URGENT — Customer Butuh Bantuan!'
            : '⚠️ Keluhan Customer',
        body: _truncate(customerMessage, 100),
        data: {
          'type': isUrgent ? 'urgent_escalation' : 'sentiment_escalation',
          'branch_id': branchId,
          'screen': 'escalation_inbox',
        },
      );

      await _logEscalation(
        branchId: branchId,
        customerMessage: customerMessage,
        sentimentLevel: result.level.name,
        reason: result.reason,
        customerName: customerName,
        sessionId: sessionId,
        managersNotified: tokens.length,
      );

      debugPrint('[Sentiment] Eskalasi selesai — ${tokens.length} manager dinotifikasi');
    } catch (e) {
      debugPrint('[Sentiment] Escalation error: $e');
    }
  }

  // ── Query FCM tokens customer ──────────────────────────────────────
  static Future<List<String>> _getCustomerTokens(String userId) async {
    try {
      final tokenRes = await Supabase.instance.client
          .from('device_tokens')
          .select('token')
          .eq('user_id', userId);

      return (tokenRes as List)
          .map((t) => t['token'] as String)
          .where((t) => t.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('[Notify] Get customer tokens error: $e');
      return [];
    }
  }

  // ── Query FCM tokens manager ───────────────────────────────────────
  static Future<List<String>> _getManagerTokens(String branchId) async {
    try {
      final sb = Supabase.instance.client;

      final staffRes = await sb
          .from('staff')
          .select('user_id')
          .eq('branch_id', branchId)
          .eq('is_active', true)
          .inFilter('role', ['manager', 'superadmin']);

      if ((staffRes as List).isEmpty) return [];

      final userIds = staffRes.map((s) => s['user_id'] as String).toList();

      final tokenRes = await sb
          .from('device_tokens')
          .select('token')
          .inFilter('user_id', userIds);

      return (tokenRes as List)
          .map((t) => t['token'] as String)
          .where((t) => t.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('[Sentiment] Get manager tokens error: $e');
      return [];
    }
  }

  // ── Kirim push via FCM proxy di Vercel ────────────────────────────
  static Future<void> _sendPushNotifications({
    required List<String> tokens,
    required String title,
    required String body,
    required Map<String, String> data,
  }) async {
    const proxyUrl =
        kIsWeb ? '/api/notify' : 'http://localhost:3000/api/notify';

    final res = await http
        .post(
          Uri.parse(proxyUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'tokens': tokens,
            'title': title,
            'body': body,
            'data': data,
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (res.statusCode != 200) {
      debugPrint('[Notify] Push error: ${res.statusCode} ${res.body}');
    }
  }

  // ── Log ke Supabase ────────────────────────────────────────────────
  static Future<void> _logEscalation({
    required String branchId,
    required String customerMessage,
    required String sentimentLevel,
    required String reason,
    String? customerName,
    String? sessionId,
    required int managersNotified,
  }) async {
    try {
      await Supabase.instance.client.from('chatbot_conversations').insert({
        'branch_id': branchId,
        'messages': [
          {
            'type': 'sentiment_escalation',
            'level': sentimentLevel,
            'reason': reason,
            'customer_message': customerMessage,
            'customer_name': customerName,
            'session_id': sessionId,
            'managers_notified': managersNotified,
            'escalated_at': DateTime.now().toIso8601String(),
          }
        ],
      });
    } catch (e) {
      debugPrint('[Sentiment] Log escalation error: $e');
    }
  }

  static String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }
}