import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/models/order_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/widgets/app_drawer.dart';
import '../../../core/models/staff_role.dart';

class KDSScreen extends ConsumerStatefulWidget {
  const KDSScreen({super.key});
  @override
  ConsumerState<KDSScreen> createState() => _KDSScreenState();
}

class _KDSScreenState extends ConsumerState<KDSScreen> {
  List<OrderModel> _orders = [];
  int _readyCount = 0;
  bool _isLoading = true;
  String? _branchId;       // branch milik staff yang login
  StaffRole? _userRole;
  RealtimeChannel? _channel;
  bool _initialized = false;

  // Multi-branch (superadmin & manager only)
  List<_BranchItem> _branches = [];
  String? _selectedBranchId; // null = semua branch

  bool get _isMultiBranchRole =>
      _userRole == StaffRole.superadmin || _userRole == StaffRole.manager;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    final staff = ref.read(currentStaffProvider);
    if (staff != null) {
      _branchId = staff.branchId;
      _userRole = staff.role;
      _initialized = true;
      if (_isMultiBranchRole) _fetchBranches();
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
          if (_isMultiBranchRole) _fetchBranches();
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
    // superadmin/manager: pakai _selectedBranchId (null = semua branch)
    // role lain: wajib pakai _branchId sendiri
    final targetBranch = _isMultiBranchRole ? _selectedBranchId : _branchId;

    if (!_isMultiBranchRole && targetBranch == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      var query = Supabase.instance.client
          .from('orders')
          .select('''
            *,
            restaurant_tables(table_number),
            order_items(
              id, menu_item_id, menu_item_name, unit_price,
              quantity, subtotal, special_requests, status
            )
          ''')
          .inFilter('status', ['new', 'created', 'preparing']);

      if (targetBranch != null) {
        query = query.eq('branch_id', targetBranch);
      }

      final res = await query.order('created_at');

      var readyQuery = Supabase.instance.client
          .from('orders')
          .select('id')
          .eq('status', 'ready');

      if (targetBranch != null) {
        readyQuery = readyQuery.eq('branch_id', targetBranch);
      }

      final readyRes = await readyQuery;

      if (mounted) {
        setState(() {
          _orders = (res as List).map((e) => OrderModel.fromJson(e)).toList();
          _readyCount = (readyRes as List).length;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('KDS load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _subscribeRealtime() {
    _channel?.unsubscribe();
    _channel = Supabase.instance.client
        .channel('kds_realtime_${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (_) => _load(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'order_items',
          callback: (_) => _load(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  // ── FIX: Tambah sent_to_kitchen_at saat dapur mulai masak ─────────────────
  Future<void> _markPreparing(String orderId) async {
    final now = DateTime.now().toIso8601String();

    // Update status order + catat waktu mulai masak
    await Supabase.instance.client.from('orders').update({
      'status':     'preparing',
      'updated_at': now,
    }).eq('id', orderId);

    // Catat sent_to_kitchen_at di semua order_items milik order ini
    // Ini adalah titik awal pengukuran actual_prep_time untuk training data ML
    await Supabase.instance.client.from('order_items').update({
      'sent_to_kitchen_at': now,
    }).eq('order_id', orderId);
  }

  Future<void> _markReady(String orderId) async {
    final now = DateTime.now().toIso8601String();

    await Supabase.instance.client.from('orders').update({
      'status':     'ready',
      'updated_at': now,
    }).eq('id', orderId);

    // prepared_at sudah ada sebelumnya, tetap diisi
    await Supabase.instance.client.from('order_items').update({
      'status':      'ready',
      'prepared_at': now,
    }).eq('order_id', orderId);
  }

  bool _isNewOrder(OrderModel order) =>
      order.status == OrderStatus.new_ || order.status == OrderStatus.created;

  bool _isQrOrder(OrderModel order) => order.orderType == 'qr_order';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      drawer: const AppDrawer(),
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Row(children: [
          Container(
            width: 10, height: 10,
            decoration: BoxDecoration(
              color: _orders.isNotEmpty ? const Color(0xFF4CAF50) : Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text('Dapur (KDS)',
            style: theme.textTheme.titleLarge?.copyWith(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            )),
        ]),
        actions: [
          if (_readyCount > 0)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.shade600,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.room_service_outlined, size: 13, color: Colors.white),
                const SizedBox(width: 4),
                Text('$_readyCount Siap Antar',
                  style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  )),
              ]),
            ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: _orders.isEmpty ? colorScheme.surfaceContainerHighest : AppColors.accent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text('${_orders.length} Aktif',
              style: TextStyle(
                fontFamily: 'Poppins', fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _orders.isEmpty ? colorScheme.outline : Colors.white,
              )),
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: colorScheme.onSurface),
            onPressed: _load),
        ],
      ),
      body: Row(children: [
        // ── Sidebar branch (superadmin & manager only) ──────────────
        if (_isMultiBranchRole)
          _KDSBranchSidebar(
            branches: _branches,
            selectedBranchId: _selectedBranchId,
            onSelect: (id) {
              setState(() {
                _selectedBranchId = id;
                _isLoading = true;
              });
              _load();
            },
          ),
        // ── Main content ────────────────────────────────────────────
        Expanded(
          child: Column(children: [
            if (_readyCount > 0) _buildReadyBanner(colorScheme),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _orders.isEmpty
                      ? _buildEmptyState(colorScheme)
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: GridView.builder(
                            padding: const EdgeInsets.all(16),
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 340,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                              childAspectRatio: 0.70,
                            ),
                            itemCount: _orders.length,
                            itemBuilder: (_, i) => _buildKDSCard(_orders[i], colorScheme),
                          ),
                        ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildReadyBanner(ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.green.shade600,
      child: Row(children: [
        const Icon(Icons.room_service_outlined, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '$_readyCount order siap diantar — waiter, cek Order Screen!',
            style: const TextStyle(
              fontFamily: 'Poppins', color: Colors.white,
              fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
      ]),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              color: Colors.green.shade50, shape: BoxShape.circle),
            child: Icon(Icons.check_circle_outline,
              size: 60, color: Colors.green.shade400),
          ),
          const SizedBox(height: 20),
          Text('Semua order selesai! 🎉',
            style: TextStyle(
              fontFamily: 'Poppins', fontSize: 20,
              fontWeight: FontWeight.w700, color: colorScheme.onSurface)),
          const SizedBox(height: 8),
          Text('Menunggu order baru...',
            style: TextStyle(fontFamily: 'Poppins', color: colorScheme.outline)),
        ],
      ),
    );
  }

  Widget _buildKDSCard(OrderModel order, ColorScheme colorScheme) {
    final isNew = _isNewOrder(order);
    final isQr = _isQrOrder(order);

    final Color statusColor = isNew
        ? (isQr ? const Color(0xFF7C3AED) : AppColors.orderNew)
        : AppColors.orderPreparing;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(children: [
        // ── Header ───────────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.10),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
          ),
          child: Row(children: [
            Container(width: 8, height: 8,
              decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(
              child: Text('# ${order.orderNumber}',
                style: TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                  fontSize: 15, color: colorScheme.onSurface))),
            if (order.tableNumber != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8)),
                child: Text('Meja ${order.tableNumber}',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onPrimaryContainer))),
          ]),
        ),

        // ── Sub-header ───────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            border: Border(
              bottom: BorderSide(color: colorScheme.outlineVariant, width: 0.5)),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: isQr
                    ? const Color(0xFF7C3AED).withValues(alpha: 0.10)
                    : AppColors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isQr
                      ? const Color(0xFF7C3AED).withValues(alpha: 0.4)
                      : AppColors.primary.withValues(alpha: 0.4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                  isQr ? Icons.qr_code_scanner : Icons.person_outline,
                  size: 11,
                  color: isQr ? const Color(0xFF7C3AED) : AppColors.primary),
                const SizedBox(width: 4),
                Text(
                  isQr ? 'QR Order' : 'Staff Order',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isQr ? const Color(0xFF7C3AED) : AppColors.primary)),
              ]),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: statusColor.withValues(alpha: 0.35))),
              child: Text(
                isNew ? 'Menunggu Masak' : 'Dimasak',
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 10,
                  fontWeight: FontWeight.w700, color: statusColor)),
            ),
          ]),
        ),

        // ── Items list ────────────────────────────────────────────────────────
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            children: order.items.map((item) {
              final notes = item.specialRequests;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colorScheme.outlineVariant, width: 0.8)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8)),
                    child: Center(child: Text('${item.quantity}',
                      style: TextStyle(
                        fontFamily: 'Poppins', fontWeight: FontWeight.w800,
                        color: statusColor, fontSize: 14)))),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.menuItemName,
                        style: TextStyle(
                          fontFamily: 'Poppins', fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface, fontSize: 13)),
                      if (notes != null && notes.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.amber.shade200)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.edit_note,
                                  size: 13, color: Colors.amber.shade700),
                                const SizedBox(width: 4),
                                Flexible(child: Text(notes,
                                  style: TextStyle(
                                    fontFamily: 'Poppins', fontSize: 11,
                                    color: Colors.amber.shade800,
                                    fontWeight: FontWeight.w500))),
                              ]),
                          )),
                    ])),
                ]),
              );
            }).toList(),
          ),
        ),

        // ── Action button ─────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: SizedBox(
            width: double.infinity, height: 44,
            child: isNew
                ? ElevatedButton.icon(
                    onPressed: () => _markPreparing(order.id),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.orderPreparing,
                      foregroundColor: Colors.white, elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                    icon: const Icon(Icons.local_fire_department_outlined, size: 16),
                    label: const Text('Mulai Masak',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600, fontSize: 13)))
                : ElevatedButton.icon(
                    onPressed: () => _markReady(order.id),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white, elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text('✓ Siap Saji',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700, fontSize: 13))),
          ),
        ),
      ]),
    );
  }
}

// ── Helper model ───────────────────────────────────────────────────────
class _BranchItem {
  final String id;
  final String name;
  _BranchItem({required this.id, required this.name});
}

// ── KDS Branch Sidebar ─────────────────────────────────────────────────
class _KDSBranchSidebar extends StatelessWidget {
  final List<_BranchItem> branches;
  final String? selectedBranchId;
  final void Function(String?) onSelect;

  const _KDSBranchSidebar({
    required this.branches,
    required this.selectedBranchId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 90,
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
              itemBuilder: (ctx, i) => _SidebarItem(
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.15)
              : Colors.transparent,
          border: isSelected
              ? const Border(left: BorderSide(color: Colors.white, width: 3))
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