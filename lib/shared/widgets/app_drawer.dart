import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/staff_role.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../features/auth/providers/auth_provider.dart';

class _NavItem {
  final String label;
  final IconData icon;
  final String route;
  final Set<StaffRole> allowedRoles;

  const _NavItem({
    required this.label,
    required this.icon,
    required this.route,
    required this.allowedRoles,
  });
}

const _allRoles = {
  StaffRole.superadmin,
  StaffRole.manager,
  StaffRole.cashier,
  StaffRole.waiter,
  StaffRole.kitchen,
  StaffRole.host,
};

const _navItems = [
  _NavItem(
    label: 'Laporan & Analitik',
    icon: Icons.bar_chart_rounded,
    route: AppRoutes.reports,
    allowedRoles: {StaffRole.superadmin, StaffRole.manager},
  ),
  _NavItem(
    label: 'Manajemen Meja',
    icon: Icons.table_restaurant_rounded,
    route: AppRoutes.tables,
    allowedRoles: {StaffRole.superadmin, StaffRole.manager, StaffRole.host, StaffRole.waiter},
  ),
  _NavItem(
    label: 'Reservasi',
    icon: Icons.calendar_month_rounded,
    route: AppRoutes.booking,
    allowedRoles: {StaffRole.superadmin, StaffRole.manager, StaffRole.host, StaffRole.waiter},
  ),
  _NavItem(
    label: 'Order',
    icon: Icons.receipt_long_rounded,
    route: AppRoutes.order,
    allowedRoles: {StaffRole.superadmin, StaffRole.manager, StaffRole.cashier, StaffRole.waiter},
  ),
  _NavItem(
    label: 'Kasir & Pembayaran',
    icon: Icons.point_of_sale_rounded,
    route: AppRoutes.cashier,
    allowedRoles: {StaffRole.superadmin, StaffRole.manager, StaffRole.cashier},
  ),
  _NavItem(
    label: 'Dapur (KDS)',
    icon: Icons.soup_kitchen_rounded,
    route: AppRoutes.kitchen,
    allowedRoles: {StaffRole.superadmin, StaffRole.manager, StaffRole.kitchen},
  ),
  _NavItem(
    label: 'Menu',
    icon: Icons.menu_book_rounded,
    route: AppRoutes.menu,
    allowedRoles: _allRoles,
  ),
  _NavItem(
    label: 'Inventori',
    icon: Icons.inventory_2_rounded,
    route: AppRoutes.inventory,
    allowedRoles: {StaffRole.superadmin, StaffRole.manager},
  ),
  _NavItem(
    label: 'Staff',
    icon: Icons.people_rounded,
    route: AppRoutes.staff,
    allowedRoles: {StaffRole.superadmin, StaffRole.manager},
  ),
  _NavItem(
    label: 'Multi Cabang',
    icon: Icons.store_rounded,
    route: AppRoutes.branches,
    allowedRoles: {StaffRole.superadmin},
  ),
  _NavItem(
    label: 'AI Chatbot',
    icon: Icons.smart_toy_rounded,
    route: AppRoutes.chatbot,
    allowedRoles: {StaffRole.superadmin, StaffRole.manager},
  ),



];

class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staff = ref.watch(currentStaffProvider);
    final role = staff?.role ?? StaffRole.waiter;
    final currentRoute = GoRouterState.of(context).matchedLocation;

    final visibleItems = _navItems
        .where((item) => item.allowedRoles.contains(role))
        .toList();

    return Drawer(
      backgroundColor: AppColors.primary,
      child: SafeArea(
        child: Column(
          children: [
            // ── Header ──
            Container(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.restaurant_menu,
                        color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('RestaurantOS',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: Colors.white,
                          )),
                        Text(staff?.fullName ?? '-',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            color: Colors.white60,
                          ),
                          overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Role Badge ──
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _roleColor(role).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: _roleColor(role).withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_roleIcon(role), size: 14, color: _roleColor(role)),
                  const SizedBox(width: 6),
                  Text(role.displayName,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _roleColor(role),
                    )),
                ],
              ),
            ),

            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 8),

            // ── Nav Items ──
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: visibleItems.length,
                itemBuilder: (context, i) {
                  final item = visibleItems[i];
                  final isActive = currentRoute == item.route;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 2),
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors.accent.withValues(alpha: 0.2)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ListTile(
                      dense: true,
                      leading: Icon(item.icon,
                        size: 22,
                        color: isActive ? AppColors.accent : Colors.white60),
                      title: Text(item.label,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          fontWeight: isActive
                              ? FontWeight.w600 : FontWeight.w400,
                          color: isActive ? Colors.white : Colors.white70,
                        )),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      onTap: () {
                        Navigator.of(context).pop(); // close drawer
                        if (currentRoute != item.route) {
                          context.go(item.route);
                        }
                      },
                    ),
                  );
                },
              ),
            ),

            const Divider(color: Colors.white12, height: 1),

            // ── Logout ──
            ListTile(
              leading: const Icon(Icons.logout_rounded,
                  color: Colors.redAccent, size: 22),
              title: const Text('Logout',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: Colors.redAccent,
                )),
              onTap: () {
                Navigator.of(context).pop();
                _showLogoutDialog(context, ref);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, WidgetRef ref) {
    // Simpan notifier SEBELUM showDialog dipanggil, di luar closure
    final authNotifier = ref.read(authStateProvider.notifier);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Konfirmasi Logout',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
        content: const Text('Yakin ingin keluar dari akun ini?',
          style: TextStyle(fontFamily: 'Poppins')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(dialogContext);
              // Gunakan authNotifier yang sudah disimpan, BUKAN ref.read
              await authNotifier.signOut();
            },
            child: const Text('Logout',
              style: TextStyle(color: Colors.white))),
        ],
      ),
    );
  }

  Color _roleColor(StaffRole role) {
    switch (role) {
      case StaffRole.superadmin: return const Color(0xFFFFD700);
      case StaffRole.manager:    return const Color(0xFF4FC3F7);
      case StaffRole.cashier:    return const Color(0xFF81C784);
      case StaffRole.waiter:     return const Color(0xFFFFB74D);
      case StaffRole.kitchen:    return const Color(0xFFFF8A65);
      case StaffRole.host:       return const Color(0xFFCE93D8);
    }
  }

  IconData _roleIcon(StaffRole role) {
    switch (role) {
      case StaffRole.superadmin: return Icons.admin_panel_settings_rounded;
      case StaffRole.manager:    return Icons.manage_accounts_rounded;
      case StaffRole.cashier:    return Icons.point_of_sale_rounded;
      case StaffRole.waiter:     return Icons.room_service_rounded;
      case StaffRole.kitchen:    return Icons.soup_kitchen_rounded;
      case StaffRole.host:       return Icons.door_front_door_rounded;
    }
  }
}