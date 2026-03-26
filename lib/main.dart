import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/config/app_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
    realtimeClientOptions: const RealtimeClientOptions(
      eventsPerSecond: 40,
    ),
  );

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
      // FIX 1: fontFamilyFallback agar emoji (👋 🍽️ dll) bisa dirender
      // tanpa perlu download font tambahan — pakai emoji font bawaan OS
      theme: AppTheme.lightTheme.copyWith(
        textTheme: AppTheme.lightTheme.textTheme.apply(
          fontFamilyFallback: const [
            'Apple Color Emoji',   // iOS / macOS
            'Noto Color Emoji',    // Android
            'Segoe UI Emoji',      // Windows
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
      localizationsDelegates: const [],
      supportedLocales: const [
        Locale('id'),
        Locale('en'),
      ],
    );
  }
}