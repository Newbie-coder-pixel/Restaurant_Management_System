import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'dart:async';
import '../providers/qr_cart_provider.dart';
import '../data/qr_order_repository.dart';
import '../models/qr_order_model.dart';
import '../services/qr_device_id_service.dart';
import '../../../shared/models/table_model.dart';
import '../../../shared/utils/branch_hours.dart';
import '../../../core/theme/app_theme.dart';

final _menuDataProvider = FutureProvider.family<List<Map<String, dynamic>>, String>(
  (ref, branchId) async => ref.read(qrOrderRepositoryProvider).fetchMenuByBranch(branchId),
);

final _tableInfoProvider = FutureProvider.family<Map<String, dynamic>?, String>(
  (ref, tableId) async => ref.read(qrOrderRepositoryProvider).fetchTableInfo(tableId),
);

// Gates entry on the `t=` query param matching today's server-computed
// token for this table — see validate_qr_token() in
// supabase/migrations/20260814020000_table_qr_rotation.sql. This is what
// actually makes a table's QR code stop working the day after it was
// printed/scanned (or immediately, if staff regenerates it early).
final _qrTokenValidProvider =
    FutureProvider.family<bool, ({String tableId, String? token})>(
  (ref, args) async => ref
      .read(qrOrderRepositoryProvider)
      .validateQrToken(args.tableId, args.token),
);

// Prevents disconnected duplicate orders: if this table already has an
// active (unpaid, uncancelled) order, a fresh QR scan should offer to join
// it rather than silently starting an unrelated second order.
final _activeOrderForTableProvider = FutureProvider.family<QrOrderModel?, String>(
  (ref, tableId) async => ref.read(qrOrderRepositoryProvider).fetchActiveOrderForTable(tableId),
);

final _selectedCategoryProvider = StateProvider<String?>((ref) => null);
final _searchQueryProvider = StateProvider<String>((ref) => '');

// Ticks every 30s so a menu screen left open across the branch's closing
// time re-evaluates isBranchOpen() without needing a network refetch or a
// user action — otherwise a customer who opened the menu while open could
// keep browsing/ordering indefinitely on that same session after close.
final _clockTickProvider = StreamProvider<int>((ref) {
  return Stream<int>.periodic(const Duration(seconds: 30), (i) => i);
});

class QrMenuScreen extends ConsumerStatefulWidget {
  final String tableId;
  final String? qrToken;
  const QrMenuScreen({super.key, required this.tableId, this.qrToken});

  @override
  ConsumerState<QrMenuScreen> createState() => _QrMenuScreenState();
}

class _QrMenuScreenState extends ConsumerState<QrMenuScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _fabAnimCtrl;
  final _searchCtrl = TextEditingController();
  bool _activeOrderPromptShown = false;

  @override
  void initState() {
    super.initState();
    _fabAnimCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
  }

  @override
  void dispose() {
    _fabAnimCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<MenuItem> _parseItems(List<Map<String, dynamic>> rows) {
    return rows.map((row) {
      final cat = row['menu_categories'] as Map<String, dynamic>?;
      return MenuItem(
        id: row['id'] as String,
        name: row['name'] as String,
        description: row['description'] as String? ?? '',
        price: (row['price'] as num).toDouble(),
        categoryId: row['category_id'] as String? ?? '',
        categoryName: cat?['name'] as String? ?? 'Other',
        imageUrl: row['image_url'] as String?,
        isAvailable: row['is_available'] as bool? ?? true,
        sortOrder: row['sort_order'] as int? ?? 0,
        preparationTimeMinutes: row['preparation_time_minutes'] as int? ?? 15,
        allergens: List<String>.from(row['allergens'] as List? ?? []),
        dietaryTags: List<String>.from(row['dietary_tags'] as List? ?? []),
      );
    }).toList();
  }

  Map<String, List<MenuItem>> _groupByCategory(List<MenuItem> items) {
    final map = <String, List<MenuItem>>{};
    for (final item in items) {
      map.putIfAbsent(item.categoryName, () => []).add(item);
    }
    return map;
  }

  void _joinActiveOrder(QrOrderModel order) {
    ref.read(addOrderModeProvider.notifier).state = AddOrderModeState(
      orderId: order.id,
      // Staff-created dine-in orders never get a queue_number (that column
      // is QR-flow-only) — fall back to order_number so a staff order can
      // still be joined/displayed with a real identifier instead of null.
      queueNumber: order.queueNumber ?? order.orderNumber,
      tableId: order.tableId,
    );
    ref.read(activeQrCartNotifierProvider).clearCart();
  }

  // Only the device that created the table's active order may add items to
  // it or start a fresh one — every other device scanning the same QR is
  // forced to finish/pay on the original device, and can only check status
  // from here. See supabase/migrations/20260803010000_qr_order_device_id.sql.
  Future<void> _showActiveOrderDialog(QrOrderModel order) async {
    if (!mounted) return;
    final deviceId = await QrDeviceIdService.getDeviceId();
    if (!mounted) return;

    // An order with no device_id recorded at all (placed before the
    // device-lock feature shipped) has no owner to defer to, so this device
    // is treated as the owner and claims it for real in the background —
    // otherwise the customer who placed it would be permanently locked out.
    final orderHasNoOwner = order.deviceId == null || order.deviceId!.isEmpty;
    final isOwner = orderHasNoOwner || order.deviceId == deviceId;
    if (orderHasNoOwner) {
      ref.read(qrOrderRepositoryProvider).claimOrderIfUnowned(order.id, deviceId);
    }
    final itemCount = order.items.fold<int>(0, (s, i) => s + i.quantity);
    // Staff-created dine-in orders never get a queue_number — fall back to
    // order_number everywhere it's shown/passed on from here.
    final displayQueue = order.queueNumber ?? order.orderNumber;

    void goToStatus(BuildContext ctx) {
      Navigator.pop(ctx);
      context.go('/qr/${widget.tableId}/track/${order.id}?queue=$displayQueue');
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            isOwner ? 'You have an order in progress' : 'This table already has an order',
            style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700),
          ),
          content: Text(
            isOwner
                ? 'Order #$displayQueue ($itemCount item${itemCount == 1 ? '' : 's'}) is '
                    'already open at this table. Add more items to it or check its status.'
                : 'Order #$displayQueue is already open at this table on another '
                    'device or browser. Please finish and complete payment there first — '
                    'this device can only check its status until then.',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
          ),
          actionsOverflowDirection: VerticalDirection.down,
          actions: isOwner
              ? [
                  OutlinedButton(
                    onPressed: () => goToStatus(ctx),
                    child: const Text('View order status',
                        style: TextStyle(fontFamily: 'Poppins')),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _joinActiveOrder(order);
                    },
                    child: Text('Add to Order #$displayQueue',
                        style: const TextStyle(fontFamily: 'Poppins')),
                  ),
                ]
              : [
                  ElevatedButton(
                    onPressed: () => goToStatus(ctx),
                    child: const Text('View order status',
                        style: TextStyle(fontFamily: 'Poppins')),
                  ),
                ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokenValidAsync = ref.watch(
      _qrTokenValidProvider((tableId: widget.tableId, token: widget.qrToken)),
    );
    final tableInfoAsync = ref.watch(_tableInfoProvider(widget.tableId));
    ref.watch(_clockTickProvider); // forces a rebuild every 30s; value unused

    // Checked before anything else loads — a stale/missing token means this
    // link shouldn't work at all, regardless of table/branch state.
    if (tokenValidAsync.valueOrNull == false) {
      return const _QrExpiredScreen();
    }
    if (!tokenValidAsync.hasValue) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    ref.listen<AsyncValue<QrOrderModel?>>(
      _activeOrderForTableProvider(widget.tableId),
      (previous, next) {
        // AsyncValue.valueOrNull collapses "no active order" and "the query
        // errored" into the same null — which previously meant a genuinely
        // active order silently failed to block a duplicate order (see
        // QrOrderModel's doc comment on queueNumber/tableName/paymentMethod).
        // Logging here means a future shape mismatch fails loudly in devtools
        // instead of quietly disabling this guard again.
        if (next.hasError) {
          debugPrint('⚠️ _activeOrderForTableProvider errored: ${next.error}');
        }
        final order = next.valueOrNull;
        if (order == null || _activeOrderPromptShown) return;
        // Already in add-order mode for this exact order (e.g. came back
        // from "Add Order" on the tracker screen) — nothing to prompt.
        if (ref.read(addOrderModeProvider)?.orderId == order.id) return;
        _activeOrderPromptShown = true;
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _showActiveOrderDialog(order));
      },
    );

    return tableInfoAsync.when(
      loading: () => const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: Text('Error loading table: $e')),
      ),
      data: (tableData) {
        final branchId = (tableData?['branch_id'] as String?)?.trim() ?? '';

        if (branchId.isEmpty) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(child: Text('Branch ID not found for this table')),
          );
        }

        final branch = tableData?['branches'] as Map<String, dynamic>?;
        final branchName = branch?['name'] as String? ?? 'Restaurant';
        final tableName = (tableData?['table_number'] as String?) ?? 'Table';

        // Gate ordering on the branch's operating hours — a customer who
        // scanned this table's QR once can keep the link/tab and reopen it
        // any time later, including outside hours, with no re-scan required.
        // Checked BEFORE the table-status gate below since it's the broader
        // condition (branch closed implies no table is orderable either).
        final openingTime = branch?['opening_time'] as String?;
        final closingTime = branch?['closing_time'] as String?;
        if (!isBranchOpen(openingTime: openingTime, closingTime: closingTime)) {
          return _BranchClosedScreen(
            tableId: widget.tableId,
            branchName: branchName,
            openingTime: openingTime,
            closingTime: closingTime,
          );
        }

        // Gate ordering on the table's real status — the staff app already
        // enforces this structurally (MenuItemSelector's table dropdown only
        // ever lists available tables), QR ordering had no equivalent check
        // at all since there's no dropdown to filter, just whichever QR was
        // scanned. 'occupied' is deliberately NOT gated here — that case is
        // already handled by the active-order-for-table dialog below (join
        // the existing order / view its status), which is more specific.
        final tableStatus =
            TableStatusExt.fromString(tableData?['status'] as String? ?? 'available');
        if (tableStatus == TableStatus.cleaning || tableStatus == TableStatus.reserved) {
          return _TableNotReadyScreen(
            tableId: widget.tableId,
            tableName: tableName,
            status: tableStatus,
          );
        }

        // Save data to activeQrTableProvider
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(activeQrTableProvider.notifier).state = (
            tableId: widget.tableId,
            tableName: tableName,
            branchId: branchId,
          );
          // Carried through to the order INSERT so the anon_insert_app_orders
          // RLS policy can re-verify it server-side — see
          // supabase/migrations/20260814030000_qr_order_token_binding.sql.
          ref.read(activeQrTokenProvider.notifier).state = widget.qrToken;
        });

        return _MenuBody(
          tableId: widget.tableId,
          tableName: tableName,
          branchId: branchId,
          parseItems: _parseItems,
          groupByCategory: _groupByCategory,
          fabAnimCtrl: _fabAnimCtrl,
          searchCtrl: _searchCtrl,
        );
      },
    );
  }
}

// ─── Branch Closed Screen ───────────────────────────────────────────────────────
// Shown instead of the menu whenever the current time falls outside the
// branch's opening_time/closing_time — including when a customer reopens a
// previously-scanned/bookmarked table QR link after hours. See
// supabase/migrations/20260804000000_enforce_branch_hours_on_orders.sql for
// the matching server-side gate (this screen is UX only; that migration is
// what actually makes it unbypassable).
class _BranchClosedScreen extends ConsumerWidget {
  final String tableId;
  final String branchName;
  final String? openingTime;
  final String? closingTime;

  const _BranchClosedScreen({
    required this.tableId,
    required this.branchName,
    required this.openingTime,
    required this.closingTime,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasHours = openingTime != null && closingTime != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.nights_stay_outlined, color: AppColors.accent, size: 40),
                ),
                const SizedBox(height: 24),
                Text(
                  branchName,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 15,
                      color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                const Text(
                  "We're currently closed",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 22,
                      color: AppColors.textPrimary, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                Text(
                  hasHours
                      ? 'Ordering opens again at ${formatHhMm(openingTime)}–${formatHhMm(closingTime)} '
                        'WIB. Please come back during operating hours.'
                      : 'Please come back during our operating hours.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 14,
                      color: AppColors.textSecondary, height: 1.5),
                ),
                const SizedBox(height: 32),
                TextButton.icon(
                  onPressed: () => ref.invalidate(_tableInfoProvider(tableId)),
                  icon: const Icon(Icons.refresh_rounded, size: 18, color: AppColors.primary),
                  label: const Text('Check again',
                      style: TextStyle(fontFamily: 'Poppins', color: AppColors.primary,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── QR Expired Screen ──────────────────────────────────────────────────────────
// Shown when the `t=` token on this link doesn't match today's server-computed
// token for the table — i.e. this is a code from a previous day (rotates
// automatically every midnight WIB) or one staff force-regenerated early. See
// supabase/migrations/20260814020000_table_qr_rotation.sql.
class _QrExpiredScreen extends StatelessWidget {
  const _QrExpiredScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.qr_code_2_outlined, color: AppColors.accent, size: 40),
                ),
                const SizedBox(height: 24),
                const Text(
                  'This QR code has expired',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 22,
                      color: AppColors.textPrimary, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Table QR codes refresh daily for security. Please scan the '
                  'current code on your table, or ask a staff member for help.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                      color: AppColors.textSecondary, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Table Not Ready Screen ────────────────────────────────────────────────────
// Shown instead of the menu when the scanned table's status is 'cleaning' or
// 'reserved' — the customer can flag staff instead of silently being allowed
// to order. See supabase/migrations/20260803040000_table_status_gate_and_anon_lockdown.sql.
class _TableNotReadyScreen extends ConsumerStatefulWidget {
  final String tableId;
  final String tableName;
  final TableStatus status;

  const _TableNotReadyScreen({
    required this.tableId,
    required this.tableName,
    required this.status,
  });

  @override
  ConsumerState<_TableNotReadyScreen> createState() => _TableNotReadyScreenState();
}

class _TableNotReadyScreenState extends ConsumerState<_TableNotReadyScreen> {
  bool _reporting = false;
  bool _reported = false;

  bool get _isCleaning => widget.status == TableStatus.cleaning;

  Future<void> _reportIssue() async {
    setState(() => _reporting = true);
    try {
      await ref.read(qrOrderRepositoryProvider).reportTableIssue(widget.tableId);
      if (mounted) setState(() { _reported = true; _reporting = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _reporting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to notify staff: $e'),
          backgroundColor: AppColors.accent,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.status.color;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isCleaning ? Icons.cleaning_services_rounded : Icons.event_seat_rounded,
                    color: color,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Table ${widget.tableName}',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 15,
                      color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Text(
                  _isCleaning ? 'This table is still being cleaned' : 'This table is reserved',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 22,
                      color: AppColors.textPrimary, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                Text(
                  _isCleaning
                      ? 'Please wait for staff to finish preparing this table before ordering. '
                        "If it actually looks ready, let staff know and they'll update it."
                      : 'This table is reserved for another booking. If this is your reservation, '
                        'please let our staff know so they can seat you.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 14,
                      color: AppColors.textSecondary, height: 1.5),
                ),
                const SizedBox(height: 32),
                if (_reported)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_outline, color: Colors.green.shade700, size: 20),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Staff notified — thanks!',
                            style: TextStyle(fontFamily: 'Poppins',
                                color: Colors.green.shade700, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _reporting ? null : _reportIssue,
                      icon: _reporting
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.campaign_outlined),
                      label: Text(_reporting ? 'Notifying...' : 'Notify Staff',
                          style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () {
                    ref.invalidate(_tableInfoProvider(widget.tableId));
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 18, color: AppColors.primary),
                  label: const Text('Check again',
                      style: TextStyle(fontFamily: 'Poppins', color: AppColors.primary,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Menu Body (Responsive) ───────────────────────────────────────────────────
class _MenuBody extends ConsumerWidget {
  final String tableId, tableName, branchId;
  final List<MenuItem> Function(List<Map<String, dynamic>>) parseItems;
  final Map<String, List<MenuItem>> Function(List<MenuItem>) groupByCategory;
  final AnimationController fabAnimCtrl;
  final TextEditingController searchCtrl;

  const _MenuBody({
    required this.tableId,
    required this.tableName,
    required this.branchId,
    required this.parseItems,
    required this.groupByCategory,
    required this.fabAnimCtrl,
    required this.searchCtrl,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menuAsync = ref.watch(_menuDataProvider(branchId));
    final selectedCat = ref.watch(_selectedCategoryProvider);
    final searchQuery = ref.watch(_searchQueryProvider);
    final cart = ref.watch(activeQrCartProvider);

    final isWideScreen = MediaQuery.of(context).size.width > 700;

    cart.totalItems > 0 ? fabAnimCtrl.forward() : fabAnimCtrl.reverse();

    final addMode = ref.watch(addOrderModeProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _QrMenuTopBar(
              tableName: tableName,
              searchCtrl: searchCtrl,
              onSearchChanged: (q) => ref.read(_searchQueryProvider.notifier).state = q,
              addOrderQueueNumber: addMode?.queueNumber,
            ),
            Expanded(
              child: menuAsync.when(
                loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
                error: (e, _) => Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.wifi_off_outlined, size: 48, color: AppColors.textHint),
                    const SizedBox(height: 12),
                    Text('Failed to load menu: $e',
                        style: const TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => ref.invalidate(_menuDataProvider(branchId)),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                      child: const Text('Try Again', style: TextStyle(fontFamily: 'Poppins')),
                    ),
                  ]),
                ),
                data: (rawItems) {
                  final allItems = parseItems(rawItems);
                  final grouped = groupByCategory(allItems);
                  final categories = grouped.keys.toList();

                  var displayItems = selectedCat == null
                      ? allItems
                      : (grouped[selectedCat] ?? []);

                  if (searchQuery.isNotEmpty) {
                    final q = searchQuery.toLowerCase();
                    displayItems = displayItems
                        .where((i) => i.name.toLowerCase().contains(q) ||
                            i.description.toLowerCase().contains(q))
                        .toList();
                  }

                  if (isWideScreen) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _CategorySidebar(
                          categories: categories,
                          selected: selectedCat,
                          onSelect: (cat) => ref.read(_selectedCategoryProvider.notifier).state = cat,
                        ),
                        Expanded(
                          child: _MenuContent(
                            displayItems: displayItems,
                            categoryLabel: selectedCat,
                            showHero: searchQuery.isEmpty,
                          ),
                        ),
                      ],
                    );
                  } else {
                    return Column(
                      children: [
                        _CategorySelector(
                          categories: categories,
                          selected: selectedCat,
                          onSelect: (cat) => ref.read(_selectedCategoryProvider.notifier).state = cat,
                        ),
                        Expanded(
                          child: _MenuContent(
                            displayItems: displayItems,
                            categoryLabel: selectedCat,
                            showHero: searchQuery.isEmpty,
                          ),
                        ),
                      ],
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                  .animate(CurvedAnimation(parent: fabAnimCtrl, curve: Curves.easeOut)),
              child: _CartBar(
                cart: cart,
                tableId: tableId,
                isAddMode: addMode != null,
              ),
            ),
    );
  }
}

// ─── Category Sidebar (Web) ───────────────────────────────────────────────────
class _CategorySidebar extends StatelessWidget {
  final List<String> categories;
  final String? selected;
  final ValueChanged<String?> onSelect;

  const _CategorySidebar({required this.categories, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final all = ['All', ...categories];

    return Container(
      width: 180,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text('CATEGORIES', style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
          ),
          ...all.map((label) {
            final isActive = selected == (label == 'All' ? null : label);
            return GestureDetector(
              onTap: () => onSelect(label == 'All' ? null : label),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isActive ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: isActive ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─── Category Selector (Mobile) ───────────────────────────────────────────────
class _CategorySelector extends StatelessWidget {
  final List<String> categories;
  final String? selected;
  final ValueChanged<String?> onSelect;

  const _CategorySelector({required this.categories, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final allCategories = ['All', ...categories];

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: allCategories.length,
        itemBuilder: (context, index) {
          final label = allCategories[index];
          final isActive = selected == (label == 'All' ? null : label);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onSelect(label == 'All' ? null : label),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: isActive ? AppColors.primary : AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: isActive ? Colors.white : AppColors.textPrimary,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Menu Content ─────────────────────────────────────────────────────────────
class _MenuContent extends StatelessWidget {
  final List<MenuItem> displayItems;
  final String? categoryLabel;
  final bool showHero;

  const _MenuContent({required this.displayItems, required this.categoryLabel, required this.showHero});

  @override
  Widget build(BuildContext context) {
    if (displayItems.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: AppColors.textHint),
            SizedBox(height: 12),
            Text('No menu items found',
                style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)),
          ],
        ),
      );
    }
    return _MenuGridSection(
      items: displayItems,
      categoryLabel: categoryLabel,
      showHero: showHero,
    );
  }
}

// ─── Menu Grid Section (Chef's Special hero + 2-column grid) ─────────────────
class _MenuGridSection extends ConsumerWidget {
  final List<MenuItem> items;
  final String? categoryLabel;
  final bool showHero;

  const _MenuGridSection({required this.items, required this.categoryLabel, required this.showHero});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(activeQrCartProvider);
    final notifier = ref.read(activeQrCartNotifierProvider);

    int qtyOf(MenuItem item) => cart.items
        .where((c) => c.menuItem.id == item.id)
        .fold(0, (s, c) => s + c.quantity);

    final hero = showHero ? items.first : null;
    final gridItems = hero == null ? items : items.sublist(1);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
      children: [
        if (hero != null) ...[
          const _SectionLabel("Chef's Special"),
          const SizedBox(height: 12),
          _HeroCard(
            item: hero,
            quantity: qtyOf(hero),
            onAdd: () => notifier.addItem(hero),
            onRemove: () => notifier.removeItem(hero.id),
          ),
          const SizedBox(height: 24),
          const _SectionDivider(),
          const SizedBox(height: 24),
        ],
        if (gridItems.isNotEmpty) ...[
          _SectionLabel(categoryLabel ?? 'All Items'),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 210,
              crossAxisSpacing: 14,
              mainAxisSpacing: 18,
              childAspectRatio: 0.68,
            ),
            itemCount: gridItems.length,
            itemBuilder: (_, i) {
              final item = gridItems[i];
              return _MenuGridCard(
                item: item,
                quantity: qtyOf(item),
                onAdd: () => notifier.addItem(item),
                onRemove: () => notifier.removeItem(item.id),
              );
            },
          ),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(label,
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 18,
            fontWeight: FontWeight.w800, color: AppColors.primary));
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    return const Row(children: [
      Expanded(child: Divider(color: AppColors.border, thickness: 1)),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Icon(Icons.eco_outlined, size: 16, color: AppColors.primary),
      ),
      Expanded(child: Divider(color: AppColors.border, thickness: 1)),
    ]);
  }
}

// ─── Chef's Special hero card ─────────────────────────────────────────────────
class _HeroCard extends StatelessWidget {
  final MenuItem item;
  final int quantity;
  final VoidCallback onAdd, onRemove;

  const _HeroCard({
    required this.item,
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final unavailable = !item.isAvailable;
    const imageHeight = 200.0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: imageHeight,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _MenuImage(imageUrl: item.imageUrl),
                    if (unavailable)
                      Container(
                        color: Colors.black.withValues(alpha: 0.52),
                        child: const Center(
                          child: Text('Sold Out',
                              style: TextStyle(fontFamily: 'Poppins', color: Colors.white,
                                  fontSize: 13, fontWeight: FontWeight.w700)),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      ),
                      child: const Text('FEATURED',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                              fontWeight: FontWeight.w700, color: AppColors.textSecondary,
                              letterSpacing: 0.5)),
                    ),
                    const SizedBox(height: 10),
                    Text(item.name,
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 18,
                            fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                    if (item.description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(item.description,
                          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                              color: AppColors.textSecondary, height: 1.4)),
                    ],
                    const SizedBox(height: 8),
                    _MenuItemBadges(item: item),
                    const SizedBox(height: 8),
                    Text(_fmt(item.price),
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 16,
                            fontWeight: FontWeight.w800, color: AppColors.primary)),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!unavailable)
          Positioned(
            right: 16,
            top: imageHeight - 24,
            child: _AddControl(
              quantity: quantity,
              onAdd: onAdd,
              onRemove: onRemove,
              large: true,
            ),
          ),
      ],
    );
  }

  String _fmt(double p) => 'Rp ${p.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';
}

// ─── Menu grid card (2-column) ─────────────────────────────────────────────────
class _MenuGridCard extends StatelessWidget {
  final MenuItem item;
  final int quantity;
  final VoidCallback onAdd, onRemove;

  const _MenuGridCard({
    required this.item,
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final inCart = quantity > 0;
    final unavailable = !item.isAvailable;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: inCart ? AppColors.primary : AppColors.border,
            width: inCart ? 1.5 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1.15,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _MenuImage(imageUrl: item.imageUrl),
                if (unavailable)
                  Container(
                    color: Colors.black.withValues(alpha: 0.52),
                    child: const Center(
                      child: Text('Sold Out',
                          style: TextStyle(fontFamily: 'Poppins', color: Colors.white,
                              fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(item.name,
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                          fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (item.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(item.description,
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                            color: AppColors.textSecondary, height: 1.3),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 4),
                  _MenuItemBadges(item: item, compact: true),
                  const Spacer(),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(_fmt(item.price),
                            style: const TextStyle(fontFamily: 'Poppins', fontSize: 12.5,
                                fontWeight: FontWeight.w800, color: AppColors.primary),
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (!unavailable)
                        _AddControl(quantity: quantity, onAdd: onAdd, onRemove: onRemove),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(double p) => 'Rp ${p.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';
}

// ─── Add / stepper control (shared by hero + grid cards) ──────────────────────
class _AddControl extends StatelessWidget {
  final int quantity;
  final VoidCallback onAdd, onRemove;
  final bool large;

  const _AddControl({
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = large ? 44.0 : 28.0;

    if (quantity == 0) {
      return GestureDetector(
        onTap: onAdd,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
            boxShadow: large
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 10, offset: const Offset(0, 3))]
                : null,
          ),
          child: Icon(Icons.add, color: Colors.white, size: large ? 24 : 16),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 4 : 2),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(size),
        boxShadow: large
            ? [BoxShadow(color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 10, offset: const Offset(0, 3))]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stepBtn(Icons.remove, onRemove, size),
          SizedBox(
            width: large ? 24 : 18,
            child: Center(
              child: Text('$quantity',
                  style: TextStyle(fontFamily: 'Poppins', color: Colors.white,
                      fontSize: large ? 15 : 12, fontWeight: FontWeight.w800)),
            ),
          ),
          _stepBtn(Icons.add, onAdd, size),
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap, double size) => GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: size * 0.68,
          height: size,
          child: Icon(icon, size: large ? 16 : 12, color: Colors.white),
        ),
      );
}

class _MenuImage extends StatelessWidget {
  final String? imageUrl;

  const _MenuImage({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.trim().isEmpty) return _placeholder();

    return CachedNetworkImage(
      imageUrl: imageUrl!,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(
        color: AppColors.surfaceVariant,
        child: const Center(
            child: SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.primary))),
      ),
      errorWidget: (_, __, ___) => _placeholder(),
    );
  }

  Widget _placeholder() => Container(
        color: AppColors.surfaceVariant,
        child: const Center(child: Icon(Icons.fastfood_outlined, size: 28, color: AppColors.textHint)),
      );
}

// ─── Top bar: utensils icon, table badge, search toggle ───────────────────────
class _QrMenuTopBar extends StatefulWidget {
  final String tableName;
  final TextEditingController searchCtrl;
  final ValueChanged<String> onSearchChanged;
  final String? addOrderQueueNumber;

  const _QrMenuTopBar({
    required this.tableName,
    required this.searchCtrl,
    required this.onSearchChanged,
    this.addOrderQueueNumber,
  });

  @override
  State<_QrMenuTopBar> createState() => _QrMenuTopBarState();
}

class _QrMenuTopBarState extends State<_QrMenuTopBar> {
  bool _searchOpen = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.restaurant, color: AppColors.textPrimary, size: 22),
              Expanded(
                child: Text('Table ${widget.tableName}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 17,
                        fontWeight: FontWeight.w800, color: AppColors.primary)),
              ),
              GestureDetector(
                onTap: () => setState(() {
                  _searchOpen = !_searchOpen;
                  if (!_searchOpen) {
                    widget.searchCtrl.clear();
                    widget.onSearchChanged('');
                  }
                }),
                child: Icon(_searchOpen ? Icons.close_rounded : Icons.search_rounded,
                    color: AppColors.textPrimary, size: 22),
              ),
            ],
          ),
          if (widget.addOrderQueueNumber != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.add_circle_outline, size: 14, color: AppColors.primary),
                const SizedBox(width: 6),
                Text('Add to order #${widget.addOrderQueueNumber}',
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                        fontWeight: FontWeight.w600, color: AppColors.primary)),
              ]),
            ),
          ],
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            child: _searchOpen
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: TextField(
                      controller: widget.searchCtrl,
                      onChanged: widget.onSearchChanged,
                      autofocus: true,
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search for food or drinks...',
                        hintStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                            color: AppColors.textHint),
                        prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.textHint),
                        filled: true,
                        fillColor: AppColors.surfaceVariant,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                            borderSide: BorderSide.none),
                        isDense: true,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// ─── Full-width floating cart bar ──────────────────────────────────────────────
class _CartBar extends StatelessWidget {
  final QrOrderSession cart;
  final String tableId;
  final bool isAddMode;

  const _CartBar({
    required this.cart,
    required this.tableId,
    required this.isAddMode,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: GestureDetector(
          onTap: () => context.push('/qr/$tableId/cart'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 16, offset: const Offset(0, 6))],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: const Icon(Icons.shopping_bag_outlined, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 12),
                Text('${cart.totalItems}',
                    style: const TextStyle(fontFamily: 'Poppins', color: Colors.white,
                        fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(width: 4),
                Text(cart.totalItems == 1 ? 'Item' : 'Items',
                    style: const TextStyle(fontFamily: 'Poppins', color: Colors.white70, fontSize: 12)),
                const Spacer(),
                Text(
                  'View Cart • ${_fmt(isAddMode ? cart.subtotal : cart.totalAmount)}',
                  style: const TextStyle(fontFamily: 'Poppins', color: Colors.white,
                      fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _fmt(double p) => 'Rp ${p.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';
}

// ─── Menu Item Badges (prep time, dietary, allergen) ─────────────────────────
// Allergen/dietary info is safety-relevant, not decorative — kept visible on
// every card, just sized down ("compact") to fit the 2-column grid cells.
class _MenuItemBadges extends StatelessWidget {
  final MenuItem item;
  final bool compact;

  const _MenuItemBadges({required this.item, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final hasInfo = item.dietaryTags.isNotEmpty ||
        item.allergens.isNotEmpty ||
        (!compact && item.preparationTimeMinutes > 0);

    if (!hasInfo) return const SizedBox.shrink();

    return Wrap(
      spacing: 4,
      runSpacing: 3,
      children: [
        // Prep time — skipped in compact (grid) cards to save vertical space.
        if (!compact && item.preparationTimeMinutes > 0)
          _Badge(
            label: '~${item.preparationTimeMinutes} min',
            icon: Icons.schedule_outlined,
            color: AppColors.textSecondary,
            bg: AppColors.surfaceVariant,
          ),
        // Dietary tags (green)
        ...item.dietaryTags.take(compact ? 1 : item.dietaryTags.length).map((tag) => _Badge(
              label: tag,
              color: Colors.green[700]!,
              bg: Colors.green.withValues(alpha: 0.10),
            )),
        // Allergens (orange) — capped, rest as "+N"
        ...item.allergens.take(compact ? 1 : 2).map((a) => _Badge(
              label: a,
              icon: Icons.warning_amber_rounded,
              color: Colors.orange[800]!,
              bg: Colors.orange.withValues(alpha: 0.10),
            )),
        if (item.allergens.length > (compact ? 1 : 2))
          _Badge(
            label: '+${item.allergens.length - (compact ? 1 : 2)} allergen',
            color: Colors.orange[800]!,
            bg: Colors.orange.withValues(alpha: 0.10),
          ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final Color bg;

  const _Badge({required this.label, this.icon, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 2),
          ],
          Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
              color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
