import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import '../../../core/config/app_config.dart';

class ChatMessage {
  final String role;
  final String content;
  final DateTime timestamp;

  const ChatMessage({
    required this.role,
    required this.content,
    required this.timestamp,
  });

  Map<String, dynamic> toGroqMessage() => {'role': role, 'content': content};
}

class ChatResponse {
  final String reply;
  final String? action;
  final Map<String, dynamic>? actionData;

  const ChatResponse({required this.reply, this.action, this.actionData});
}

class OrderItemData {
  final String menuItemName;
  final int quantity;
  final String? notes;

  const OrderItemData({
    required this.menuItemName,
    required this.quantity,
    this.notes,
  });
}

class ChatbotApi {
  // On web, /api/chat is relative to the origin currently being served
  // (Vercel staff app project). On native builds (Android/iOS/desktop) there
  // is no such origin, so it has to hit the staff app's Vercel domain
  // explicitly — this used to be hardcoded to 'http://localhost:3000',
  // which on a real phone points back to the phone itself, so the chatbot
  // always failed outside of local dev.
  // Override for local dev: `--dart-define=CHAT_API_BASE_URL=http://localhost:3000`
  static String get _proxyUrl {
    if (kIsWeb) return '/api/chat';
    const override = String.fromEnvironment('CHAT_API_BASE_URL');
    final base = override.isNotEmpty ? override : AppConfig.staffAppUrl;
    return '$base/api/chat';
  }

  static const String _model = 'openai/gpt-oss-120b';

  static String _systemPrompt(String branchId,
      {String openingTime = '10:00',
      String closingTime = '22:00',
      String menuText = '(menu not loaded yet)'}) {
    final now = DateTime.now();
    final todayStr = '${now.day} ${_bulanIndo(now.month)} ${now.year}';
    return '''
You are RestaurantOS's friendly and professional AI assistant for restaurant staff.
Branch ID: $branchId
Today: $todayStr

LIST OF MENU ITEMS AVAILABLE AT THIS RESTAURANT (USE THIS DATA, DON'T MAKE THINGS UP):
$menuText
Only recommend or process orders from the menu list above. If an item isn't on the list, say that menu item isn't available.

MANDATORY ORDERING FLOW:
When a customer/staff member says they want to order food/drinks:
1. Show the available menu choices from the list above
2. Wait for the user to pick an item (by name or number). If the user answers with something that is NOT a menu name/number (e.g. "none", "nah", "no", etc.) BEFORE picking a menu item, REPEAT the menu selection question politely.
3. After the user picks a VALID item from the list, confirm the item and ask: "Any special notes for this order? (e.g. no vegetables, not spicy, extra sauce) Type 'none' if there aren't any."
4. An answer of "none" or "no" at this stage = notes: null. Process it IMMEDIATELY, DON'T ask again.
5. After getting the notes answer, output the confirmation + ACTION JSON:

ACTION:create_order
{"items":[{"name":"Menu Item Name","qty":1,"notes":"note or null"}],"table_notes":"table info if any"}

IMPORTANT ABOUT THE ORDER FLOW:
- Order: show menu → user picks → ask for notes → process. DON'T skip this order.
- "none" is ONLY a valid notes answer AFTER the user has already picked a menu item.
- If the user hasn't picked a menu item yet and says "none", it means they don't want to order yet, NOT that it's a note.

TABLE BOOKING/RESERVATION FLOW:
When a customer/staff member wants to book a table:
1. Ask for the guest's name, party size, arrival date, arrival time, and phone number (optional)
2. DATE: the user may mention the date in any format. You must interpret it intelligently:
   - "march 14" → March 14, ${now.year} (ALWAYS assume the current year if not stated)
   - "tomorrow" → today + 1
   - "next week" → estimate the date
   - NEVER ask the user to rewrite the date just because the year is missing. Just assume it.
3. VALIDATE the date (ONLY reject if it's truly already past):
   - Today is $todayStr
   - VALID ✅: today's date or later → process immediately
   - PAST ❌: a date before today → politely decline
4. VALIDATE the time: Operating hours are $openingTime - $closingTime local time. Decline if outside this range.
5. Once all data is complete and valid, output this EXACT format:

ACTION:create_booking
{"customer_name":"Guest Name","guest_count":2,"booking_date":"2026-03-19","booking_time":"10:00","phone":"08xx or null","special_requests":"note or null"}

booking_date format: YYYY-MM-DD
booking_time format: HH:MM

IMPORTANT:
- Reply in friendly, concise English
- Use emoji sparingly
- For questions unrelated to the restaurant, redirect back to restaurant topics
- Always state the FULL date (day + month + year) when asking for or confirming a date
''';
  }

  static String _bulanIndo(int month) {
    const list = [
      '',
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return list[month];
  }

  static Future<ChatResponse> sendMessage({
    required String sessionId,
    required String branchId,
    required String message,
    required List<ChatMessage> history,
    String? customerName,
  }) async {
    try {
      return await _callGroqProxy(branchId, message, history);
    } catch (e) {
      debugPrint('Groq proxy error: $e');
    }

    return _mockResponse(message);
  }

  static Future<Map<String, String>> _fetchBranchHours(String branchId) async {
    if (branchId.isEmpty) return {'opening': '10:00', 'closing': '22:00'};
    try {
      final res = await Supabase.instance.client
          .from('branches')
          .select('opening_time, closing_time')
          .eq('id', branchId)
          .maybeSingle();
      if (res != null) {
        final open =
            (res['opening_time'] as String?)?.substring(0, 5) ?? '10:00';
        final close =
            (res['closing_time'] as String?)?.substring(0, 5) ?? '22:00';
        return {'opening': open, 'closing': close};
      }
    } catch (_) {}
    return {'opening': '10:00', 'closing': '22:00'};
  }

  // ✅ FIXED: handle branchId null/empty + 2 separate queries to avoid error 400
  static Future<String> _fetchMenu(String branchId) async {
    // Guard: don't query if branchId is empty
    if (branchId.isEmpty) return '(branch not selected yet)';
    try {
      // Query 1: Fetch menu items without a join
      final items = await Supabase.instance.client
          .from('menu_items')
          .select('name, price, description, is_available, category_id')
          .eq('branch_id', branchId)
          .eq('is_available', true)
          .order('name');

      if ((items as List).isEmpty) return '(no menu items yet)';

      // Query 2: Fetch all categories for this branch
      final categories = await Supabase.instance.client
          .from('menu_categories')
          .select('id, name')
          .eq('branch_id', branchId);

      // Build a map of id -> category name
      final catMap = <String, String>{};
      for (final cat in (categories as List)) {
        catMap[cat['id'] as String] = cat['name'] as String;
      }

      final buf = StringBuffer();
      for (final item in items) {
        final cat = catMap[item['category_id']] ?? 'Umum';
        final price = (item['price'] as num?)?.toStringAsFixed(0) ?? '0';
        final desc = item['description'] as String?;
        buf.writeln(
            '- ${item['name']} (Rp $price) [$cat]${desc != null ? " — $desc" : ""}');
      }
      return buf.toString().trim();
    } catch (e) {
      debugPrint('Error fetch menu: $e');
      return '(failed to load menu)';
    }
  }

  static Future<ChatResponse> _callGroqProxy(
      String branchId, String message, List<ChatMessage> history) async {
    final hours = await _fetchBranchHours(branchId);
    final menuText = branchId.isNotEmpty
        ? await _fetchMenu(branchId)
        : '(select a branch to see the menu)';
    final recent =
        history.length > 14 ? history.sublist(history.length - 14) : history;
    final messages = [
      {
        'role': 'system',
        'content': _systemPrompt(branchId,
            openingTime: hours['opening']!,
            closingTime: hours['closing']!,
            menuText: menuText)
      },
      ...recent.map((m) => m.toGroqMessage()),
      {'role': 'user', 'content': message},
    ];

    final res = await http
        .post(
          Uri.parse(_proxyUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'model': _model,
            // gpt-oss models spend part of max_tokens on a hidden "reasoning"
            // field before writing the actual reply — "low" keeps that
            // overhead small so replies don't get cut off empty.
            'reasoning_effort': 'low',
            'messages': messages,
            'max_tokens': 600,
            'temperature': 0.6,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final raw =
          (data['choices'][0]['message']['content'] as String).trim();
      return _parseResponse(raw);
    }

    // api/chat.js forwards Groq's status code verbatim, so a 404 here can
    // mean either "the Vercel function itself is missing" or "Groq rejected
    // the request" (e.g. a decommissioned model) — the body's shape tells
    // them apart, since only the latter has a Groq-style `error.message`.
    final groqError = _tryParseGroqError(res.body);
    if (groqError != null) {
      throw Exception('Groq error: $groqError');
    }

    // Error 404 → the /api/chat function isn't deployed on Vercel yet
    if (res.statusCode == 404) {
      throw Exception(
        'Proxy 404: Serverless function /api/chat not found. '
        'Make sure api/chat.js is deployed on Vercel '
        'and vercel.json has a "functions" block.',
      );
    }

    throw Exception('Proxy error ${res.statusCode}: ${res.body}');
  }

  static String? _tryParseGroqError(String body) {
    try {
      final decoded = jsonDecode(body);
      final error = decoded is Map ? decoded['error'] : null;
      if (error is Map && error['message'] is String) {
        return error['message'] as String;
      }
    } catch (_) {
      // Not JSON, or not the Groq error shape — fall through.
    }
    return null;
  }

  static ChatResponse _parseResponse(String raw) {
    for (final marker in ['ACTION:create_booking', 'ACTION:create_order']) {
      final idx = raw.indexOf(marker);
      if (idx != -1) {
        final before = raw.substring(0, idx).trim();
        final jsonStart = raw.indexOf('{', idx);
        final jsonEnd = raw.lastIndexOf('}');
        if (jsonStart != -1 && jsonEnd != -1) {
          try {
            final jsonStr = raw.substring(jsonStart, jsonEnd + 1);
            final actionData = jsonDecode(jsonStr) as Map<String, dynamic>;
            final isBooking = marker == 'ACTION:create_booking';
            return ChatResponse(
              reply: before.isNotEmpty
                  ? before
                  : isBooking
                      ? '📅 Reservation ready to confirm!'
                      : '✅ Order ready to confirm!',
              action: isBooking ? 'create_booking' : 'create_order',
              actionData: actionData,
            );
          } catch (_) {}
        }
      }
    }
    return ChatResponse(reply: raw);
  }

  static ChatResponse _mockResponse(String message) {
    final msg = message.toLowerCase();
    if (msg.contains('menu') || msg.contains('food')) {
      return const ChatResponse(
          reply:
              '🍽️ Open the Menu page in the navigation drawer (☰) to see the full menu.');
    }
    if (msg.contains('booking') || msg.contains('reservation')) {
      return const ChatResponse(
          reply:
              '📅 Open the Reservations page in the navigation drawer (☰) to make a reservation.');
    }
    return const ChatResponse(
        reply: '🤖 Chatbot is currently unavailable. Please try again later.');
  }
}