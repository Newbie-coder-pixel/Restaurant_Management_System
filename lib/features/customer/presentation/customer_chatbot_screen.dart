// lib/features/customer/presentation/customer_chatbot_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/cart_provider.dart';
import '../providers/customer_auth_provider.dart';
import '../services/sentiment_escalation_service.dart';
import '../services/recommendation_service.dart';
import '../services/table_assignment_service.dart';

// ── Models ─────────────────────────────────────────────────────────────
class _ChatMessage {
  final String role;
  final String content;
  final DateTime timestamp;

  const _ChatMessage({
    required this.role,
    required this.content,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
      };
}

// ── Quick Actions ──────────────────────────────────────────────────────
const _quickActions = [
  ('✨ Rekomendasi', 'Rekomendasikan menu untuk saya'),
  ('🍽️ Lihat Menu', 'Apa saja menu yang tersedia?'),
  ('🛒 Pesan Makanan', 'Saya ingin memesan makanan'),
  ('📅 Reservasi Meja', 'Saya ingin reservasi meja'),
  ('🌿 Vegetarian', 'Ada menu vegetarian apa saja?'),
  ('⚠️ Info Alergen', 'Saya punya alergi, bisa bantu cek menu?'),
  ('⏰ Jam Buka', 'Jam berapa restoran buka dan tutup?'),
];

// ── Screen ─────────────────────────────────────────────────────────────
class CustomerChatbotScreen extends ConsumerStatefulWidget {
  final String? branchId;
  const CustomerChatbotScreen({super.key, this.branchId});

  @override
  ConsumerState<CustomerChatbotScreen> createState() =>
      _CustomerChatbotScreenState();
}

class _CustomerChatbotScreenState
    extends ConsumerState<CustomerChatbotScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<_ChatMessage> _messages = [];
  final _tableService = TableAssignmentService();

  bool _isTyping = false;
  String? _sessionId;

  String? _cachedMenuText;
  String? _cachedOpeningTime;
  String? _cachedClosingTime;
  String? _cachedBranchName;
  RecommendationResult? _cachedRecommendations;

  // Raw menu items list — digunakan untuk resolve menuItemId saat order
  List<Map<String, dynamic>> _menuItems = [];

  DateTime? _lastEscalatedAt;
  bool get _canEscalate {
    if (_lastEscalatedAt == null) return true;
    return DateTime.now().difference(_lastEscalatedAt!) >
        const Duration(minutes: 5);
  }

  String get _proxyUrl {
    if (kIsWeb) return '/api/chat';
    return 'http://localhost:3000/api/chat';
  }

  String get _branchId => widget.branchId ?? '';

  @override
  void initState() {
    super.initState();
    _addBot(
      'Halo! 👋 Selamat datang di layanan customer support kami.\n\n'
      'Saya bisa membantu Anda dengan:\n'
      '• 🍽️ Informasi menu & bahan\n'
      '• 🛒 Pemesanan makanan\n'
      '• ⚠️ Info alergen & diet khusus\n'
      '• 📅 Reservasi meja\n'
      '• ⏰ Jam operasional\n\n'
      'Silakan pilih topik di bawah atau ketik pertanyaan Anda 👇',
    );
    _loadBranchData();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Load Branch Data ───────────────────────────────────────────────
  Future<void> _loadBranchData() async {
    if (_branchId.isEmpty) return;
    try {
      final sb = Supabase.instance.client;

      final branch = await sb
          .from('branches')
          .select('name, opening_time, closing_time')
          .eq('id', _branchId)
          .maybeSingle();

      if (branch != null) {
        _cachedBranchName = branch['name'] as String?;
        _cachedOpeningTime =
            (branch['opening_time'] as String?)?.substring(0, 5) ?? '10:00';
        _cachedClosingTime =
            (branch['closing_time'] as String?)?.substring(0, 5) ?? '22:00';
      }

      try {
        final user = ref.read(customerUserProvider).value;
        final result = await RecommendationService.getRecommendations(
          branchId: _branchId,
          customerUserId: user?.id,
          limit: 5,
        );
        if (mounted) setState(() => _cachedRecommendations = result);
      } catch (e) {
        debugPrint('[Recommendation] Load error: $e');
      }

      final items = await sb
          .from('menu_items')
          .select(
              'id, name, price, description, preparation_time_minutes, is_seasonal, menu_categories(name)')
          .eq('branch_id', _branchId)
          .eq('is_available', true)
          .order('name');

      _menuItems = List<Map<String, dynamic>>.from(items as List);

      if (_menuItems.isEmpty) {
        _cachedMenuText = '(belum ada menu)';
        return;
      }

      final ids = _menuItems.map((i) => i['id'] as String).toList();

      final allergens = await sb
          .from('menu_item_allergens')
          .select('menu_item_id, allergen')
          .inFilter('menu_item_id', ids);

      final dietaries = await sb
          .from('menu_item_dietary')
          .select('menu_item_id, dietary_tag')
          .inFilter('menu_item_id', ids);

      final Map<String, List<String>> allergenMap = {};
      for (final a in allergens as List) {
        final id = a['menu_item_id'] as String;
        allergenMap.putIfAbsent(id, () => []).add(a['allergen'] as String);
      }

      final Map<String, List<String>> dietaryMap = {};
      for (final d in dietaries as List) {
        final id = d['menu_item_id'] as String;
        dietaryMap.putIfAbsent(id, () => []).add(d['dietary_tag'] as String);
      }

      final buf = StringBuffer();
      for (final item in _menuItems) {
        final id = item['id'] as String;
        final cat = (item['menu_categories'] as Map?)?['name'] ?? 'Umum';
        final price = (item['price'] as num?)?.toStringAsFixed(0) ?? '0';
        final desc = item['description'] as String?;
        final prepTime = item['preparation_time_minutes'] as int?;
        final isSeasonal = item['is_seasonal'] as bool? ?? false;
        final alergenList = allergenMap[id] ?? [];
        final dietList = dietaryMap[id] ?? [];

        buf.write('- ${item['name']} (Rp $price) [$cat]');
        if (desc != null && desc.isNotEmpty) buf.write(' — $desc');
        if (prepTime != null) buf.write(' | Waktu saji: ${prepTime}mnt');
        if (isSeasonal) buf.write(' | 🌿 Menu Musiman');
        if (alergenList.isNotEmpty) {
          buf.write(' | ⚠️ Alergen: ${alergenList.join(', ')}');
        }
        if (dietList.isNotEmpty) {
          buf.write(' | 🥗 Diet: ${dietList.join(', ')}');
        }
        buf.writeln();
      }
      _cachedMenuText = buf.toString().trim();
    } catch (e) {
      debugPrint('Error loading branch data: $e');
      _cachedMenuText = '(gagal memuat menu)';
    }
  }

  // ── Language Detection ─────────────────────────────────────────────
  static String detectLanguage(String text) {
    final lower = text.toLowerCase();
    const idIndicators = [
      'apa', 'ada', 'saya', 'mau', 'bisa', 'dong', 'yuk', 'tolong',
      'makasih', 'terima kasih', 'halo', 'hai', 'makan', 'pesan',
      'berapa', 'kapan', 'dimana', 'kenapa', 'gimana', 'gak', 'tidak',
      'ya', 'iya', 'boleh', 'ingin', 'minta', 'coba', 'bantu',
    ];
    const enIndicators = [
      'what', 'how', 'when', 'where', 'why', 'can', 'could', 'would',
      'please', 'thank', 'hello', 'hi', 'want', 'need', 'have', 'are',
      'is', 'the', 'and', 'for', 'menu', 'book', 'reserve', 'order',
    ];
    int idScore = 0, enScore = 0;
    for (final word in lower.split(RegExp(r'\s+'))) {
      if (idIndicators.contains(word)) idScore++;
      if (enIndicators.contains(word)) enScore++;
    }
    return enScore > idScore ? 'en' : 'id';
  }

  // ── System Prompt ──────────────────────────────────────────────────
  String _buildSystemPrompt() {
    final now = DateTime.now();
    final todayStr = '${now.day} ${_bulanIndo(now.month)} ${now.year}';
    final openTime = _cachedOpeningTime ?? '10:00';
    final closeTime = _cachedClosingTime ?? '22:00';
    final branchName = _cachedBranchName ?? 'Restoran Kami';
    final menuText = _cachedMenuText ?? '(menu sedang dimuat)';
    final recoText = _cachedRecommendations != null
        ? RecommendationService.formatForPrompt(_cachedRecommendations!)
        : '';

    return '''
Kamu adalah asisten AI customer support untuk $branchName yang ramah dan helpful.
Hari ini: $todayStr
Jam Operasional: $openTime - $closeTime WIB

DAFTAR MENU TERSEDIA (gunakan data ini, jangan karang sendiri):
$menuText

${recoText.isNotEmpty ? '$recoText\n' : ''}KEMAMPUAN KAMU:
1. INFO MENU — jawab pertanyaan tentang menu, harga, bahan, deskripsi
2. INFO ALERGEN — bantu customer dengan alergi, lihat kolom "Alergen" di data menu
3. INFO DIET — bantu customer dengan preferensi diet (vegetarian, vegan, dll), lihat kolom "Diet"
4. INFO JAM BUKA — sampaikan jam operasional di atas
5. RESERVASI MEJA — proses booking meja untuk customer
6. REKOMENDASI — gunakan data REKOMENDASI MENU PERSONAL di atas jika ada
7. PEMESANAN MAKANAN — bantu customer memesan makanan via chatbot

ALUR PEMESANAN MAKANAN:
Saat customer ingin memesan makanan:
1. Tanya menu apa yang ingin dipesan dan berapa porsi (bisa lebih dari 1 item)
2. Konfirmasi ringkasan pesanan customer (nama menu PERSIS sesuai daftar, jumlah, harga satuan, total)
3. Setelah customer konfirmasi, output PERSIS format ini (tanpa teks lain setelahnya):

ACTION:create_order
{"items":[{"name":"Nama Menu Persis","quantity":2,"notes":"catatan atau null"},{"name":"Nama Menu Lain","quantity":1,"notes":null}]}

ATURAN PENTING PEMESANAN:
- Nama menu di JSON HARUS PERSIS sama dengan daftar menu (case-sensitive)
- Jangan output ACTION:create_order sebelum customer mengkonfirmasi pesanan
- Jika menu tidak ada di daftar, tolak dengan sopan
- Setelah output action, jangan tambahkan teks lagi

ALUR RESERVASI MEJA:
Saat customer ingin reservasi:
1. Tanya: nama, jumlah orang, tanggal kedatangan, jam kedatangan, nomor HP (opsional)
2. Interpretasi tanggal dengan cerdas:
   - "besok" → $todayStr + 1 hari
   - "minggu depan" → perkirakan tanggalnya
   - Selalu asumsikan tahun ${now.year} jika tidak disebutkan
   - JANGAN minta user tulis ulang tanggal
3. Validasi:
   - VALID ✅: tanggal hari ini atau setelahnya
   - LEWAT ❌: tolak sopan
   - JAM VALID: $openTime - $closeTime WIB saja
4. Setelah semua data lengkap, output PERSIS format ini:

ACTION:create_booking
{"customer_name":"Nama Tamu","guest_count":2,"booking_date":"2026-03-19","booking_time":"10:00","phone":"08xx atau null","special_requests":"catatan atau null"}

ATURAN BAHASA (WAJIB):
- Deteksi bahasa dari pesan customer secara otomatis
- Balas SELALU dalam bahasa yang SAMA dengan pesan customer
- Nama menu tetap ditulis PERSIS sesuai daftar menu

ATURAN PENTING:
- Gunakan emoji secukupnya
- Jika customer komplain/tidak puas, akui dengan empati dan tawarkan eskalasi ke staff
- Format booking_date: YYYY-MM-DD, booking_time: HH:MM
''';
  }

  static String _bulanIndo(int bulan) {
    const list = [
      '', 'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
      'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
    ];
    return list[bulan];
  }

  // ── AI Call ────────────────────────────────────────────────────────
  Future<String> _callAI(String text) async {
    final recent = _messages.length > 14
        ? _messages.sublist(_messages.length - 14)
        : _messages;

    final res = await http
        .post(
          Uri.parse(_proxyUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'model': 'llama-3.3-70b-versatile',
            'messages': [
              {'role': 'system', 'content': _buildSystemPrompt()},
              ...recent.map((m) => {'role': m.role, 'content': m.content}),
              {'role': 'user', 'content': text},
            ],
            'max_tokens': 700,
            'temperature': 0.6,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (res.statusCode == 200) {
      final d = jsonDecode(res.body);
      return (d['choices'][0]['message']['content'] as String).trim();
    }
    throw Exception('Proxy error ${res.statusCode}');
  }

  // ── Parse Response ─────────────────────────────────────────────────
  Future<void> _parseAndHandleResponse(String raw) async {
    // Cek order action dulu
    const orderMarker = 'ACTION:create_order';
    final orderIdx = raw.indexOf(orderMarker);
    if (orderIdx != -1) {
      final before = raw.substring(0, orderIdx).trim();
      final jsonStart = raw.indexOf('{', orderIdx);
      final jsonEnd = raw.lastIndexOf('}');
      if (jsonStart != -1 && jsonEnd != -1) {
        try {
          final jsonStr = raw.substring(jsonStart, jsonEnd + 1);
          final data = jsonDecode(jsonStr) as Map<String, dynamic>;
          if (before.isNotEmpty) _addBot(before);
          await _createOrder(data);
          return;
        } catch (e) {
          debugPrint('Parse order error: $e');
        }
      }
    }

    // Cek booking action
    const bookingMarker = 'ACTION:create_booking';
    final bookingIdx = raw.indexOf(bookingMarker);
    if (bookingIdx != -1) {
      final before = raw.substring(0, bookingIdx).trim();
      final jsonStart = raw.indexOf('{', bookingIdx);
      final jsonEnd = raw.lastIndexOf('}');
      if (jsonStart != -1 && jsonEnd != -1) {
        try {
          final jsonStr = raw.substring(jsonStart, jsonEnd + 1);
          final data = jsonDecode(jsonStr) as Map<String, dynamic>;
          final displayMsg = before.isNotEmpty
              ? before
              : '📅 Baik, saya akan memproses reservasi Anda!';
          _addBot(displayMsg);
          await _createBooking(data);
          return;
        } catch (e) {
          debugPrint('Parse booking error: $e');
        }
      }
    }

    _addBot(raw);
  }

  // ── Create Order → Cart → Navigate Checkout ────────────────────────
  Future<void> _createOrder(Map<String, dynamic> data) async {
    try {
      final rawItems = data['items'] as List<dynamic>?;
      if (rawItems == null || rawItems.isEmpty) {
        _addBot('⚠️ Maaf, pesanan tidak valid. Silakan coba lagi.');
        return;
      }

      if (_branchId.isEmpty) {
        _addBot('⚠️ Maaf, informasi cabang tidak ditemukan.');
        return;
      }

      // Set branch di cart
      final cartNotifier = ref.read(cartProvider.notifier);
      cartNotifier.setBranch(_branchId, _cachedBranchName ?? 'Restoran');

      final List<String> notFound = [];
      final List<String> added = [];

      for (final raw in rawItems) {
        final itemMap = raw as Map<String, dynamic>;
        final requestedName = itemMap['name'] as String? ?? '';
        final quantity = (itemMap['quantity'] as num?)?.toInt() ?? 1;
        final notes = itemMap['notes'] as String?;

        // Cari menu item berdasarkan nama (case-insensitive tolerant tapi exact-match prefer)
        Map<String, dynamic>? found;

        // 1. Exact match dulu
        for (final m in _menuItems) {
          if ((m['name'] as String).toLowerCase() ==
              requestedName.toLowerCase()) {
            found = m;
            break;
          }
        }

        // 2. Fallback: contains match
        found ??= _menuItems.cast<Map<String, dynamic>?>().firstWhere(
              (m) => (m!['name'] as String)
                  .toLowerCase()
                  .contains(requestedName.toLowerCase()),
              orElse: () => null,
            );

        if (found == null) {
          notFound.add(requestedName);
          continue;
        }

        final price = (found['price'] as num).toDouble();
        final cartItem = CartItem(
          menuItemId: found['id'] as String,
          name: found['name'] as String,
          price: price,
          quantity: quantity,
          notes: (notes != null && notes != 'null' && notes.isNotEmpty)
              ? notes
              : null,
        );

        cartNotifier.addItem(cartItem);
        added.add('${found['name']} x$quantity');
      }

      if (added.isEmpty) {
        _addBot(
          '⚠️ Tidak ada menu yang cocok ditemukan:\n'
          '${notFound.map((n) => '• $n').join('\n')}\n\n'
          'Silakan cek nama menu dan coba lagi.',
        );
        return;
      }

      // Tampilkan konfirmasi sebelum ke checkout
      final cart = ref.read(cartProvider);
      final subtotal = cart.subtotal;
      final tax = cart.tax;
      final total = cart.total;

      String msg =
          '✅ Item berhasil ditambahkan ke keranjang!\n\n'
          '🛒 *Ringkasan Pesanan:*\n'
          '${added.map((a) => '• $a').join('\n')}\n';

      if (notFound.isNotEmpty) {
        msg +=
            '\n⚠️ Menu berikut tidak ditemukan:\n'
            '${notFound.map((n) => '• $n').join('\n')}\n';
      }

      msg +=
          '\n💰 Subtotal: Rp ${_fmtPrice(subtotal)}\n'
          '🧾 Pajak (11%): Rp ${_fmtPrice(tax)}\n'
          '💵 Total: Rp ${_fmtPrice(total)}\n\n'
          'Mengarahkan ke halaman checkout... 🚀';

      _addBot(msg);

      // Delay sedikit biar pesan terbaca, lalu navigate
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) {
        context.push('/customer/checkout');
      }

      await _saveSession();
    } catch (e) {
      debugPrint('Create order error: $e');
      _addBot(
        '⚠️ Maaf, terjadi kendala saat memproses pesanan.\n'
        'Silakan coba lagi atau pesan langsung di menu.',
      );
    }
  }

  String _fmtPrice(double v) {
    final s = v.toStringAsFixed(0);
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write('.');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }

  // ── Create Booking + Auto-Assign + Notifikasi Customer ────────────
  Future<void> _createBooking(Map<String, dynamic> data) async {
    try {
      final user = ref.read(customerUserProvider).value;

      final dateStr = data['booking_date'] as String;
      final timeStr = data['booking_time'] as String;
      final dp = dateStr.split('-');
      final tp = timeStr.split(':');
      final bookingDateTime = DateTime(
        int.parse(dp[0]),
        int.parse(dp[1]),
        int.parse(dp[2]),
        int.parse(tp[0]),
        int.parse(tp[1]),
      );

      final result = await _tableService.createAndAssign(
        branchId: _branchId,
        customerName: data['customer_name'] as String? ?? 'Tamu',
        customerPhone: data['phone'] as String?,
        customerEmail: null,
        customerUserId: user?.id,
        guestCount: (data['guest_count'] as num?)?.toInt() ?? 1,
        bookingDateTime: bookingDateTime,
        specialRequests: data['special_requests'] as String? ?? '',
      );

      if (result.isConfirmed) {
        _addBot(
          '✅ Reservasi berhasil dikonfirmasi!\n\n'
          '👤 Nama: ${data['customer_name']}\n'
          '👥 Jumlah tamu: ${data['guest_count']} orang\n'
          '📅 Tanggal: ${data['booking_date']}\n'
          '⏰ Jam: ${data['booking_time']} WIB\n'
          '🪑 Meja: ${result.tableNumber ?? '-'}\n'
          '${_hasSpecialRequest(data) ? '📝 Catatan: ${data['special_requests']}\n' : ''}\n'
          'Notifikasi konfirmasi sudah dikirim ke HP Anda. Sampai jumpa! 😊',
        );

        if (user != null) {
          SentimentEscalationService.notifyCustomerBooking(
            customerUserId: user.id,
            customerName: data['customer_name'] as String? ?? 'Tamu',
            bookingDate: data['booking_date'] as String,
            bookingTime: data['booking_time'] as String,
            guestCount: (data['guest_count'] as num?)?.toInt() ?? 1,
            tableNumber: result.tableNumber ?? '-',
            isWaitlisted: false,
          ).catchError((e) => debugPrint('Customer notify error: $e'));
        }
      } else if (result.isWaitlisted) {
        _addBot(
          '📋 Reservasi Anda masuk daftar tunggu.\n\n'
          '👤 Nama: ${data['customer_name']}\n'
          '👥 Jumlah tamu: ${data['guest_count']} orang\n'
          '📅 Tanggal: ${data['booking_date']}\n'
          '⏰ Jam: ${data['booking_time']} WIB\n\n'
          'Saat ini meja belum tersedia di jam tersebut. '
          'Staff kami akan menghubungi Anda segera. 🙏',
        );

        if (user != null) {
          SentimentEscalationService.notifyCustomerBooking(
            customerUserId: user.id,
            customerName: data['customer_name'] as String? ?? 'Tamu',
            bookingDate: data['booking_date'] as String,
            bookingTime: data['booking_time'] as String,
            guestCount: (data['guest_count'] as num?)?.toInt() ?? 1,
            tableNumber: '-',
            isWaitlisted: true,
          ).catchError((e) => debugPrint('Customer notify error: $e'));
        }
      } else {
        _addBot(
          '⚠️ Maaf, terjadi kendala saat memproses reservasi.\n'
          '${result.message != null ? '${result.message!}\n' : ''}'
          'Silakan hubungi kami langsung atau coba lagi.',
        );
      }

      await _saveSession();
    } catch (e) {
      debugPrint('Create booking error: $e');
      _addBot(
        '⚠️ Maaf, terjadi kendala saat memproses reservasi.\n'
        'Silakan hubungi kami langsung atau coba lagi.',
      );
    }
  }

  bool _hasSpecialRequest(Map<String, dynamic> data) {
    final sr = data['special_requests'];
    return sr != null && sr.toString().isNotEmpty && sr.toString() != 'null';
  }

  // ── Save Session ───────────────────────────────────────────────────
  Future<void> _saveSession() async {
    try {
      final user = ref.read(customerUserProvider).value;
      if (user == null) return;

      final messagesJson = _messages.map((m) => m.toJson()).toList();

      if (_sessionId == null) {
        final result = await Supabase.instance.client
            .from('customer_chat_sessions')
            .insert({
              'user_id': user.id,
              'title': _generateSessionTitle(),
              'messages': messagesJson,
            })
            .select('id')
            .single();
        _sessionId = result['id'] as String?;
      } else {
        await Supabase.instance.client
            .from('customer_chat_sessions')
            .update({
              'messages': messagesJson,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', _sessionId!);
      }
    } catch (e) {
      debugPrint('Save session error: $e');
    }
  }

  String _generateSessionTitle() {
    final now = DateTime.now();
    return 'Chat ${now.day}/${now.month}/${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
  }

  // ── Send Message ───────────────────────────────────────────────────
  Future<void> _send([String? quick]) async {
    final text = (quick ?? _msgCtrl.text).trim();
    if (text.isEmpty || _isTyping) return;

    _msgCtrl.clear();

    setState(() {
      _messages.add(_ChatMessage(
        role: 'user',
        content: text,
        timestamp: DateTime.now(),
      ));
      _isTyping = true;
    });

    _scrollToBottom();

    final detectedLang = _CustomerChatbotScreenState.detectLanguage(text);
    final sentimentResult = SentimentEscalationService.analyze(text);

    try {
      if (_cachedMenuText == null) await _loadBranchData();

      final promptText = sentimentResult.shouldEscalate
          ? '$text\n\n[SISTEM: Customer tampak '
              '${sentimentResult.level == SentimentLevel.urgent ? "dalam situasi darurat" : "kecewa/tidak puas"}. '
              'Respons dengan empati tinggi, akui perasaan customer terlebih dahulu, '
              'tawarkan solusi konkret, dan sampaikan bahwa staff kami siap membantu langsung.]'
          : text;

      final raw = await _callAI(promptText);
      await _parseAndHandleResponse(raw);

      if (sentimentResult.shouldEscalate &&
          _canEscalate &&
          _branchId.isNotEmpty) {
        _lastEscalatedAt = DateTime.now();
        SentimentEscalationService.escalate(
          branchId: _branchId,
          customerMessage: text,
          result: sentimentResult,
          sessionId: _sessionId,
        ).catchError((e) => debugPrint('Escalation error: $e'));

        if (sentimentResult.level == SentimentLevel.urgent) {
          _addBot(detectedLang == 'en'
              ? '🚨 Your message has been forwarded to our staff who will assist you shortly.'
              : '🚨 Pesan Anda telah diteruskan ke staff kami yang akan segera membantu.');
        }
      }
    } catch (e) {
      _addBot(detectedLang == 'en'
          ? '⚠️ Sorry, something went wrong. Please try again or contact us directly.'
          : '⚠️ Maaf, terjadi kesalahan. Silakan coba lagi atau hubungi kami langsung.');
    } finally {
      if (mounted) setState(() => _isTyping = false);
      _scrollToBottom();
      if (_messages.length % 3 == 0) await _saveSession();
    }
  }

  void _addBot(String content) {
    setState(() {
      _messages.add(_ChatMessage(
        role: 'assistant',
        content: content,
        timestamp: DateTime.now(),
      ));
    });
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

  // ── Build ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Customer Support',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            if (_cachedBranchName != null)
              Text(
                _cachedBranchName!,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.green[100],
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
        actions: [
          // Badge cart jika ada item
          Consumer(
            builder: (context, ref, _) {
              final cartCount = ref.watch(cartProvider).itemCount;
              if (cartCount == 0) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Stack(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.shopping_cart_outlined, size: 22),
                      tooltip: 'Lihat Keranjang',
                      onPressed: () => context.push('/customer/checkout'),
                    ),
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '$cartCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            tooltip: 'Chat Baru',
            onPressed: () {
              setState(() {
                _messages.clear();
                _sessionId = null;
              });
              _addBot('Halo lagi! 👋 Ada yang bisa saya bantu?');
            },
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.green[600]),
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessages()),
          _buildQuickActions(),
          _buildInput(),
        ],
      ),
    );
  }

  Widget _buildMessages() => ListView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        itemCount: _messages.length + (_isTyping ? 1 : 0),
        itemBuilder: (_, i) {
          if (i == _messages.length) return _buildTypingIndicator();
          final m = _messages[i];
          final isUser = m.role == 'user';

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment:
                  isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isUser) ...[
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.green[50],
                    child: Icon(Icons.support_agent,
                        size: 18, color: Colors.green[700]),
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isUser ? Colors.green[700] : Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: isUser
                            ? const Radius.circular(16)
                            : const Radius.circular(4),
                        bottomRight: isUser
                            ? const Radius.circular(4)
                            : const Radius.circular(16),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.content,
                          style: TextStyle(
                            color: isUser ? Colors.white : Colors.grey[800],
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatTime(m.timestamp),
                          style: TextStyle(
                            fontSize: 10,
                            color: isUser
                                ? Colors.green[200]
                                : Colors.grey[400],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (isUser) ...[
                  const SizedBox(width: 8),
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.green[100],
                    child: Icon(Icons.person,
                        size: 18, color: Colors.green[700]),
                  ),
                ],
              ],
            ),
          );
        },
      );

  Widget _buildTypingIndicator() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.green[50],
              child: Icon(Icons.support_agent,
                  size: 18, color: Colors.green[700]),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                  bottomLeft: Radius.circular(4),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _dot(0),
                  const SizedBox(width: 4),
                  _dot(150),
                  const SizedBox(width: 4),
                  _dot(300),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _dot(int delayMs) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.3, end: 1.0),
        duration: Duration(milliseconds: 600 + delayMs),
        builder: (_, v, __) => Opacity(
          opacity: v,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: Colors.green[400],
              shape: BoxShape.circle,
            ),
          ),
        ),
      );

  Widget _buildQuickActions() => Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _quickActions
                .map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => _send(e.$2),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.green[200]!),
                        ),
                        child: Text(
                          e.$1,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.green[800],
                          ),
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      );

  Widget _buildInput() => Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: TextField(
                  controller: _msgCtrl,
                  onSubmitted: (_) => _send(),
                  textInputAction: TextInputAction.send,
                  decoration: InputDecoration(
                    hintText: 'Tulis pesan...',
                    hintStyle:
                        TextStyle(color: Colors.grey[400], fontSize: 14),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: _isTyping ? Colors.green[300] : Colors.green[700],
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.send_rounded,
                    color: Colors.white, size: 20),
                onPressed: _isTyping ? null : _send,
                padding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
      );

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDate = DateTime(time.year, time.month, time.day);
    if (msgDate == today) {
      return '${time.hour.toString().padLeft(2, '0')}:'
          '${time.minute.toString().padLeft(2, '0')}';
    }
    return '${time.day}/${time.month} '
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }
}