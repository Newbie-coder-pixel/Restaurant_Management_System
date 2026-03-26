// lib/core/router/app_router.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/presentation/staff_gateway_screen.dart';
import '../../features/screens.dart';
import '../../features/customer/presentation/customer_landing_screen.dart';
import '../../features/customer/presentation/customer_menu_screen.dart';
import '../../features/customer/presentation/customer_my_bookings_screen.dart';
import '../../features/customer/presentation/customer_checkout_screen.dart';
import '../../features/customer/presentation/customer_order_tracker_screen.dart';
// FIX: Hapus unused import 'customer_auth_provider.dart'
import '../models/staff_role.dart';

abstract class AppRoutes {
  static const staffGateway   = '/staff-access';
  static const login          = '/login';
  static const tables         = '/tables';
  static const booking        = '/booking';
  static const order          = '/order';
  static const cashier        = '/cashier';
  static const kitchen        = '/kitchen';
  static const menu           = '/menu';
  static const inventory      = '/inventory';
  static const staff          = '/staff';
  static const reports        = '/reports';
  static const branches       = '/branches';
  static const chatbot        = '/chatbot';
  // Customer PWA
  static const customer              = '/customer';
  static const customerMenu          = '/customer/menu/:branchId';
  static const customerBooking       = '/customer/booking/:branchId';
  static const customerCheckout      = '/customer/checkout';
  static const customerTrack         = '/customer/track';
  static const customerOrderSuccess  = '/customer/order-success/:orderNumber';
  static const customerBookingSuccess = '/customer/booking-success';
}

String _defaultRouteForRole(StaffRole role) {
  switch (role) {
    case StaffRole.superadmin:
    case StaffRole.manager:
      return AppRoutes.reports;
    case StaffRole.cashier:
      return AppRoutes.cashier;
    case StaffRole.waiter:
      return AppRoutes.order;
    case StaffRole.kitchen:
      return AppRoutes.kitchen;
    case StaffRole.host:
      return AppRoutes.tables;
  }
}

class _AuthChangeNotifier extends ChangeNotifier {
  _AuthChangeNotifier(this._ref) {
    _sub = _ref.listen<AuthState>(authStateProvider, (_, __) => notifyListeners());
  }
  final Ref _ref;
  late final ProviderSubscription _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthChangeNotifier(ref);
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: AppRoutes.customer,
    debugLogDiagnostics: false,
    refreshListenable: notifier,
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final isLoggedIn = Supabase.instance.client.auth.currentUser != null;
      final loc = state.matchedLocation;

      // Customer routes — bebas, tidak perlu auth
      if (loc.startsWith('/customer')) return null;

      // Staff gateway — URL rahasia, tidak perlu auth
      if (loc == AppRoutes.staffGateway) return null;

      if (kIsWeb && !isLoggedIn && loc != AppRoutes.login) {
        return AppRoutes.customer;
      }

      // Di mobile/desktop: kalau belum login → ke login
      if (!isLoggedIn && loc != AppRoutes.login) return AppRoutes.login;

      // Masih loading data staff → tunggu
      if (isLoggedIn && authState.isLoading) return null;

      // Sudah login + di halaman login → arahkan ke halaman sesuai role
      if (isLoggedIn && loc == AppRoutes.login) {
        final s = authState.staff;
        if (s != null) return _defaultRouteForRole(s.role);
      }

      return null;
    },
    routes: [
      // ── Customer PWA (no auth) — di atas agar prioritas ───
      GoRoute(path: AppRoutes.customer,
  builder: (_, state) {
    final tab = int.tryParse(
      state.uri.queryParameters['tab'] ?? '0') ?? 0;
    return CustomerLandingScreen(initialTab: tab);
  }),
      GoRoute(path: '/customer/menu/:branchId',
        builder: (_, state) => CustomerMenuScreen(
          branchId: state.pathParameters['branchId']!)),
      GoRoute(
  path: '/customer/booking/:branchId',
  builder: (_, state) => const CustomerMyBookingsScreen(),
),
      GoRoute(path: AppRoutes.customerCheckout,
        builder: (_, __) => const CustomerCheckoutScreen()),
      GoRoute(path: AppRoutes.customerTrack,
        builder: (_, __) => const CustomerOrderTrackerScreen()),
      GoRoute(path: '/customer/order-success/:orderNumber',
        builder: (_, state) => CustomerOrderSuccessScreen(
          orderNumber: state.pathParameters['orderNumber']!)),
      GoRoute(path: AppRoutes.customerBookingSuccess,
        builder: (_, __) => const CustomerBookingSuccessScreen()),

      // ── Staff gateway (URL rahasia, no auth) ──────────────
      GoRoute(path: AppRoutes.staffGateway,
        builder: (_, __) => const StaffGatewayScreen()),

      // ── Staff routes (auth required) ──────────────────────
      GoRoute(path: AppRoutes.login,     builder: (_, __) => const LoginScreen()),
      GoRoute(path: AppRoutes.tables,    builder: (_, __) => const TableScreen()),
      GoRoute(path: AppRoutes.booking,   builder: (_, __) => const BookingScreen()),
      GoRoute(path: AppRoutes.order,     builder: (_, __) => const OrderScreen()),
      GoRoute(path: AppRoutes.cashier,   builder: (_, __) => const CashierScreen()),
      GoRoute(path: AppRoutes.kitchen,   builder: (_, __) => const KDSScreen()),
      GoRoute(path: AppRoutes.menu,      builder: (_, __) => const MenuScreen()),
      GoRoute(path: AppRoutes.inventory, builder: (_, __) => const InventoryScreen()),
      GoRoute(path: AppRoutes.staff,     builder: (_, __) => const StaffScreen()),
      GoRoute(path: AppRoutes.reports,   builder: (_, __) => const ReportsScreen()),
      GoRoute(path: AppRoutes.branches,  builder: (_, __) => const BranchDashboardScreen()),
      GoRoute(path: AppRoutes.chatbot,   builder: (_, __) => const ChatbotScreen()),
    ],
    errorBuilder: (_, __) => const Scaffold(
      body: Center(child: Text('Page not found')),
    ),
  );
});