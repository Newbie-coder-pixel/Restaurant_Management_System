// lib/shared/widgets/staff_shell.dart
//
// Shared chrome for the Pusaka-styled staff screens: a persistent left
// sidebar (Service Portal nav) on wide layouts + a top bar (title, role
// badge, live clock, notification bell, drawer/settings toggle), falling
// back to the hamburger AppDrawer on narrow layouts. Extracted from
// table_screen.dart so every rebuilt staff screen shares one implementation
// instead of copy-pasting the sidebar/top-bar chrome.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/staff_role.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../models/staff_model.dart';
import 'app_drawer.dart';
import 'clock_in_out_control.dart';
import 'notification_bell.dart';

const double kStaffShellSidebarBreakpoint = 900;

class StaffShellSidebarItem {
  final String label;
  final IconData icon;
  final String route;
  final String requiredFeature;
  const StaffShellSidebarItem({
    required this.label, required this.icon,
    required this.route, required this.requiredFeature,
  });
}

const staffShellSidebarItems = [
  StaffShellSidebarItem(
    label: 'Floor Plan', icon: Icons.table_restaurant_rounded,
    route: AppRoutes.tables, requiredFeature: 'Table Management'),
  StaffShellSidebarItem(
    label: 'Orders', icon: Icons.receipt_long_rounded,
    route: AppRoutes.order, requiredFeature: 'Order'),
  StaffShellSidebarItem(
    label: 'Inventory', icon: Icons.inventory_2_rounded,
    route: AppRoutes.inventory, requiredFeature: 'Inventory'),
  StaffShellSidebarItem(
    label: 'Staff Shift', icon: Icons.badge_rounded,
    route: AppRoutes.staff, requiredFeature: 'Staff'),
  StaffShellSidebarItem(
    label: 'Reports', icon: Icons.bar_chart_rounded,
    route: AppRoutes.reports, requiredFeature: 'Reports & Analytics'),
];

// ── Clock-in/out control wrapped in the sidebar's amber pill styling. ──
class ClockOutButton extends StatelessWidget {
  const ClockOutButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: const ClockInOutControl(),
    );
  }
}

class StaffShell extends ConsumerStatefulWidget {
  final String pageTitle;
  final String activeRoute;
  final Widget body;
  final Widget? floatingActionButton;
  /// Screen-specific controls (e.g. branch dropdown, refresh button) shown
  /// in the top bar before the clock/notification-bell/settings cluster.
  final List<Widget> topBarActions;

  const StaffShell({
    super.key,
    required this.pageTitle,
    required this.activeRoute,
    required this.body,
    this.floatingActionButton,
    this.topBarActions = const [],
  });

  @override
  ConsumerState<StaffShell> createState() => _StaffShellState();
}

class _StaffShellState extends ConsumerState<StaffShell> {
  // Purely decorative wall-clock in the top bar — no business logic behind it.
  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final staff = ref.watch(currentStaffProvider);
    final isWide = MediaQuery.of(context).size.width >= kStaffShellSidebarBreakpoint;

    return Scaffold(
      drawer: const AppDrawer(),
      backgroundColor: AppColors.background,
      floatingActionButton: widget.floatingActionButton,
      body: SafeArea(
        child: Row(
          children: [
            if (isWide) _buildSidebar(context, staff?.role),
            Expanded(
              child: Column(
                children: [
                  _buildTopBar(context, staff, isWide: isWide),
                  Expanded(child: widget.body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Sidebar (wide layouts only) ─────────────────────────────────────────
  Widget _buildSidebar(BuildContext context, StaffRole? role) {
    final r = role ?? StaffRole.waiter;
    final items = staffShellSidebarItems.where(
      (i) => r == StaffRole.superadmin || r.accessFeatures.contains(i.requiredFeature)).toList();

    return Container(
      width: 260,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Row(
              children: [
                Container(
                  width: 44, height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.storefront_rounded,
                    color: AppColors.accent, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Service Portal',
                        style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 16,
                          fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text('STAFF ACCESS ONLY',
                        style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 10,
                          fontWeight: FontWeight.w700, letterSpacing: 0.6,
                          color: AppColors.accent.withValues(alpha: 0.8))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              children: items.map((item) {
                final isActive = widget.activeRoute == item.route;
                return Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ListTile(
                    dense: true,
                    leading: Icon(item.icon, size: 20,
                      color: isActive ? Colors.white : AppColors.textSecondary),
                    title: Text(item.label,
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 13,
                        fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                        color: isActive ? Colors.white : AppColors.textPrimary)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    onTap: () {
                      if (widget.activeRoute != item.route) context.go(item.route);
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.help_outline_rounded,
                    size: 20, color: AppColors.textSecondary),
                  title: const Text('Support',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textPrimary)),
                  onTap: () => showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      title: const Text('Need Help?',
                        style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
                      content: const Text(
                        'Contact your branch manager or superadmin for support with the Service Portal.',
                        style: TextStyle(fontFamily: 'Poppins')),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close')),
                      ],
                    ),
                  ),
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.logout_rounded,
                    size: 20, color: Colors.redAccent),
                  title: const Text('Logout',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Colors.redAccent)),
                  onTap: _confirmLogout,
                ),
                const SizedBox(height: 8),
                const ClockOutButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmLogout() {
    final authNotifier = ref.read(authStateProvider.notifier);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Logout',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
        content: const Text('Are you sure you want to log out of this account?',
          style: TextStyle(fontFamily: 'Poppins')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(dialogContext);
              await authNotifier.signOut();
            },
            child: const Text('Logout', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
  }

  // ── Top bar ──────────────────────────────────────────────────────────────
  Widget _buildTopBar(BuildContext context, StaffMember? staff, {required bool isWide}) {
    final timeLabel =
        '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (!isWide)
            Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu_rounded, color: AppColors.textPrimary),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
          Flexible(
            child: Text(widget.pageTitle,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 18,
                fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          ),
          // Decorative on narrow layouts — dropped first to make room for
          // the functional controls (topBarActions, notification bell).
          if (staff != null && isWide) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(staff.role.displayName,
                style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 11,
                  fontWeight: FontWeight.w700, color: Color(0xFF4CAF50))),
            ),
          ],
          const Spacer(),
          ...widget.topBarActions,
          if (isWide) ...[
            Text('$timeLabel WIB',
              style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(width: 12),
          ],
          if (staff?.branchId != null) NotificationBell(branchId: staff!.branchId!),
          Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.settings_outlined, color: AppColors.textSecondary),
              tooltip: 'Menu',
              onPressed: () => Scaffold.of(ctx).openDrawer(),
            ),
          ),
        ],
      ),
    );
  }
}
