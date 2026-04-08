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
import '../../features/qr_order/presentation/qr_payment_screen.dart';
import '../../features/qr_order/presentation/qr_order_tracker_screen.dart';

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
  static const qrPayment    = '/qr/:tableId/payment';
  static const qrQris       = '/qr/:tableId/payment/qris';
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
    debugLogDiagnostics: true,
    refreshListenable: notifier,
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final isLoggedIn = Supabase.instance.client.auth.currentUser != null;

      final loc = state.matchedLocation;
      final fullPath = state.uri.path;

      bool isQrRoute(String path) => path.startsWith('/qr/') || path == '/qr';
      bool isCustomerRoute(String path) => path.startsWith('/customer/') || path == '/customer';

      if (isCustomerRoute(loc) || isCustomerRoute(fullPath) || isQrRoute(loc) || isQrRoute(fullPath)) {
        return null;
      }

      if (loc == AppRoutes.staffGateway) return null;

      if (kIsWeb) {
        final uri = Uri.base;
        final type = uri.queryParameters['type'];
        if (type == 'recovery' && loc != AppRoutes.customerResetPassword) {
          return AppRoutes.customerResetPassword;
        }
      }

      if (kIsWeb && !isLoggedIn && loc != AppRoutes.login) {
        return AppRoutes.customer;
      }

      if (!isLoggedIn && loc != AppRoutes.login) {
        return AppRoutes.login;
      }

      if (isLoggedIn && authState.isLoading) return null;

      if (isLoggedIn && loc == AppRoutes.login) {
        final s = authState.staff;
        if (s != null) return _defaultRouteForRole(s.role);
      }

      return null;
    },
    routes: [
      // Customer PWA Routes
      GoRoute(
        path: AppRoutes.customer,
        builder: (_, state) {
          final tab = int.tryParse(state.uri.queryParameters['tab'] ?? '0') ?? 0;
          return CustomerLandingScreen(initialTab: tab);
        },
      ),
      GoRoute(
        path: '/customer/menu/:branchId',
        builder: (_, state) => CustomerMenuScreen(branchId: state.pathParameters['branchId']!),
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
        path: '/customer/order-success/:orderNumber',
        builder: (_, state) => CustomerOrderSuccessScreen(
          orderNumber: state.pathParameters['orderNumber']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.customerBookingSuccess,
        builder: (_, __) => const CustomerBookingSuccessScreen(),
      ),
      GoRoute(
        path: AppRoutes.customerResetPassword,
        builder: (_, __) => const CustomerResetPasswordScreen(),
      ),

     // QR Order Routes
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
      path: 'payment',
      name: 'qrPayment',
      pageBuilder: (context, state) {
        final tableId = state.pathParameters['tableId']!;
        return MaterialPage(
          key: state.pageKey,
          child: QrPaymentScreen(tableId: tableId),
        );
      },
      routes: [
        GoRoute(
          path: 'qris',
          name: 'qrQris',
          pageBuilder: (context, state) {
            final tableId = state.pathParameters['tableId']!;
            final extra = state.extra as Map<String, dynamic>? ?? {};
            return MaterialPage(
              key: state.pageKey,
              child: QrQrisScreen(
                tableId: tableId,
                orderId: extra['orderId'] ?? '',
                totalAmount: (extra['totalAmount'] as num?)?.toDouble() ?? 0.0,
              ),
            );
          },
        ),
      ],
    ),
    // Perbaikan Route Tracker
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

      // Staff Routes
      GoRoute(path: AppRoutes.staffGateway, builder: (_, __) => const StaffGatewayScreen()),
      GoRoute(path: AppRoutes.login, builder: (_, __) => const LoginScreen()),
      GoRoute(path: AppRoutes.tables, builder: (_, __) => const TableScreen()),
      GoRoute(path: AppRoutes.booking, builder: (_, __) => const BookingScreen()),
      GoRoute(path: AppRoutes.order, builder: (_, __) => const OrderScreen()),
      GoRoute(path: AppRoutes.cashier, builder: (_, __) => const CashierScreen()),
      GoRoute(path: AppRoutes.kitchen, builder: (_, __) => const KDSScreen()),
      GoRoute(path: AppRoutes.menu, builder: (_, __) => const MenuScreen()),
      GoRoute(path: AppRoutes.inventory, builder: (_, __) => const InventoryScreen()),
      GoRoute(path: AppRoutes.staff, builder: (_, __) => const StaffScreen()),
      GoRoute(path: AppRoutes.reports, builder: (_, __) => const ReportsScreen()),
      GoRoute(path: AppRoutes.branches, builder: (_, __) => const BranchDashboardScreen()),
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
              onPressed: () => GoRouter.of(context).go(AppRoutes.customer),
              child: const Text('Kembali ke Beranda'),
            ),
          ],
        ),
      ),
    ),
  );
});