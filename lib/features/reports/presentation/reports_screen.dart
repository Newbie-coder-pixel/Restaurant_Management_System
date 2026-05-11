import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../shared/models/order_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/staff_role.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/widgets/app_drawer.dart';
import '../../menu/presentation/services/menu_service.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});
  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  int    _todayOrders   = 0;
  double _todayRevenue  = 0;
  int    _todayBookings = 0;
  double _todayCogs     = 0;
  final List<FlSpot> _revenueSpots = [];
  List<OrderModel>   _recentOrders = [];
  bool _isLoading = true;
  List<Map<String, dynamic>> _topMenus   = []; // {name, qty, revenue}
  List<Map<String, dynamic>> _menuMargins    = []; // {name, price, cogs, margin}
  List<Map<String, dynamic>> _branchRevenue = []; // {name, revenue} superadmin only
  String? _branchId;
  bool _isSuperAdmin = false;
  List<Map<String, dynamic>> _branches = [];
  String? _selectedBranchId; // null = semua cabang

  @override
  void initState() {
    super.initState();
  }

  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    final staff = ref.read(currentStaffProvider);
    if (staff != null) {
      _isSuperAdmin = staff.role == StaffRole.superadmin;
      _branchId = _isSuperAdmin ? null : staff.branchId;
      _initialized = true;
      _init();
    } else {
      _initialized = true;
      ref.listenManual(currentStaffProvider, (_, next) {
        if (next != null && mounted) {
          setState(() {
            _isSuperAdmin = next.role == StaffRole.superadmin;
            _branchId = _isSuperAdmin ? null : next.branchId;
          });
          _init();
        }
      });
    }
  }

  Future<void> _init() async {
    await _loadBranches();
    await _load();
  }

  Future<void> _loadBranches() async {
    if (!_isSuperAdmin) return;
    try {
      final res = await Supabase.instance.client
          .from('branches').select('id, name').order('name');
      if (mounted) {
        setState(() => _branches = List<Map<String, dynamic>>.from(res));
      }
    } catch (e) {
      debugPrint('_loadBranches error: \$e');
    }
  }

  Future<void> _load() async {
    // Superadmin boleh lihat semua cabang (branchId null),
    // role lain harus punya branchId
    if (!_isSuperAdmin && _branchId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    final effectiveBranchId = _isSuperAdmin ? _selectedBranchId : _branchId;
    if (mounted) setState(() => _isLoading = true);

    final today = DateTime.now().toLocal();
    final todayStr =
        '${today.year}-${today.month.toString().padLeft(2,'0')}-${today.day.toString().padLeft(2,'0')}';
    final tomorrowStr = () {
      final t = today.add(const Duration(days: 1));
      return '${t.year}-${t.month.toString().padLeft(2,'0')}-${t.day.toString().padLeft(2,'0')}';
    }();
    // Gunakan ISO8601 dengan offset timezone lokal agar Supabase filter benar
    final todayStart = DateTime(today.year, today.month, today.day).toIso8601String();
    final tomorrowStart = DateTime(today.year, today.month, today.day + 1).toIso8601String();
    final weekStartDate = today.subtract(const Duration(days: 6));
    final weekStartIso = DateTime(weekStartDate.year, weekStartDate.month, weekStartDate.day).toIso8601String();

    try {
      // ── Today orders (paid status) ──────────────────────────────
      var ordQ = Supabase.instance.client
          .from('orders')
          .select('id, total_amount, created_at')
          .eq('status', 'paid')
          .gte('created_at', todayStart)
          .lt('created_at', tomorrowStart);
      if (effectiveBranchId != null) ordQ = ordQ.eq('branch_id', effectiveBranchId);
      final ordRes = await ordQ;

      // ── Revenue dari payments (lebih akurat) ────────────────────
      var payQ = Supabase.instance.client
          .from('payments')
          .select('amount, created_at')
          .eq('status', 'paid')
          .gte('created_at', todayStart)
          .lt('created_at', tomorrowStart);
      if (effectiveBranchId != null) payQ = payQ.eq('branch_id', effectiveBranchId);
      final payRes = await payQ;

      // ── Today bookings ──────────────────────────────────────────
      var bookQ = Supabase.instance.client
          .from('bookings')
          .select('id')
          .gte('booking_date', todayStr)
          .lt('booking_date', tomorrowStr);
      if (effectiveBranchId != null) bookQ = bookQ.eq('branch_id', effectiveBranchId);
      final bookRes = await bookQ;

      // ── 7-day revenue dari payments ─────────────────────────────
      var weekQ = Supabase.instance.client
          .from('payments')
          .select('amount, created_at')
          .eq('status', 'paid')
          .gte('created_at', weekStartIso);
      if (effectiveBranchId != null) weekQ = weekQ.eq('branch_id', effectiveBranchId);
      final weekRes = await weekQ;

      // ── Recent orders ───────────────────────────────────────────
      var recentQ = Supabase.instance.client
          .from('orders')
          .select('*, restaurant_tables(table_number), order_items(*)');
      if (effectiveBranchId != null) recentQ = recentQ.eq('branch_id', effectiveBranchId);
      final recentRes = await recentQ.order('created_at', ascending: false).limit(20);

      // ── COGS dari inventory_transactions ────────────────────────
      double todayCogs = 0;
      try {
        var cogsQ = Supabase.instance.client
            .from('inventory_transactions')
            .select('quantity, unit_cost')
            .eq('transaction_type', 'usage')
            .gte('created_at', todayStart)
            .lt('created_at', tomorrowStart);
        if (effectiveBranchId != null) cogsQ = cogsQ.eq('branch_id', effectiveBranchId);
        final cogsRes = await cogsQ;
        for (final item in cogsRes as List) {
          final qty  = (item['quantity']  ?? 0) as num;
          final cost = (item['unit_cost'] ?? 0) as num;
          todayCogs += qty * cost;
        }
      } catch (e) {
        debugPrint('⚠️ Gagal fetch COGS: $e');
      }

      // ── Top Menu (Best Sellers) ────────────────────────────
      List<Map<String, dynamic>> topMenus = [];
      try {
        var topMenuQ = Supabase.instance.client
            .from('order_items')
            .select('menu_item_name, quantity, subtotal');
        // Filter by branch via join ke orders
        if (effectiveBranchId != null) {
          topMenuQ = topMenuQ.eq('orders.branch_id', effectiveBranchId);
        }
        final topMenuRes = await topMenuQ;

        // Aggregate manual: group by menu_item_name
        final Map<String, Map<String, dynamic>> agg = {};
        for (final row in topMenuRes as List) {
          final name = (row['menu_item_name'] as String?) ?? 'Unknown';
          final qty  = (row['quantity']  as num?)?.toInt()    ?? 0;
          final rev  = (row['subtotal']  as num?)?.toDouble() ?? 0;
          if (!agg.containsKey(name)) {
            agg[name] = {'name': name, 'qty': 0, 'revenue': 0.0};
          }
          agg[name]!['qty']     = (agg[name]!['qty'] as int) + qty;
          agg[name]!['revenue'] = (agg[name]!['revenue'] as double) + rev;
        }

        topMenus = agg.values.toList()
          ..sort((a, b) => (b['qty'] as int).compareTo(a['qty'] as int));
        topMenus = topMenus.take(10).toList();
      } catch (e) {
        debugPrint('⚠️ Gagal fetch top menus: $e');
      }

      // ── Margin per Menu ───────────────────────────────────
      List<Map<String, dynamic>> menuMargins = [];
      try {
        final menuService = MenuService(Supabase.instance.client);

        // Fetch semua menu items untuk branch ini
        final allMenus = await menuService.fetchMenus(
          branchId: effectiveBranchId,
        );

        if (allMenus.isNotEmpty) {
          // Fetch ingredients semua menu secara paralel
          final ingredientsList = await Future.wait(
            allMenus.map((m) => menuService.fetchIngredients(m.id)),
          );

          for (int i = 0; i < allMenus.length; i++) {
            final menu        = allMenus[i];
            final ingredients = ingredientsList[i];

            // Hitung COGS dari ingredients
            final cogs = ingredients.fold<double>(
              0,
              (sum, ing) => sum + (ing.quantity * ing.costPerUnit),
            );

            final price  = menu.price;
            final margin = price > 0 ? ((price - cogs) / price * 100) : 0.0;

            menuMargins.add({
              'name'  : menu.name,
              'price' : price,
              'cogs'  : cogs,
              'margin': margin,
            });
          }

          // Sort by margin descending
          menuMargins.sort(
            (a, b) => (b['margin'] as double).compareTo(a['margin'] as double),
          );
        }
      } catch (e) {
        debugPrint('⚠️ Gagal fetch menu margins: $e');
      }

      // ── Revenue per Cabang (superadmin only) ──────────────────
      List<Map<String, dynamic>> branchRevenue = [];
      if (_isSuperAdmin && _branches.isNotEmpty) {
        try {
          // Fetch revenue bulan ini per cabang secara paralel
          final now        = DateTime.now();
          final monthStart = DateTime(now.year, now.month, 1).toIso8601String();

          final results = await Future.wait(
            _branches.map((b) async {
              final branchId = b['id'] as String;
              final res = await Supabase.instance.client
                  .from('payments')
                  .select('amount')
                  .eq('branch_id', branchId)
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

      if (!mounted) return;

      // ── Process 7-day revenue chart ─────────────────────────────
      final Map<int, double> dayRevenue = {0:0,1:0,2:0,3:0,4:0,5:0,6:0};
      for (final p in weekRes as List) {
        final created = DateTime.parse(p['created_at']).toLocal();
        final diff = DateTime(today.year, today.month, today.day)
            .difference(DateTime(created.year, created.month, created.day))
            .inDays;
        if (diff >= 0 && diff <= 6) {
          dayRevenue[6 - diff] = (dayRevenue[6 - diff]! + ((p['amount'] ?? 0) as num).toDouble());
        }
      }
      final spots = dayRevenue.entries
          .map((e) => FlSpot(e.key.toDouble(), e.value / 1000))
          .toList();

      // ── Revenue hari ini dari payments ──────────────────────────
      final revenue = (payRes as List).fold<double>(
          0, (s, p) => s + ((p['amount'] ?? 0) as num).toDouble());

      setState(() {
        _todayOrders   = (ordRes as List).length;
        _todayRevenue  = revenue;
        _todayBookings = (bookRes as List).length;
        _todayCogs     = todayCogs;
        _revenueSpots
          ..clear()
          ..addAll(spots);
        _topMenus      = topMenus;
        _menuMargins   = menuMargins;
        _branchRevenue = branchRevenue;
        _recentOrders  = (recentRes as List).map((e) => OrderModel.fromJson(e)).toList();
        _isLoading     = false;
      });
    } catch (e, st) {
      debugPrint('ReportsScreen _load error: $e\n$st');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Reports & Analytics'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        titleTextStyle: const TextStyle(
          fontFamily: 'Poppins', fontSize: 18,
          fontWeight: FontWeight.w600, color: Colors.white),
        actions: [
          if (_isSuperAdmin)
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
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.white70))),
                  ..._branches.map((b) => DropdownMenuItem<String?>(
                    value: b['id'] as String,
                    child: Text(b['name'] as String,
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.white)))),
                ],
                onChanged: (val) {
                  setState(() => _selectedBranchId = val);
                  _load();
                },
              ),
            ),
          const SizedBox(width: 8),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // KPI row
                Row(children: [
                  _kpiCard('Order Hari Ini', '$_todayOrders',
                    Icons.receipt_long, AppColors.primary),
                  const SizedBox(width: 12),
                  _kpiCard('Revenue', 'Rp ${(_todayRevenue/1000).toStringAsFixed(0)}rb',
                    Icons.monetization_on_outlined, AppColors.available),
                  const SizedBox(width: 12),
                  _kpiCard('Booking', '$_todayBookings',
                    Icons.event_available, AppColors.reserved),
                ]),
                // ── COGS ──────────────────────────
                const SizedBox(height: 8),
                Row(children: [
                  _kpiCard('COGS Hari Ini',
                    'Rp ${(_todayCogs/1000).toStringAsFixed(0)}rb',
                    Icons.calculate_outlined, Colors.orange),
                ]),
                // ──────────────────────────────────
                const SizedBox(height: 24),
                // Revenue chart
                const Text('Revenue 7 Hari Terakhir',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 12),
                Card(child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    height: 200,
                    child: _revenueSpots.isEmpty
                        ? const Center(child: Text('Belum ada data revenue',
                            style: TextStyle(fontFamily: 'Poppins')))
                        : LineChart(LineChartData(
                            gridData: const FlGridData(show: true),
                            titlesData: FlTitlesData(
                              bottomTitles: AxisTitles(sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (v, _) {
                                  final labels = ['Sen','Sel','Rab','Kam','Jum','Sab','Min'];
                                  final idx = v.toInt();
                                  if (idx < 0 || idx >= labels.length) return const SizedBox();
                                  return Text(labels[idx],
                                    style: const TextStyle(
                                      fontFamily: 'Poppins', fontSize: 10));
                                },
                              )),
                              leftTitles: AxisTitles(sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (v, _) => Text(
                                  '${v.toInt()}rb',
                                  style: const TextStyle(
                                    fontFamily: 'Poppins', fontSize: 10)),
                                reservedSize: 40,
                              )),
                              topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                              rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                            ),
                            borderData: FlBorderData(show: false),
                            lineBarsData: [LineChartBarData(
                              spots: _revenueSpots,
                              isCurved: true,
                              color: AppColors.primary,
                              barWidth: 3,
                              belowBarData: BarAreaData(
                                show: true,
                                color: AppColors.primary.withValues(alpha: 0.15)),
                              dotData: const FlDotData(show: true),
                            )],
                          )),
                  ),
                )),
                const SizedBox(height: 24),
                // Top Menu
                _TopMenuSection(topMenus: _topMenus),
                const SizedBox(height: 24),
                // Margin per Menu
                _MenuMarginSection(menuMargins: _menuMargins),
                const SizedBox(height: 24),
                // Branch comparison (superadmin only)
                if (_isSuperAdmin)
                  _BranchRevenueSection(branchRevenue: _branchRevenue),
                if (_isSuperAdmin)
                  const SizedBox(height: 24),
                // Recent orders
                const Text('Order Terbaru',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 12),
                ..._recentOrders.map((o) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10)),
                      child: Center(child: Text(
                        o.orderNumber.split('-').last,
                        style: const TextStyle(
                          fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                          fontSize: 11, color: AppColors.primary))),
                    ),
                    title: Text(
                      o.tableNumber != null ? 'Meja ${o.tableNumber}' : 'Takeaway',
                      style: const TextStyle(
                        fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      '${o.items.length} item • ${o.status.label}',
                      style: AppTextStyles.caption),
                    trailing: Text(
                      'Rp ${o.totalAmount.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                        color: AppColors.accent)),
                  ),
                )),
              ]),
            ),
    );
  }

  Widget _kpiCard(String label, String value, IconData icon, Color color) =>
    Expanded(child: Card(child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 8),
        Text(value,
          style: TextStyle(
            fontFamily: 'Poppins', fontWeight: FontWeight.w700,
            fontSize: 18, color: color)),
        const SizedBox(height: 4),
        Text(label, style: AppTextStyles.caption),
      ]),
    )));
}

// ── Top Menu Section ──────────────────────────────────────────────────────────
class _TopMenuSection extends StatelessWidget {
  final List<Map<String, dynamic>> topMenus;
  const _TopMenuSection({required this.topMenus});

  String _fmtRev(double v) =>
      'Rp \${(v / 1000).toStringAsFixed(0)}rb';

  @override
  Widget build(BuildContext context) {
    if (topMenus.isEmpty) {
      return const SizedBox.shrink();
    }

    final maxQty = (topMenus.first['qty'] as int).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '🏆 Menu Terlaris',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              children: topMenus.asMap().entries.map((entry) {
                final rank  = entry.key + 1;
                final item  = entry.value;
                final name  = item['name'] as String;
                final qty   = item['qty'] as int;
                final rev   = item['revenue'] as double;
                final ratio = maxQty > 0 ? qty / maxQty : 0.0;

                final Color rankColor;
                if (rank == 1) {
                  rankColor = const Color(0xFFFFD700); // gold
                } else if (rank == 2) {
                  rankColor = const Color(0xFFC0C0C0); // silver
                } else if (rank == 3) {
                  rankColor = const Color(0xFFCD7F32); // bronze
                } else {
                  rankColor = AppColors.textSecondary;
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    children: [
                      // Rank number
                      SizedBox(
                        width: 28,
                        child: Text(
                          '#\$rank',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: rankColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Name + bar + revenue
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    name,
                                    style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  '\$qty terjual',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            // Progress bar
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: ratio,
                                minHeight: 6,
                                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  rank <= 3
                                      ? AppColors.primary
                                      : AppColors.primary.withValues(alpha: 0.45),
                                ),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _fmtRev(rev),
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Menu Margin Section ───────────────────────────────────────────────────────
class _MenuMarginSection extends StatelessWidget {
  final List<Map<String, dynamic>> menuMargins;
  const _MenuMarginSection({required this.menuMargins});

  @override
  Widget build(BuildContext context) {
    if (menuMargins.isEmpty) return const SizedBox.shrink();

    // Top 5 margin tertinggi & 3 terendah (warning)
    final top    = menuMargins.take(5).toList();
    final bottom = menuMargins.length > 5
        ? menuMargins.reversed.take(3).toList()
        : <Map<String, dynamic>>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '💡 Margin per Menu',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Berdasarkan harga bahan dari menu_ingredients',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 12),

        // ── Top margin card ──────────────────────────────────────
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🟢 Margin Tertinggi',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(height: 12),
                ...top.map((item) => _MarginRow(item: item)),
              ],
            ),
          ),
        ),

        // ── Bottom margin warning card ───────────────────────────
        if (bottom.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '🔴 Perlu Perhatian (Margin Rendah)',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...bottom.map((item) => _MarginRow(item: item)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _MarginRow extends StatelessWidget {
  final Map<String, dynamic> item;
  const _MarginRow({required this.item});

  String _fmtRp(double v) =>
      'Rp ${v.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';

  @override
  Widget build(BuildContext context) {
    final name   = item['name']   as String;
    final price  = item['price']  as double;
    final cogs   = item['cogs']   as double;
    final margin = item['margin'] as double;

    final Color marginColor;
    if (margin >= 50) {
      marginColor = Colors.green[700]!;
    } else if (margin >= 30) {
      marginColor = Colors.orange[700]!;
    } else {
      marginColor = Colors.red[700]!;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          // Margin badge
          Container(
            width: 54,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: marginColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${margin.toStringAsFixed(0)}%',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: marginColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Name + price vs cogs
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Jual ${_fmtRp(price)}  •  COGS ${cogs > 0 ? _fmtRp(cogs) : "belum diisi"}',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Branch Revenue Section ────────────────────────────────────────────────────
class _BranchRevenueSection extends StatelessWidget {
  final List<Map<String, dynamic>> branchRevenue;
  const _BranchRevenueSection({required this.branchRevenue});

  String _fmtRp(double v) {
    if (v >= 1000000) {
      return 'Rp ${(v / 1000000).toStringAsFixed(1)}jt';
    }
    return 'Rp ${(v / 1000).toStringAsFixed(0)}rb';
  }

  @override
  Widget build(BuildContext context) {
    if (branchRevenue.isEmpty) return const SizedBox.shrink();

    final maxRevenue = (branchRevenue.first['revenue'] as double);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '🏪 Perbandingan Cabang',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Revenue bulan ini per cabang',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: branchRevenue.asMap().entries.map((entry) {
                final rank    = entry.key;
                final item    = entry.value;
                final name    = item['name'] as String;
                final revenue = item['revenue'] as double;
                final ratio   = maxRevenue > 0 ? revenue / maxRevenue : 0.0;

                // Top cabang warna primary, sisanya lebih muted
                final barColor = rank == 0
                    ? AppColors.primary
                    : AppColors.primary.withValues(alpha: 0.45);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              if (rank == 0)
                                const Text(
                                  '👑 ',
                                  style: TextStyle(fontSize: 12),
                                ),
                              Text(
                                name,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: rank == 0
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            revenue > 0 ? _fmtRp(revenue) : 'Belum ada',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: rank == 0
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 8,
                          backgroundColor:
                              AppColors.primary.withValues(alpha: 0.08),
                          valueColor:
                              AlwaysStoppedAnimation<Color>(barColor),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}