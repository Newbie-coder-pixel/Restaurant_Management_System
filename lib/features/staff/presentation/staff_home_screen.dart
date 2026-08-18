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
  final String route;
  final Set<StaffRole> allowedRoles;

  const _PortalTile({
    required this.label,
    required this.subtitle,
    required this.route,
    required this.allowedRoles,
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

const _portalTiles = [
  _PortalTile(
    label: 'Floor Plan',
    subtitle: 'FRONT OF HOUSE',
    route: AppRoutes.tables,
    allowedRoles: {StaffRole.superadmin, StaffRole.manager, StaffRole.host, StaffRole.waiter},
  ),
  _PortalTile(
    label: 'Reservations',
    subtitle: 'BOOKINGS',
    route: AppRoutes.booking,
    allowedRoles: {StaffRole.superadmin, StaffRole.manager, StaffRole.host, StaffRole.waiter},
  ),
  _PortalTile(
    label: 'Orders',
    subtitle: 'ACTIVE TICKETS',
    route: AppRoutes.order,
    allowedRoles: {StaffRole.superadmin, StaffRole.manager, StaffRole.cashier, StaffRole.waiter},
  ),
  _PortalTile(
    label: 'Kitchen',
    subtitle: 'KITCHEN DISPLAY',
    route: AppRoutes.kitchen,
    allowedRoles: {StaffRole.superadmin, StaffRole.manager, StaffRole.kitchen},
  ),
  _PortalTile(
    label: 'Cashier',
    subtitle: 'PAYMENTS',
    route: AppRoutes.cashier,
    allowedRoles: {StaffRole.superadmin, StaffRole.manager, StaffRole.cashier},
  ),
  _PortalTile(
    label: 'Menu',
    subtitle: 'DISHES & PRICING',
    route: AppRoutes.menu,
    allowedRoles: _allStaffRoles,
  ),
  _PortalTile(
    label: 'Inventory',
    subtitle: 'STOCK LEVELS',
    route: AppRoutes.inventory,
    allowedRoles: {StaffRole.superadmin, StaffRole.manager},
  ),
  _PortalTile(
    label: 'Staff',
    subtitle: 'TEAM & SCHEDULES',
    route: AppRoutes.staff,
    allowedRoles: {StaffRole.superadmin, StaffRole.manager},
  ),
  _PortalTile(
    label: 'Multi Branch',
    subtitle: 'ALL LOCATIONS',
    route: AppRoutes.branches,
    allowedRoles: {StaffRole.superadmin},
  ),
  _PortalTile(
    label: 'Operating Expense',
    subtitle: 'COST ALLOCATION',
    route: AppRoutes.operatingExpense,
    allowedRoles: {StaffRole.superadmin, StaffRole.manager},
  ),
  _PortalTile(
    label: 'Costing & COGS',
    subtitle: 'RECIPE COSTING',
    route: AppRoutes.costing,
    allowedRoles: {StaffRole.superadmin, StaffRole.manager},
  ),
  _PortalTile(
    label: 'Reports',
    subtitle: 'DAILY INSIGHTS',
    route: AppRoutes.reports,
    allowedRoles: {StaffRole.superadmin, StaffRole.manager},
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
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(24, 40, 24, 32),
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
          decoration: BoxDecoration(
            color: AppColors.background,
            border: const Border(bottom: BorderSide(color: AppColors.border)),
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
              if (staff != null)
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Clock-in is inherently branch-scoped (unlike the
                      // notification bell below, which now supports a null
                      // branchId as "all branches") — a superadmin with no
                      // fixed home branch has nothing to clock into here.
                      if (staff!.branchId != null)
                        const ClockInOutControl(compact: true),
                      const NotificationBell(),
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
            Text(tile.label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 17,
                    fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text(tile.subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                    fontWeight: FontWeight.w700, color: AppColors.textSecondary,
                    letterSpacing: 0.6)),
          ],
        ),
      ),
    );
  }
}
