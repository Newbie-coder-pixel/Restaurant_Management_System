// lib/features/auth/presentation/staff_reset_password_screen.dart
// Layar untuk staff membuat password baru setelah klik link reset dari email.
// Dibuka via route /reset-password (lihat app_router.dart, redirect type=recovery).
import 'dart:js_interop';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

@JS('window.history.replaceState')
external void _replaceState(JSAny? data, String title, String url);

class StaffResetPasswordScreen extends StatefulWidget {
  const StaffResetPasswordScreen({super.key});

  @override
  State<StaffResetPasswordScreen> createState() =>
      _StaffResetPasswordScreenState();
}

class _StaffResetPasswordScreenState extends State<StaffResetPasswordScreen> {
  final _newPassCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  bool _success = false;

  @override
  void dispose() {
    _newPassCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final newPass = _newPassCtrl.text.trim();
    final confirmPass = _confirmCtrl.text.trim();

    if (newPass.isEmpty) {
      _err('Password baru wajib diisi.');
      return;
    }
    if (newPass.length < 6) {
      _err('Password minimal 6 karakter.');
      return;
    }
    if (newPass != confirmPass) {
      _err('Konfirmasi password tidak cocok.');
      return;
    }

    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: newPass),
      );
      if (mounted) setState(() => _success = true);
    } on AuthException catch (e) {
      if (mounted) _err(_translate(e.message));
    } catch (_) {
      if (mounted) _err('Gagal mereset password. Coba lagi.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _translate(String raw) {
    final msg = raw.toLowerCase();
    if (msg.contains('same password')) {
      return 'Password baru tidak boleh sama dengan password lama.';
    }
    if (msg.contains('weak password') || msg.contains('password should be')) {
      return 'Password terlalu lemah. Gunakan minimal 6 karakter.';
    }
    if (msg.contains('session') || msg.contains('expired')) {
      return 'Link sudah kedaluwarsa. Minta link reset baru dari halaman login.';
    }
    return 'Terjadi kesalahan: $raw';
  }

  void _err(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m, style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
      backgroundColor: const Color(0xFFE53935),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 5),
    ));
  }

  // Bersihkan `?type=recovery` dari URL supaya router tidak terus-terusan
  // memaksa balik ke layar ini setiap kali navigasi setelah selesai reset.
  void _goToLogin() {
    if (kIsWeb) {
      try {
        _replaceState(null, '', '/#${AppRoutes.login}');
      } catch (_) {}
    }
    context.go(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: const Text('Reset Password',
            style: TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 20)),
        automaticallyImplyLeading: false,
        leading: _success
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                onPressed: _goToLogin,
              ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: _success ? _buildSuccess() : _buildForm(),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccess() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.available.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_rounded,
                color: AppColors.available, size: 60),
          ),
          const SizedBox(height: 32),
          const Text('Password Berhasil Diubah!',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          const Text('Silakan masuk kembali dengan password baru kamu.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 14, color: AppColors.textSecondary)),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _goToLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: const Text('Ke Halaman Login',
                  style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      );

  Widget _buildForm() => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Buat Password Baru',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          const Text('Masukkan password baru untuk akun staff kamu.',
              style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 24),
          TextField(
            controller: _newPassCtrl,
            obscureText: _obscureNew,
            decoration: InputDecoration(
              labelText: 'Password Baru',
              hintText: 'Minimal 6 karakter',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscureNew ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscureNew = !_obscureNew),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _confirmCtrl,
            obscureText: _obscureConfirm,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Konfirmasi Password',
              hintText: 'Ulangi password baru',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Simpan Password Baru'),
            ),
          ),
        ],
      );
}
