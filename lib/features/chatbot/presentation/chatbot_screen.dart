// lib/features/chatbot/presentation/chatbot_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;

class _Msg {
  final String role;
  final String content;
  final DateTime timestamp;
  const _Msg({
    required this.role,
    required this.content,
    required this.timestamp,
  });
}

const _quickActions = [
  ('📊 Report Harian', 'Buatkan report harian hari ini'),
  ('🏆 Menu Terlaris', 'Analisis menu terlaris minggu ini'),
  ('📦 Ringkasan Stok', 'Ringkasan status inventory saat ini'),
  ('💰 Revenue Hari Ini', 'Berapa total revenue hari ini?'),
  ('📅 Booking Hari Ini', 'Daftar booking yang masuk hari ini'),
];

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<_Msg> _messages = [];

  bool _isTyping = false;

  // ✅ PROXY URL — API key aman di Vercel, tidak ada di Flutter
  String get _proxyUrl {
    if (kIsWeb) return '/api/chat';
    return 'http://localhost:3000/api/chat';
  }

  @override
  void initState() {
    super.initState();
    _addBot(
      '👋 Halo! Saya **Resto Analytics AI**.\n\n'
      'Saya bisa bantu:\n'
      '• 📊 Report harian\n'
      '• 🏆 Analisis menu\n'
      '• 📦 Status inventory\n'
      '• 💡 Insight bisnis\n\n'
      'Silakan pilih atau ketik pertanyaan 👇',
    );
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _fetchAnalyticsData() async {
    final sb = Supabase.instance.client;
    final today = DateTime.now();
    final todayStr = today.toIso8601String().substring(0, 10);

    try {
      final ordersToday = await sb
          .from('orders')
          .select('total_amount, status, created_at')
          .gte('created_at', '${todayStr}T00:00:00')
          .lte('created_at', '${todayStr}T23:59:59');

      final list = (ordersToday as List).cast<Map<String, dynamic>>();
      final completed = list.where((o) => o['status'] == 'completed');
      final revenue = completed.fold<double>(
          0, (s, o) => s + ((o['total_amount'] as num?)?.toDouble() ?? 0));

      return {
        'orders': list.length,
        'completed': completed.length,
        'revenue': revenue,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<String> _callAI({
    required String systemPrompt,
    required List<Map<String, String>> history,
    required String text,
  }) async {
    final res = await http
        .post(
          Uri.parse(_proxyUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'model': 'llama-3.3-70b-versatile',
            'messages': [
              {'role': 'system', 'content': systemPrompt},
              ...history,
              {'role': 'user', 'content': text},
            ],
            'max_tokens': 1200,
            'temperature': 0.3,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (res.statusCode == 200) {
      final d = jsonDecode(res.body);
      return (d['choices'][0]['message']['content'] as String).trim();
    } else {
      throw Exception('Proxy error ${res.statusCode}');
    }
  }

  Future<void> _send([String? quick]) async {
    final text = (quick ?? _msgCtrl.text).trim();
    if (text.isEmpty || _isTyping) return;

    _msgCtrl.clear();

    setState(() {
      _messages.add(_Msg(role: 'user', content: text, timestamp: DateTime.now()));
      _isTyping = true;
    });

    _scrollToBottom();

    final data = await _fetchAnalyticsData();

    final systemPrompt = '''
Kamu adalah AI Analytics restoran.

DATA:
${data.toString()}

Berikan insight singkat, jelas, dan actionable.
''';

    try {
      final recent = _messages.length > 10
          ? _messages.sublist(_messages.length - 10)
          : _messages;

      final history = recent
          .where((m) => m != _messages.last)
          .map((m) => {'role': m.role, 'content': m.content})
          .toList();

      final raw = await _callAI(
        systemPrompt: systemPrompt,
        history: history,
        text: text,
      );

      _addBot(raw);
    } catch (e) {
      _addBot('⚠️ Error: $e');
    } finally {
      if (mounted) setState(() => _isTyping = false);
      _scrollToBottom();
    }
  }

  void _addBot(String content) {
    setState(() {
      _messages.add(_Msg(role: 'assistant', content: content, timestamp: DateTime.now()));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Resto AI')),
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
        itemCount: _messages.length,
        itemBuilder: (_, i) {
          final m = _messages[i];
          return ListTile(
            title: Text(m.content),
            subtitle: Text(m.role),
          );
        },
      );

  Widget _buildQuickActions() => Wrap(
        children: _quickActions
            .map((e) => TextButton(
                  onPressed: () => _send(e.$2),
                  child: Text(e.$1),
                ))
            .toList(),
      );

  Widget _buildInput() => Row(
        children: [
          Expanded(
            child: TextField(
              controller: _msgCtrl,
              onSubmitted: (_) => _send(),
            ),
          ),
          IconButton(icon: const Icon(Icons.send), onPressed: _send),
        ],
      );
}