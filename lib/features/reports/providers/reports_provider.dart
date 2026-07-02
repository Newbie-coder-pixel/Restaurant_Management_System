// lib/features/reports/providers/reports_provider.dart

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../shared/models/order_model.dart';
import '../../../core/models/staff_role.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../costing/providers/costing_providers.dart';

// ── Period enum ──────────────────────────────────────────────────────────────

enum ReportPeriod { week, month }

extension ReportPeriodExt on ReportPeriod {
  String get label => this == ReportPeriod.week ? 'Minggu Ini' : 'Bulan Ini';
  int get days => this == ReportPeriod.week ? 7 : 30;
}

// ── State model ──────────────────────────────────────────────────────────────

class ReportsState {
  final bool isLoading;
  final int todayOrders;
  final double todayRevenue;
  final int todayBookings;
  final double todayCogs;
  final List<FlSpot> revenueSpots;
  final List<OrderModel> recentOrders;
  final List<Map<String, dynamic>> topMenus;
  final List<String> topMenuCategories; // daftar unik kategori untuk filter
  final List<Map<String, dynamic>> menuMargins;
  final List<Map<String, dynamic>> branchRevenue;
  final List<Map<String, dynamic>> branches;
  final String? selectedBranchId;
  final bool isSuperAdmin;
  final String? branchId;
  final ReportPeriod period;

  const ReportsState({
    this.isLoading = true,
    this.todayOrders = 0,
    this.todayRevenue = 0,
    this.todayBookings = 0,
    this.todayCogs = 0,
    this.revenueSpots = const [],
    this.recentOrders = const [],
    this.topMenus = const [],
    this.topMenuCategories = const [],
    this.menuMargins = const [],
    this.branchRevenue = const [],
    this.branches = const [],
    this.selectedBranchId,
    this.isSuperAdmin = false,
    this.branchId,
    this.period = ReportPeriod.week,
  });

  ReportsState copyWith({
    bool? isLoading,
    int? todayOrders,
    double? todayRevenue,
    int? todayBookings,
    double? todayCogs,
    List<FlSpot>? revenueSpots,
    List<OrderModel>? recentOrders,
    List<Map<String, dynamic>>? topMenus,
    List<String>? topMenuCategories,
    List<Map<String, dynamic>>? menuMargins,
    List<Map<String, dynamic>>? branchRevenue,
    List<Map<String, dynamic>>? branches,
    String? selectedBranchId,
    bool? isSuperAdmin,
    String? branchId,
    bool clearSelectedBranch = false,
    ReportPeriod? period,
  }) {
    return ReportsState(
      isLoading: isLoading ?? this.isLoading,
      todayOrders: todayOrders ?? this.todayOrders,
      todayRevenue: todayRevenue ?? this.todayRevenue,
      todayBookings: todayBookings ?? this.todayBookings,
      todayCogs: todayCogs ?? this.todayCogs,
      revenueSpots: revenueSpots ?? this.revenueSpots,
      recentOrders: recentOrders ?? this.recentOrders,
      topMenus: topMenus ?? this.topMenus,
      topMenuCategories: topMenuCategories ?? this.topMenuCategories,
      menuMargins: menuMargins ?? this.menuMargins,
      branchRevenue: branchRevenue ?? this.branchRevenue,
      branches: branches ?? this.branches,
      selectedBranchId: clearSelectedBranch ? null : selectedBranchId ?? this.selectedBranchId,
      isSuperAdmin: isSuperAdmin ?? this.isSuperAdmin,
      branchId: branchId ?? this.branchId,
      period: period ?? this.period,
    );
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────

final reportsProvider =
    ChangeNotifierProvider<ReportsNotifier>((ref) {
  return ReportsNotifier(ref);
});

// ── Notifier ──────────────────────────────────────────────────────────────────

class ReportsNotifier extends ChangeNotifier {
  final Ref _ref;
  ReportsState _state = const ReportsState();
  bool _initialized = false;

  ReportsNotifier(this._ref);

  ReportsState get state => _state;

  // ── Init ─────────────────────────────────────────────────────────────────

Future<void> init() async {
  if (_initialized) return;
  _initialized = true;

  final staff = _ref.read(currentStaffProvider);
  if (staff == null) {
    // Staff belum ready, coba lagi setelah delay singkat
    await Future.delayed(const Duration(milliseconds: 300));
    final retryStaff = _ref.read(currentStaffProvider);
    if (retryStaff == null) return;
    _state = _state.copyWith(
      isSuperAdmin: retryStaff.role == StaffRole.superadmin,
      branchId: retryStaff.role == StaffRole.superadmin ? null : retryStaff.branchId,
    );
  } else {
    _state = _state.copyWith(
      isSuperAdmin: staff.role == StaffRole.superadmin,
      branchId: staff.role == StaffRole.superadmin ? null : staff.branchId,
    );
  }

  await _loadBranches();
  await load();
}

  // ── Branch filter ─────────────────────────────────────────────────────────

  Future<void> selectBranch(String? branchId) async {
    if (branchId == null) {
      _state = _state.copyWith(clearSelectedBranch: true);
    } else {
      _state = _state.copyWith(selectedBranchId: branchId);
    }
    notifyListeners();
    await load();
  }

  // ── Period filter ─────────────────────────────────────────────────────────

  Future<void> selectPeriod(ReportPeriod period) async {
    if (_state.period == period) return;
    _state = _state.copyWith(period: period);
    notifyListeners();
    await load();
  }

  // ── Load branches (superadmin only) ───────────────────────────────────────

  Future<void> _loadBranches() async {
    if (!_state.isSuperAdmin) return;
    try {
      final res = await Supabase.instance.client
          .from('branches')
          .select('id, name')
          .order('name');
      _state = _state.copyWith(
        branches: List<Map<String, dynamic>>.from(res),
      );
      notifyListeners();
    } catch (e) {
      debugPrint('_loadBranches error: $e');
    }
  }

  // ── Main load ─────────────────────────────────────────────────────────────

  Future<void> load() async {
    if (!_state.isSuperAdmin && _state.branchId == null) {
      _state = _state.copyWith(isLoading: false);
      notifyListeners();
      return;
    }

    _state = _state.copyWith(isLoading: true);
    notifyListeners();

    final effectiveBranchId =
        _state.isSuperAdmin ? _state.selectedBranchId : _state.branchId;

    final today = DateTime.now().toLocal();
    final todayStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final tomorrowStr = () {
      final t = today.add(const Duration(days: 1));
      return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    }();
    final todayStart =
        DateTime(today.year, today.month, today.day).toIso8601String();
    final tomorrowStart =
        DateTime(today.year, today.month, today.day + 1).toIso8601String();

    // Hitung range berdasarkan periode yang dipilih
    final periodDays = _state.period.days; // 7 atau 30
    final periodStartDate = today.subtract(Duration(days: periodDays - 1));
    final periodStartIso = DateTime(
            periodStartDate.year, periodStartDate.month, periodStartDate.day)
        .toIso8601String();

    try {
      // ── Today orders ───────────────────────────────────────────
      var ordQ = Supabase.instance.client
          .from('orders')
          .select('id, total_amount, created_at')
          .eq('status', 'paid')
          .gte('created_at', todayStart)
          .lt('created_at', tomorrowStart);
      if (effectiveBranchId != null) ordQ = ordQ.eq('branch_id', effectiveBranchId);
      final ordRes = await ordQ;

      // ── Revenue dari payments ──────────────────────────────────
      var payQ = Supabase.instance.client
          .from('payments')
          .select('amount, created_at')
          .eq('status', 'paid')
          .gte('created_at', todayStart)
          .lt('created_at', tomorrowStart);
      if (effectiveBranchId != null) payQ = payQ.eq('branch_id', effectiveBranchId);
      final payRes = await payQ;

      // ── Today bookings ─────────────────────────────────────────
      var bookQ = Supabase.instance.client
          .from('bookings')
          .select('id')
          .gte('booking_date', todayStr)
          .lt('booking_date', tomorrowStr);
      if (effectiveBranchId != null) bookQ = bookQ.eq('branch_id', effectiveBranchId);
      final bookRes = await bookQ;

      // ── Revenue chart (periode dipilih) ────────────────────────
      var weekQ = Supabase.instance.client
          .from('payments')
          .select('amount, created_at')
          .eq('status', 'paid')
          .gte('created_at', periodStartIso);
      if (effectiveBranchId != null) weekQ = weekQ.eq('branch_id', effectiveBranchId);
      final weekRes = await weekQ;

      // ── Recent orders ──────────────────────────────────────────
      var recentQ = Supabase.instance.client
          .from('orders')
          .select('*, restaurant_tables(table_number), order_items(*)');
      if (effectiveBranchId != null) {
        recentQ = recentQ.eq('branch_id', effectiveBranchId);
      }
      final recentRes =
          await recentQ.order('created_at', ascending: false).limit(20);

      // ── COGS dari inventory_transactions ───────────────────────
      double todayCogs = 0;
      try {
        var cogsQ = Supabase.instance.client
            .from('inventory_transactions')
            .select('quantity, unit_cost')
            .eq('transaction_type', 'usage')
            .gte('created_at', todayStart)
            .lt('created_at', tomorrowStart);
        if (effectiveBranchId != null) {
          cogsQ = cogsQ.eq('branch_id', effectiveBranchId);
        }
        final cogsRes = await cogsQ;
        for (final item in cogsRes as List) {
          final qty = (item['quantity'] ?? 0) as num;
          final cost = (item['unit_cost'] ?? 0) as num;
          todayCogs += qty * cost;
        }
      } catch (e) {
        debugPrint('⚠️ Gagal fetch COGS: $e');
      }

      // ── Top Menu ───────────────────────────────────────────────
      List<Map<String, dynamic>> topMenus = [];
      List<String> topMenuCategories = [];
      try {
        // Join ke menu_items → menu_categories supaya dapat nama kategori
        var topMenuQ = Supabase.instance.client
            .from('order_items')
            .select(
              'menu_item_name, quantity, subtotal, menu_item_id, '
              'orders!inner(branch_id, created_at, status), '
              'menu_items(category_id, menu_categories(name))',
            )
            .eq('orders.status', 'paid')
            .gte('orders.created_at', periodStartIso);
        if (effectiveBranchId != null) {
          topMenuQ = topMenuQ.eq('orders.branch_id', effectiveBranchId);
        }
        final topMenuRes = await topMenuQ;

        final Map<String, Map<String, dynamic>> agg = {};
        for (final row in topMenuRes as List) {
          final name = (row['menu_item_name'] as String?) ?? 'Unknown';
          final qty = (row['quantity'] as num?)?.toInt() ?? 0;
          final rev = (row['subtotal'] as num?)?.toDouble() ?? 0;

          // Ambil nama kategori dari join (nullable karena item lama mungkin null)
          final menuItem = row['menu_items'] as Map<String, dynamic>?;
          final menuCat = menuItem?['menu_categories'] as Map<String, dynamic>?;
          final categoryName = menuCat?['name'] as String? ?? 'Lainnya';

          if (!agg.containsKey(name)) {
            agg[name] = {
              'name': name,
              'qty': 0,
              'revenue': 0.0,
              'category': categoryName,
            };
          }
          agg[name]!['qty'] = (agg[name]!['qty'] as int) + qty;
          agg[name]!['revenue'] = (agg[name]!['revenue'] as double) + rev;
        }

        topMenus = agg.values.toList()
          ..sort((a, b) => (b['qty'] as int).compareTo(a['qty'] as int));
        topMenus = topMenus.take(20).toList(); // ambil 20 supaya filter kategori punya cukup data

        // Kumpulkan daftar kategori unik (urut abjad, 'Semua' di depan)
        final catSet = topMenus.map((m) => m['category'] as String).toSet();
        topMenuCategories = ['Semua', ...catSet.toList()..sort()];
      } catch (e) {
        debugPrint('⚠️ Gagal fetch top menus: $e');
      }

      // ── Menu Margins dari costingProvider ──────────────────────
      // Tidak query ulang — pakai data yang sudah ada di costingProvider
      List<Map<String, dynamic>> menuMargins = [];
      try {
        final costingNotifier = _ref.read(costingProvider);
        // Load dulu kalau belum ada datanya
        if (costingNotifier.costings.isEmpty) {
          await costingNotifier.loadAll();
        }
        final exported = costingNotifier.exportForReports();
        final items = exported['items'] as List<dynamic>;

        menuMargins = items.map((item) {
          final map = item as Map<String, dynamic>;
          return {
            'name': map['menu_item_name'] as String,
            'price': (map['current_price'] as num).toDouble(),
            'cogs': (map['hpp'] as num).toDouble(),
            'margin': (map['margin_pct'] as num).toDouble(),
          };
        }).toList();

        // Sort by margin descending (tertinggi dulu)
        menuMargins.sort(
          (a, b) =>
              (b['margin'] as double).compareTo(a['margin'] as double),
        );
      } catch (e) {
        debugPrint('⚠️ Gagal fetch menu margins dari costingProvider: $e');
      }

      // ── Revenue per Cabang (superadmin only) ───────────────────
      List<Map<String, dynamic>> branchRevenue = [];
      if (_state.isSuperAdmin && _state.branches.isNotEmpty) {
        try {
          final now = DateTime.now();
          final monthStart =
              DateTime(now.year, now.month, 1).toIso8601String();

          final results = await Future.wait(
            _state.branches.map((b) async {
              final bId = b['id'] as String;
              final res = await Supabase.instance.client
                  .from('payments')
                  .select('amount')
                  .eq('branch_id', bId)
                  .eq('status', 'paid')
                  .gte('created_at', monthStart);

              final rev = (res as List).fold<double>(
                0,
                (s, p) => s + ((p['amount'] as num?)?.toDouble() ?? 0),
              );
              return {'name': b['name'] as String, 'revenue': rev};
            }),
          );

          branchRevenue = results.toList()
            ..sort((a, b) =>
                (b['revenue'] as double).compareTo(a['revenue'] as double));
        } catch (e) {
          debugPrint('⚠️ Gagal fetch branch revenue: $e');
        }
      }

      // ── Process revenue chart (dinamis sesuai periode) ────────
      final Map<int, double> dayRevenue = {
        for (int i = 0; i < periodDays; i++) i: 0.0,
      };
      for (final p in weekRes as List) {
        final created = DateTime.parse(p['created_at']).toLocal();
        final diff = DateTime(today.year, today.month, today.day)
            .difference(
                DateTime(created.year, created.month, created.day))
            .inDays;
        if (diff >= 0 && diff < periodDays) {
          final idx = periodDays - 1 - diff;
          dayRevenue[idx] = (dayRevenue[idx]! +
              ((p['amount'] ?? 0) as num).toDouble());
        }
      }
      final spots = dayRevenue.entries
          .map((e) => FlSpot(e.key.toDouble(), e.value / 1000))
          .toList();

      final revenue = (payRes as List).fold<double>(
          0, (s, p) => s + ((p['amount'] ?? 0) as num).toDouble());

      _state = _state.copyWith(
        isLoading: false,
        todayOrders: (ordRes as List).length,
        todayRevenue: revenue,
        todayBookings: (bookRes as List).length,
        todayCogs: todayCogs,
        revenueSpots: spots,
        topMenus: topMenus,
        topMenuCategories: topMenuCategories,
        menuMargins: menuMargins,
        branchRevenue: branchRevenue,
        period: _state.period,
        recentOrders: (recentRes as List)
            .map((e) => OrderModel.fromJson(e))
            .toList(),
      );
      notifyListeners();
    } catch (e, st) {
      debugPrint('ReportsNotifier load error: $e\n$st');
      _state = _state.copyWith(isLoading: false);
      notifyListeners();
    }
  }
}