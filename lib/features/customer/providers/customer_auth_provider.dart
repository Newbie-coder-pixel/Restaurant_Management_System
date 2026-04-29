// lib/features/customer/providers/customer_auth_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Current customer user (null = belum login)
// Langsung emit currentUser sebagai nilai awal supaya tidak flash ke login saat refresh
final customerUserProvider = StreamProvider<User?>((ref) async* {
  // Emit session yang sudah ada DULU sebelum listen stream
  yield Supabase.instance.client.auth.currentUser;

  // Baru listen perubahan auth selanjutnya
  yield* Supabase.instance.client.auth.onAuthStateChange
      .map((e) => e.session?.user);
});

// ── Helper: apakah customer sudah login
final isCustomerLoggedInProvider = Provider<bool>((ref) {
  final asyncUser = ref.watch(customerUserProvider);
  return asyncUser.maybeWhen(data: (u) => u != null, orElse: () => false);
});