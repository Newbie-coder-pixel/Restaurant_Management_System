import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;

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
  // ✅ Panggil proxy Vercel, bukan Groq langsung
  // Di local dev pakai localhost, di production otomatis pakai domain Vercel
  static String get _proxyUrl {
    if (kIsWeb) {
      // Di web: pakai relative URL supaya otomatis sesuai domain
      return '/api/chat';
    }
    // Di mobile/desktop local dev (opsional)
    return 'http://localhost:3000/api/chat';
  }

  static const String _model = 'llama-3.3-70b-versatile';

  static String _systemPrompt(String branchId,
      {String openingTime = '10:00',
      String closingTime = '22:00',
      String menuText = '(menu belum dimuat)'}) {
    final now = DateTime.now();
    final todayStr = '${now.day} ${_bulanIndo(now.month)} ${now.year}';
    return '''
Kamu adalah asisten AI RestaurantOS yang ramah dan profesional untuk staff restoran.
Branch ID: $branchId
Hari ini: $todayStr

DAFTAR MENU YANG TERSEDIA DI RESTORAN INI (GUNAKAN DATA INI, JANGAN KARANG SENDIRI):
$menuText
Hanya rekomendasikan atau proses pesanan dari daftar menu di atas. Jika item tidak ada di daftar, sampaikan bahwa menu tersebut tidak tersedia.

ALUR PEMESANAN WAJIB:
Saat customer/staff menyebut ingin memesan makanan/minuman:
1. Tampilkan pilihan menu yang tersedia dari daftar di atas
2. Tunggu user memilih item (dengan nama atau nomor). Jika user menjawab sesuatu yang BUKAN nama/nomor menu (contoh: "tidak ada", "gak", "tidak", dll) SEBELUM memilih menu, ULANGI pertanyaan pilih menu dengan ramah.
3. Setelah user memilih item yang VALID dari daftar, konfirmasi item dan tanya: "Ada catatan khusus untuk pesanan ini? (contoh: tanpa sayur, tidak pedas, ekstra saus) Ketik 'tidak ada' jika tidak ada."
4. Jawaban "tidak ada" atau "gak ada" di tahap ini = notes: null. LANGSUNG proses, JANGAN tanya ulang.
5. Setelah mendapat jawaban notes, output konfirmasi + ACTION JSON:

ACTION:create_order
{"items":[{"name":"Nama Menu","qty":1,"notes":"catatan atau null"}],"table_notes":"info meja jika ada"}

PENTING ALUR PESANAN:
- Urutan: tampil menu → user pilih → tanya notes → proses. JANGAN skip urutan ini.
- "tidak ada" HANYA valid sebagai jawaban notes SETELAH user sudah memilih menu.
- Jika user belum pilih menu lalu bilang "tidak ada", itu artinya mereka belum mau pesan, BUKAN notes.

ALUR BOOKING/RESERVASI MEJA:
Saat customer/staff ingin booking meja:
1. Tanya nama tamu, jumlah orang, tanggal kedatangan, jam kedatangan, dan nomor HP (opsional)
2. TANGGAL: user boleh menyebut tanggal dalam format apapun. Kamu harus cerdas menginterpretasikannya:
   - "14 maret" → 14 Maret ${now.year} (SELALU asumsikan tahun sekarang jika tidak disebutkan)
   - "besok" → hari ini + 1
   - "minggu depan" → perkirakan tanggalnya
   - JANGAN pernah minta user untuk menulis ulang tanggal hanya karena tidak ada tahun. Asumsikan saja.
3. VALIDASI tanggal (HANYA tolak jika benar-benar sudah lewat):
   - Hari ini adalah $todayStr
   - VALID ✅: tanggal hari ini atau setelahnya → langsung proses
   - LEWAT ❌: tanggal sebelum hari ini → tolak sopan
4. VALIDASI jam: Operasional $openingTime - $closingTime WIB. Tolak jika di luar rentang ini.
5. Setelah semua data lengkap dan valid, langsung output format ini PERSIS:

ACTION:create_booking
{"customer_name":"Nama Tamu","guest_count":2,"booking_date":"2026-03-19","booking_time":"10:00","phone":"08xx atau null","special_requests":"catatan atau null"}

Format booking_date: YYYY-MM-DD
Format booking_time: HH:MM

PENTING:
- Jawab dalam Bahasa Indonesia yang ramah dan singkat
- Gunakan emoji secukupnya
- Untuk pertanyaan di luar restoran, arahkan kembali ke topik restoran
- Selalu sebut tanggal LENGKAP (hari + bulan + tahun) saat meminta atau mengkonfirmasi tanggal
''';
  }

  static String _bulanIndo(int bulan) {
    const list = [
      '',
      'Januari',
      'Februari',
      'Maret',
      'April',
      'Mei',
      'Juni',
      'Juli',
      'Agustus',
      'September',
      'Oktober',
      'November',
      'Desember'
    ];
    return list[bulan];
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

  static Future<String> _fetchMenu(String branchId) async {
    try {
      final items = await Supabase.instance.client
          .from('menu_items')
          .select(
              'name, price, description, is_available, menu_categories(name)')
          .eq('branch_id', branchId)
          .eq('is_available', true)
          .order('name');
      if ((items as List).isEmpty) return '(belum ada menu)';
      final buf = StringBuffer();
      for (final item in items) {
        final cat = (item['menu_categories'] as Map?)?['name'] ?? 'Umum';
        final price = (item['price'] as num?)?.toStringAsFixed(0) ?? '0';
        final desc = item['description'] as String?;
        buf.writeln(
            '- ${item['name']} (Rp $price) [$cat]${desc != null ? " — $desc" : ""}');
      }
      return buf.toString().trim();
    } catch (_) {
      return '(gagal memuat menu)';
    }
  }

  // ✅ Panggil proxy Vercel — API key tidak pernah ada di Flutter
  static Future<ChatResponse> _callGroqProxy(
      String branchId, String message, List<ChatMessage> history) async {
    final hours = await _fetchBranchHours(branchId);
    final menuText = await _fetchMenu(branchId);
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
    throw Exception('Proxy ${res.statusCode}: ${res.body}');
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
                      ? '📅 Reservasi siap dikonfirmasi!'
                      : '✅ Pesanan siap dikonfirmasi!',
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
    if (msg.contains('menu') || msg.contains('makanan')) {
      return const ChatResponse(
          reply:
              '🍽️ Buka halaman Menu di drawer navigasi (☰) untuk melihat menu lengkap.');
    }
    if (msg.contains('booking') || msg.contains('reservasi')) {
      return const ChatResponse(
          reply:
              '📅 Buka halaman Reservasi di drawer navigasi (☰) untuk membuat reservasi.');
    }
    return const ChatResponse(
        reply: '🤖 Chatbot sedang tidak tersedia. Silakan coba lagi nanti.');
  }
}