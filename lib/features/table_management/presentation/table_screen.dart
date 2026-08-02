import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/models/table_model.dart';
import '../../../core/models/staff_role.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/auth/providers/auth_provider.dart';
import 'widgets/table_card.dart';
import 'widgets/add_table_dialog.dart';
import '../../../shared/widgets/app_drawer.dart';

class TableScreen extends ConsumerStatefulWidget {
  const TableScreen({super.key});
  @override
  ConsumerState<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends ConsumerState<TableScreen> {
  List<TableModel> _tables = [];
  // table_id → time the food was served (most recent active order at that table).
  // Used by TableCard to compute the 2-hour dine-in limit & overtime charge.
  Map<String, DateTime?> _servedAtByTable = {};
  bool _isLoading = true;
  String? _branchId;
  RealtimeChannel? _channel;
  TableStatus? _filterStatus;

  // Multi-branch (superadmin only)
  List<_BranchItem> _branches = [];
  String? _selectedBranchId; // null = all branches
  StaffRole? _userRole;

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
      _userRole = staff.role;
      _initialized = true;
      if (staff.role == StaffRole.superadmin) {
        _fetchBranches();
      }
      _load();
      _subscribeRealtime();
    } else {
      _initialized = true;
      ref.listenManual(currentStaffProvider, (_, next) {
        if (next != null && _branchId == null && mounted) {
          setState(() {
            _branchId = next.branchId;
            _userRole = next.role;
          });
          if (next.role == StaffRole.superadmin) {
            _fetchBranches();
          }
          _load();
          _subscribeRealtime();
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

  Future<void> _load() async {
    // superadmin: uses _selectedBranchId (can be null = all branches)
    // other roles: must use their own _branchId
    final isSuperadmin = _userRole == StaffRole.superadmin;
    final targetBranch = isSuperadmin ? _selectedBranchId : _branchId;

    if (!isSuperadmin && targetBranch == null) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      var query = Supabase.instance.client
          .from('restaurant_tables')
          .select();

      if (targetBranch != null) {
        query = query.eq('branch_id', targetBranch);
      }

      final res = await query.order('table_number');
      final tables = (res as List).map((e) => TableModel.fromJson(e)).toList();
      final servedAtByTable = await _loadServedAtByTable(targetBranch);
      if (mounted) {
        setState(() {
          _tables = tables;
          _servedAtByTable = servedAtByTable;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Fetch served_at from each table's active order ────────────────────
  // Used to compute the 2-hour dine-in limit from when the food was served.
  Future<Map<String, DateTime?>> _loadServedAtByTable(String? targetBranch) async {
    try {
      var query = Supabase.instance.client
          .from('orders')
          .select('table_id, served_at, created_at')
          .not('table_id', 'is', null)
          .inFilter('status', ['new', 'created', 'preparing', 'ready', 'served']);
      if (targetBranch != null) {
        query = query.eq('branch_id', targetBranch);
      }
      final res = await query.order('created_at', ascending: false);
      final map = <String, DateTime?>{};
      for (final row in (res as List)) {
        final tableId = row['table_id'] as String?;
        if (tableId == null || map.containsKey(tableId)) continue;
        final servedAtRaw = row['served_at'] as String?;
        map[tableId] = servedAtRaw != null ? DateTime.tryParse(servedAtRaw) : null;
      }
      return map;
    } catch (e) {
      return {};
    }
  }

  void _subscribeRealtime() {
    if (_branchId == null) return;
    _channel = Supabase.instance.client
        .channel('tables_channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'restaurant_tables',
          callback: (_) => _load(),
        )
        // Order status changes (e.g. → served) also need to trigger a reload,
        // so the dine-in time limit badge in TableCard updates too.
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (_) => _load(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _updateStatus(String id, TableStatus status) async {
    await Supabase.instance.client.from('restaurant_tables').update(
      {'status': status.name, 'updated_at': DateTime.now().toIso8601String()},
    ).eq('id', id);
  }

  // ── Seed data: create sample tables if empty ──────────────────
  Future<void> _seedTables() async {
    if (_branchId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('❌ Branch ID not found. Try logging out & back in.'),
          backgroundColor: Colors.red,
        ));
      }
      return;
    }
    final seeds = [
      {'table_number': 'A1', 'capacity': 2, 'shape': 'round',     'floor_level': 1},
      {'table_number': 'A2', 'capacity': 2, 'shape': 'round',     'floor_level': 1},
      {'table_number': 'B1', 'capacity': 4, 'shape': 'square',    'floor_level': 1},
      {'table_number': 'B2', 'capacity': 4, 'shape': 'square',    'floor_level': 1},
      {'table_number': 'B3', 'capacity': 4, 'shape': 'square',    'floor_level': 1},
      {'table_number': 'C1', 'capacity': 6, 'shape': 'rectangle', 'floor_level': 1},
      {'table_number': 'C2', 'capacity': 6, 'shape': 'rectangle', 'floor_level': 1},
      {'table_number': 'VIP1', 'capacity': 8, 'shape': 'rectangle', 'floor_level': 2},
    ];
    try {
      for (final s in seeds) {
        await Supabase.instance.client.from('restaurant_tables').insert({
          ...s,
          'branch_id': _branchId,
          'status': 'available',
          'is_mergeable': true,
          'position_x': 0,
          'position_y': 0,
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ 8 sample tables added successfully!'),
          backgroundColor: Color(0xFF4CAF50),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ Failed: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 8),
        ));
      }
    }
    await _load();
  }

  List<TableModel> get _filtered => _filterStatus == null
      ? _tables
      : _tables.where((t) => t.status == _filterStatus).toList();

  Map<TableStatus, int> get _counts => {
    for (final s in TableStatus.values)
      s: _tables.where((t) => t.status == s).length,
  };

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
          fontFamily: 'Poppins', fontSize: 18,
          fontWeight: FontWeight.w600, color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Table Management'),
            if (staff != null)
              Text(
                staff.fullName,
                style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 11,
                  color: Colors.white60, fontWeight: FontWeight.normal),
              ),
          ],
        ),
        actions: [
          // ── STAFF VIEW BADGE ─────────────────────────
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
                  fontFamily: 'Poppins', fontSize: 11,
                  fontWeight: FontWeight.w700, color: Color(0xFF4CAF50)),
              ),
            ),
          // ── BRANCH FILTER DROPDOWN (superadmin only) ──
          if (_userRole == StaffRole.superadmin)
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
                    child: Text('All Branches',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.white70))),
                  ..._branches.map((b) => DropdownMenuItem<String?>(
                    value: b.id,
                    child: Text(b.name,
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.white)))),
                ],
                onChanged: (val) {
                  setState(() {
                    _selectedBranchId = val;
                    _isLoading = true;
                  });
                  _load();
                },
              ),
            ),
          const SizedBox(width: 4),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          // Store the messenger before the async gap
          final messenger = ScaffoldMessenger.of(context);

          final result = await showDialog<Map<String, dynamic>>(
            context: context,
            builder: (_) => const AddTableDialog(),
          );
          if (result == null || !mounted) return;

          // Superadmin: use the branch selected in the sidebar,
          // fallback to their own branch if "All" is selected
          final targetBranch = (_userRole == StaffRole.superadmin)
              ? (_selectedBranchId ?? _branchId)
              : _branchId;

          if (targetBranch == null) {
            messenger.showSnackBar(const SnackBar(
              content: Text('❌ Select a branch in the sidebar first'),
              backgroundColor: Colors.red,
            ));
            return;
          }

          try {
            await Supabase.instance.client.from('restaurant_tables').insert({
              'branch_id': targetBranch,
              'table_number': result['number'],
              'capacity': result['capacity'],
              'shape': result['shape'],
              'status': 'available',
              'position_x': 0,
              'position_y': 0,
            });
            if (mounted) {
              messenger.showSnackBar(SnackBar(
                content: Text('✅ Table ${result["number"]} added successfully'),
                backgroundColor: const Color(0xFF4CAF50),
              ));
            }
          } on PostgrestException catch (e) {
            if (!mounted) return;
            final isDuplicate = e.code == '23505';
            messenger.showSnackBar(SnackBar(
              content: Text(isDuplicate
                ? '❌ Table "${result["number"]}" already exists in this branch'
                : '❌ Failed to add table: ${e.message}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ));
          }
        },
        backgroundColor: AppColors.accent,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Table',
          style: TextStyle(
            color: Colors.white, fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildSummaryBar(),
                _buildFilterChips(),
                Expanded(
                  child: _filtered.isEmpty && _tables.isEmpty
                      ? _buildEmptyState()
                      : _filtered.isEmpty
                          ? _buildNoFilterResult()
                          : GridView.builder(
                              padding: const EdgeInsets.all(16),
                              gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 200,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: 0.85,
                                ),
                              itemCount: _filtered.length,
                              itemBuilder: (ctx, i) => TableCard(
                                table: _filtered[i],
                                servedAt: _servedAtByTable[_filtered[i].id],
                                onStatusChange: (s) =>
                                  _updateStatus(_filtered[i].id, s),
                              ),
                            ),
                ),
              ],
            ),
    );
  }

  Widget _buildSummaryBar() {
    final counts = _counts;
    return Container(
      color: AppColors.primary,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: TableStatus.values.map((s) => Expanded(
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: s.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: s.color.withValues(alpha: 0.4)),
            ),
            child: Column(children: [
              Text('${counts[s] ?? 0}',
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 20,
                  fontWeight: FontWeight.w700, color: s.color)),
              Text(s.label,
                style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 10, color: Colors.white70)),
            ]),
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildFilterChips() {
    return Container(
      height: 50,
      color: AppColors.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _filterChip(null, 'All'),
            ...TableStatus.values.map((s) => _filterChip(s, s.label)),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(TableStatus? status, String label) {
    final selected = _filterStatus == status;
    final color = status?.color ?? AppColors.primary;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _filterStatus = status),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? color : AppColors.border),
          ),
          child: Text(label,
            style: TextStyle(
              fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w500,
              color: selected ? Colors.white : AppColors.textSecondary)),
        ),
      ),
    );
  }

  // ── Empty state: database is empty, offer seed data ─────────
  Widget _buildEmptyState() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.table_restaurant_outlined, size: 72,
        color: AppColors.textHint),
      const SizedBox(height: 16),
      const Text('No tables yet',
        style: TextStyle(
          fontFamily: 'Poppins', fontWeight: FontWeight.w700,
          fontSize: 20, color: AppColors.textSecondary)),
      const SizedBox(height: 8),
      const Text('Add tables one by one, or\nload sample data for a quick setup',
        textAlign: TextAlign.center,
        style: TextStyle(fontFamily: 'Poppins', color: AppColors.textHint)),
      const SizedBox(height: 28),
      // ── Seed button ──────────────────────────────────
      OutlinedButton.icon(
        onPressed: () => showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Load Sample Data?',
              style: TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
            content: const Text(
              'This will add 8 sample tables (A1, A2, B1-B3, C1-C2, VIP1) '
              'to the database. Good for first-time setup.',
              style: TextStyle(fontFamily: 'Poppins')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _seedTables();
                },
                child: const Text('Yes, Load Data')),
            ],
          ),
        ),
        icon: const Icon(Icons.auto_fix_high),
        label: const Text('Load 8 Sample Tables',
          style: TextStyle(
            fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
      ),
      const SizedBox(height: 12),
      const Text('or use the "+ Add Table" button below',
        style: TextStyle(
          fontFamily: 'Poppins', fontSize: 12, color: AppColors.textHint)),
    ]),
  );

  Widget _buildNoFilterResult() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.filter_list_off, size: 48, color: AppColors.textHint),
      const SizedBox(height: 12),
      Text('No tables with status "${_filterStatus?.label}"',
        style: const TextStyle(
          fontFamily: 'Poppins', color: AppColors.textSecondary)),
    ]),
  );
}

// ── Helper model ───────────────────────────────────────────────────────
class _BranchItem {
  final String id;
  final String name;
  _BranchItem({required this.id, required this.name});
}