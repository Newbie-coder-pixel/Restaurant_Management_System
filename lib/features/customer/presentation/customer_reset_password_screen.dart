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
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.error_outline, color: Colors.white, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(m,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, height: 1.4))),
      ]),
      backgroundColor: const Color(0xFFEF4444),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        title: const Text('Reset Password',
            style: TextStyle(
                fontFamily: 'Poppins', 
                fontWeight: FontWeight.w700,
                fontSize: 20)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => context.go('/customer'),
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
      // Animated success container
      TweenAnimationBuilder(
        duration: const Duration(milliseconds: 500),
        tween: Tween<double>(begin: 0, end: 1),
        builder: (context, double value, child) {
          return Transform.scale(
            scale: value,
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF1D9E75).withValues(alpha: 0.1),
                    const Color(0xFF1D9E75).withValues(alpha: 0.05),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1D9E75).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded,
                    color: Color(0xFF1D9E75), size: 60),
              ),
            ),
          );
        },
      ),
      const SizedBox(height: 32),
      const Text('Password Berhasil Diubah! 🎉',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A2E),
              letterSpacing: -0.5)),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1D9E75).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'Password kamu sudah diperbarui.\nSilakan masuk dengan password baru.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              color: Color(0xFF4B5563),
              height: 1.6),
        ),
      ),
      const SizedBox(height: 40),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => context.go('/customer'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFE94560),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
          child: const Text('Kembali ke Beranda',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
        ),
      ),
    ],
  );

  Widget _buildForm() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      // Enhanced Header
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF0F3460).withValues(alpha: 0.08),
              const Color(0xFF1A1A2E).withValues(alpha: 0.04),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFF0F3460).withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1A1A2E), Color(0xFF0F3460)],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F3460).withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.lock_reset_outlined,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Buat Password Baru',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E),
                      letterSpacing: -0.3)),
              SizedBox(height: 4),
              Text('Masukkan password baru kamu di bawah ini.',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      color: Color(0xFF6B7280),
                      height: 1.4)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 32),

      // Password baru with strength indicator
      _label('Password Baru', Icons.lock_outline),
      const SizedBox(height: 8),
      _field(
        ctrl: _newPassCtrl,
        hint: 'Minimal 6 karakter',
        obscure: _obscureNew,
        suffix: IconButton(
          icon: Icon(_obscureNew
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
              size: 20, color: Colors.grey.shade500),
          onPressed: () => setState(() => _obscureNew = !_obscureNew),
        ),
        onChanged: (_) => setState(() {}),
      ),
      if (_newPassCtrl.text.isNotEmpty && _newPassCtrl.text.length < 6)
        Padding(
          padding: const EdgeInsets.only(top: 8, left: 12),
          child: Row(children: [
            Icon(Icons.info_outline, size: 14, color: Colors.orange.shade600),
            const SizedBox(width: 6),
            Text('Minimal 6 karakter untuk keamanan yang lebih baik',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: Colors.orange.shade600)),
          ]),
        ),
      const SizedBox(height: 20),

      // Konfirmasi password
      _label('Konfirmasi Password', Icons.lock_outline),
      const SizedBox(height: 8),
      _field(
        ctrl: _confirmCtrl,
        hint: 'Ulangi password baru',
        obscure: _obscureConfirm,
        suffix: IconButton(
          icon: Icon(_obscureConfirm
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
              size: 20, color: Colors.grey.shade500),
          onPressed: () =>
              setState(() => _obscureConfirm = !_obscureConfirm),
        ),
      ),
      if (_confirmCtrl.text.isNotEmpty && 
          _newPassCtrl.text.isNotEmpty && 
          _newPassCtrl.text != _confirmCtrl.text)
        Padding(
          padding: const EdgeInsets.only(top: 8, left: 12),
          child: Row(children: [
            Icon(Icons.error_outline, size: 14, color: Colors.red.shade400),
            const SizedBox(width: 6),
            Text('Password tidak cocok',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: Colors.red.shade400)),
          ]),
        ),
      const SizedBox(height: 32),

      // Submit button with enhanced design
      AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        child: ElevatedButton(
          onPressed: _loading ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFE94560),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            elevation: 0,
            disabledBackgroundColor: const Color(0xFFE94560).withValues(alpha: 0.5),
          ),
          child: _loading
              ? const SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5))
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.save_outlined, size: 18),
                    SizedBox(width: 10),
                    Text('Simpan Password Baru',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
        ),
      ),
      
      const SizedBox(height: 24),
      
      // Info note
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.shade100),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Pastikan password baru kamu mudah diingat namun sulit ditebak.',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: Colors.blue.shade700,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _label(String text, IconData icon) => Row(
    children: [
      Icon(icon, size: 16, color: const Color(0xFF6B7280)),
      const SizedBox(width: 8),
      Text(text,
          style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF374151))),
    ],
  );

  Widget _field({
    required TextEditingController ctrl,
    required String hint,
    bool obscure = false,
    Widget? suffix,
    Function(String)? onChanged,
  }) =>
      TextField(
        controller: ctrl,
        obscureText: obscure,
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(
              fontFamily: 'Poppins', fontSize: 13, color: Color(0xFF9CA3AF)),
          suffixIcon: suffix,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE94560), width: 1.5)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        ),
      );
}