// lib/features/customer/providers/customer_auth_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Current customer user (null = not logged in)
// Emit currentUser immediately as the initial value so it doesn't flash to login on refresh
final customerUserProvider = StreamProvider<User?>((ref) async* {
  // Emit the existing session FIRST before listening to the stream
  yield Supabase.instance.client.auth.currentUser;

  // Then listen for subsequent auth changes
  yield* Supabase.instance.client.auth.onAuthStateChange
      .map((e) => e.session?.user);
});

// ── Helper: whether the customer is logged in
final isCustomerLoggedInProvider = Provider<bool>((ref) {
  final asyncUser = ref.watch(customerUserProvider);
  return asyncUser.maybeWhen(data: (u) => u != null, orElse: () => false);
});