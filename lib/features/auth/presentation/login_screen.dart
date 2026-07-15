import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  bool _isSubmitting = false;

  Future<void> _handleLogin() async {
    if (_emailCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
      _showToast('Email dan password tidak boleh kosong', isError: true);
      return;
    }
    setState(() => _isSubmitting = true);
    final success = await ref.read(authStateProvider.notifier).signIn(
      _emailCtrl.text.trim(),
      _passCtrl.text,
    );
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    if (!success) {
      final error = ref.read(authStateProvider).error ?? '';
      final msg = error.contains('Invalid') || error.contains('credentials')
          ? '❌ Email atau password salah. Coba lagi!'
          : error.contains('network') || error.contains('connect')
              ? '🌐 Tidak ada koneksi internet'
              : '❌ Login gagal. Periksa email & password kamu';
      _showToast(msg, isError: true);
    } else {
      // Show success briefly - router will redirect automatically
      _showToast('✅ Login berhasil! Memuat dashboard...', isError: false);
    }
  }

  Future<void> _forgotPassword() async {
    final resetCtrl = TextEditingController(text: _emailCtrl.text.trim());

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        bool sending = false;
        return StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Lupa Password',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 18)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Kami akan mengirimkan link reset password ke email yang '
                  'dipakai saat akun staff ini dibuat.',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: resetCtrl,
                  keyboardType: TextInputType.emailAddress,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: sending ? null : () => Navigator.pop(ctx),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: sending
                    ? null
                    : () async {
                        final email = resetCtrl.text.trim();
                        if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
                          _showToast('Masukkan email yang valid.', isError: true);
                          return;
                        }
                        setS(() => sending = true);
                        try {
                          await Supabase.instance.client.auth.resetPasswordForEmail(
                            email,
                            redirectTo: '${Uri.base.origin}/#/reset-password',
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            _showToast(
                              'Link reset password dikirim ke $email. '
                              'Cek inbox atau folder spam.',
                              isError: false,
                            );
                          }
                        } on AuthException catch (e) {
                          if (mounted) _showToast('Gagal: ${e.message}', isError: true);
                        } catch (_) {
                          if (mounted) _showToast('Gagal mengirim email. Coba lagi.', isError: true);
                        } finally {
                          if (ctx.mounted) setS(() => sending = false);
                        }
                      },
                child: sending
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Kirim Link Reset'),
              ),
            ],
          ),
        );
      },
    );
    resetCtrl.dispose();
  }

  void _showToast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13))),
        ]),
        backgroundColor: isError ? const Color(0xFFE53935) : const Color(0xFF43A047),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    // Already logged in but staff still loading → show splash
    if (authState.isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF1A1A2E),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.restaurant_menu, size: 64, color: Colors.white),
              SizedBox(height: 24),
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text('Memuat...', style: TextStyle(color: Colors.white70, fontFamily: 'Poppins')),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.restaurant_menu, size: 44, color: Colors.white),
                ),
                const SizedBox(height: 24),
                const Text('RestaurantOS',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 28,
                    fontWeight: FontWeight.w700, color: Colors.white)),
                const SizedBox(height: 8),
                const Text('Staff Login',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 14, color: Colors.white60)),
                const SizedBox(height: 48),
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: Colors.white, borderRadius: BorderRadius.circular(20)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Masuk ke Akun Anda',
                        style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 18,
                          fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined)),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passCtrl,
                        obscureText: _obscure,
                        onSubmitted: (_) => _handleLogin(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: (_isSubmitting || authState.isLoading) ? null : _forgotPassword,
                          child: const Text('Lupa Password?',
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          onPressed: (_isSubmitting || authState.isLoading) ? null : _handleLogin,
                          child: (_isSubmitting || authState.isLoading)
                              ? const SizedBox(width: 20, height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                              : const Text('Masuk'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text('Hanya untuk staff yang berwenang',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 12, color: Colors.white38)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}