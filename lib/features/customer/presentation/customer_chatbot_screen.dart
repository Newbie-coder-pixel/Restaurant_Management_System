// lib/features/customer/presentation/customer_chatbot_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/customer_auth_provider.dart';
import '../services/sentiment_escalation_service.dart';
import '../services/recommendation_service.dart';

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

// ── Quick Actions untuk Customer ───────────────────────────────────────
const _quickActions = [
  ('✨ Rekomendasi', 'Rekomendasikan menu untuk saya'),
  ('🍽️ Lihat Menu', 'Apa saja menu yang tersedia?'),
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

  bool _isTyping = false;
  String? _sessionId;

  // ── Cached data dari Supabase ──────────────────────────────────────
  String? _cachedMenuText;
  String? _cachedOpeningTime;
  String? _cachedClosingTime;
  String? _cachedBranchName;

  // ── Cached recommendation data ────────────────────────────────────
  RecommendationResult? _cachedRecommendations;

  // ── Escalation cooldown — jangan spam notif manager ──────────────
  // Eskalasi maksimal 1x per 5 menit per sesi
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

  // ── Load Branch Data (cache supaya tidak fetch ulang tiap pesan) ───
  Future<void> _loadBranchData() async {
    if (_branchId.isEmpty) return;
    try {
      final sb = Supabase.instance.client;

      // Fetch jam buka + nama cabang
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

      // Fetch rekomendasi
      try {
        final user = ref.read(customerUserProvider).value;
        final result = await RecommendationService.getRecommendations(
          branchId: _branchId,
          customerUserId: user?.id,
          limit: 5,
        );
        if (mounted) {
          setState(() {
            _cachedRecommendations = result;
          });
        }
      } catch (e) {
        debugPrint('[Recommendation] Load error: $e');
      }

      // Fetch menu + kategori + alergen + dietary
      final items = await sb
          .from('menu_items')
          .select(
              'id, name, price, description, preparation_time_minutes, is_seasonal, menu_categories(name)')
          .eq('branch_id', _branchId)
          .eq('is_available', true)
          .order('name');

      if ((items as List).isEmpty) {
        _cachedMenuText = '(belum ada menu)';
        return;
      }

      // Kumpulkan semua menu_item id untuk fetch alergen & dietary sekaligus
      final ids = items.map((i) => i['id'] as String).toList();

      final allergens = await sb
          .from('menu_item_allergens')
          .select('menu_item_id, allergen')
          .inFilter('menu_item_id', ids);

      final dietaries = await sb
          .from('menu_item_dietary')
          .select('menu_item_id, dietary_tag')
          .inFilter('menu_item_id', ids);

      // Map: id → list alergen
      final Map<String, List<String>> allergenMap = {};
      for (final a in allergens as List) {
        final id = a['menu_item_id'] as String;
        allergenMap.putIfAbsent(id, () => []).add(a['allergen'] as String);
      }

      // Map: id → list dietary tag
      final Map<String, List<String>> dietaryMap = {};
      for (final d in dietaries as List) {
        final id = d['menu_item_id'] as String;
        dietaryMap.putIfAbsent(id, () => []).add(d['dietary_tag'] as String);
      }

      // Build menu text
      final buf = StringBuffer();
      for (final item in items) {
        final id = item['id'] as String;
        final cat =
            (item['menu_categories'] as Map?)?['name'] ?? 'Umum';
        final price =
            (item['price'] as num?)?.toStringAsFixed(0) ?? '0';
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

  // ── Language Detection ────────────────────────────────────────────
  // Deteksi bahasa dominan dari teks — digunakan untuk logging/sentiment
  // (AI akan auto-detect sendiri dari system prompt, ini untuk fallback UI)
  static String detectLanguage(String text) {
    final lower = text.toLowerCase();

    // Indikator Bahasa Indonesia
    const idIndicators = [
      'apa', 'ada', 'saya', 'mau', 'bisa', 'dong', 'yuk', 'tolong',
      'makasih', 'terima kasih', 'halo', 'hai', 'makan', 'pesan',
      'berapa', 'kapan', 'dimana', 'kenapa', 'gimana', 'gak', 'tidak',
      'ya', 'iya', 'boleh', 'ingin', 'minta', 'coba', 'bantu',
    ];

    // Indikator English
    const enIndicators = [
      'what', 'how', 'when', 'where', 'why', 'can', 'could', 'would',
      'please', 'thank', 'hello', 'hi', 'want', 'need', 'have', 'are',
      'is', 'the', 'and', 'for', 'menu', 'book', 'reserve', 'order',
    ];

    int idScore = 0;
    int enScore = 0;

    for (final word in lower.split(RegExp(r'\s+'))) {
      if (idIndicators.contains(word)) idScore++;
      if (enIndicators.contains(word)) enScore++;
    }

    if (enScore > idScore) return 'en';
    return 'id'; // Default Indonesia
  }

  // ── System Prompt untuk Customer ──────────────────────────────────
  String _buildSystemPrompt() {
    final now = DateTime.now();
    final todayStr = '${now.day} ${_bulanIndo(now.month)} ${now.year}';
    final openTime = _cachedOpeningTime ?? '10:00';
    final closeTime = _cachedClosingTime ?? '22:00';
    final branchName = _cachedBranchName ?? 'Restoran Kami';
    final menuText = _cachedMenuText ?? '(menu sedang dimuat)';

    // Tambahkan data rekomendasi ke prompt jika tersedia
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
6. REKOMENDASI — jika customer minta rekomendasi, gunakan data REKOMENDASI MENU PERSONAL di atas (jika ada), sebutkan alasannya (favorit/sering dipesan bareng/terpopuler)

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
- Contoh: customer tulis Bahasa Indonesia → balas Indonesia, customer tulis English → reply in English
- Jika campur (Bahasa + English), ikuti bahasa yang dominan
- Nama menu tetap ditulis PERSIS sesuai daftar menu (jangan diterjemahkan)

ATURAN PENTING:
- Gunakan emoji secukupnya
- Jika ditanya di luar topik restoran, arahkan kembali dengan sopan
- Jika customer komplain/tidak puas, akui dengan empati dan tawarkan eskalasi ke staff
- Format booking_date: YYYY-MM-DD, booking_time: HH:MM
- Selalu sebut nama menu PERSIS sesuai daftar menu di atas
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

    final history = recent
        .map((m) => {'role': m.role, 'content': m.content})
        .toList();

    final res = await http
        .post(
          Uri.parse(_proxyUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'model': 'llama-3.3-70b-versatile',
            'messages': [
              {'role': 'system', 'content': _buildSystemPrompt()},
              ...history,
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

  // ── Parse Response (detect booking action) ─────────────────────────
  Future<void> _parseAndHandleResponse(String raw) async {
    const marker = 'ACTION:create_booking';
    final idx = raw.indexOf(marker);

    if (idx != -1) {
      final before = raw.substring(0, idx).trim();
      final jsonStart = raw.indexOf('{', idx);
      final jsonEnd = raw.lastIndexOf('}');

      if (jsonStart != -1 && jsonEnd != -1) {
        try {
          final jsonStr = raw.substring(jsonStart, jsonEnd + 1);
          final data = jsonDecode(jsonStr) as Map<String, dynamic>;

          // Tampilkan pesan konfirmasi dulu
          final displayMsg = before.isNotEmpty
              ? before
              : '📅 Baik, saya akan memproses reservasi Anda!';
          _addBot(displayMsg);

          // Proses booking ke Supabase
          await _createBooking(data);
          return;
        } catch (e) {
          debugPrint('Parse booking error: $e');
        }
      }
    }

    // Tidak ada action, tampilkan respons biasa
    _addBot(raw);
  }

  // ── Create Booking ke Supabase ────────────────────────────────────
  Future<void> _createBooking(Map<String, dynamic> data) async {
    try {
      final user = ref.read(customerUserProvider).value;

      final payload = {
        'branch_id': _branchId.isNotEmpty ? _branchId : null,
        'customer_name': data['customer_name'] ?? 'Tamu',
        'customer_phone': data['phone'],
        'guest_count': data['guest_count'] ?? 1,
        'booking_date': data['booking_date'],
        'booking_time': data['booking_time'],
        'special_requests': data['special_requests'],
        'status': 'pending',
        'source': 'chatbot',
        if (user != null) 'customer_user_id': user.id,
      };

      final result = await Supabase.instance.client
          .from('bookings')
          .insert(payload)
          .select('confirmation_code')
          .single();

      final code = result['confirmation_code'] as String?;

      _addBot(
        '✅ Reservasi berhasil dibuat!\n\n'
        '📋 **Kode Konfirmasi:** ${code ?? '-'}\n'
        '👤 Nama: ${data['customer_name']}\n'
        '👥 Jumlah tamu: ${data['guest_count']} orang\n'
        '📅 Tanggal: ${data['booking_date']}\n'
        '⏰ Jam: ${data['booking_time']} WIB\n'
        '${data['special_requests'] != null ? '📝 Catatan: ${data['special_requests']}\n' : ''}\n'
        'Tim kami akan menghubungi Anda untuk konfirmasi lebih lanjut. '
        'Simpan kode konfirmasi Anda ya! 😊',
      );

      // Simpan session setelah booking berhasil
      await _saveSession();
    } catch (e) {
      debugPrint('Create booking error: $e');
      _addBot(
        '⚠️ Maaf, terjadi kendala saat memproses reservasi.\n'
        'Silakan hubungi kami langsung atau coba lagi.',
      );
    }
  }

  // ── Simpan/Update Chat Session ke Supabase ─────────────────────────
  Future<void> _saveSession() async {
    try {
      final user = ref.read(customerUserProvider).value;
      if (user == null) return; // Hanya simpan jika sudah login

      final messagesJson = _messages.map((m) => m.toJson()).toList();

      if (_sessionId == null) {
        // Buat session baru
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
        // Update session yang ada
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
    return 'Chat ${now.day}/${now.month}/${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  // ── Send Message ───────────────────────────────────────────────────
  Future<void> _send([String? quick]) async {
    final text = (quick ?? _msgCtrl.text).trim();
    if (text.isEmpty || _isTyping) return;

    _msgCtrl.clear();

    final userMsg = _ChatMessage(
      role: 'user',
      content: text,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(userMsg);
      _isTyping = true;
    });

    _scrollToBottom();

    // ── Deteksi bahasa & sentiment ────────────────────────────────────
    final detectedLang = _CustomerChatbotScreenState.detectLanguage(text);
    final sentimentResult = SentimentEscalationService.analyze(text);
    final shouldModifyPrompt = sentimentResult.shouldEscalate;
    debugPrint('[Chat] Lang: $detectedLang | Sentiment: ${sentimentResult.level.name}');

    try {
      // Jika menu belum dimuat, tunggu sebentar
      if (_cachedMenuText == null) {
        await _loadBranchData();
      }

      // Modifikasi prompt jika sentiment negatif/urgent
      final promptText = shouldModifyPrompt
          ? '$text\n\n[SISTEM: Customer tampak ${sentimentResult.level == SentimentLevel.urgent ? "dalam situasi darurat" : "kecewa/tidak puas"}. '
              'Respons dengan empati tinggi, akui perasaan customer terlebih dahulu, '
              'tawarkan solusi konkret, dan sampaikan bahwa staff kami siap membantu langsung.]'
          : text;

      final raw = await _callAI(promptText);
      await _parseAndHandleResponse(raw);

      // ── Eskalasi ke manager jika perlu ───────────────────────────
      if (sentimentResult.shouldEscalate && _canEscalate && _branchId.isNotEmpty) {
        _lastEscalatedAt = DateTime.now();

        // Fire-and-forget — jangan await supaya tidak delay respons ke customer
        SentimentEscalationService.escalate(
          branchId: _branchId,
          customerMessage: text,
          result: sentimentResult,
          sessionId: _sessionId,
        ).catchError((e) => debugPrint('Escalation error: $e'));

        // Tampilkan banner di chat jika urgent — dalam bahasa customer
        if (sentimentResult.level == SentimentLevel.urgent) {
          final urgentMsg = detectedLang == 'en'
              ? '🚨 Your message has been forwarded to our staff who will assist you shortly. Please wait a moment.'
              : '🚨 Pesan Anda telah diteruskan ke staff kami yang akan segera membantu. Mohon tunggu sebentar.';
          _addBot(urgentMsg);
        }
      }
    } catch (e) {
      final errMsg = _CustomerChatbotScreenState.detectLanguage(text) == 'en'
          ? '⚠️ Sorry, something went wrong. Please try again or contact us directly.'
          : '⚠️ Maaf, terjadi kesalahan. Silakan coba lagi atau hubungi kami langsung.';
      _addBot(errMsg);
    } finally {
      if (mounted) setState(() => _isTyping = false);
      _scrollToBottom();

      // Auto-save session setiap 3 pesan
      if (_messages.length % 3 == 0) {
        await _saveSession();
      }
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

  // ── Messages ───────────────────────────────────────────────────────
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

  // ── Quick Actions ──────────────────────────────────────────────────
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

  // ── Input ──────────────────────────────────────────────────────────
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
                    hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
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
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else {
      return '${time.day}/${time.month} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
  }
}