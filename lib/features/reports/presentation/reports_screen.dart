import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../shared/models/order_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/widgets/app_drawer.dart';

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
  String? _branchId;

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
      _branchId = staff.branchId;
      _initialized = true;
      _init();
    } else {
      _initialized = true;
      ref.listenManual(currentStaffProvider, (_, next) {
        if (next != null && _branchId == null && mounted) {
          setState(() => _branchId = next.branchId);
          _init();
        }
      });
    }
  }

  Future<void> _init() async {
    await _load();
  }

  Future<void> _load() async {
    if (_branchId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    final today = DateTime.now();
    final todayStr =
        '${today.year}-${today.month.toString().padLeft(2,'0')}-${today.day.toString().padLeft(2,'0')}';

    // Today orders
    final ordRes = await Supabase.instance.client
        .from('orders')
        .select()
        .eq('branch_id', _branchId!)
        .eq('status', 'paid')
        .gte('created_at', '$todayStr 00:00:00');

    // Today bookings
    final bookRes = await Supabase.instance.client
        .from('bookings')
        .select()
        .eq('branch_id', _branchId!)
        .eq('booking_date', todayStr);

    // 7-day revenue
    final weekStart = today.subtract(const Duration(days: 6));
    final weekRes = await Supabase.instance.client
        .from('orders')
        .select()
        .eq('branch_id', _branchId!)
        .eq('status', 'paid')
        .gte('created_at', weekStart.toIso8601String());

    // Recent orders (any status, last 20)
    final recentRes = await Supabase.instance.client
        .from('orders')
        .select('*, restaurant_tables(table_number), order_items(*, menu_items(name))')
        .eq('branch_id', _branchId!)
        .order('created_at', ascending: false)
        .limit(20);
    // ── Inventory COGS hari ini ──────────────────────────────────
    double todayCogs = 0;
    try {
      final cogsRes = await Supabase.instance.client
          .from('inventory_items')
          .select('used_stock, cost_per_unit')
          .eq('branch_id', _branchId!)
          .eq('date', todayStr);
      for (final item in cogsRes as List) {
        final used = (item['used_stock'] ?? 0) as num;
        final cost = (item['cost_per_unit'] ?? 0) as num;
        todayCogs += used * cost;
      }
    } catch (e) {
      debugPrint('⚠️ Gagal fetch COGS: $e');
    }
    // ─────────────────────────────────────────────────────────────
    if (!mounted) return;

    // Process 7-day revenue chart
    final Map<int, double> dayRevenue = {0:0,1:0,2:0,3:0,4:0,5:0,6:0};
    for (final o in weekRes as List) {
      final created = DateTime.parse(o['created_at']);
      final diff = today.difference(created).inDays;
      if (diff >= 0 && diff <= 6) {
        dayRevenue[6 - diff] = (dayRevenue[6 - diff]! + (o['total_amount'] ?? 0));
      }
    }
    final spots = dayRevenue.entries
        .map((e) => FlSpot(e.key.toDouble(), e.value / 1000))
        .toList();

    final todayPaidOrders = (ordRes as List);
    final revenue = todayPaidOrders.fold<double>(0, (s, o) => s + (o['total_amount'] ?? 0));

    setState(() {
      _todayOrders   = todayPaidOrders.length;
      _todayRevenue  = revenue;
      _todayBookings = (bookRes as List).length;
      _todayCogs     = todayCogs; // ← tambah ini
      _revenueSpots
        ..clear()
        ..addAll(spots);
      _recentOrders  = (recentRes as List).map((e) => OrderModel.fromJson(e)).toList();
      _isLoading     = false;
    });
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
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
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