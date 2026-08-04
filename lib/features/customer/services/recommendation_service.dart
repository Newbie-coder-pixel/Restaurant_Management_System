// lib/features/customer/services/recommendation_service.dart
//
// Recommendation layers:
// 1. Personal History  — items this customer frequently orders
// 2. Collaborative     — items frequently ordered TOGETHER WITH the customer's favorite items
// 3. Popular Fallback  — most popular menu items at the branch (for new/guest customers)
//
// Previously ALL 3 layers (including the popular fallback) filtered on
// orders.status == 'completed' — a status an order never has
// (a paid order's status is 'paid'; 'completed' is a booking status). As a
// result, getRecommendations() always returned empty, with no visible
// error — this recommendation feature silently never produced anything
// since it was created.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Recommendation result model ────────────────────────────────────────
class RecommendedItem {
  final String menuItemId;
  final String menuItemName;
  final double score;       // Relevance score (higher = more relevant)
  final String reason;      // Label to display to the customer

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
  /// Main entry point.
  /// Call this from the chatbot when a customer asks for a recommendation.
  static Future<RecommendationResult> getRecommendations({
    required String branchId,
    String? customerUserId,   // null if not logged in
    String? customerPhone,    // optional, for guest tracking
    int limit = 5,
  }) async {
    try {
      // ── Layer 1: Personal (if logged in) ──────────────────────────
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

      // ── Layer 2: Collaborative (based on co-occurrence) ────────────
      // First get the customer's favorite menu items as a seed
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
          excludeItemIds: seedItems, // Don't recommend items already frequently ordered
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
  // Query the items this customer has ordered most in the last 90 days
  static Future<List<RecommendedItem>> _getPersonalRecommendations({
    required String branchId,
    required String customerUserId,
    required int limit,
  }) async {
    try {
      final sb = Supabase.instance.client;
      final since = DateTime.now().subtract(const Duration(days: 90));

      // get_customer_order_items RPC rather than a direct SELECT — see
      // supabase/migrations/20260805070000_recommendation_service_rpc.sql.
      final res = await sb.rpc('get_customer_order_items', params: {
        'p_branch_id': branchId,
        'p_customer_user_id': customerUserId,
        'p_since': since.toIso8601String(),
      }) as List<dynamic>;

      if (res.isEmpty) return [];

      // Calculate frequency + total quantity per menu item
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

      // Sort by frequency desc, take top N
      final sorted = scores.values.toList()
        ..sort((a, b) => b.frequency.compareTo(a.frequency));

      return sorted.take(limit).map((s) => RecommendedItem(
            menuItemId: s.id,
            menuItemName: s.name,
            score: s.frequency.toDouble(),
            reason: 'Your favorite 🩷',
          )).toList();
    } catch (e) {
      debugPrint('[Recommendation] Personal error: $e');
      return [];
    }
  }

  // ── Helper: Get the customer's favorite item IDs (seed for collaborative) ─
  static Future<List<String>> _getCustomerFavorites({
    required String branchId,
    required String customerUserId,
    required int limit,
  }) async {
    try {
      final sb = Supabase.instance.client;
      final since = DateTime.now().subtract(const Duration(days: 90));

      // get_customer_order_items RPC rather than a direct SELECT — see
      // supabase/migrations/20260805070000_recommendation_service_rpc.sql.
      final res = await sb.rpc('get_customer_order_items', params: {
        'p_branch_id': branchId,
        'p_customer_user_id': customerUserId,
        'p_since': since.toIso8601String(),
      }) as List<dynamic>;

      final Map<String, int> freq = {};
      for (final item in res) {
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
  // Find other orders that contain the seed items → see what other items
  // frequently appear alongside them → recommend those
  static Future<List<RecommendedItem>> _getCollaborativeRecommendations({
    required String branchId,
    required List<String> seedItemIds,
    required List<String> excludeItemIds,
    required int limit,
  }) async {
    try {
      final sb = Supabase.instance.client;
      final since = DateTime.now().subtract(const Duration(days: 60));

      // Find all order_ids that contain one of the seed items — via RPC,
      // see supabase/migrations/20260805070000_recommendation_service_rpc.sql.
      final seedOrders = await sb.rpc('get_orders_containing_items', params: {
        'p_branch_id': branchId,
        'p_menu_item_ids': seedItemIds,
        'p_since': since.toIso8601String(),
      }) as List<dynamic>;

      if (seedOrders.isEmpty) return [];

      final orderIds = seedOrders
          .map((o) => o['order_id'] as String)
          .toSet()
          .toList();

      if (orderIds.isEmpty) return [];

      // From those orders, get all the other items — via RPC.
      final coItems = await sb.rpc('get_items_in_orders', params: {
        'p_order_ids': orderIds,
        'p_exclude_menu_item_ids': excludeItemIds,
      }) as List<dynamic>;

      if (coItems.isEmpty) return [];

      // Calculate co-occurrence score
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
            reason: 'Often ordered together with your favorites ⭐',
          )).toList();
    } catch (e) {
      debugPrint('[Recommendation] Collaborative error: $e');
      return [];
    }
  }

  // ── Layer 3: Popular Items (fallback) ─────────────────────────────
  // The most-ordered menu items at this branch in the last 30 days
  static Future<List<RecommendedItem>> _getPopularItems({
    required String branchId,
    required int limit,
  }) async {
    try {
      final sb = Supabase.instance.client;
      final since = DateTime.now().subtract(const Duration(days: 30));

      // get_branch_popular_items RPC rather than a direct SELECT — see
      // supabase/migrations/20260805070000_recommendation_service_rpc.sql.
      final res = await sb.rpc('get_branch_popular_items', params: {
        'p_branch_id': branchId,
        'p_since': since.toIso8601String(),
      }) as List<dynamic>;

      if (res.isEmpty) return [];

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

      // Score = order frequency × total qty (so items ordered often & in bulk rank higher)
      final sorted = scores.values.toList()
        ..sort((a, b) =>
            (b.frequency * b.totalQty).compareTo(a.frequency * a.totalQty));

      return sorted.take(limit).map((s) => RecommendedItem(
            menuItemId: s.id,
            menuItemName: s.name,
            score: (s.frequency * s.totalQty).toDouble(),
            reason: 'Most popular this week 🔥',
          )).toList();
    } catch (e) {
      debugPrint('[Recommendation] Popular error: $e');
      return [];
    }
  }

  /// Format the recommendation result as text to feed into the AI system prompt.
  /// The AI will use this data when a customer asks for a recommendation.
  static String formatForPrompt(RecommendationResult result) {
    if (result.isEmpty) return '(no recommendation data yet)';

    final buf = StringBuffer();
    buf.writeln('PERSONAL MENU RECOMMENDATION (${result.strategyUsed}):');
    for (int i = 0; i < result.items.length; i++) {
      final item = result.items[i];
      buf.writeln('${i + 1}. ${item.menuItemName} — ${item.reason}');
    }
    return buf.toString().trim();
  }
}

// ── Internal helper class ────────────────────────────────────────────
class _ItemScore {
  final String id;
  final String name;
  int frequency = 0;
  int totalQty = 0;

  _ItemScore({required this.id, required this.name});
}