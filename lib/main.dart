import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/config/app_config.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'core/services/notification_service.dart';
import 'shared/widgets/floating_chatbot_overlay.dart';
import 'shared/widgets/order_notification_overlay.dart';
import 'features/qr_order/presentation/qr_chatbot_overlay.dart';
import 'features/payment/midtrans/midtrans_service.dart';
import 'firebase_options.dart';
import 'dart:js_interop';

@JS('window.history.replaceState')
external void _replaceState(JSAny? data, String title, String url);

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Firebase dulu
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // 2. Supabase
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
    realtimeClientOptions: const RealtimeClientOptions(
      eventsPerSecond: 40,
    ),
  );

  // 3. Midtrans SDK
  // Only initialized on Android/iOS — midtrans_sdk doesn't support Flutter Web
  if (!kIsWeb) {
    await MidtransService.initialize(
      clientKey: AppConfig.midtransClientKey,
      isProduction: AppConfig.midtransIsProduction,
    );
  }

  // 4. Notification listener after Supabase is ready
  // Dedupe per user_id so initialize() isn't called again on every auth
  // event (initialSession, tokenRefreshed, etc.) — but still retry if the
  // previous attempt to save the token failed (e.g. the token was still stale).
  String? notifReadyForUserId;
  Supabase.instance.client.auth.onAuthStateChange.listen((event) async {
    final user = event.session?.user;
    if (user == null) {
      notifReadyForUserId = null;
      return;
    }
    if (notifReadyForUserId == user.id) return;

    final saved = await NotificationService.initialize();
    if (saved) notifReadyForUserId = user.id;
  });

  // 5. Handle OAuth Web
  if (kIsWeb) {
    final uri = Uri.base;
    final code = uri.queryParameters['code'];
    if (code != null && code.isNotEmpty) {
      final existingSession = Supabase.instance.client.auth.currentSession;
      if (existingSession == null) {
        try {
          await Supabase.instance.client.auth.exchangeCodeForSession(code);
        } catch (_) {}
      }

      // Determine where to land after stripping ?code= from the URL.
      // Preference order:
      // 1. Existing hash route (e.g. #/qr/<tableId>) — keep it as-is.
      // 2. Existing path (e.g. a QR sticker link like /qr/<tableId> with no
      //    hash yet) — without this, a lingering ?code= param on a QR/customer
      //    deep link would wipe out the tableId/branchId and strand the user
      //    on the generic mode fallback below.
      // 3. Mode default — customer/qr → /customer, staff → /login (router
      //    handles the per-role redirect from there).
      const fallbackFragment = appMode == 'staff' ? '#/login' : '#/customer';
      final String fragment;
      if (uri.fragment.isNotEmpty) {
        fragment = '#${uri.fragment}';
      } else if (uri.path.isNotEmpty && uri.path != '/') {
        fragment = '#${uri.path}';
      } else {
        fragment = fallbackFragment;
      }
      _replaceState(null, '', '/$fragment');
    }
  }

  runApp(const ProviderScope(child: RestaurantApp()));
}

class RestaurantApp extends ConsumerWidget {
  const RestaurantApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Restaurant Management System',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme.copyWith(
        textTheme: AppTheme.lightTheme.textTheme.apply(
          fontFamilyFallback: const [
            'Apple Color Emoji',
            'Noto Color Emoji',
            'Segoe UI Emoji',
          ],
        ),
      ),
      darkTheme: AppTheme.darkTheme.copyWith(
        textTheme: AppTheme.darkTheme.textTheme.apply(
          fontFamilyFallback: const [
            'Apple Color Emoji',
            'Noto Color Emoji',
            'Segoe UI Emoji',
          ],
        ),
      ),
      themeMode: ThemeMode.light,
      routerConfig: router,
      builder: (context, child) => Navigator(
        // The floating chatbot lives alongside `child` here, outside
        // GoRouter's own Navigator — so it has no Overlay/Navigator ancestor
        // of its own. Tooltip (OverlayPortal) and DropdownButton (which pushes
        // a route) both need one; this nested Navigator supplies it without
        // touching GoRouter's navigation stack.
        onGenerateRoute: (settings) => PageRouteBuilder(
          settings: settings,
          pageBuilder: (context, animation, secondaryAnimation) => Stack(
            children: [
              if (child != null) child,
              const FloatingChatbotOverlay(),
              // Rebuilds whenever GoRouter navigates so the QR menu
              // assistant can show/hide itself based on the current route
              // (see QrChatbotOverlay's doc comment for why it needs this
              // instead of just reading GoRouterState from context).
              ListenableBuilder(
                listenable: router.routerDelegate,
                builder: (context, _) => QrChatbotOverlay(
                  currentPath: router.routerDelegate.currentConfiguration.uri.path,
                ),
              ),
              // Global order-progress banner (staff/customer/qr) — see
              // OrderNotificationOverlay's doc comment.
              ListenableBuilder(
                listenable: router.routerDelegate,
                builder: (context, _) => OrderNotificationOverlay(
                  currentPath: router.routerDelegate.currentConfiguration.uri.path,
                ),
              ),
            ],
          ),
        ),
      ),
      localizationsDelegates: const [],
      supportedLocales: const [
        Locale('id'),
        Locale('en'),
      ],
    );
  }
}