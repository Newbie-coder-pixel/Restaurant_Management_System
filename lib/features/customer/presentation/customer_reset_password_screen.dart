// lib/features/customer/presentation/customer_reset_password_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CustomerResetPasswordScreen extends StatefulWidget {
  const CustomerResetPasswordScreen({super.key});

  @override
  State<CustomerResetPasswordScreen> createState() =>
      _CustomerResetPasswordScreenState();
}

class _CustomerResetPasswordScreenState
    extends State<CustomerResetPasswordScreen> {
  final _newPassCtrl    = TextEditingController();
  final _confirmCtrl    = TextEditingController();
  bool _obscureNew      = true;
  bool _obscureConfirm  = true;
  bool _loading         = false;
  bool _success         = false;

  @override
  void dispose() {
    _newPassCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final newPass     = _newPassCtrl.text.trim();
    final confirmPass = _confirmCtrl.text.trim();

    if (newPass.isEmpty) {
      _err('Password baru wajib diisi.'); return;
    }
    if (newPass.length < 6) {
      _err('Password minimal 6 karakter.'); return;
    }
    if (newPass != confirmPass) {
      _err('Konfirmasi password tidak cocok.'); return;
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
      return 'Link sudah kedaluwarsa. Minta link reset baru.';
    }
    return 'Terjadi kesalahan: $raw';
  }

  void _err(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.error_outline, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(m,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13))),
      ]),
      backgroundColor: const Color(0xFFE94560),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        title: const Text('Reset Password',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => context.go('/customer'),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
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
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF1D9E75).withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check_circle_outline,
            color: Color(0xFF1D9E75), size: 64),
      ),
      const SizedBox(height: 24),
      const Text('Password Berhasil Diubah! 🎉',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A2E))),
      const SizedBox(height: 12),
      const Text(
        'Password kamu sudah diperbarui.\nSilakan masuk dengan password baru.',
        textAlign: TextAlign.center,
        style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14,
            color: Color(0xFF6B7280),
            height: 1.6),
      ),
      const SizedBox(height: 32),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => context.go('/customer'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFE94560),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Kembali ke Beranda',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
        ),
      ),
    ],
  );

  Widget _buildForm() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      // Header
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0F3460).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0F3460).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.lock_reset_outlined,
                color: Color(0xFF0F3460), size: 28),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Buat Password Baru',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E))),
              SizedBox(height: 2),
              Text('Masukkan password baru kamu di bawah ini.',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: Color(0xFF6B7280))),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 28),

      // Password baru
      _label('Password Baru'),
      const SizedBox(height: 6),
      _field(
        ctrl: _newPassCtrl,
        hint: 'Minimal 6 karakter',
        icon: Icons.lock_outline,
        obscure: _obscureNew,
        suffix: IconButton(
          icon: Icon(_obscureNew
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
              size: 18, color: Colors.grey),
          onPressed: () => setState(() => _obscureNew = !_obscureNew),
        ),
      ),
      const SizedBox(height: 16),

      // Konfirmasi password
      _label('Konfirmasi Password'),
      const SizedBox(height: 6),
      _field(
        ctrl: _confirmCtrl,
        hint: 'Ulangi password baru',
        icon: Icons.lock_outline,
        obscure: _obscureConfirm,
        suffix: IconButton(
          icon: Icon(_obscureConfirm
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
              size: 18, color: Colors.grey),
          onPressed: () =>
              setState(() => _obscureConfirm = !_obscureConfirm),
        ),
      ),
      const SizedBox(height: 28),

      // Submit button
      GestureDetector(
        onTap: _loading ? null : _submit,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF1A1A2E), Color(0xFF0F3460)]),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(
              color: const Color(0xFF1A1A2E).withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            )],
          ),
          child: Center(
            child: _loading
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Text('Simpan Password Baru',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    ],
  );

  Widget _label(String text) => Text(text,
      style: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF374151)));

  Widget _field({
    required TextEditingController ctrl,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
  }) =>
      TextField(
        controller: ctrl,
        obscureText: obscure,
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(
              fontFamily: 'Poppins', fontSize: 13, color: Colors.grey),
          prefixIcon: Icon(icon, size: 18, color: const Color(0xFF6B7280)),
          suffixIcon: suffix,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: Color(0xFF0F3460), width: 1.5)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      );
}