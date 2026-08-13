import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/models/table_model.dart';
import '../../../shared/models/order_model.dart' show calculateOvertimeCharge;
import '../../../core/models/staff_role.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/widgets/staff_shell.dart';
import '../../../shared/widgets/diamond_pattern_painter.dart';
import 'widgets/table_card.dart' show showTableDetailSheet;
import 'widgets/add_table_dialog.dart';

class TableScreen extends ConsumerStatefulWidget {
  const TableScreen({super.key});
  @override
  ConsumerState<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends ConsumerState<TableScreen> {
  List<TableModel> _tables = [];
  // table_id → time the food was served (most recent active order at that table).
  // Used by _FloorTableTile to compute the 2-hour dine-in limit & overtime charge.
  Map<String, DateTime?> _servedAtByTable = {};
  bool _isLoading = true;
  String? _branchId;
  RealtimeChannel? _channel;
  TableStatus? _filterStatus;
  String? _selectedTableId;

  // Multi-branch (superadmin only)
  List<_BranchItem> _branches = [];
  String? _selectedBranchId; // null = all branches
  StaffRole? _userRole;

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
        // so the dine-in time limit badge in _FloorTableTile updates too.
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
    await Supabase.instance.client.from('restaurant_tables').update({
      'status': status.name,
      'updated_at': DateTime.now().toIso8601String(),
      // Clear any customer-reported mismatch — staff just acted on this
      // table's status, so whatever prompted the report no longer applies.
      'customer_reported_at': null,
    }).eq('id', id);
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

  void _openTable(TableModel table, {required bool wide}) {
    setState(() => _selectedTableId = table.id);
    showTableDetailSheet(
      context,
      table,
      (s) => _updateStatus(table.id, s),
      anchorRight: wide,
    ).then((_) {
      if (mounted) setState(() => _selectedTableId = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= kStaffShellSidebarBreakpoint;

    return StaffShell(
      pageTitle: 'Floor Plan',
      activeRoute: AppRoutes.tables,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _handleAddTable(),
        backgroundColor: AppColors.accent,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Table',
          style: TextStyle(
            color: Colors.white, fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
      ),
      topBarActions: [
        if (_userRole == StaffRole.superadmin)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _selectedBranchId,
                isDense: true,
                icon: const Icon(Icons.keyboard_arrow_down, size: 16, color: AppColors.textSecondary),
                style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 12, color: AppColors.textPrimary),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All Branches',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 12))),
                  ..._branches.map((b) => DropdownMenuItem<String?>(
                    value: b.id,
                    child: Text(b.name,
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 12)))),
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
          ),
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
          onPressed: _load,
        ),
        const SizedBox(width: 4),
      ],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildFloorPlanArea(isWide: isWide),
    );
  }

  Future<void> _handleAddTable() async {
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
  }

  // ── Floor plan area: legend + canvas ────────────────────────────────────
  Widget _buildFloorPlanArea({required bool isWide}) {
    return Column(
      children: [
        _buildLegendBar(),
        Expanded(
          child: _tables.isEmpty
              ? _buildEmptyState()
              : _filtered.isEmpty
                  ? _buildNoFilterResult()
                  : _buildCanvas(isWide: isWide),
        ),
      ],
    );
  }

  Widget _buildLegendBar() {
    final counts = _counts;
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _legendChip(null, 'All', AppColors.primary, _tables.length),
            ...TableStatus.values.map(
              (s) => _legendChip(s, s.label, s.color, counts[s] ?? 0)),
          ],
        ),
      ),
    );
  }

  Widget _legendChip(TableStatus? status, String label, Color color, int count) {
    final selected = _filterStatus == status;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: () => setState(() => _filterStatus = status),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? color : AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12, height: 12,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
              ),
              const SizedBox(width: 6),
              Text(label,
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600,
                  color: selected ? color : AppColors.textPrimary)),
              const SizedBox(width: 4),
              Text('($count)',
                style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 11, color: AppColors.textHint)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCanvas({required bool isWide}) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: DiamondPatternPainter())),
          Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 28,
                runSpacing: 28,
                children: _filtered.map((table) => _FloorTableTile(
                  table: table,
                  servedAt: _servedAtByTable[table.id],
                  selected: _selectedTableId == table.id,
                  onTap: () => _openTable(table, wide: isWide),
                )).toList(),
              ),
            ),
          ),
        ],
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
          builder: (dialogCtx) => AlertDialog(
            title: const Text('Load Sample Data?',
              style: TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
            content: const Text(
              'This will add 8 sample tables (A1, A2, B1-B3, C1-C2, VIP1) '
              'to the database. Good for first-time setup.',
              style: TextStyle(fontFamily: 'Poppins')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(dialogCtx);
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

// ── Floor-plan table tile: colored/shaped by status, positioned via Wrap. ──
class _FloorTableTile extends StatefulWidget {
  final TableModel table;
  final DateTime? servedAt;
  final bool selected;
  final VoidCallback onTap;

  const _FloorTableTile({
    required this.table,
    required this.servedAt,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_FloorTableTile> createState() => _FloorTableTileState();
}

class _FloorTableTileState extends State<_FloorTableTile> {
  Timer? _timer;
  int _minutesSinceServed = 0;
  int _overtimeCharge = 0;

  @override
  void initState() {
    super.initState();
    _updateTimer();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) setState(_updateTimer);
    });
  }

  void _updateTimer() {
    if (widget.table.status == TableStatus.occupied && widget.servedAt != null) {
      final diff = DateTime.now().difference(widget.servedAt!);
      _minutesSinceServed = diff.inMinutes;
      _overtimeCharge = calculateOvertimeCharge(widget.servedAt);
    } else {
      _minutesSinceServed = 0;
      _overtimeCharge = 0;
    }
  }

  @override
  void didUpdateWidget(_FloorTableTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.table.status != widget.table.status ||
        oldWidget.servedAt != widget.servedAt) {
      setState(_updateTimer);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final table = widget.table;
    final color = table.status.color;
    final isRound = table.shape == TableShape.round;
    final size = switch (table.shape) {
      TableShape.round => const Size(84, 84),
      TableShape.square => const Size(96, 96),
      TableShape.rectangle => const Size(126, 78),
    };

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: size.width,
        height: size.height,
        decoration: BoxDecoration(
          color: color,
          shape: isRound ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: isRound ? null : BorderRadius.circular(14),
          border: Border.all(
            color: widget.selected ? AppColors.textPrimary : Colors.white,
            width: widget.selected ? 3 : 2,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 4)),
          ],
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(table.tableNumber,
                    style: const TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w800,
                      fontSize: 16, color: Colors.white)),
                  const SizedBox(height: 3),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.person_rounded, size: 11, color: Colors.white70),
                    const SizedBox(width: 2),
                    Text('${table.capacity}',
                      style: const TextStyle(
                        fontFamily: 'Poppins', fontSize: 11, color: Colors.white70)),
                  ]),
                  if (table.status == TableStatus.occupied && widget.servedAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        _overtimeCharge > 0
                            ? 'Overtime'
                            : (_minutesSinceServed >= 60
                                ? '${(_minutesSinceServed / 60).toStringAsFixed(0)}h ${_minutesSinceServed % 60}m'
                                : '${_minutesSinceServed}m'),
                        style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 9, fontWeight: FontWeight.w700,
                          color: _overtimeCharge > 0 ? Colors.yellowAccent : Colors.white)),
                    ),
                  if (table.status == TableStatus.cleaning)
                    const Padding(
                      padding: EdgeInsets.only(top: 3),
                      child: Icon(Icons.cleaning_services_rounded, size: 14, color: Colors.white),
                    ),
                ],
              ),
            ),
            if (table.customerReportedAt != null)
              Positioned(
                top: 4, left: 4,
                child: Tooltip(
                  message: 'A customer flagged this table from the QR screen',
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade700,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                    child: const Icon(Icons.flag_rounded, size: 9, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

