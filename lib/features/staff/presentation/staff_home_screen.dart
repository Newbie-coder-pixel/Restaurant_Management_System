// lib/features/staff/presentation/staff_home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/staff_role.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/staff_model.dart';
import '../../../shared/widgets/app_drawer.dart';
import '../../../shared/widgets/clock_in_out_control.dart';
import '../../../shared/widgets/notification_bell.dart';
import '../../auth/providers/auth_provider.dart';

class _PortalTile {
  final String label;
  final String subtitle;
  final IconData icon;
  final String route;
  final Set<StaffRole> allowedRoles;
  final Color background;
  final Color foreground;

  const _PortalTile({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.route,
    required this.allowedRoles,
    required this.background,
    required this.foreground,
  });
}

const _allStaffRoles = {
  StaffRole.superadmin,
  StaffRole.manager,
  StaffRole.cashier,
  StaffRole.waiter,
  StaffRole.kitchen,
  StaffRole.host,
};

final _portalTiles = [
  _PortalTile(
    label: 'Floor Plan',
    subtitle: 'FRONT OF HOUSE',
    icon: Icons.table_restaurant_rounded,
    route: AppRoutes.tables,
    allowedRoles: const {StaffRole.superadmin, StaffRole.manager, StaffRole.host, StaffRole.waiter},
    background: AppColors.accent.withValues(alpha: 0.15),
    foreground: AppColors.accent,
  ),
  _PortalTile(
    label: 'Reservations',
    subtitle: 'BOOKINGS',
    icon: Icons.calendar_month_rounded,
    route: AppRoutes.booking,
    allowedRoles: const {StaffRole.superadmin, StaffRole.manager, StaffRole.host, StaffRole.waiter},
    background: AppColors.reserved.withValues(alpha: 0.15),
    foreground: AppColors.reserved,
  ),
  const _PortalTile(
    label: 'Reservation Stats',
    subtitle: 'BOOKING INSIGHTS',
    icon: Icons.insert_chart_outlined_rounded,
    route: AppRoutes.bookingStats,
    allowedRoles: {StaffRole.superadmin, StaffRole.manager},
    background: AppColors.surfaceVariant,
    foreground: AppColors.textSecondary,
  ),
  const _PortalTile(
    label: 'Closed Days',
    subtitle: 'RESTAURANT CLOSURES',
    icon: Icons.event_busy_rounded,
    route: AppRoutes.closures,
    allowedRoles: {StaffRole.superadmin, StaffRole.manager},
    background: AppColors.surfaceVariant,
    foreground: AppColors.textSecondary,
  ),
  _PortalTile(
    label: 'Orders',
    subtitle: 'ACTIVE TICKETS',
    icon: Icons.receipt_long_rounded,
    route: AppRoutes.order,
    allowedRoles: const {StaffRole.superadmin, StaffRole.manager, StaffRole.cashier, StaffRole.waiter},
    background: AppColors.primary.withValues(alpha: 0.12),
    foreground: AppColors.primary,
  ),
  const _PortalTile(
    label: 'Kitchen',
    subtitle: 'KITCHEN DISPLAY',
    icon: Icons.soup_kitchen_rounded,
    route: AppRoutes.kitchen,
    allowedRoles: {StaffRole.superadmin, StaffRole.manager, StaffRole.kitchen},
    background: AppColors.primary,
    foreground: Colors.white,
  ),
  const _PortalTile(
    label: 'Cashier',
    subtitle: 'PAYMENTS',
    icon: Icons.point_of_sale_rounded,
    route: AppRoutes.cashier,
    allowedRoles: {StaffRole.superadmin, StaffRole.manager, StaffRole.cashier},
    background: AppColors.surfaceVariant,
    foreground: AppColors.textSecondary,
  ),
  const _PortalTile(
    label: 'Menu',
    subtitle: 'DISHES & PRICING',
    icon: Icons.menu_book_rounded,
    route: AppRoutes.menu,
    allowedRoles: _allStaffRoles,
    background: AppColors.accentOrange,
    foreground: Colors.white,
  ),
  const _PortalTile(
    label: 'Inventory',
    subtitle: 'STOCK LEVELS',
    icon: Icons.inventory_2_rounded,
    route: AppRoutes.inventory,
    allowedRoles: {StaffRole.superadmin, StaffRole.manager},
    background: AppColors.surfaceVariant,
    foreground: AppColors.textSecondary,
  ),
  const _PortalTile(
    label: 'Staff',
    subtitle: 'TEAM & SCHEDULES',
    icon: Icons.people_rounded,
    route: AppRoutes.staff,
    allowedRoles: {StaffRole.superadmin, StaffRole.manager},
    background: AppColors.surfaceVariant,
    foreground: AppColors.textSecondary,
  ),
  const _PortalTile(
    label: 'Multi Branch',
    subtitle: 'ALL LOCATIONS',
    icon: Icons.store_rounded,
    route: AppRoutes.branches,
    allowedRoles: {StaffRole.superadmin},
    background: AppColors.iconAccentBlue,
    foreground: Colors.white,
  ),
  const _PortalTile(
    label: 'Operating Expense',
    subtitle: 'COST ALLOCATION',
    icon: Icons.payments_rounded,
    route: AppRoutes.operatingExpense,
    allowedRoles: {StaffRole.superadmin, StaffRole.manager},
    background: AppColors.surfaceVariant,
    foreground: AppColors.textSecondary,
  ),
  const _PortalTile(
    label: 'Costing & COGS',
    subtitle: 'RECIPE COSTING',
    icon: Icons.calculate_rounded,
    route: AppRoutes.costing,
    allowedRoles: {StaffRole.superadmin, StaffRole.manager},
    background: AppColors.surfaceVariant,
    foreground: AppColors.textSecondary,
  ),
  const _PortalTile(
    label: 'Reports',
    subtitle: 'DAILY INSIGHTS',
    icon: Icons.bar_chart_rounded,
    route: AppRoutes.reports,
    allowedRoles: {StaffRole.superadmin, StaffRole.manager},
    background: AppColors.surfaceVariant,
    foreground: AppColors.textSecondary,
  ),
];

/// Landing hub shown to every staff role right after login. Tiles are
/// filtered against each tile's [_PortalTile.allowedRoles], mirroring the
/// role gating in AppDrawer and the router's _roleCanAccessRoute — a role
/// with access to only one module (e.g. kitchen) still lands on this screen,
/// just sees a single tile, rather than being redirected straight past it.
/// See _defaultRouteForRole in app_router.dart.
class StaffHomeScreen extends ConsumerWidget {
  const StaffHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staff = ref.watch(currentStaffProvider);
    final role = staff?.role ?? StaffRole.waiter;
    final tiles = _portalTiles.where((t) => t.allowedRoles.contains(role)).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const AppDrawer(),
      body: SafeArea(
        child: Column(
          children: [
            _Header(staff: staff),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
                          child: Column(
                            children: [
                              const Text('Service Portal',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontFamily: 'Poppins', fontSize: 30,
                                      fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                              const SizedBox(height: 8),
                              const Text(
                                'Select a module to get started.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                                    color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                        sliver: SliverGrid(
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 320,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                            childAspectRatio: 1.05,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, i) => _PortalCard(tile: tiles[i]),
                            childCount: tiles.length,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Header ─────────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final StaffMember? staff;
  const _Header({required this.staff});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showGreeting = constraints.maxWidth > 640;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: const BoxDecoration(
            color: AppColors.background,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              const Text('RestaurantOS',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 20,
                      fontWeight: FontWeight.w800, color: AppColors.primary)),
              const Spacer(),
              if (showGreeting && staff != null) ...[
                Text('Welcome, ${staff!.fullName}',
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 13.5,
                        color: AppColors.textPrimary)),
                const SizedBox(width: 14),
              ],
              if (staff?.branchId != null)
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const ClockInOutControl(),
                      NotificationBell(branchId: staff!.branchId!),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              const SizedBox(width: 4),
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
      },
    );
  }
}

// ─── Portal Card ──────────────────────────────────────────────────────────────
class _PortalCard extends StatelessWidget {
  final _PortalTile tile;
  const _PortalCard({required this.tile});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      onTap: () => context.go(tile.route),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.12), offset: const Offset(0, 3)),
          ],
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64, height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tile.background,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Icon(tile.icon, size: 30, color: tile.foreground),
            ),
            const SizedBox(height: 16),
            Text(tile.label,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 17,
                    fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text(tile.subtitle,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                    fontWeight: FontWeight.w700, color: AppColors.textSecondary,
                    letterSpacing: 0.6)),
          ],
        ),
      ),
    );
  }
}
