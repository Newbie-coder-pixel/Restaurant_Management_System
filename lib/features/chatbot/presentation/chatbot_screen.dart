// lib/features/chatbot/presentation/chatbot_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;

import '../../../core/theme/app_theme.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/widgets/app_drawer.dart';

// ── Model ──────────────────────────────────────────────────────────────
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

class _BranchItem {
  final String id;
  final String name;
  _BranchItem({required this.id, required this.name});
}

// ── Quick Actions ──────────────────────────────────────────────────────
const _quickActions = [
  ('📊 Report Harian', 'Buatkan report harian hari ini'),
  ('🏆 Menu Terlaris', 'Analisis menu terlaris minggu ini'),
  ('📦 Ringkasan Stok', 'Ringkasan status inventory saat ini'),
  ('💰 Revenue Hari Ini', 'Berapa total revenue hari ini?'),
  ('📅 Booking Hari Ini', 'Daftar booking yang masuk hari ini'),
];

// ── Screen ─────────────────────────────────────────────────────────────
class ChatbotScreen extends ConsumerStatefulWidget {
  const ChatbotScreen({super.key});

  @override
  ConsumerState<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends ConsumerState<ChatbotScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<_Msg> _messages = [];

  bool _isTyping = false;

  // Branch sidebar (superadmin only)
  List<_BranchItem> _branches = [];
  String? _selectedBranchId;
  String? _myBranchId;
  bool _isSuperadmin = false;

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

  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    final staff = ref.read(currentStaffProvider);
    if (staff != null) {
      _myBranchId = staff.branchId;
      _selectedBranchId = staff.branchId;
      _isSuperadmin = staff.role.name == 'superadmin';
      _initialized = true;
      if (_isSuperadmin) _fetchBranches();
    } else {
      _initialized = true;
      ref.listenManual(currentStaffProvider, (_, next) {
        if (next != null && _myBranchId == null && mounted) {
          setState(() {
            _myBranchId = next.branchId;
            _selectedBranchId = next.branchId;
            _isSuperadmin = next.role.name == 'superadmin';
          });
          if (_isSuperadmin) _fetchBranches();
        }
      });
    }
  }

  Future<void> _fetchBranches() async {
    final res = await Supabase.instance.client
        .from('branches')
        .select('id, name')
        .eq('is_active', true)
        .order('name');
    if (mounted) {
      setState(() {
        _branches = (res as List)
            .map((e) => _BranchItem(id: e['id'], name: e['name']))
            .toList();
      });
    }
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Analytics Data ─────────────────────────────────────────────────
  Future<Map<String, dynamic>> _fetchAnalyticsData() async {
    final sb = Supabase.instance.client;
    final today = DateTime.now();
    final todayStr = today.toIso8601String().substring(0, 10);
    final branchId = _isSuperadmin ? _selectedBranchId : _myBranchId;

    try {
      var query = sb
          .from('orders')
          .select('total_amount, status, created_at')
          .gte('created_at', '${todayStr}T00:00:00')
          .lte('created_at', '${todayStr}T23:59:59');

      if (branchId != null) {
        query = query.eq('branch_id', branchId);
      }

      final ordersToday = await query;
      final list = (ordersToday as List).cast<Map<String, dynamic>>();
      final completed = list.where((o) => o['status'] == 'completed');
      final revenue = completed.fold<double>(
          0, (s, o) => s + ((o['total_amount'] as num?)?.toDouble() ?? 0));

      final branchLabel = _isSuperadmin && _selectedBranchId == null
          ? 'Semua Cabang'
          : _branches
                  .where((b) => b.id == _selectedBranchId)
                  .firstOrNull
                  ?.name ??
              'Cabang Saya';

      return {
        'branch': branchLabel,
        'orders': list.length,
        'completed': completed.length,
        'revenue': revenue,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // ── AI Call ────────────────────────────────────────────────────────
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

  // ── Send Message ───────────────────────────────────────────────────
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

Berikan insight singkat, jelas, dan actionable dalam Bahasa Indonesia.
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
      _messages.add(
          _Msg(role: 'assistant', content: content, timestamp: DateTime.now()));
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
    final staff = ref.watch(currentStaffProvider);

    return Scaffold(
      drawer: const AppDrawer(),
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        titleTextStyle: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('AI Chatbot'),
            if (staff != null)
              Text(
                staff.fullName,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: Colors.white60,
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
        actions: [
          if (staff != null)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                staff.role.displayName,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF4CAF50),
                ),
              ),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: Row(
        children: [
          // ── Sidebar cabang (superadmin only) ──────────────────────
          if (_isSuperadmin && _branches.isNotEmpty)
            _BranchSidebar(
              branches: _branches,
              selectedBranchId: _selectedBranchId,
              onSelect: (id) {
                setState(() {
                  _selectedBranchId = id;
                  _messages.clear();
                });
                _addBot(
                  '🏢 Beralih ke cabang: ${id == null ? "Semua Cabang" : _branches.firstWhere((b) => b.id == id).name}\n\nSilakan ajukan pertanyaan 👇',
                );
              },
            ),

          // ── Chat area ─────────────────────────────────────────────
          Expanded(
            child: Column(
              children: [
                Expanded(child: _buildMessages()),
                _buildQuickActions(),
                _buildInput(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Messages ────────────────────────────────────────────────────────
  Widget _buildMessages() => ListView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        itemCount: _messages.length + (_isTyping ? 1 : 0),
        itemBuilder: (_, i) {
          if (i == _messages.length) return _buildTypingIndicator();
          final m = _messages[i];
          final isUser = m.role == 'user';
          return Align(
            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: isUser
                  ? Text(
                      m.content,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: Colors.white,
                        height: 1.5,
                      ),
                    )
                  : MarkdownBody(
                      data: m.content,
                      styleSheet: MarkdownStyleSheet(
                        p: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          color: AppColors.textPrimary,
                          height: 1.5,
                        ),
                        strong: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                        h1: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                        h2: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                        h3: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        listBullet: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                        blockquote: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          fontStyle: FontStyle.italic,
                        ),
                        code: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          color: AppColors.primary,
                          backgroundColor: AppColors.primary,
                        ),
                      ),
                    ),
            ),
          );
        },
      );

  Widget _buildTypingIndicator() => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomRight: Radius.circular(16),
              bottomLeft: Radius.circular(4),
            ),
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
      );

  Widget _dot(int delayMs) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 600 + delayMs),
        builder: (_, v, __) => Opacity(
          opacity: 0.3 + (v * 0.7),
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
        ),
      );

  // ── Quick Actions ──────────────────────────────────────────────────
  Widget _buildQuickActions() => Container(
        color: AppColors.surface,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _quickActions
                .map((e) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => _send(e.$2),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            e.$1,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
        ),
      );

  // ── Input ──────────────────────────────────────────────────────────
  Widget _buildInput() => Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(
            top: BorderSide(color: AppColors.border),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _msgCtrl,
                onSubmitted: (_) => _send(),
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Ketik pertanyaan...',
                  hintStyle: const TextStyle(
                    fontFamily: 'Poppins',
                    color: AppColors.textHint,
                    fontSize: 14,
                  ),
                  filled: true,
                  fillColor: AppColors.background,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
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
                    borderSide:
                        const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _send,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _isTyping
                      ? AppColors.primary.withValues(alpha: 0.4)
                      : AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.send_rounded,
                    color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      );
}

// ── Branch Sidebar ─────────────────────────────────────────────────────
class _BranchSidebar extends StatelessWidget {
  final List<_BranchItem> branches;
  final String? selectedBranchId;
  final void Function(String?) onSelect;

  const _BranchSidebar({
    required this.branches,
    required this.selectedBranchId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      color: AppColors.primary,
      child: Column(
        children: [
          _SidebarItem(
            label: 'Semua',
            isSelected: selectedBranchId == null,
            onTap: () => onSelect(null),
          ),
          const Divider(color: Colors.white24, height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: branches.length,
              itemBuilder: (_, i) => _SidebarItem(
                label: branches[i].name,
                isSelected: selectedBranchId == branches[i].id,
                onTap: () => onSelect(branches[i].id),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.15)
              : Colors.transparent,
          border: isSelected
              ? const Border(
                  left: BorderSide(color: Colors.white, width: 3),
                )
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Poppins',
            color: isSelected ? Colors.white : Colors.white60,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}