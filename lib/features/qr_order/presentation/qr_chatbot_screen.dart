// lib/features/qr_order/presentation/qr_chatbot_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../data/qr_order_repository.dart';
import '../providers/qr_cart_provider.dart';
import '../services/qr_chatbot_service.dart';
import '../services/qr_weather_service.dart';

class _QrChatMessage {
  final String role;
  final String content;
  const _QrChatMessage({required this.role, required this.content});
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
  String? _buildOrderStatusContext() {
    final orderId = widget.orderId;
    if (orderId == null) return null;
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
        return 'Queue number $queue, status: "${order.status.label}" '
            '(placed $minutesAgo minute(s) ago). Items: $itemsText. '
            '${order.billRequested ? "The bill has been requested." : ""}';
      },
      loading: () => 'Order status is currently loading — tell the customer '
          'you\'re checking and to give it a moment if they ask again.',
      error: (e, _) => null,
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

    final systemPrompt = QrChatbotService.buildSystemPrompt(
      branchName: _branchName,
      tableName: _tableName,
      openingTime: _openingTime,
      closingTime: _closingTime,
      menu: _menu,
      allowAddToCart: widget.allowAddToCart,
      weatherContext: weatherContext,
      topSellersText: _topSellersText,
      orderStatusContext: _buildOrderStatusContext(),
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
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surface,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _buildHeader(cs),
          Expanded(child: _buildMessages(cs)),
          _buildQuickActions(cs),
          _buildInput(cs),
        ],
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      color: cs.primary,
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [cs.primary, cs.tertiary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Menu Assistant',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: cs.onPrimary)),
                Text(_tableName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10,
                        color: cs.onPrimary.withValues(alpha: 0.7))),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, size: 20, color: cs.onPrimary),
            tooltip: 'Close',
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _buildMessages(ColorScheme cs) {
    if (_loadingContext && _messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      itemCount: _messages.length + (_isTyping ? 1 : 0),
      itemBuilder: (_, i) {
        if (i == _messages.length) return _buildTypingIndicator(cs);
        final m = _messages[i];
        final isUser = m.role == 'user';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isUser ? cs.primary : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(14),
                      topRight: const Radius.circular(14),
                      bottomLeft: Radius.circular(isUser ? 14 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 14),
                    ),
                  ),
                  child: isUser
                      ? Text(m.content,
                          style: TextStyle(color: cs.onPrimary, fontSize: 13, height: 1.4))
                      : MarkdownBody(
                          data: m.content,
                          styleSheet: MarkdownStyleSheet(
                            p: TextStyle(color: cs.onSurface, fontSize: 13, height: 1.4),
                          ),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTypingIndicator(ColorScheme cs) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
            ),
          ),
        ),
      );

  Widget _buildQuickActions(ColorScheme cs) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: (_awaitingWeatherReply
                    ? _weatherFallbackReplies
                    : _quickActions)
                .map((e) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onTap: () => _send(e.$2),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: cs.primaryContainer.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(e.$1,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: cs.onPrimaryContainer)),
                        ),
                      ),
                    ))
                .toList(),
          ),
        ),
      );

  Widget _buildInput(ColorScheme cs) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _msgCtrl,
                onSubmitted: (_) => _send(),
                textInputAction: TextInputAction.send,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Ask about the menu...',
                  hintStyle: const TextStyle(fontSize: 13),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(Icons.send_rounded, color: cs.primary),
              onPressed: (_isTyping || _loadingContext) ? null : _send,
            ),
          ],
        ),
      );
}
