// lib/features/qr_order/services/qr_chatbot_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/app_config.dart';
import '../providers/qr_cart_provider.dart' show MenuItem;

/// Groq proxy client + prompt builder for the QR app's menu-recommendation
/// chatbot. Deliberately separate from ChatbotApi (staff) and the customer
/// app's CustomerChatbotScreen — this one only ever talks about the menu for
/// a single already-seated table, never bookings/analytics.
class QrChatbotService {
  QrChatbotService._();

  static String get proxyUrl {
    if (kIsWeb) return '/api/chat';
    const override = String.fromEnvironment('CHAT_API_BASE_URL');
    final base = override.isNotEmpty ? override : AppConfig.qrAppUrl;
    return '$base/api/chat';
  }

  static const String model = 'llama-3.3-70b-versatile';

  /// [allowAddToCart] is false on the order-tracking screen — there's no
  /// cart FAB there to check out a chat-added item, so the assistant is
  /// told to point the customer at the "Add Order" button instead.
  static String buildSystemPrompt({
    required String branchName,
    required String tableName,
    required String openingTime,
    required String closingTime,
    required List<MenuItem> menu,
    required bool allowAddToCart,
    String? weatherContext,
    String topSellersText = '(no sales data yet)',
    String? orderStatusContext,
  }) {
    final buf = StringBuffer();
    for (final item in menu) {
      buf.write('- ${item.name} (Rp ${item.price.toStringAsFixed(0)}) [${item.categoryName}]');
      if (item.description.isNotEmpty) buf.write(' — ${item.description}');
      buf.write(' | Prep: ${item.preparationTimeMinutes}min');
      if (item.allergens.isNotEmpty) {
        buf.write(' | ⚠️ Allergen: ${item.allergens.join(', ')}');
      }
      if (item.dietaryTags.isNotEmpty) {
        buf.write(' | 🥗 ${item.dietaryTags.join(', ')}');
      }
      buf.writeln();
    }
    final menuText = buf.toString().trim().isEmpty
        ? '(menu not loaded yet)'
        : buf.toString().trim();

    final addToCartSection = allowAddToCart
        ? '''
ADD TO CART:
If the customer clearly wants to add an item to their cart (e.g. "add 2 of that",
"I'll take the Nasi Goreng"), confirm the item + quantity, then output EXACTLY
this format with nothing else after it:

ACTION:add_to_cart
{"items":[{"name":"Exact Menu Name","quantity":1,"notes":"note or null"}]}

RULES:
- The "name" must match the menu list above EXACTLY (case-sensitive)
- Never output ACTION:add_to_cart for an item not in the menu list
- Never output ACTION:add_to_cart until the customer has clearly confirmed
- Checkout/payment itself happens on the Cart screen — you only add items,
  you never take payment or finalize the order'''
        : '''
The customer already placed an order and is tracking it — you cannot add
items to their cart from here. If they want something else, tell them to tap
the "Add Order" button on this screen, which reopens the menu (and this chat)
in ordering mode.''';

    final orderStatusSection = orderStatusContext != null
        ? '''

LIVE ORDER STATUS (real-time, read directly from the restaurant's database —
this is the ONLY source you may use to answer "where's my order" / "sudah
sampai mana" questions):
$orderStatusContext
When asked about order progress, answer directly using this data — do NOT
tell the customer you can't track status or to ask staff instead, you have
the real, current status right here.'''
        : '';

    return '''
You are a friendly AI menu assistant for $branchName, helping a customer
seated at $tableName who is ordering via QR code on their phone.
Operating hours: $openingTime - $closingTime.

MENU (use ONLY this data — never invent items, prices, or availability):
$menuText

YOUR JOB:
- Recommend menu items based on what the customer asks (mood, budget, spice
  level, dietary need, pairing, popularity, etc.)
- Answer questions about ingredients, price, allergens, dietary tags, and
  preparation time
- Keep answers short and appetizing — this is a small mobile chat panel, not
  a report

REAL CONTEXT (verified data — this is the ONLY source you may use for
weather or popularity claims):
${weatherContext ?? "Weather info not available for this customer."}
Real sales data: $topSellersText
$orderStatusSection

RECOMMENDATION RULES (STRICT — NEVER HALLUCINATE):
- NEVER invent or guess sales numbers, "customer favorites", or popularity
  claims of any kind. Only cite the "Real sales data" line above, and only
  if it isn't "(no sales data yet)". That line already tells you which time
  period the numbers cover (today / the past 7 days / the past 30 days) —
  ALWAYS state that same period when you mention it (e.g. say "this week's
  most ordered item is..." if the data says "the past 7 days", never say
  "today" if the data doesn't). If the line says "(no sales data yet)", say
  plainly that there's no sales data yet instead of making a claim up — you
  can still recommend based on the menu's own attributes (ingredients,
  category, price) in that case.
- If the customer asks for a general recommendation ("recommend me
  something", "what's good?", "what's popular?") without stating a
  preference (mood, spice level, budget, dietary need) AND they haven't
  already told you one earlier in this conversation, ask ONE short
  clarifying question first (e.g. "Spicy or mild?" / "Any budget in mind?"
  / "Vegetarian?") instead of guessing blindly.
- Exception: if the weather context above is available (not "not
  available"), that alone is enough for a sensible first suggestion — you
  may recommend directly, explain the weather reasoning ("since it's
  pretty hot right now, something cold might hit the spot..."), and cite
  the real sales data (with its correct time period) if it applies, instead
  of asking further questions.
- Never state or imply an item is "popular", "a favorite", or "best-selling"
  unless it is literally in the real sales data line above — and always with
  that line's actual time period, never a period you made up.

$addToCartSection

STYLE RULES:
- Reply in the same language the customer writes in (Indonesian or English)
- Use emojis sparingly
- If asked about something unrelated to this restaurant's menu or dining
  experience, politely redirect back to menu topics
''';
  }

  static Future<String> sendMessage({
    required String systemPrompt,
    required List<Map<String, String>> history,
    required String message,
  }) async {
    final res = await http
        .post(
          Uri.parse(proxyUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'model': model,
            'messages': [
              {'role': 'system', 'content': systemPrompt},
              ...history,
              {'role': 'user', 'content': message},
            ],
            'max_tokens': 500,
            'temperature': 0.6,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return (data['choices'][0]['message']['content'] as String).trim();
    }
    if (res.statusCode == 404) {
      throw Exception(
          'Proxy 404: /api/chat is not deployed on this Vercel project yet.');
    }
    if (res.statusCode == 500) {
      final body = jsonDecode(res.body);
      if ((body['error'] as String?)?.contains('GROQ_API_KEY') == true) {
        throw Exception('GROQ_API_KEY is not configured for this project.');
      }
    }
    throw Exception('Proxy error ${res.statusCode}: ${res.body}');
  }

  /// Mirrors QrMenuScreen._parseItems — kept here too so the chatbot can
  /// build its menu context without depending on that screen's private state.
  static List<MenuItem> parseMenuRows(List<Map<String, dynamic>> rows) {
    return rows.map((row) {
      final cat = row['menu_categories'] as Map<String, dynamic>?;
      return MenuItem(
        id: row['id'] as String,
        name: row['name'] as String,
        description: row['description'] as String? ?? '',
        price: (row['price'] as num).toDouble(),
        categoryId: row['category_id'] as String? ?? '',
        categoryName: cat?['name'] as String? ?? 'Other',
        imageUrl: row['image_url'] as String?,
        isAvailable: row['is_available'] as bool? ?? true,
        sortOrder: row['sort_order'] as int? ?? 0,
        preparationTimeMinutes: row['preparation_time_minutes'] as int? ?? 15,
        allergens: List<String>.from(row['allergens'] as List? ?? []),
        dietaryTags: List<String>.from(row['dietary_tags'] as List? ?? []),
      );
    }).toList();
  }
}
