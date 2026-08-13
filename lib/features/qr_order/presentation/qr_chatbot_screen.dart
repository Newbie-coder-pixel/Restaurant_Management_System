// lib/features/qr_order/presentation/qr_chatbot_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../data/qr_order_repository.dart';
import '../providers/qr_cart_provider.dart';
import '../services/qr_chatbot_service.dart';
import '../services/qr_weather_service.dart';
import '../../../core/theme/app_theme.dart';

class _QrChatMessage {
  final String role;
  final String content;
  final DateTime timestamp;
  _QrChatMessage({required this.role, required this.content})
      : timestamp = DateTime.now();
}

const _quickActions = [
  ('✨ Recommend something', 'Recommend a menu for me'),
  ('🔥 Popular picks', "What's popular here?"),
  ('🌿 Vegetarian', 'What vegetarian options do you have?'),
  ('⚠️ Allergies', 'I have allergies, can you help me pick something safe?'),
  ('💸 Budget-friendly', "What's good and cheap?"),
];

// Quick-reply chips shown while waiting for the customer to answer the
// hot/cold fallback question (see _awaitingWeatherReply).
const _weatherFallbackReplies = [
  ('🔥 Panas/gerah', 'Lagi panas dan gerah di sini'),
  ('❄️ Sejuk/adem', 'Lagi sejuk dan adem di sini'),
];

// Free-text triggers that mean "give me a general recommendation" — these
// are gated on a weather check (see _isRecommendationTrigger) so the AI has
// real context instead of guessing. Deliberately excludes generic "good"
// wording that could false-positive on unrelated chat.
const _recommendationKeywords = [
  'recommend', 'recommendation', 'suggest', 'suggestion',
  'rekomendasi', 'sarankan', 'usulkan', 'usul',
  'popular', 'terlaris', 'best seller', 'bestseller', 'laris',
  'paling enak', 'apa yang enak', 'menu apa yang enak', 'menu apa yang cocok',
];

// Gates _mentionsAnotherQueue (see below) so plain digits in unrelated
// sentences ("order 2 fried rice") never false-trigger the block — only
// digits paired with actual queue/order-tracking language do.
const _queueTrackingKeywords = [
  'antrian', 'antrean', 'giliran', 'nomor antrian', 'no antrian',
  'queue', 'order number', 'order no', 'no order', 'nomor order',
  'status pesanan', 'status order', 'cek pesanan', 'cek order',
  'sampai mana', 'sudah sampai', 'udah sampai', 'gimana pesanan',
  'pesanan nomor', 'order nomor',
];

/// Strips everything but digits and leading zeros, so "A001", "001", and "1"
/// all normalize the same way for comparison.
String? _normalizeQueueToken(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  final stripped = digits.replaceFirst(RegExp(r'^0+'), '');
  return stripped.isEmpty ? '0' : stripped;
}

/// Menu-recommendation chatbot for the QR ordering flow. Shown while
/// browsing the menu (with add-to-cart) and while tracking an order
/// (Q&A only) — never during cart/checkout/payment. See QrChatbotOverlay
/// for the route gating.
class QrChatbotScreen extends ConsumerStatefulWidget {
  final String tableId;
  final String? orderId;
  final bool allowAddToCart;
  final VoidCallback onClose;

  const QrChatbotScreen({
    super.key,
    required this.tableId,
    this.orderId,
    required this.allowAddToCart,
    required this.onClose,
  });

  @override
  ConsumerState<QrChatbotScreen> createState() => _QrChatbotScreenState();
}

class _QrChatbotScreenState extends ConsumerState<QrChatbotScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<_QrChatMessage> _messages = [];
  bool _isTyping = false;
  bool _loadingContext = true;
  bool _quickActionsExpanded = false;

  String _branchId = '';
  String _branchName = 'Restaurant';
  String _tableName = 'Table';
  String _openingTime = '10:00';
  String _closingTime = '22:00';
  List<MenuItem> _menu = [];

  // ── Recommendation grounding (weather + real sales data) ──────────
  QrWeatherInfo? _weather;
  String? _weatherManualAnswer;
  bool _weatherAsked = false;
  bool _awaitingWeatherReply = false;
  String _topSellersText = '(no sales data yet)';
  bool _topSellersLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadContext();
  }

  @override
  void didUpdateWidget(covariant QrChatbotScreen old) {
    super.didUpdateWidget(old);
    if (old.tableId != widget.tableId) _loadContext();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadContext() async {
    setState(() => _loadingContext = true);
    final repo = ref.read(qrOrderRepositoryProvider);
    try {
      final tableInfo = await repo.fetchTableInfo(widget.tableId);
      final branch = tableInfo?['branches'] as Map<String, dynamic>?;
      final branchId = (tableInfo?['branch_id'] as String?)?.trim() ?? '';
      _branchId = branchId;

      _branchName = branch?['name'] as String? ?? 'Restaurant';
      _tableName = (tableInfo?['table_number'] as String?) ?? 'Table';
      _openingTime = (branch?['opening_time'] as String?)?.substring(0, 5) ?? '10:00';
      _closingTime = (branch?['closing_time'] as String?)?.substring(0, 5) ?? '22:00';

      // Keep the shared active-table provider in sync so a chat-added item
      // lands in the same cart the menu/cart screens read from — matters
      // mainly for a customer who deep-links straight to the tracker without
      // ever opening the menu screen first (which normally sets this).
      final current = ref.read(activeQrTableProvider);
      if (current.tableId != widget.tableId || current.branchId != branchId) {
        ref.read(activeQrTableProvider.notifier).state =
            (tableId: widget.tableId, tableName: _tableName, branchId: branchId);
      }

      if (branchId.isNotEmpty) {
        final rows = await repo.fetchMenuByBranch(branchId);
        _menu = QrChatbotService.parseMenuRows(rows);
      }
    } catch (e) {
      debugPrint('QrChatbotScreen._loadContext error: $e');
    } finally {
      if (mounted) {
        setState(() => _loadingContext = false);
        if (_messages.isEmpty) _addBot(_welcomeMessage());
      }
    }
  }

  String _welcomeMessage() {
    return widget.allowAddToCart
        ? "Hi! 👋 I'm your menu assistant. Ask me for a recommendation, "
            "check allergens/dietary info, or tell me what to add to your cart."
        : "Hi again! 👋 Still hungry? Ask me about the menu while you wait — "
            "tap \"Add Order\" on this screen when you're ready to order more.";
  }

  // ── Weather/recommendation grounding ─────────────────────────────
  bool _isRecommendationTrigger(String text) {
    final lower = text.toLowerCase();
    return _recommendationKeywords.any((k) => lower.contains(k));
  }

  // ── Cross-queue guard (deterministic — never relies on the LLM) ───
  /// True when [text] both (a) uses queue/order-tracking language and
  /// (b) contains a number that doesn't match [myQueue]. Used to hard-block
  /// the AI from ever being asked "what's the status of queue 002" while
  /// serving queue 001 — the check (and its fixed reply) happens entirely
  /// in Dart, before any request reaches the LLM, so there is no prompt for
  /// the model to misinterpret or get talked out of.
  bool _mentionsAnotherQueue(String text, String? myQueue) {
    if (myQueue == null) return false;
    final lower = text.toLowerCase();
    final hasTrackingIntent =
        _queueTrackingKeywords.any((k) => lower.contains(k));
    if (!hasTrackingIntent) return false;

    final myNormalized = _normalizeQueueToken(myQueue);
    final tokens = RegExp(r'[A-Za-z]?\d{1,4}\b')
        .allMatches(text)
        .map((m) => m.group(0)!);
    for (final t in tokens) {
      final n = _normalizeQueueToken(t);
      if (n != null && n != myNormalized) return true;
    }
    return false;
  }

  Future<void> _fetchTopSellersIfNeeded() async {
    if (_topSellersLoaded) return;
    _topSellersLoaded = true;
    if (_branchId.isEmpty) return;
    try {
      final repo = ref.read(qrOrderRepositoryProvider);
      final result = await repo.fetchTopOrderedSmart(_branchId);
      if (result.items.isNotEmpty) {
        final list = result.items
            .map((e) => '${e['name']} (${e['qty']}x ordered)')
            .join(', ');
        _topSellersText =
            'Top-selling items over ${result.periodLabel}: $list';
      }
    } catch (e) {
      debugPrint('QrChatbotScreen._fetchTopSellersIfNeeded error: $e');
    }
  }

  // ── Send ──────────────────────────────────────────────────────────
  Future<void> _send([String? quick]) async {
    final text = (quick ?? _msgCtrl.text).trim();
    if (text.isEmpty || _isTyping || _loadingContext) return;

    _msgCtrl.clear();

    // Hard block BEFORE anything reaches the LLM: if we're tracking an
    // order and the customer's message names a different queue/order
    // number, answer with a fixed, code-generated message instead of ever
    // letting the model see (and possibly answer) the question. This is
    // what actually prevents "what's the status of queue 002" from getting
    // an answer while serving queue 001 — the system-prompt instruction in
    // QrChatbotService is a second line of defense, not the only one.
    if (widget.orderId != null) {
      final orderStatus = _buildOrderStatusContext();
      if (_mentionsAnotherQueue(text, orderStatus.queue)) {
        setState(() {
          _messages.add(_QrChatMessage(role: 'user', content: text));
        });
        _scrollToBottom();
        _addBot(
          "I can only see your own order"
          "${orderStatus.queue != null ? ' (queue ${orderStatus.queue})' : ''} "
          "— I don't have access to any other customer's queue number or "
          "order status. Please ask a staff member to check that queue for "
          "you. 🙏",
        );
        return;
      }
    }

    // Treat this message as the answer to the hot/cold fallback question,
    // then resume the recommendation normally — the original request is
    // still right there in the chat history for the model to see.
    if (_awaitingWeatherReply) {
      setState(() {
        _messages.add(_QrChatMessage(role: 'user', content: text));
        _awaitingWeatherReply = false;
      });
      _weatherManualAnswer = text;
      _scrollToBottom();
      await _fetchTopSellersIfNeeded();
      await _dispatchToAi(text);
      return;
    }

    setState(() {
      _messages.add(_QrChatMessage(role: 'user', content: text));
    });
    _scrollToBottom();

    // First time the customer asks for a general recommendation this
    // session: try to ground it in real weather via device location before
    // letting the AI answer at all. If permission is denied/unavailable,
    // fall back to asking the customer directly in chat instead of guessing.
    if (!_weatherAsked && _isRecommendationTrigger(text)) {
      _weatherAsked = true;
      setState(() => _isTyping = true);
      final weather = await QrWeatherService.tryFetch();
      if (mounted) setState(() => _isTyping = false);

      if (weather != null) {
        _weather = weather;
        await _fetchTopSellersIfNeeded();
        await _dispatchToAi(text);
      } else {
        _awaitingWeatherReply = true;
        _addBot(
          "Biar rekomendasinya pas dulu ya — di tempat kamu sekarang lagi "
          "panas/gerah atau adem/sejuk? 🌤️",
        );
      }
      return;
    }

    await _dispatchToAi(text);
  }

  /// Live status of the order being tracked, read straight from the same
  /// realtime-backed provider the tracker screen itself watches — so the AI
  /// always answers "where's my order" with the current DB row, never a
  /// stale snapshot from when the chat panel first opened.
  ///
  /// Returns the queue number separately (not just embedded in [text]) so
  /// the prompt builder can state it explicitly and tell the model to
  /// refuse questions about any OTHER queue/order number — otherwise nothing
  /// stops the LLM from answering "how about queue 002?" using this
  /// customer's own 001 data just because it's the only data in context.
  ({String? queue, String? text}) _buildOrderStatusContext() {
    final orderId = widget.orderId;
    if (orderId == null) return (queue: null, text: null);
    // read(), not watch(): this is called from an event handler, not build().
    // The tracker screen underneath already keeps this provider's realtime
    // subscription alive via its own watch(), so read() here always reflects
    // the current row, not a one-time snapshot.
    final async = ref.read(qrOrderWatchProvider(orderId));
    return async.when(
      data: (order) {
        final itemsText = order.items
            .map((i) => '${i.quantity}x ${i.menuItemName}')
            .join(', ');
        final minutesAgo = DateTime.now().difference(order.createdAt).inMinutes;
        final queue = order.queueNumber ?? order.orderNumber;
        final text = 'Queue number $queue, status: "${order.status.label}" '
            '(placed $minutesAgo minute(s) ago). Items: $itemsText. '
            '${order.billRequested ? "The bill has been requested." : ""}';
        return (queue: queue, text: text);
      },
      loading: () => (
        queue: null,
        text: 'Order status is currently loading — tell the customer '
            'you\'re checking and to give it a moment if they ask again.'
      ),
      error: (e, _) => (queue: null, text: null),
    );
  }

  Future<void> _dispatchToAi(String text) async {
    setState(() => _isTyping = true);
    _scrollToBottom();

    final weatherContext = _weather?.toPromptLine() ??
        (_weatherManualAnswer != null
            ? "Customer self-reported weather (location permission wasn't "
                "available, so this is what they typed, not a live reading): "
                "\"$_weatherManualAnswer\"."
            : null);

    final orderStatus = _buildOrderStatusContext();
    final systemPrompt = QrChatbotService.buildSystemPrompt(
      branchName: _branchName,
      tableName: _tableName,
      openingTime: _openingTime,
      closingTime: _closingTime,
      menu: _menu,
      allowAddToCart: widget.allowAddToCart,
      weatherContext: weatherContext,
      topSellersText: _topSellersText,
      orderStatusContext: orderStatus.text,
      myQueueNumber: orderStatus.queue,
    );

    final recent = _messages.length > 12
        ? _messages.sublist(_messages.length - 12)
        : _messages;
    final history = recent
        .where((m) => m != _messages.last)
        .map((m) => {'role': m.role, 'content': m.content})
        .toList();

    try {
      final raw = await QrChatbotService.sendMessage(
        systemPrompt: systemPrompt,
        history: history,
        message: text,
      );
      await _handleResponse(raw);
    } catch (e) {
      _addBot('⚠️ Sorry, something went wrong: $e');
    } finally {
      if (mounted) setState(() => _isTyping = false);
      _scrollToBottom();
    }
  }

  Future<void> _handleResponse(String raw) async {
    const marker = 'ACTION:add_to_cart';
    final idx = raw.indexOf(marker);
    if (widget.allowAddToCart && idx != -1) {
      final before = raw.substring(0, idx).trim();
      final jsonStart = raw.indexOf('{', idx);
      final jsonEnd = raw.lastIndexOf('}');
      if (jsonStart != -1 && jsonEnd != -1) {
        try {
          final data = jsonDecode(raw.substring(jsonStart, jsonEnd + 1))
              as Map<String, dynamic>;
          if (before.isNotEmpty) _addBot(before);
          _addToCart(data);
          return;
        } catch (e) {
          debugPrint('QrChatbotScreen parse add_to_cart error: $e');
        }
      }
    }
    _addBot(raw);
  }

  void _addToCart(Map<String, dynamic> data) {
    final rawItems = data['items'] as List<dynamic>?;
    if (rawItems == null || rawItems.isEmpty) return;

    final notifier = ref.read(activeQrCartNotifierProvider);
    final added = <String>[];
    final notFound = <String>[];

    for (final raw in rawItems) {
      final itemMap = raw as Map<String, dynamic>;
      final requestedName = itemMap['name'] as String? ?? '';
      final quantity = (itemMap['quantity'] as num?)?.toInt() ?? 1;

      MenuItem? found;
      for (final m in _menu) {
        if (m.name.toLowerCase() == requestedName.toLowerCase()) {
          found = m;
          break;
        }
      }
      found ??= _menu.cast<MenuItem?>().firstWhere(
            (m) => m!.name.toLowerCase().contains(requestedName.toLowerCase()),
            orElse: () => null,
          );

      if (found == null || !found.isAvailable) {
        notFound.add(requestedName);
        continue;
      }

      for (var i = 0; i < quantity; i++) {
        notifier.addItem(found);
      }
      added.add('${found.name} x$quantity');
    }

    if (added.isEmpty) {
      _addBot("⚠️ Couldn't find that on the menu — could you rephrase it?");
      return;
    }

    var msg = '🛒 Added to cart:\n${added.map((a) => '• $a').join('\n')}';
    if (notFound.isNotEmpty) {
      msg += "\n\n⚠️ Not found: ${notFound.join(', ')}";
    }
    _addBot(msg);
  }

  void _addBot(String content) {
    if (!mounted) return;
    setState(() => _messages.add(_QrChatMessage(role: 'assistant', content: content)));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Build ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: _DiamondPatternPainter()),
                  ),
                  _buildMessages(),
                ],
              ),
            ),
            _buildQuickActions(),
            _buildInput(),
          ],
        ),
      ),
    );
  }

  // Styled to match the staff app's Restaurant Assistant panel header
  // (chatbot_screen.dart's _buildEmbeddedHeader) — light surface background
  // with a bottom border, a small accent-colored icon box, and an
  // ONLINE/status row, instead of the solid gold header this used to have.
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
        borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20), topRight: Radius.circular(20)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.restaurant_menu_rounded,
                color: Colors.white, size: 17),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Menu Assistant',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                        fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                          color: AppColors.available, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 4),
                    Text('$_tableName • ONLINE',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 10,
                            fontWeight: FontWeight.w600, letterSpacing: 0.3,
                            color: AppColors.textSecondary)),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.textSecondary),
            tooltip: 'Close',
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }

  String _fmtTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Widget _buildMessages() {
    if (_loadingContext && _messages.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: _messages.length + (_isTyping ? 1 : 0),
      itemBuilder: (_, i) {
        if (i == _messages.length) return _buildTypingIndicator();
        final m = _messages[i];
        return m.role == 'user' ? _buildUserBubble(m) : _buildBotBubble(m);
      },
    );
  }

  // User bubble — matches the staff app's ChatBubble (chat_bubble.dart):
  // a right-aligned surfaceVariant pill with the timestamp under the text.
  Widget _buildUserBubble(_QrChatMessage m) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.8,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(m.content,
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 13.5,
                          color: AppColors.textPrimary, height: 1.4)),
                  const SizedBox(height: 4),
                  Text(_fmtTime(m.timestamp),
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 10,
                          color: AppColors.textHint)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Bot bubble — matches the staff app's _buildBotBubble: an "ASSISTANT +
  // timestamp" label row above a bordered card, instead of a chat-tail
  // bubble with an avatar circle.
  Widget _buildBotBubble(_QrChatMessage m) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(Icons.restaurant_menu_rounded, color: Colors.white, size: 13),
              ),
              const SizedBox(width: 8),
              const Text('ASSISTANT',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                      fontWeight: FontWeight.w700, letterSpacing: 0.6,
                      color: AppColors.textSecondary)),
              const SizedBox(width: 6),
              Text(_fmtTime(m.timestamp),
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 10, color: AppColors.textHint)),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.86,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: MarkdownBody(
              data: m.content,
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                    color: AppColors.textPrimary, height: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Icon(Icons.restaurant_menu_rounded, color: Colors.white, size: 13),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
              ),
            ),
          ],
        ),
      );

  // Maps a quick-action's leading emoji to a Material icon, mirroring the
  // staff app's _categoryIcon — chips there use an icon glyph, not an emoji,
  // so this keeps the two apps' quick-action chips visually consistent.
  IconData _quickActionIcon(String label) {
    if (label.contains('🔥')) return Icons.local_fire_department_rounded;
    if (label.contains('🌿')) return Icons.eco_rounded;
    if (label.contains('⚠️')) return Icons.warning_amber_rounded;
    if (label.contains('💸')) return Icons.savings_rounded;
    if (label.contains('❄️')) return Icons.ac_unit_rounded;
    return Icons.bolt_rounded;
  }

  String _stripEmoji(String label) =>
      label.replaceFirst(RegExp(r'^[^\s]+\s*'), '');

  // Styled to match the staff app's collapsible "Quick Actions" section
  // (chatbot_screen.dart's _buildQuickActions): a toggleable header row,
  // a horizontal chip scroller when collapsed, and a 2-column grid when
  // expanded. The weather fallback question is left un-collapsible (the
  // customer needs to answer it, not have it hidden behind a toggle), and
  // the "Recommend something" CTA stays as its own prominent accent button
  // above the section — this app grounds recommendations in live weather,
  // so that action needs to stand out rather than blend into the chip row.
  Widget _buildQuickActions() {
    if (_awaitingWeatherReply) {
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _weatherFallbackReplies
              .map((e) => _QrQuickChip(
                    icon: _quickActionIcon(e.$1),
                    label: _stripEmoji(e.$1),
                    onTap: () => _send(e.$2),
                  ))
              .toList(),
        ),
      );
    }

    final featured = _quickActions.first;
    final rest = _quickActions.sublist(1);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      color: AppColors.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: GestureDetector(
              onTap: () => _send(featured.$2),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Text(featured.$1,
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                        fontWeight: FontWeight.w700, color: AppColors.accent)),
              ),
            ),
          ),
          InkWell(
            onTap: () => setState(() => _quickActionsExpanded = !_quickActionsExpanded),
            child: Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppColors.border),
                  bottom: BorderSide(color: AppColors.border),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.flash_on_rounded, size: 14, color: AppColors.primary),
                  const SizedBox(width: 6),
                  const Text('Quick Actions',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                          fontWeight: FontWeight.w600, color: AppColors.primary)),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _quickActionsExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: const Icon(Icons.expand_more, size: 18, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          if (_quickActionsExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 3.0,
                ),
                itemCount: rest.length,
                itemBuilder: (_, i) => _QrQuickChip(
                  icon: _quickActionIcon(rest[i].$1),
                  label: _stripEmoji(rest[i].$1),
                  onTap: () => _send(rest[i].$2),
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
              child: Row(
                children: rest
                    .map((e) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _QrQuickChip(
                            icon: _quickActionIcon(e.$1),
                            label: _stripEmoji(e.$1),
                            onTap: () => _send(e.$2),
                          ),
                        ))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  // Styled to match the staff app's _buildInput: an outlined pill (not a
  // filled, borderless field) with a highlighted focus border, a circular
  // accent send button instead of a bare IconButton, and the same
  // "AI generated info" disclaimer underneath.
  Widget _buildInput() => Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    onSubmitted: (_) => _send(),
                    textInputAction: TextInputAction.send,
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 14,
                          color: AppColors.textHint),
                      filled: true,
                      fillColor: AppColors.background,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: (_isTyping || _loadingContext) ? null : _send,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: (_isTyping || _loadingContext)
                          ? AppColors.accent.withValues(alpha: 0.4)
                          : AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                    child: (_isTyping || _loadingContext)
                        ? const Padding(
                            padding: EdgeInsets.all(13),
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text('AI generated info. Verify critical data.',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: AppColors.textHint)),
          ],
        ),
      );
}

// Quick-action chip — matches the staff app's _QuickActionButton
// (chatbot_screen.dart): icon + single-line label in a bordered pill.
class _QrQuickChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QrQuickChip({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: AppColors.accent),
            const SizedBox(width: 8),
            Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                      fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiamondPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.border.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const spacing = 28.0;
    for (double y = -spacing; y < size.height + spacing; y += spacing) {
      for (double x = -spacing; x < size.width + spacing; x += spacing) {
        final path = Path()
          ..moveTo(x, y - spacing / 2)
          ..lineTo(x + spacing / 2, y)
          ..lineTo(x, y + spacing / 2)
          ..lineTo(x - spacing / 2, y)
          ..close();
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
