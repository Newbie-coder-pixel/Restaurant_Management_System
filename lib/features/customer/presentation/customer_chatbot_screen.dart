// lib/features/customer/presentation/customer_chatbot_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class _ChatMessage {
  final String role;
  final String content;
  final DateTime timestamp;

  const _ChatMessage({
    required this.role,
    required this.content,
    required this.timestamp,
  });
}

class CustomerChatbotScreen extends StatefulWidget {
  final String? branchId;
  const CustomerChatbotScreen({super.key, this.branchId});

  @override
  State<CustomerChatbotScreen> createState() => _CustomerChatbotScreenState();
}

class _CustomerChatbotScreenState extends State<CustomerChatbotScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  final List<_ChatMessage> _messages = [];
  bool _isTyping = false;

  // ✅ PROXY URL — API key aman di Vercel, tidak ada di Flutter
  String get _proxyUrl {
    if (kIsWeb) return '/api/chat';
    return 'http://localhost:3000/api/chat';
  }

  @override
  void initState() {
    super.initState();
    _addBot('Halo! 👋 Ada yang bisa saya bantu?');
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<String> _callAI({
    required String systemPrompt,
    required List<Map<String, String>> history,
    required String text,
  }) async {
    final res = await http.post(
      Uri.parse(_proxyUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'model': 'llama-3.3-70b-versatile',
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          ...history,
          {'role': 'user', 'content': text},
        ],
        'max_tokens': 600,
        'temperature': 0.6,
      }),
    ).timeout(const Duration(seconds: 30));

    if (res.statusCode == 200) {
      final d = jsonDecode(res.body);
      return (d['choices'][0]['message']['content'] as String).trim();
    } else {
      throw Exception('Proxy error ${res.statusCode}');
    }
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _isTyping) return;

    _msgCtrl.clear();

    setState(() {
      _messages.add(_ChatMessage(role: 'user', content: text, timestamp: DateTime.now()));
      _isTyping = true;
    });

    _scrollToBottom();

    const systemPrompt = '''
Kamu adalah AI customer restoran.
Jawab dengan ramah, singkat, dan membantu.
''';

    try {
      final history = _messages
          .map((m) => {'role': m.role, 'content': m.content})
          .toList();

      final raw = await _callAI(
        systemPrompt: systemPrompt,
        history: history,
        text: text,
      );

      _addBot(raw);
    } catch (e) {
      _addBot('⚠️ Terjadi kesalahan, coba lagi.');
    } finally {
      if (mounted) setState(() => _isTyping = false);
      _scrollToBottom();
    }
  }

  void _addBot(String content) {
    setState(() {
      _messages.add(_ChatMessage(role: 'assistant', content: content, timestamp: DateTime.now()));
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
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Customer Support',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.grey[800],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: Colors.grey[200],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessages()),
          _buildInput(),
        ],
      ),
    );
  }

  Widget _buildMessages() => ListView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        itemCount: _messages.length,
        itemBuilder: (_, i) {
          final m = _messages[i];
          final isUser = m.role == 'user';
          
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isUser) ...[
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.green[50],
                    child: Icon(
                      Icons.support_agent,
                      size: 18,
                      color: Colors.green[700],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isUser ? Colors.green[600] : Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: isUser ? const Radius.circular(16) : const Radius.circular(4),
                        bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(16),
                      ),
                      boxShadow: isUser
                          ? null
                          : [
                              BoxShadow(
                                color: Colors.grey.withValues(alpha: 0.1),
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
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatTime(m.timestamp),
                          style: TextStyle(
                            fontSize: 10,
                            color: isUser ? Colors.green[100] : Colors.grey[400],
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
                    child: Icon(
                      Icons.person,
                      size: 18,
                      color: Colors.green[700],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      );

  Widget _buildInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: TextField(
                controller: _msgCtrl,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'Tulis pesan...',
                  hintStyle: TextStyle(color: Colors.grey[400]),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.green[600],
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white, size: 18),
              onPressed: _isTyping ? null : _send,
              padding: const EdgeInsets.all(12),
            ),
          ),
        ],
      ),
    );
  }

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