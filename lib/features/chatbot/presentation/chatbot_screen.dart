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
import '../providers/chat_provider.dart';
import '../services/chatbot_api.dart';
import '../services/report_export_service.dart';
import 'widgets/chat_bubble.dart';

// ── Branch Model ───────────────────────────────────────────────────────
class _BranchItem {
  final String id;
  final String name;
  _BranchItem({required this.id, required this.name});
}

// ── Quick Actions ──────────────────────────────────────────────────────
const _quickActionsV2 = [
  _QuickAction(label: 'Report Harian',      emoji: '📊', prompt: 'Buatkan report harian lengkap hari ini',                                                          category: 'analytics'),
  _QuickAction(label: 'Bandingkan Minggu',  emoji: '📈', prompt: 'Bandingkan revenue minggu ini vs minggu lalu',                                                    category: 'analytics'),
  _QuickAction(label: 'Menu Terlaris',      emoji: '🏆', prompt: 'Menu apa yang paling terlaris bulan ini?',                                                        category: 'menu'),
  _QuickAction(label: 'Booking Hari Ini',   emoji: '📅', prompt: 'Tampilkan semua booking hari ini beserta detailnya',                                              category: 'booking'),
  _QuickAction(label: 'Revenue Bulan Ini',  emoji: '💰', prompt: 'Berapa total revenue bulan ini dan tren pertumbuhannya?',                                         category: 'analytics'),
  _QuickAction(label: 'Info Menu',          emoji: '🍽️', prompt: 'Tampilkan semua menu beserta harga, kategori, dan info allergen/dietary-nya',                    category: 'menu'),
  _QuickAction(label: 'Margin Menu',        emoji: '💡', prompt: 'Menu mana yang margin keuntungannya paling tinggi? Tampilkan perbandingannya',                    category: 'menu'),
  _QuickAction(label: 'Export Laporan',     emoji: '📥', prompt: '__export__',                                                                                      category: 'export'),
];

class _QuickAction {
  final String label;
  final String emoji;
  final String prompt;
  final String category;
  const _QuickAction({required this.label, required this.emoji, required this.prompt, required this.category});
}

// Keyword trigger export
const _exportKeywords = [
  'export', 'ekspor', 'download', 'unduh', 'cetak', 'simpan laporan',
  'laporan pdf', 'laporan excel', 'laporan csv', 'generate report',
  'buat laporan', 'kirim laporan', 'share laporan',
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

  List<String> _lowStockAlert = [];
bool _quickActionsExpanded = false; // ← TAMBAH BARIS INI

  // ── Sentiment Detection ────────────────────────────────────────────
  static const _negativeKeywords = [
    'lambat', 'lama', 'error', 'rusak', 'masalah', 'problem', 'gagal',
    'tidak bisa', 'gabisa', 'kenapa', 'bug', 'salah', 'keluhan', 'komplain',
    'kecewa', 'buruk', 'jelek', 'parah', 'bingung', 'susah', 'ribet',
    'tidak jalan', 'ga jalan', 'tidak muncul', 'ga muncul', 'hilang',
  ];
  static const _urgentKeywords = [
    'urgent', 'darurat', 'segera', 'cepat', 'bos', 'penting', 'kritis',
    'tidak berfungsi', 'mati', 'down', 'offline',
  ];

  String _detectSentiment(String text) {
    final lower = text.toLowerCase();
    if (_urgentKeywords.any((k) => lower.contains(k))) return 'urgent';
    if (_negativeKeywords.any((k) => lower.contains(k))) return 'negative';
    return 'neutral';
  }

  // Branch sidebar (superadmin only)
  List<_BranchItem> _branches = [];
  String? _selectedBranchId;
  String? _myBranchId;
  bool _isSuperadmin = false;
  bool _initialized = false;

  String get _proxyUrl {
    if (kIsWeb) return '/api/chat';
    return 'http://localhost:3000/api/chat';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final messages = ref.read(chatProvider).messages;
      if (messages.isEmpty) {
        _addBot(
          '👋 Halo! Saya **Resto Analytics AI**.\n\n'
          'Saya bisa bantu:\n'
          '• 📊 Report harian\n'
          '• 🏆 Analisis menu & margin\n'
          '• 📦 Status inventory\n'
          '• 🍽️ Info menu, allergen & dietary\n'
          '• 💡 Insight bisnis\n\n'
          'Silakan pilih atau ketik pertanyaan 👇',
        );
      }
    });
  }

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

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
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

  // ── Analytics Data ─────────────────────────────────────────────────
  Future<Map<String, dynamic>> _fetchAnalyticsData() async {
    final sb = Supabase.instance.client;
    final now = DateTime.now();
    final branchId = _isSuperadmin ? _selectedBranchId : _myBranchId;

    String dateStr(DateTime d) => d.toIso8601String().substring(0, 10);

    final todayStart = '${dateStr(now)}T00:00:00';
    final todayEnd = '${dateStr(now)}T23:59:59';

    final weekStart = dateStr(now.subtract(Duration(days: now.weekday - 1)));
    final lastWeekStart =
        dateStr(now.subtract(Duration(days: now.weekday + 6)));
    final lastWeekEnd = dateStr(now.subtract(Duration(days: now.weekday)));

    final monthStart =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-01';

    final branchLabel = _isSuperadmin && _selectedBranchId == null
        ? 'Semua Cabang'
        : _branches
                .where((b) => b.id == _selectedBranchId)
                .firstOrNull
                ?.name ??
            'Cabang Saya';

    try {
      // ── 1. Orders hari ini ──────────────────────────────────────────
      var qToday = sb
          .from('orders')
          .select(
              'total_amount, status, created_at, order_type, payment_method')
          .gte('created_at', todayStart)
          .lte('created_at', todayEnd);
      if (branchId != null) qToday = qToday.eq('branch_id', branchId);
      final ordersToday =
          (await qToday as List).cast<Map<String, dynamic>>();

      final completedToday =
          ordersToday.where((o) => (o['status'] == 'paid' || o['status'] == 'served')).toList();
      final revenueToday = completedToday.fold<double>(
          0, (s, o) => s + ((o['total_amount'] as num?)?.toDouble() ?? 0));
      final cancelledToday =
          ordersToday.where((o) => o['status'] == 'cancelled').length;
      final avgOrderValue =
          completedToday.isEmpty ? 0.0 : revenueToday / completedToday.length;

      // ── Hitung order berdasarkan order_type ──────────────────────────
      final Map<String, int> orderTypeCount = {};
      final Map<String, double> orderTypeRevenue = {};
      for (final o in completedToday) {
        final type = (o['order_type'] as String?) ?? 'unknown';
        orderTypeCount[type] = (orderTypeCount[type] ?? 0) + 1;
        orderTypeRevenue[type] = (orderTypeRevenue[type] ?? 0) +
            ((o['total_amount'] as num?)?.toDouble() ?? 0);
      }
      final orderTypeSummary = orderTypeCount.entries
          .map((e) =>
              '${e.key}: ${e.value} transaksi (Rp ${orderTypeRevenue[e.key]!.toStringAsFixed(0)})')
          .toList();

      final Map<String, int> paymentCount = {};
      final Map<String, double> paymentRevenue = {};
      for (final o in completedToday) {
        final method = (o['payment_method'] as String?) ?? 'unknown';
        paymentCount[method] = (paymentCount[method] ?? 0) + 1;
        paymentRevenue[method] = (paymentRevenue[method] ?? 0) +
            ((o['total_amount'] as num?)?.toDouble() ?? 0);
      }
      final paymentSummary = paymentCount.entries
          .map((e) =>
              '${e.key}: ${e.value} transaksi (Rp ${paymentRevenue[e.key]!.toStringAsFixed(0)})')
          .toList();

      final Map<int, int> perJam = {};
      for (final o in ordersToday) {
        if (o['created_at'] != null) {
          final jam = DateTime.parse(o['created_at']).toLocal().hour;
          perJam[jam] = (perJam[jam] ?? 0) + 1;
        }
      }
      final jamTerramai = perJam.isEmpty
          ? '-'
          : perJam.entries.reduce((a, b) => a.value > b.value ? a : b).key;

      // ── 2. Orders minggu ini ────────────────────────────────────────
      var qWeek = sb
          .from('orders')
          .select('total_amount, status, created_at')
          .gte('created_at', '${weekStart}T00:00:00')
          .lte('created_at', todayEnd);
      if (branchId != null) qWeek = qWeek.eq('branch_id', branchId);
      final ordersWeek =
          (await qWeek as List).cast<Map<String, dynamic>>();
      final revenueWeek = ordersWeek
          .where((o) => (o['status'] == 'paid' || o['status'] == 'served'))
          .fold<double>(
              0, (s, o) => s + ((o['total_amount'] as num?)?.toDouble() ?? 0));

      // ── 3. Orders minggu lalu ───────────────────────────────────────
      var qLastWeek = sb
          .from('orders')
          .select('total_amount, status')
          .gte('created_at', '${lastWeekStart}T00:00:00')
          .lte('created_at', '${lastWeekEnd}T23:59:59');
      if (branchId != null) qLastWeek = qLastWeek.eq('branch_id', branchId);
      final ordersLastWeek =
          (await qLastWeek as List).cast<Map<String, dynamic>>();
      final revenueLastWeek = ordersLastWeek
          .where((o) => (o['status'] == 'paid' || o['status'] == 'served'))
          .fold<double>(
              0, (s, o) => s + ((o['total_amount'] as num?)?.toDouble() ?? 0));

      // ── 4. Orders bulan ini ─────────────────────────────────────────
      var qMonth = sb
          .from('orders')
          .select('total_amount, status')
          .gte('created_at', '${monthStart}T00:00:00')
          .lte('created_at', todayEnd);
      if (branchId != null) qMonth = qMonth.eq('branch_id', branchId);
      final ordersMonth =
          (await qMonth as List).cast<Map<String, dynamic>>();
      final revenueMonth = ordersMonth
          .where((o) => (o['status'] == 'paid' || o['status'] == 'served'))
          .fold<double>(
              0, (s, o) => s + ((o['total_amount'] as num?)?.toDouble() ?? 0));

      // ── 5. Menu terlaris bulan ini ──────────────────────────────────
      var qCompletedOrders = sb
          .from('orders')
          .select('id')
          .inFilter('status', ['paid', 'served'])
          .gte('created_at', '${monthStart}T00:00:00')
          .lte('created_at', todayEnd);
      if (branchId != null) qCompletedOrders = qCompletedOrders.eq('branch_id', branchId);
      final completedOrders = (await qCompletedOrders as List).cast<Map<String, dynamic>>();
      final completedOrderIds = completedOrders.map((o) => o['id'] as String).toList();

      final Map<String, int> menuCount = {};
      if (completedOrderIds.isNotEmpty) {
        final itemsRaw = (await sb
            .from('order_items')
            .select('menu_item_name, quantity')
            .inFilter('order_id', completedOrderIds) as List)
            .cast<Map<String, dynamic>>();
        for (final item in itemsRaw) {
          final name = (item['menu_item_name'] as String?) ?? 'Unknown';
          final qty = (item['quantity'] as num?)?.toInt() ?? 1;
          menuCount[name] = (menuCount[name] ?? 0) + qty;
        }
      }
      final topMenu = (menuCount.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .take(5)
          .map((e) => '${e.key} (${e.value}x)')
          .toList();

      final weekGrowth = revenueLastWeek == 0
          ? 'N/A'
          : '${((revenueWeek - revenueLastWeek) / revenueLastWeek * 100).toStringAsFixed(1)}%';

      // ── 6. Booking hari ini ─────────────────────────────────────────
      final todayDate = dateStr(now);
      var qBooking = sb
          .from('bookings')
          .select(
              'customer_name, guest_count, booking_time, status, special_requests, deposit_status')
          .eq('booking_date', todayDate);
      if (branchId != null) qBooking = qBooking.eq('branch_id', branchId);
      final bookingsToday =
          (await qBooking as List).cast<Map<String, dynamic>>();

      final bookingConfirmed =
          bookingsToday.where((b) => b['status'] == 'confirmed').toList();
      final bookingPending =
          bookingsToday.where((b) => b['status'] == 'pending').toList();
      final bookingCancelled =
          bookingsToday.where((b) => b['status'] == 'cancelled').length;
      final bookingNoShow =
          bookingsToday.where((b) => b['status'] == 'no_show').length;
      final totalGuests = bookingConfirmed.fold<int>(
          0, (s, b) => s + ((b['guest_count'] as num?)?.toInt() ?? 0));

      final bookingList = bookingConfirmed.map((b) {
        final time = (b['booking_time'] as String?)?.substring(0, 5) ?? '-';
        final name = b['customer_name'] ?? '-';
        final guests = b['guest_count'] ?? 0;
        final deposit = b['deposit_status'] ?? 'none';
        final notes = b['special_requests'];
        return '$time - $name ($guests orang)${deposit == 'paid' ? ' [DP✅]' : ''}${notes != null ? ' - $notes' : ''}';
      }).toList()
        ..sort();

      final pendingList = bookingPending.map((b) {
        final time = (b['booking_time'] as String?)?.substring(0, 5) ?? '-';
        final name = b['customer_name'] ?? '-';
        final guests = b['guest_count'] ?? 0;
        return '$time - $name ($guests orang)';
      }).toList()
        ..sort();

      // ── 7. Inventory stok menipis ───────────────────────────────────
      var qInv = sb
          .from('inventory_items')
          .select('name, current_stock, minimum_stock, unit, category');
      if (branchId != null) qInv = qInv.eq('branch_id', branchId);
      final invRaw = (await qInv as List).cast<Map<String, dynamic>>();

      final lowStock = invRaw.where((i) {
        final cur = (i['current_stock'] as num?)?.toDouble() ?? 0;
        final min = (i['minimum_stock'] as num?)?.toDouble() ?? 0;
        return cur <= min;
      }).map((i) {
        final cur = (i['current_stock'] as num?)?.toDouble() ?? 0;
        final min = (i['minimum_stock'] as num?)?.toDouble() ?? 0;
        return '${i['name']} (stok: $cur ${i['unit']}, min: $min ${i['unit']})';
      }).toList();

      final nearLowStock = invRaw.where((i) {
        final cur = (i['current_stock'] as num?)?.toDouble() ?? 0;
        final min = (i['minimum_stock'] as num?)?.toDouble() ?? 0;
        return cur > min && cur <= min * 1.5 && min > 0;
      }).map((i) {
        final cur = (i['current_stock'] as num?)?.toDouble() ?? 0;
        return '${i['name']} (stok: $cur ${i['unit']})';
      }).toList();

      return {
        'cabang': branchLabel,
        'tanggal': dateStr(now),
        'hari_ini': {
          'total_order': ordersToday.length,
          'order_selesai': completedToday.length,
          'order_dibatalkan': cancelledToday,
          'revenue': 'Rp ${revenueToday.toStringAsFixed(0)}',
          'rata_rata_nilai_order': 'Rp ${avgOrderValue.toStringAsFixed(0)}',
          'jam_paling_ramai':
              jamTerramai == '-' ? '-' : '$jamTerramai:00',
          'payment_method': paymentSummary,
          'order_type': orderTypeSummary,  // ✅ DITAMBAHKAN
        },
        'minggu_ini': {
          'total_order': ordersWeek.length,
          'revenue': 'Rp ${revenueWeek.toStringAsFixed(0)}',
        },
        'minggu_lalu': {
          'total_order': ordersLastWeek.length,
          'revenue': 'Rp ${revenueLastWeek.toStringAsFixed(0)}',
        },
        'pertumbuhan_minggu': weekGrowth,
        'bulan_ini': {
          'total_order': ordersMonth.length,
          'revenue': 'Rp ${revenueMonth.toStringAsFixed(0)}',
        },
        'top_menu_bulan_ini': topMenu,
        'booking_hari_ini': {
          'total': bookingsToday.length,
          'confirmed': bookingConfirmed.length,
          'pending': bookingPending.length,
          'cancelled': bookingCancelled,
          'no_show': bookingNoShow,
          'total_tamu': totalGuests,
          'daftar_confirmed': bookingList,
          'daftar_pending': pendingList,
        },
        'peringatan_stok': {
          'stok_habis_atau_dibawah_minimum': lowStock,
          'stok_hampir_habis': nearLowStock,
        },
      };
    } catch (e) {
      return {'error': e.toString(), 'cabang': branchLabel};
    }
  }

  // ── Menu Data untuk AI ─────────────────────────────────────────────
  Future<Map<String, dynamic>> _fetchMenuData() async {
    final sb = Supabase.instance.client;
    final branchId = _isSuperadmin ? _selectedBranchId : _myBranchId;

    try {
      // 1. Fetch menu items tanpa join
      dynamic qMenu = sb
          .from('menu_items')
          .select('id, name, price, description, is_available, preparation_time_minutes, category_id');
      if (branchId != null) qMenu = (qMenu as dynamic).eq('branch_id', branchId);
      final menuRaw = ((await (qMenu as dynamic).order('name')) as List)
          .cast<Map<String, dynamic>>();

      // 2. Fetch kategori terpisah
      // PENTING: jangan kirim .eq('branch_id', '') saat branchId null (Semua Cabang)
      // karena string kosong membuat Supabase return 400 Bad Request
      dynamic catQuery = sb.from('menu_categories').select('id, name');
      if (branchId != null) catQuery = catQuery.eq('branch_id', branchId);
      final catRaw = (await catQuery) as List;
      final catMap = <String, String>{
        for (final c in catRaw) c['id'] as String: c['name'] as String
      };

      if (menuRaw.isEmpty) {
        return {'total_menu': 0, 'menu_tersedia': [], 'menu_tidak_tersedia': [], 'ranking_margin': []};
      }

      final menuIds = menuRaw.map((m) => m['id'] as String).toList();

      // 3. Fetch allergens untuk semua menu
      final allergensRaw = (await sb
          .from('menu_item_allergens')
          .select('menu_item_id, allergen')
          .inFilter('menu_item_id', menuIds) as List)
          .cast<Map<String, dynamic>>();

      final Map<String, List<String>> allergenMap = {};
      for (final a in allergensRaw) {
        final id = a['menu_item_id'] as String;
        allergenMap.putIfAbsent(id, () => []).add(a['allergen'] as String);
      }

      // 4. Fetch dietary tags untuk semua menu
      final dietaryRaw = (await sb
          .from('menu_item_dietary')
          .select('menu_item_id, dietary_tag')
          .inFilter('menu_item_id', menuIds) as List)
          .cast<Map<String, dynamic>>();

      final Map<String, List<String>> dietaryMap = {};
      for (final d in dietaryRaw) {
        final id = d['menu_item_id'] as String;
        dietaryMap.putIfAbsent(id, () => []).add(d['dietary_tag'] as String);
      }

      // 5. Fetch menu_ingredients untuk hitung COGS
      final ingredientsRaw = (await sb
          .from('menu_ingredients')
          .select('menu_item_id, quantity, cost_per_unit')
          .inFilter('menu_item_id', menuIds) as List)
          .cast<Map<String, dynamic>>();

      final Map<String, double> cogsMap = {};
      for (final ing in ingredientsRaw) {
        final id = ing['menu_item_id'] as String;
        final qty = (ing['quantity'] as num?)?.toDouble() ?? 0;
        final cost = (ing['cost_per_unit'] as num?)?.toDouble() ?? 0;
        cogsMap[id] = (cogsMap[id] ?? 0) + (qty * cost);
      }

      // 6. Gabungkan semua data per menu item
      final List<Map<String, dynamic>> available = [];
      final List<String> unavailable = [];

      for (final m in menuRaw) {
        final id = m['id'] as String;
        final price = (m['price'] as num?)?.toDouble() ?? 0;
        final cogs = cogsMap[id] ?? 0;
        final margin = price > 0 ? ((price - cogs) / price * 100) : null;
        final allergens = allergenMap[id] ?? [];
        final dietary = dietaryMap[id] ?? [];
        final category = catMap[m['category_id']] ?? 'Umum';
        final prepTime = m['preparation_time_minutes'] as int?;

        final item = {
          'nama': m['name'],
          'harga': 'Rp ${price.toStringAsFixed(0)}',
          'harga_raw': price,
          'kategori': category,
          'deskripsi': m['description'] ?? '-',
          'prep_time': prepTime != null ? '$prepTime menit' : '-',
          'cogs': cogs > 0 ? 'Rp ${cogs.toStringAsFixed(0)}' : 'belum diset',
          'cogs_raw': cogs,
          'margin_persen': margin != null ? '${margin.toStringAsFixed(1)}%' : 'belum diset',
          'margin_raw': margin,
          'allergen': allergens.isEmpty ? 'tidak ada' : allergens.join(', '),
          'dietary': dietary.isEmpty ? '-' : dietary.join(', '),
        };

        if (m['is_available'] == true) {
          available.add(item);
        } else {
          unavailable.add(m['name'] as String);
        }
      }

      // 7. Ranking margin terbaik (hanya yang sudah ada COGS-nya)
      final withMargin = available
          .where((m) => (m['margin_raw'] as double?) != null && (m['cogs_raw'] as double) > 0)
          .toList()
        ..sort((a, b) {
          final ma = (a['margin_raw'] as double?) ?? 0;
          final mb = (b['margin_raw'] as double?) ?? 0;
          return mb.compareTo(ma);
        });

      final rankingMargin = withMargin.take(5).map((m) =>
          '${m['nama']}: margin ${m['margin_persen']} (jual ${m['harga']}, COGS ${m['cogs']})').toList();

      // 8. Format detail menu untuk AI (tanpa field raw)
      final availableForAI = available.map((m) => {
        'nama': m['nama'],
        'harga': m['harga'],
        'kategori': m['kategori'],
        'deskripsi': m['deskripsi'],
        'prep_time': m['prep_time'],
        'cogs': m['cogs'],
        'margin_persen': m['margin_persen'],
        'allergen': m['allergen'],
        'dietary': m['dietary'],
      }).toList();

      return {
        'total_menu': menuRaw.length,
        'total_tersedia': available.length,
        'total_tidak_tersedia': unavailable.length,
        'menu_tersedia': availableForAI,
        'menu_tidak_tersedia': unavailable,
        'ranking_margin': rankingMargin,
      };
    } catch (e) {
      return {
        'error': e.toString(),
        'total_menu': 0,
        'menu_tersedia': [],
        'menu_tidak_tersedia': [],
        'ranking_margin': [],
      };
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
    }

    if (res.statusCode == 404) {
      throw Exception(
        'Proxy 404: Vercel function /api/chat belum aktif.\n'
        'Solusi: Tambahkan blok "functions" di vercel.json lalu redeploy.',
      );
    }

    if (res.statusCode == 500) {
      final body = jsonDecode(res.body);
      if ((body['error'] as String?)?.contains('GROQ_API_KEY') == true) {
        throw Exception(
          'GROQ_API_KEY belum dikonfigurasi di Vercel Environment Variables.',
        );
      }
    }

    throw Exception('Proxy error ${res.statusCode}: ${res.body}');
  }

  // ── Show Export Sheet ─────────────────────────────────────────────
  Future<void> _showExportSheet() async {
    final branchName = _isSuperadmin
        ? (_selectedBranchId == null
            ? 'Semua Cabang'
            : _branches
                    .where((b) => b.id == _selectedBranchId)
                    .firstOrNull
                    ?.name ??
                'Cabang')
        : (_branches.where((b) => b.id == _myBranchId).firstOrNull?.name ??
            'Cabang Saya');

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReportExportSheet(
        branchId: _isSuperadmin ? _selectedBranchId : _myBranchId,
        branchName: branchName,
      ),
    );

    if (result == true && mounted) {
      _addBot('✅ Laporan berhasil diekspor! File sudah tersedia di share sheet.');
    }
  }

  // ── Send Message ───────────────────────────────────────────────────
  Future<void> _send([String? quick]) async {
    final text = (quick ?? _msgCtrl.text).trim();
    final chatNotifier = ref.read(chatProvider.notifier);

    if (text.isEmpty || ref.read(chatProvider).isTyping) return;

    // Intercept export quick action
    if (text == '__export__') {
      await _showExportSheet();
      return;
    }

    // Intercept export keywords dari user input
    final lower = text.toLowerCase();
    if (_exportKeywords.any((k) => lower.contains(k))) {
      chatNotifier.addMessage(
          ChatMessage(role: 'user', content: text, timestamp: DateTime.now()));
      _addBot('📥 Buka panel export laporan...');
      await Future.delayed(const Duration(milliseconds: 400));
      await _showExportSheet();
      return;
    }

    _msgCtrl.clear();

    chatNotifier.addMessage(
        ChatMessage(role: 'user', content: text, timestamp: DateTime.now()));
    chatNotifier.setTyping(true);

    _scrollToBottom();

    final sentiment = _detectSentiment(text);

    // Fetch analytics + menu data secara paralel
    final results = await Future.wait([
      _fetchAnalyticsData(),
      _fetchMenuData(),
    ]);
    final data = results[0];
    final menuData = results[1];

    // Update proactive stock alert banner
    final warnings = data['peringatan_stok'] as Map?;
    if (warnings != null && mounted) {
      final low = (warnings['stok_habis_atau_dibawah_minimum'] as List? ?? [])
          .cast<String>();
      final near =
          (warnings['stok_hampir_habis'] as List? ?? []).cast<String>();
      setState(() {
        _lowStockAlert = [
          ...low.map((s) => '🚨 $s'),
          ...near.map((s) => '⚠️ $s'),
        ];
      });
    }

    // Format detail menu untuk system prompt
    final menuTersedia = (menuData['menu_tersedia'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final menuDetail = menuTersedia.map((m) =>
        '• ${m['nama']} — ${m['harga']} [${m['kategori']}]\n'
        '  Deskripsi: ${m['deskripsi']}\n'
        '  COGS: ${m['cogs']} | Margin: ${m['margin_persen']} | Prep: ${m['prep_time']}\n'
        '  Allergen: ${m['allergen']} | Dietary: ${m['dietary']}').join('\n');

    final menuTidakTersedia = (menuData['menu_tidak_tersedia'] as List? ?? []);
    final rankingMargin = (menuData['ranking_margin'] as List? ?? []);

    final systemPrompt = '''
Kamu adalah AI Analytics restoran yang cerdas dan helpful untuk tim internal.

DATA ANALYTICS (sudah diambil dari database real-time):
${data.toString()}

DATA MENU RESTORAN (real-time dari database):
- Total menu: ${menuData['total_menu']} item (tersedia: ${menuData['total_tersedia']}, tidak tersedia: ${menuData['total_tidak_tersedia']})
- Menu tidak tersedia saat ini: ${menuTidakTersedia.isEmpty ? 'tidak ada' : menuTidakTersedia.join(', ')}
- Ranking margin terbaik: ${rankingMargin.isEmpty ? 'belum ada data COGS' : rankingMargin.join(' | ')}

DETAIL MENU YANG TERSEDIA:
${menuDetail.isEmpty ? '(belum ada menu tersedia)' : menuDetail}

KEMAMPUAN KAMU:
- Analisis performa hari ini, minggu ini, bulan ini
- Bandingkan revenue/order minggu ini vs minggu lalu
- Identifikasi jam paling ramai
- Analisis menu terlaris & margin keuntungan
- Hitung pertumbuhan bisnis
- Peringatan stok menipis/habis
- Info booking hari ini (confirmed, pending, no-show, daftar tamu)
- Info lengkap menu: harga, kategori, allergen, dietary, COGS, margin
- Rekomendasikan menu berdasarkan margin, kategori, atau dietary preference
- Analisis order berdasarkan tipe (app, staff, qr_order, dll)
- Berikan rekomendasi actionable berdasarkan data

ATURAN MENU:
- Jika ditanya tentang allergen (contoh: "ada menu bebas gluten?"), cek kolom allergen di data menu
- Jika ditanya tentang dietary (contoh: "ada menu vegetarian?"), cek kolom dietary di data menu
- Jika ditanya margin atau profitabilitas menu, gunakan data ranking_margin dan detail margin per item
- Jika ditanya COGS atau harga pokok, tampilkan dari data menu
- Jika menu belum punya data COGS, sampaikan bahwa data belum diisi
- Selalu rekomendasikan menu dengan margin tinggi jika relevan

ATURAN ORDER TYPE:
- Data order_type di hari_ini berisi breakdown per tipe: app, staff, qr_order, atau lainnya
- Jika ditanya "paling banyak dari mana" atau "app/staff/qr", gunakan data order_type
- Tampilkan jumlah transaksi dan revenue per tipe pemesanan

ATURAN PROACTIVE INSIGHT:
- Jika ada data di "stok_habis_atau_dibawah_minimum", SELALU tampilkan peringatan 🚨 di awal respons
- Jika ada data di "stok_hampir_habis", tampilkan peringatan ⚠️
- Jika order dibatalkan > 20% dari total order, beri peringatan dan saran
- Jika pertumbuhan minggu negatif, berikan analisis dan rekomendasi

ATURAN FORMAT:
- Jawab dalam Bahasa Indonesia yang ramah dan profesional
- Format angka rupiah dengan titik sebagai separator ribuan (Rp 1.250.000)
- Jika ditanya perbandingan, tampilkan kedua angka + persentase perubahan
- Gunakan emoji secukupnya untuk keterbacaan
- Berikan insight dan rekomendasi, bukan hanya angka mentah

SENTIMENT STAFF: $sentiment
${sentiment == 'urgent' ? '- URGENT: Prioritaskan solusi cepat. Mulai dengan mengakui urgensi. Sarankan eskalasi ke manager jika perlu.' : sentiment == 'negative' ? '- Staff mengalami kesulitan. Mulai dengan empati, akui masalah dulu, gunakan tone supportif, berikan langkah troubleshooting yang jelas.' : '- Respons normal, ramah dan profesional.'}
''';

    try {
      final allMessages = ref.read(chatProvider).messages;
      final recent = allMessages.length > 10
          ? allMessages.sublist(allMessages.length - 10)
          : allMessages;

      // Exclude pesan user terakhir (yang baru saja ditambahkan)
      final history = recent
          .where((m) => m != allMessages.last)
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
      chatNotifier.setTyping(false);
      _scrollToBottom();
    }
  }

  void _addBot(String content) {
    ref.read(chatProvider.notifier).addMessage(
        ChatMessage(role: 'assistant', content: content, timestamp: DateTime.now()));
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
    final chatState = ref.watch(chatProvider);

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
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
          // ── BRANCH FILTER DROPDOWN (superadmin only) ──
          if (_isSuperadmin && _branches.isNotEmpty)
            DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _selectedBranchId,
                isDense: true,
                dropdownColor: const Color(0xFF1A1A2E),
                iconEnabledColor: Colors.white60,
                icon: const Icon(Icons.keyboard_arrow_down, size: 16),
                style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 11, color: Colors.white70),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Semua Cabang',
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 11, color: Colors.white70))),
                  ..._branches.map((b) => DropdownMenuItem<String?>(
                    value: b.id,
                    child: Text(b.name,
                      style: const TextStyle(
                        fontFamily: 'Poppins', fontSize: 11, color: Colors.white)))),
                ],
                onChanged: (val) {
                  setState(() {
                    _selectedBranchId = val;
                    _lowStockAlert = [];
                  });
                  ref.read(chatProvider.notifier).clearHistory();
                  _addBot(
                    '🏢 Beralih ke cabang: ${val == null ? "Semua Cabang" : _branches.firstWhere((b) => b.id == val).name}\n\nSilakan ajukan pertanyaan 👇',
                  );
                },
              ),
            ),
          const SizedBox(width: 4),
          // Tombol clear history
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            tooltip: 'Hapus History Chat',
            onPressed: () {
              ref.read(chatProvider.notifier).clearHistory();
              _addBot(
                '👋 Halo! Saya **Resto Analytics AI**.\n\n'
                'Saya bisa bantu:\n'
                '• 📊 Report harian\n'
                '• 🏆 Analisis menu & margin\n'
                '• 📦 Status inventory\n'
                '• 🍽️ Info menu, allergen & dietary\n'
                '• 💡 Insight bisnis\n\n'
                'Silakan pilih atau ketik pertanyaan 👇',
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Row(
        children: [
          // ── Chat area ─────────────────────────────────────────────
          Expanded(
            child: Column(
              children: [
                if (_lowStockAlert.isNotEmpty) _buildStockAlert(),
                Expanded(child: _buildMessages(chatState)),
                _buildQuickActions(),
                _buildInput(chatState.isTyping),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Stock Alert Banner ─────────────────────────────────────────────
  Widget _buildStockAlert() {
    final hasUrgent = _lowStockAlert.any((s) => s.startsWith('🚨'));
    return Container(
      width: double.infinity,
      color:
          hasUrgent ? const Color(0xFFFFEBEE) : const Color(0xFFFFF8E1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(hasUrgent ? '🚨' : '⚠️',
              style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasUrgent ? 'Stok Di Bawah Minimum!' : 'Stok Hampir Habis',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: hasUrgent
                        ? const Color(0xFFC62828)
                        : const Color(0xFFE65100),
                  ),
                ),
                Text(
                  _lowStockAlert.take(3).join(' • '),
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: hasUrgent
                        ? const Color(0xFFB71C1C)
                        : const Color(0xFFBF360C),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _send(
                'Tampilkan detail peringatan stok yang bermasalah dan rekomendasinya'),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: hasUrgent
                    ? const Color(0xFFC62828)
                    : const Color(0xFFE65100),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Detail',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Messages ───────────────────────────────────────────────────────
  Widget _buildMessages(ChatState chatState) => ListView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount:
            chatState.messages.length + (chatState.isTyping ? 1 : 0),
        itemBuilder: (_, i) {
          if (i == chatState.messages.length) {
            return const TypingIndicator();
          }
          final m = chatState.messages[i];
          final isUser = m.role == 'user';
          if (isUser) {
            return ChatBubble(message: m);
          }
          return _buildBotBubble(m);
        },
      );

  // Bot bubble dengan MarkdownBody
  Widget _buildBotBubble(ChatMessage m) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A1A2E), Color(0xFFE94560)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.restaurant,
                color: Colors.white, size: 16),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MarkdownBody(
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
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${m.timestamp.hour.toString().padLeft(2, '0')}:${m.timestamp.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Quick Actions ──────────────────────────────────────────────────
  Widget _buildQuickActions() {
  return AnimatedContainer(
    duration: const Duration(milliseconds: 250),
    curve: Curves.easeInOut,
    color: AppColors.surface,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Header toggle ──────────────────────────────────────
        InkWell(
          onTap: () => setState(() => _quickActionsExpanded = !_quickActionsExpanded),
          child: Container(
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
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 12,
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

        // ── Grid 2 kolom (hanya saat expanded) ────────────────
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
              itemCount: _quickActionsV2.length,
              itemBuilder: (_, i) {
                final action = _quickActionsV2[i];
                return _QuickActionButton(
                  action: action,
                  onTap: () => _send(action.prompt),
                );
              },
            ),
          ),

        // ── Horizontal scroll kecil saat collapsed ─────────────
        if (!_quickActionsExpanded)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: Row(
              children: _quickActionsV2.map((action) {
                final color = _categoryColor(action.category);
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => _send(action.prompt),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: color.withValues(alpha: 0.4)),
                      ),
                      child: Text('${action.emoji} ${action.label}',
                        style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 12,
                          fontWeight: FontWeight.w600, color: color)),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    ),
  );
}

Color _categoryColor(String category) {
  switch (category) {
    case 'menu':    return Colors.orange;
    case 'booking': return Colors.purple;
    case 'export':  return Colors.green;
    default:        return AppColors.primary;
  }
}

  // ── Input ──────────────────────────────────────────────────────────
  Widget _buildInput(bool isTyping) => Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
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
                    borderSide:
                        const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide:
                        const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(
                        color: AppColors.primary, width: 1.5),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: isTyping ? null : _send,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isTyping
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


// ── Quick Action Button Widget ────────────────────────────────────────────────
class _QuickActionButton extends StatelessWidget {
  final _QuickAction action;
  final VoidCallback onTap;
  const _QuickActionButton({required this.action, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(action.category);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Text(action.emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(action.label,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 12,
                  fontWeight: FontWeight.w600, color: color)),
            ),
          ],
        ),
      ),
    );
  }

  static Color _colorFor(String category) {
    switch (category) {
      case 'menu':    return Colors.orange;
      case 'booking': return Colors.purple;
      case 'export':  return Colors.green;
      default:        return AppColors.primary;
    }
  }
}