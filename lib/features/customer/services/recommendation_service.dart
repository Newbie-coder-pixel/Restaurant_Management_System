// lib/features/customer/services/recommendation_service.dart
//
// Layer rekomendasi:
// 1. Personal History  — item yang sering dipesan customer ini
// 2. Collaborative     — item yang sering dipesan BARENG item favorit customer
// 3. Popular Fallback  — menu terpopuler di branch (untuk customer baru/guest)

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Model hasil rekomendasi ────────────────────────────────────────────
class RecommendedItem {
  final String menuItemId;
  final String menuItemName;
  final double score;       // Skor relevansi (makin tinggi makin relevan)
  final String reason;      // Label untuk ditampilkan ke customer

  const RecommendedItem({
    required this.menuItemId,
    required this.menuItemName,
    required this.score,
    required this.reason,
  });
}

class RecommendationResult {
  final List<RecommendedItem> items;
  final String strategyUsed; // 'personal' | 'collaborative' | 'popular'

  const RecommendationResult({
    required this.items,
    required this.strategyUsed,
  });

  bool get isEmpty => items.isEmpty;
}

// ── Service ────────────────────────────────────────────────────────────
class RecommendationService {
  /// Entry point utama.
  /// Panggil ini dari chatbot saat customer minta rekomendasi.
  static Future<RecommendationResult> getRecommendations({
    required String branchId,
    String? customerUserId,   // null jika belum login
    String? customerPhone,    // opsional, untuk tracking guest
    int limit = 5,
  }) async {
    try {
      // ── Layer 1: Personal (jika sudah login) ──────────────────────
      if (customerUserId != null) {
        final personal = await _getPersonalRecommendations(
          branchId: branchId,
          customerUserId: customerUserId,
          limit: limit,
        );
        if (personal.isNotEmpty) {
          return RecommendationResult(
            items: personal,
            strategyUsed: 'personal',
          );
        }
      }

      // ── Layer 2: Collaborative (berdasarkan co-occurrence) ────────
      // Ambil menu favorit customer dulu sebagai seed
      final seedItems = customerUserId != null
          ? await _getCustomerFavorites(
              branchId: branchId,
              customerUserId: customerUserId,
              limit: 3,
            )
          : <String>[];

      if (seedItems.isNotEmpty) {
        final collaborative = await _getCollaborativeRecommendations(
          branchId: branchId,
          seedItemIds: seedItems,
          excludeItemIds: seedItems, // Jangan rekomendasikan yang sudah sering dipesan
          limit: limit,
        );
        if (collaborative.isNotEmpty) {
          return RecommendationResult(
            items: collaborative,
            strategyUsed: 'collaborative',
          );
        }
      }

      // ── Layer 3: Popular fallback ─────────────────────────────────
      final popular = await _getPopularItems(
        branchId: branchId,
        limit: limit,
      );
      return RecommendationResult(
        items: popular,
        strategyUsed: 'popular',
      );
    } catch (e) {
      debugPrint('[Recommendation] Error: $e');
      return const RecommendationResult(items: [], strategyUsed: 'error');
    }
  }

  // ── Layer 1: Personal History ──────────────────────────────────────
  // Query item yang paling sering dipesan customer ini dalam 90 hari terakhir
  static Future<List<RecommendedItem>> _getPersonalRecommendations({
    required String branchId,
    required String customerUserId,
    required int limit,
  }) async {
    try {
      final sb = Supabase.instance.client;
      final since = DateTime.now().subtract(const Duration(days: 90));

      // Ambil semua order_items dari order customer ini yang completed
      final res = await sb
          .from('order_items')
          .select(
              'menu_item_id, menu_item_name, quantity, orders!inner(branch_id, status, customer_user_id, created_at)')
          .eq('orders.branch_id', branchId)
          .eq('orders.customer_user_id', customerUserId)
          .eq('orders.status', 'completed')
          .gte('orders.created_at', since.toIso8601String());

      if ((res as List).isEmpty) return [];

      // Hitung frekuensi + total quantity per menu item
      final Map<String, _ItemScore> scores = {};
      for (final item in res) {
        final id = item['menu_item_id'] as String? ?? '';
        final name = item['menu_item_name'] as String? ?? 'Unknown';
        final qty = (item['quantity'] as num?)?.toInt() ?? 1;
        if (id.isEmpty) continue;

        scores.putIfAbsent(id, () => _ItemScore(id: id, name: name));
        scores[id]!.frequency++;
        scores[id]!.totalQty += qty;
      }

      if (scores.isEmpty) return [];

      // Sort by frequency desc, ambil top N
      final sorted = scores.values.toList()
        ..sort((a, b) => b.frequency.compareTo(a.frequency));

      return sorted.take(limit).map((s) => RecommendedItem(
            menuItemId: s.id,
            menuItemName: s.name,
            score: s.frequency.toDouble(),
            reason: 'Favorit kamu 🩷',
          )).toList();
    } catch (e) {
      debugPrint('[Recommendation] Personal error: $e');
      return [];
    }
  }

  // ── Helper: Ambil ID item favorit customer (seed untuk collaborative) ─
  static Future<List<String>> _getCustomerFavorites({
    required String branchId,
    required String customerUserId,
    required int limit,
  }) async {
    try {
      final sb = Supabase.instance.client;
      final since = DateTime.now().subtract(const Duration(days: 90));

      final res = await sb
          .from('order_items')
          .select('menu_item_id, quantity, orders!inner(branch_id, status, customer_user_id, created_at)')
          .eq('orders.branch_id', branchId)
          .eq('orders.customer_user_id', customerUserId)
          .eq('orders.status', 'completed')
          .gte('orders.created_at', since.toIso8601String());

      final Map<String, int> freq = {};
      for (final item in res as List) {
        final id = item['menu_item_id'] as String? ?? '';
        if (id.isEmpty) continue;
        freq[id] = (freq[id] ?? 0) + 1;
      }

      return (freq.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .take(limit)
          .map((e) => e.key)
          .toList();
    } catch (e) {
      return [];
    }
  }

  // ── Layer 2: Collaborative Filtering (Item Co-occurrence) ─────────
  // Cari order lain yang mengandung seed items → lihat item lain apa
  // yang sering muncul bareng → rekomendasikan itu
  static Future<List<RecommendedItem>> _getCollaborativeRecommendations({
    required String branchId,
    required List<String> seedItemIds,
    required List<String> excludeItemIds,
    required int limit,
  }) async {
    try {
      final sb = Supabase.instance.client;
      final since = DateTime.now().subtract(const Duration(days: 60));

      // Cari semua order_id yang mengandung salah satu seed item
      final seedOrders = await sb
          .from('order_items')
          .select('order_id, orders!inner(branch_id, status, created_at)')
          .inFilter('menu_item_id', seedItemIds)
          .eq('orders.branch_id', branchId)
          .eq('orders.status', 'completed')
          .gte('orders.created_at', since.toIso8601String());

      if ((seedOrders as List).isEmpty) return [];

      final orderIds = seedOrders
          .map((o) => o['order_id'] as String)
          .toSet()
          .toList();

      if (orderIds.isEmpty) return [];

      // Dari order-order tersebut, ambil semua item lainnya
      final coItems = await sb
          .from('order_items')
          .select('menu_item_id, menu_item_name, quantity')
          .inFilter('order_id', orderIds)
          .not('menu_item_id', 'in', '(${excludeItemIds.join(',')})');

      if ((coItems as List).isEmpty) return [];

      // Hitung co-occurrence score
      final Map<String, _ItemScore> scores = {};
      for (final item in coItems) {
        final id = item['menu_item_id'] as String? ?? '';
        final name = item['menu_item_name'] as String? ?? 'Unknown';
        if (id.isEmpty || excludeItemIds.contains(id)) continue;

        scores.putIfAbsent(id, () => _ItemScore(id: id, name: name));
        scores[id]!.frequency++;
      }

      if (scores.isEmpty) return [];

      final sorted = scores.values.toList()
        ..sort((a, b) => b.frequency.compareTo(a.frequency));

      return sorted.take(limit).map((s) => RecommendedItem(
            menuItemId: s.id,
            menuItemName: s.name,
            score: s.frequency.toDouble(),
            reason: 'Sering dipesan bareng favoritmu ⭐',
          )).toList();
    } catch (e) {
      debugPrint('[Recommendation] Collaborative error: $e');
      return [];
    }
  }

  // ── Layer 3: Popular Items (fallback) ─────────────────────────────
  // Menu yang paling banyak dipesan di branch ini dalam 30 hari terakhir
  static Future<List<RecommendedItem>> _getPopularItems({
    required String branchId,
    required int limit,
  }) async {
    try {
      final sb = Supabase.instance.client;
      final since = DateTime.now().subtract(const Duration(days: 30));

      final res = await sb
          .from('order_items')
          .select('menu_item_id, menu_item_name, quantity, orders!inner(branch_id, status, created_at)')
          .eq('orders.branch_id', branchId)
          .eq('orders.status', 'completed')
          .gte('orders.created_at', since.toIso8601String());

      if ((res as List).isEmpty) return [];

      final Map<String, _ItemScore> scores = {};
      for (final item in res) {
        final id = item['menu_item_id'] as String? ?? '';
        final name = item['menu_item_name'] as String? ?? 'Unknown';
        final qty = (item['quantity'] as num?)?.toInt() ?? 1;
        if (id.isEmpty) continue;

        scores.putIfAbsent(id, () => _ItemScore(id: id, name: name));
        scores[id]!.frequency++;
        scores[id]!.totalQty += qty;
      }

      if (scores.isEmpty) return [];

      // Score = frekuensi order × total qty (biar yang sering dipesan banyak naik)
      final sorted = scores.values.toList()
        ..sort((a, b) =>
            (b.frequency * b.totalQty).compareTo(a.frequency * a.totalQty));

      return sorted.take(limit).map((s) => RecommendedItem(
            menuItemId: s.id,
            menuItemName: s.name,
            score: (s.frequency * s.totalQty).toDouble(),
            reason: 'Terpopuler minggu ini 🔥',
          )).toList();
    } catch (e) {
      debugPrint('[Recommendation] Popular error: $e');
      return [];
    }
  }

  /// Format hasil rekomendasi jadi teks untuk dimasukkan ke system prompt AI.
  /// AI akan menggunakan data ini saat customer minta rekomendasi.
  static String formatForPrompt(RecommendationResult result) {
    if (result.isEmpty) return '(belum ada data rekomendasi)';

    final buf = StringBuffer();
    buf.writeln('REKOMENDASI MENU PERSONAL (${result.strategyUsed}):');
    for (int i = 0; i < result.items.length; i++) {
      final item = result.items[i];
      buf.writeln('${i + 1}. ${item.menuItemName} — ${item.reason}');
    }
    return buf.toString().trim();
  }
}

// ── Helper class internal ──────────────────────────────────────────────
class _ItemScore {
  final String id;
  final String name;
  int frequency = 0;
  int totalQty = 0;

  _ItemScore({required this.id, required this.name});
}