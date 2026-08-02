// lib/features/customer/services/sentiment_escalation_service.dart
//
// Flow:
// 1. CustomerChatbotScreen calls SentimentEscalationService.analyze(text)
// 2. If sentiment == negative/urgent → escalate()
// 3. escalate() → query manager tokens → send FCM via Vercel proxy → log to Supabase
// 4. notifyCustomerBooking() → query customer token → send FCM booking confirmation

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/app_config.dart';

// ── Sentiment analysis result ──────────────────────────────────────────
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

  /// Analyze sentiment from customer text.
  static SentimentResult analyze(String text) {
    final lower = text.toLowerCase();

    for (final kw in _urgentKeywords) {
      if (lower.contains(kw)) {
        return SentimentResult(
          level: SentimentLevel.urgent,
          reason: 'Urgent keyword: "$kw"',
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
        reason: 'Negative keyword: "$matchedKw" (+${negativeHits - 1} more)',
      );
    }

    return const SentimentResult(level: SentimentLevel.neutral, reason: 'OK');
  }

  // ── Booking confirmation notification to customer ──────────────────
  /// Called after a booking is successfully created & the table is assigned.
  /// Sends a push notification to the customer's device as confirmation.
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
      // 1. Get the customer's FCM token
      final tokens = await _getCustomerTokens(customerUserId);
      if (tokens.isEmpty) {
        debugPrint('[Notify] No token for customer $customerUserId');
        return;
      }

      // 2. Compose the message based on booking status
      final String title;
      final String body;

      if (isWaitlisted) {
        title = '📋 Reservation Added to Waitlist';
        body = 'Hi $customerName! Your reservation for $bookingDate at $bookingTime '
            'for $guestCount guest(s) has been added to the waitlist. '
            'We will contact you if a table becomes available.';
      } else {
        title = '✅ Reservation Confirmed!';
        body = 'Hi $customerName! Table $tableNumber is ready for '
            '$guestCount guest(s) on $bookingDate at $bookingTime. '
            'See you soon! 😊';
      }

      // 3. Send the push notification
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
          'screen': 'my_bookings', // Deep link to the customer's bookings page
        },
      );

      debugPrint('[Notify] Booking confirmation sent to customer $customerUserId');
    } catch (e) {
      debugPrint('[Notify] notifyCustomerBooking error: $e');
      // Don't throw — a failed notification must not crash the booking flow
    }
  }

  // ── Escalation to manager ────────────────────────────────────────────
  /// Called only if [result.shouldEscalate] == true.
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
        debugPrint('[Sentiment] No manager token for branch $branchId');
        return;
      }

      final isUrgent = result.level == SentimentLevel.urgent;
      await _sendPushNotifications(
        tokens: tokens,
        title: isUrgent
            ? '🚨 URGENT — Customer Needs Help!'
            : '⚠️ Customer Complaint',
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

      debugPrint('[Sentiment] Escalation complete — ${tokens.length} manager(s) notified');
    } catch (e) {
      debugPrint('[Sentiment] Escalation error: $e');
    }
  }

  // ── Query customer FCM tokens ────────────────────────────────────────
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

  // ── Query manager FCM tokens ─────────────────────────────────────────
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

  // ── Send push via the FCM proxy on Vercel ──────────────────────────
  static Future<void> _sendPushNotifications({
    required List<String> tokens,
    required String title,
    required String body,
    required Map<String, String> data,
  }) async {
    // Same as ChatbotApi/customer_chatbot_screen — native builds have no
    // origin for the relative path '/api/notify', so we must hit the
    // customer app's Vercel domain explicitly. It used to be hardcoded to
    // localhost:3000, which always failed on real phones, so push
    // notifications (escalation & booking confirmation) never got sent
    // outside of local dev.
    // Local dev override: `--dart-define=NOTIFY_API_BASE_URL=http://localhost:3000`
    final String proxyUrl;
    if (kIsWeb) {
      proxyUrl = '/api/notify';
    } else {
      const override = String.fromEnvironment('NOTIFY_API_BASE_URL');
      final base = override.isNotEmpty ? override : AppConfig.customerAppUrl;
      proxyUrl = '$base/api/notify';
    }

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

  // ── Log to Supabase ──────────────────────────────────────────────────
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