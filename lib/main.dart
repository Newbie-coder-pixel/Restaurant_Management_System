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
import 'core/services/order_sound_service.dart';
import 'shared/widgets/floating_chatbot_overlay.dart';
import 'shared/widgets/order_notification_overlay.dart';
import 'shared/widgets/theme_mode_toggle.dart';
import 'core/providers/theme_mode_provider.dart';
import 'features/qr_order/presentation/qr_chatbot_overlay.dart';
import 'features/customer/presentation/customer_chatbot_overlay.dart';
import 'features/payment/midtrans/midtrans_service.dart';
import 'firebase_options.dart';
import 'dart:js_interop';

@JS('window.history.replaceState')
external void _replaceState(JSAny? data, String title, String url);

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Firebase dulu
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // 2. Supabase
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
    realtimeClientOptions: const RealtimeClientOptions(eventsPerSecond: 40),
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
      themeMode: ref.watch(themeModeProvider),
      routerConfig: router,
      builder: (context, child) => Listener(
        // Primes OrderSoundService's shared player on the very first tap
        // anywhere in the app — see its unlock() doc comment. Cheaper to
        // hang this off every pointer-down than to track "has the user
        // interacted yet" state ourselves; unlock() already no-ops after
        // the first successful call.
        onPointerDown: (_) => OrderSoundService.unlock(),
        child: Overlay(
          // The floating chatbot lives alongside `child` here, outside
          // GoRouter's own Navigator — so it has no Overlay ancestor of its
          // own, which Tooltip/OverlayPortal (used by these floating widgets)
          // need. A plain Overlay supplies that without being a second,
          // separate route stack: an earlier `Navigator(...)` here was a
          // second root-ish Navigator that `showDialog(useRootNavigator:
          // true)` (the default) would target instead of GoRouter's own
          // Navigator, while the dialog's own pop calls (and, more subtly,
          // Flutter's browser-back handling) resolved against GoRouter's
          // Navigator — a mismatch that could pop the wrong thing or leave
          // stale routes/render state behind after rapid browser
          // back-navigation. Overlay can't receive a pushed route at all, so
          // that whole class of bug can't happen here anymore.
          initialEntries: [
            OverlayEntry(
              builder: (context) => Stack(
                children: [
                  if (child != null) child,
                  // These three float alongside `child` rather than inside
                  // it, so — unlike every real screen, which gets one from
                  // its own Scaffold — they have no Material ancestor of
                  // their own. Any InkWell/ink effect inside them (e.g. the
                  // QR chatbot's InkWell at qr_chatbot_screen.dart:799)
                  // throws "No Material widget found" without this.
                  const Material(
                    type: MaterialType.transparency,
                    child: FloatingChatbotOverlay(),
                  ),
                  // Rebuilds whenever GoRouter navigates so the QR menu
                  // assistant can show/hide itself based on the current route
                  // (see QrChatbotOverlay's doc comment for why it needs this
                  // instead of just reading GoRouterState from context).
                  Material(
                    type: MaterialType.transparency,
                    child: ListenableBuilder(
                      listenable: router.routerDelegate,
                      builder: (context, _) => QrChatbotOverlay(
                        currentPath: router.routerDelegate.currentConfiguration
                            .uri.path,
                      ),
                    ),
                  ),
                  // Same pattern for the customer app's AI chat launcher —
                  // see CustomerChatbotOverlay's doc comment.
                  Material(
                    type: MaterialType.transparency,
                    child: ListenableBuilder(
                      listenable: router.routerDelegate,
                      builder: (context, _) => CustomerChatbotOverlay(
                        currentPath: router.routerDelegate.currentConfiguration
                            .uri.path,
                      ),
                    ),
                  ),
                  // Global order-progress banner (staff/customer/qr) — see
                  // OrderNotificationOverlay's doc comment.
                  Material(
                    type: MaterialType.transparency,
                    child: ListenableBuilder(
                      listenable: router.routerDelegate,
                      builder: (context, _) => OrderNotificationOverlay(
                        currentPath: router.routerDelegate.currentConfiguration
                            .uri.path,
                      ),
                    ),
                  ),
                  // Global Light/Dark/System toggle — see ThemeModeToggle's
                  // doc comment. Bottom-left so it never collides with the
                  // chatbot FABs (bottom-right) or the notification banner
                  // (top). Positioned must be a direct Stack child (unlike
                  // the other overlay widgets above, which wrap themselves
                  // in Material here since they don't return Positioned as
                  // their own root) — ThemeModeToggle owns its own Material
                  // internally instead.
                  const ThemeModeToggle(),
                ],
              ),
            ),
          ],
        ),
      ),
      localizationsDelegates: const [],
      supportedLocales: const [Locale('id'), Locale('en')],
    );
  }
}
