// lib/features/customer/services/sentiment_escalation_service.dart
//
// Alur:
// 1. CustomerChatbotScreen panggil SentimentEscalationService.analyze(text)
// 2. Jika sentiment == negative/urgent → escalate()
// 3. escalate() → query manager tokens → kirim FCM via Vercel proxy → log ke Supabase

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Hasil analisis sentiment ───────────────────────────────────────────
enum SentimentLevel { neutral, negative, urgent }

class SentimentResult {
  final SentimentLevel level;
  final String reason; // Untuk logging/debug

  const SentimentResult({required this.level, required this.reason});

  bool get shouldEscalate => level != SentimentLevel.neutral;
}

// ── Service ────────────────────────────────────────────────────────────
class SentimentEscalationService {
  // ── Keyword-based detection (fast, no API call) ────────────────────
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
  /// Menggunakan keyword matching (cepat, tanpa API call).
  static SentimentResult analyze(String text) {
    final lower = text.toLowerCase();

    // Cek urgent dulu (lebih prioritas)
    for (final kw in _urgentKeywords) {
      if (lower.contains(kw)) {
        return SentimentResult(
          level: SentimentLevel.urgent,
          reason: 'Keyword urgent: "$kw"',
        );
      }
    }

    // Cek negative
    int negativeHits = 0;
    String matchedKw = '';
    for (final kw in _negativeKeywords) {
      if (lower.contains(kw)) {
        negativeHits++;
        if (matchedKw.isEmpty) matchedKw = kw;
      }
    }

    // 1 keyword negatif kuat = eskalasi, atau 2+ keyword negatif ringan
    if (negativeHits >= 1) {
      return SentimentResult(
        level: SentimentLevel.negative,
        reason: 'Keyword negatif: "$matchedKw" (+${negativeHits - 1} lainnya)',
      );
    }

    return const SentimentResult(level: SentimentLevel.neutral, reason: 'OK');
  }

  /// Eskalasi ke manager — kirim notifikasi push + log ke Supabase.
  /// Dipanggil hanya jika [result.shouldEscalate] == true.
  static Future<void> escalate({
    required String branchId,
    required String customerMessage,
    required SentimentResult result,
    String? customerName,
    String? sessionId,
  }) async {
    try {
      // 1. Ambil FCM tokens semua manager aktif di branch ini
      final tokens = await _getManagerTokens(branchId);
      if (tokens.isEmpty) {
        debugPrint('[Sentiment] Tidak ada manager token untuk branch $branchId');
        return;
      }

      // 2. Kirim notifikasi push via FCM proxy
      final isUrgent = result.level == SentimentLevel.urgent;
      await _sendPushNotifications(
        tokens: tokens,
        title: isUrgent ? '🚨 URGENT — Customer Butuh Bantuan!' : '⚠️ Keluhan Customer',
        body: _truncate(customerMessage, 100),
        branchId: branchId,
        isUrgent: isUrgent,
      );

      // 3. Log eskalasi ke Supabase untuk audit trail
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
      // Jangan throw — jangan sampai eskalasi gagal malah crash chatbot
    }
  }

  // ── Query FCM tokens manager ───────────────────────────────────────
  static Future<List<String>> _getManagerTokens(String branchId) async {
    try {
      final sb = Supabase.instance.client;

      // Ambil user_id semua manager + superadmin aktif di branch ini
      final staffRes = await sb
          .from('staff')
          .select('user_id')
          .eq('branch_id', branchId)
          .eq('is_active', true)
          .inFilter('role', ['manager', 'superadmin']);

      if ((staffRes as List).isEmpty) return [];

      final userIds =
          staffRes.map((s) => s['user_id'] as String).toList();

      // Ambil FCM token dari device_tokens
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
  // Vercel proxy endpoint: /api/notify
  // (perlu dibuat di api/notify.js — lihat instruksi di bawah)
  static Future<void> _sendPushNotifications({
    required List<String> tokens,
    required String title,
    required String body,
    required String branchId,
    required bool isUrgent,
  }) async {
    const proxyUrl = kIsWeb ? '/api/notify' : 'http://localhost:3000/api/notify';

    // Kirim dalam batch (FCM multicast maksimal 500 token per request)
    // Untuk restoran, jarang lebih dari 10 manager, jadi 1 request cukup
    final res = await http
        .post(
          Uri.parse(proxyUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'tokens': tokens,
            'title': title,
            'body': body,
            'data': {
              'type': isUrgent ? 'urgent_escalation' : 'sentiment_escalation',
              'branch_id': branchId,
              'screen': 'escalation_inbox', // Deep link target di app manager
            },
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (res.statusCode != 200) {
      debugPrint('[Sentiment] Push notif error: ${res.statusCode} ${res.body}');
    }
  }

  // ── Log ke Supabase (audit trail) ─────────────────────────────────
  // Menggunakan tabel chatbot_conversations yang sudah ada
  // (field: id, branch_id, messages jsonb, created_at, dll)
  // Jika ingin tabel terpisah, bisa buat tabel baru 'sentiment_escalations'
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