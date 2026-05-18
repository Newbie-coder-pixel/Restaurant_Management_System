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
import '../../features/customer/presentation/customer_reset_password_screen.dart';

import '../../features/qr_order/presentation/qr_menu_screen.dart';
import '../../features/qr_order/presentation/qr_cart_screen.dart';
import '../../features/qr_order/presentation/qr_order_tracker_screen.dart';

import '../models/staff_role.dart';

// ─────────────────────────────────────────────────────────────────────────────
// APP MODE — di-set saat build via --dart-define=APP_MODE=staff|customer|qr
// Default: 'staff' supaya kalau build tanpa define, yang muncul adalah staff app
// ─────────────────────────────────────────────────────────────────────────────
const String appMode = String.fromEnvironment('APP_MODE', defaultValue: 'staff');

abstract class AppRoutes {
  static const staffGateway   = '/staff-access';
  static const login          = '/login';
  static const tables         = '/tables';
  static const booking        = '/booking';
  static const bookingStats   = '/booking-stats';
  static const closures       = '/closures';
  static const order          = '/order';
  static const cashier        = '/cashier';
  static const kitchen        = '/kitchen';
  static const menu           = '/menu';
  static const inventory      = '/inventory';
  static const staff          = '/staff';
  static const reports        = '/reports';
  static const branches       = '/branches';
  static const transferStock  = '/branches/transfer-stock';
  static const chatbot        = '/chatbot';
  static const costing          = '/costing';
  static const operatingExpense = '/operating-expense';

  // Customer PWA
  static const customer               = '/customer';
  static const customerMenu           = '/customer/menu/:branchId';
  static const customerBooking        = '/customer/booking/:branchId';
  static const customerCheckout       = '/customer/checkout';
  static const customerTrack          = '/customer/track';
  static const customerTrackOrder     = '/customer/track/:orderNumber';
  static const customerOrderSuccess   = '/customer/order-success/:orderNumber';
  static const customerBookingSuccess = '/customer/booking-success';
  static const customerResetPassword  = '/customer/reset-password';

  // QR Order Routes
  static const qrMenu       = '/qr/:tableId';
  static const qrCart       = '/qr/:tableId/cart';
  static const qrTrack      = '/qr/:tableId/track/:orderId';
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
    _sub = _ref.listen<AuthState>(authStateProvider, (prev, next) {
      if (prev?.isLoading == true && next.isLoading == false) {
        notifyListeners();
      } else if (prev?.staff != next.staff) {
        notifyListeners();
      }
    });
  }
  final Ref _ref;
  late final ProviderSubscription _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}

String _getInitialLocation() {
  if (kIsWeb) {
    final uri = Uri.base;
    final path = uri.fragment.isNotEmpty
        ? '/${uri.fragment}'
        : uri.path;
    if (path.isNotEmpty && path != '/') return path;
  }

  // Initial location sesuai mode
  if (appMode == 'customer') return AppRoutes.customer;
  if (appMode == 'qr') return '/'; // QR butuh tableId dari URL, biarkan dari URL
  return AppRoutes.customer; // staff default ke customer dulu, redirect handle sisanya
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthChangeNotifier(ref);
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: _getInitialLocation(),
    debugLogDiagnostics: true,
    refreshListenable: notifier,
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final isLoggedIn = Supabase.instance.client.auth.currentUser != null;

      final loc = state.matchedLocation;
      final fullPath = state.uri.path;

      bool isQrRoute(String path) => path.startsWith('/qr/') || path == '/qr';
      bool isCustomerRoute(String path) =>
          path.startsWith('/customer') || path == '/customer';

      // ─── GUARD: Customer App ───────────────────────────────────────────────
      // Kalau build dengan APP_MODE=customer, hanya boleh akses /customer/...
      // Semua route lain (staff, qr) di-redirect balik ke /customer
      if (appMode == 'customer') {
        if (!isCustomerRoute(loc) && !isCustomerRoute(fullPath)) {
          return AppRoutes.customer;
        }
        // Tetap handle reset password via email link
        if (kIsWeb) {
          final uri = Uri.base;
          final type = uri.queryParameters['type'];
          if (type == 'recovery') return AppRoutes.customerResetPassword;
        }
        return null;
      }

      // ─── GUARD: QR App ────────────────────────────────────────────────────
      // Kalau build dengan APP_MODE=qr, hanya boleh akses /qr/...
      // Tidak perlu redirect karena QR URL sudah pasti mengandung tableId
      if (appMode == 'qr') {
        if (!isQrRoute(loc) && !isQrRoute(fullPath)) {
          // Tidak ada halaman fallback untuk QR, tampilkan error
          return null;
        }
        return null;
      }

      // ─── GUARD: Staff App ─────────────────────────────────────────────────
      // Kalau build dengan APP_MODE=staff (default), blok akses ke /customer dan /qr
      // Staff tidak boleh akses halaman customer atau QR
      if (appMode == 'staff') {
        if (isCustomerRoute(loc) || isCustomerRoute(fullPath) ||
            isQrRoute(loc) || isQrRoute(fullPath)) {
          // Redirect ke login kalau belum login, atau ke default role
          if (!isLoggedIn) return AppRoutes.login;
          final s = authState.staff;
          if (s != null) return _defaultRouteForRole(s.role);
          return AppRoutes.login;
        }
      }

      // ─── Logic staff lama (tidak berubah) ─────────────────────────────────
      if (loc == AppRoutes.staffGateway) return null;

      if (kIsWeb) {
        final uri = Uri.base;
        final type = uri.queryParameters['type'];
        if (type == 'recovery' && loc != AppRoutes.customerResetPassword) {
          return AppRoutes.customerResetPassword;
        }
      }

      if (authState.isLoading) return null;

      if (kIsWeb && !isLoggedIn && loc != AppRoutes.login) {
        return AppRoutes.login;
      }

      if (!isLoggedIn && loc != AppRoutes.login) {
        return AppRoutes.login;
      }

      if (isLoggedIn && loc == AppRoutes.login) {
        final s = authState.staff;
        if (s != null) return _defaultRouteForRole(s.role);
      }

      return null;
    },
    routes: [
      // ── Customer PWA Routes ───────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.customer,
        builder: (_, state) {
          final tab = int.tryParse(state.uri.queryParameters['tab'] ?? '0') ?? 0;
          return CustomerLandingScreen(initialTab: tab);
        },
      ),
      GoRoute(
        path: '/customer/menu/:branchId',
        builder: (_, state) => CustomerMenuScreen(
            branchId: state.pathParameters['branchId']!),
      ),
      GoRoute(
        path: '/customer/booking/:branchId',
        builder: (_, state) => const CustomerMyBookingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.customerCheckout,
        builder: (_, __) => const CustomerCheckoutScreen(),
      ),
      GoRoute(
        path: AppRoutes.customerTrack,
        builder: (_, __) => const CustomerOrderTrackerScreen(),
      ),
      GoRoute(
        path: AppRoutes.customerTrackOrder,
        builder: (_, state) => CustomerOrderTrackerScreen(
          initialOrderNumber: state.pathParameters['orderNumber'],
        ),
      ),
      GoRoute(
        path: AppRoutes.customerOrderSuccess,
        builder: (_, state) => CustomerOrderTrackerScreen(
          initialOrderNumber: state.pathParameters['orderNumber'],
        ),
      ),
      GoRoute(
        path: AppRoutes.customerResetPassword,
        builder: (_, __) => const CustomerResetPasswordScreen(),
      ),

      // ── QR Order Routes ───────────────────────────────────────────────────
      GoRoute(
        path: '/qr/:tableId',
        name: 'qrMenu',
        pageBuilder: (context, state) {
          final tableId = state.pathParameters['tableId']!;
          return NoTransitionPage(
            key: state.pageKey,
            child: QrMenuScreen(tableId: tableId),
          );
        },
        routes: [
          GoRoute(
            path: 'cart',
            name: 'qrCart',
            pageBuilder: (context, state) {
              final tableId = state.pathParameters['tableId']!;
              return MaterialPage(
                key: state.pageKey,
                child: QrCartScreen(tableId: tableId),
              );
            },
          ),
          GoRoute(
            path: 'track/:orderId',
            name: 'qrTrack',
            pageBuilder: (context, state) {
              final orderId = state.pathParameters['orderId']!;
              final queueNumber = state.uri.queryParameters['queue'];
              return MaterialPage(
                key: state.pageKey,
                child: QrOrderTrackerScreen(
                  orderId: orderId,
                  queueNumber: queueNumber,
                ),
              );
            },
          ),
        ],
      ),

      // ── Staff Routes ──────────────────────────────────────────────────────
      GoRoute(path: AppRoutes.staffGateway, builder: (_, __) => const StaffGatewayScreen()),
      GoRoute(path: AppRoutes.login,        builder: (_, __) => const LoginScreen()),
      GoRoute(path: AppRoutes.tables,       builder: (_, __) => const TableScreen()),
      GoRoute(path: AppRoutes.booking,      builder: (_, __) => const BookingScreen()),
      GoRoute(path: AppRoutes.bookingStats, builder: (_, __) => const BookingStatsScreen()),
      GoRoute(path: AppRoutes.order,        builder: (_, __) => const OrderScreen()),
      GoRoute(path: AppRoutes.cashier,      builder: (_, __) => const CashierScreen()),
      GoRoute(path: AppRoutes.kitchen,      builder: (_, __) => const KDSScreen()),
      GoRoute(path: AppRoutes.menu,         builder: (_, __) => const MenuScreen()),
      GoRoute(path: AppRoutes.closures,     builder: (_, __) => const RestaurantClosureScreen()),
      GoRoute(path: AppRoutes.inventory,    builder: (_, __) => const InventoryScreen()),
      GoRoute(path: AppRoutes.staff,        builder: (_, __) => const StaffScreen()),
      GoRoute(path: AppRoutes.reports,      builder: (_, __) => const ReportsScreen()),
      GoRoute(path: '/costing',           builder: (_, __) => const CostingCalculatorScreen()),
      GoRoute(path: '/operating-expense', builder: (_, __) => const OperatingExpenseScreen()),

      // ── Multi Branch Routes ───────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.branches,
        builder: (_, __) => const BranchDashboardScreen(),
      ),
      GoRoute(
        path: AppRoutes.transferStock,
        builder: (_, __) => const TransferStockListScreen(),
      ),

      GoRoute(path: AppRoutes.chatbot, builder: (_, __) => const ChatbotScreen()),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 80, color: Colors.red),
            const SizedBox(height: 16),
            Text('Page not found:\n${state.uri.path}'),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => GoRouter.of(context).go(
                appMode == 'staff' ? AppRoutes.login : AppRoutes.customer,
              ),
              child: const Text('Kembali'),
            ),
          ],
        ),
      ),
    ),
  );
});