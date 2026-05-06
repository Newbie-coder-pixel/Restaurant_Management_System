import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import '../../../shared/models/staff_model.dart';

class AuthState {
  final StaffMember? staff;
  final bool isLoading;
  final String? error;

  const AuthState({this.staff, this.isLoading = false, this.error});

  AuthState copyWith({StaffMember? staff, bool? isLoading, String? error}) =>
    AuthState(
      staff: staff ?? this.staff,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState(isLoading: true)) {
    _init();
  }

  StreamSubscription<dynamic>? _authSub;

  Future<void> _init() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      await _fetchStaff(user.id);
    } else {
      if (mounted) state = const AuthState();
    }
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((event) async {
      if (!mounted) return;
      final u = event.session?.user;
      if (u != null) {
        await _fetchStaff(u.id);
      } else {
        if (mounted) state = const AuthState();
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  // Hanya satu definisi _fetchStaff — versi lengkap dengan login history
  Future<void> _fetchStaff(String userId) async {
    if (!mounted) return;
    state = state.copyWith(isLoading: true);
    try {
      final res = await Supabase.instance.client
          .from('staff')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      if (!mounted) return;
      if (res != null) {
        final staff = StaffMember.fromJson(res);
        state = AuthState(staff: staff);
        // Catat login history — fire and forget, tidak boleh block auth
        _insertLoginHistory(staff);
      } else {
        state = const AuthState(error: 'Staff tidak ditemukan');
      }
    } catch (e) {
      if (mounted) state = AuthState(error: e.toString());
    }
  }

  // Insert login history tanpa throw — gagal insert tidak ganggu login
  Future<void> _insertLoginHistory(StaffMember staff) async {
    if (staff.branchId == null) return;
    try {
      await Supabase.instance.client
          .from('staff_login_history')
          .insert({
            'staff_id':     staff.id,
            'branch_id':    staff.branchId,
            'logged_in_at': DateTime.now().toUtc().toIso8601String(),
          });
    } catch (_) {
      // Gagal insert history tidak perlu ditampilkan ke user
    }
  }

  Future<bool> signIn(String email, String password) async {
    if (!mounted) return false;
    state = state.copyWith(isLoading: true);
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: email, password: password);
      return true;
    } catch (e) {
      if (mounted) state = AuthState(error: e.toString());
      return false;
    }
  }

  Future<void> signOut() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) state = const AuthState();
  }
}

final authStateProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) => AuthNotifier());

final currentStaffProvider = Provider<StaffMember?>((ref) {
  return ref.watch(authStateProvider).staff;
});

final currentBranchIdProvider = Provider<String?>((ref) {
  return ref.watch(currentStaffProvider)?.branchId;
});