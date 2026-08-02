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
      _showToast('Email and password cannot be empty', isError: true);
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
          ? '❌ Wrong email or password. Try again!'
          : error.contains('network') || error.contains('connect')
              ? '🌐 No internet connection'
              : '❌ Login failed. Check your email & password';
      _showToast(msg, isError: true);
    } else {
      // Show success briefly - router will redirect automatically
      _showToast('✅ Login successful! Loading dashboard...', isError: false);
    }
  }

  // ── Forgot Password: OTP code sent via WhatsApp (Fonnte), 2 steps
  // in 1 dialog — without opening email/clicking a link/switching pages.
  Future<void> _forgotPassword() async {
    final emailCtrl = TextEditingController(text: _emailCtrl.text.trim());
    final otpCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        int step = 1; // 1 = request code, 2 = enter code + new password
        bool sending = false;
        bool obscureNew = true;
        bool obscureConfirm = true;

        return StatefulBuilder(
          builder: (ctx, setS) {
            Future<void> requestOtp() async {
              final email = emailCtrl.text.trim();
              if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
                _showToast('Enter a valid email.', isError: true);
                return;
              }
              setS(() => sending = true);
              try {
                final response = await Supabase.instance.client.functions.invoke(
                  'staff-password-reset',
                  body: {'step': 'request', 'email': email},
                );
                final data = response.data;
                final msg = data is Map && data['message'] != null
                    ? data['message'].toString()
                    : 'If the email is registered and has a WhatsApp number, the reset code has been sent.';
                if (mounted) _showToast(msg, isError: false);
                setS(() => step = 2);
              } on FunctionException catch (e) {
                final msg = (e.details is Map ? e.details['error'] : null) ??
                    'Failed to send code. Try again.';
                if (mounted) _showToast(msg.toString(), isError: true);
              } catch (_) {
                if (mounted) _showToast('Failed to send code. Try again.', isError: true);
              } finally {
                if (ctx.mounted) setS(() => sending = false);
              }
            }

            Future<void> verifyAndReset() async {
              final otp = otpCtrl.text.trim();
              final newPass = newPassCtrl.text.trim();
              final confirmPass = confirmCtrl.text.trim();

              if (otp.length != 6) {
                _showToast('OTP code must be 6 digits.', isError: true);
                return;
              }
              if (newPass.length < 6) {
                _showToast('Password must be at least 6 characters.', isError: true);
                return;
              }
              if (newPass != confirmPass) {
                _showToast('Password confirmation does not match.', isError: true);
                return;
              }

              setS(() => sending = true);
              try {
                final response = await Supabase.instance.client.functions.invoke(
                  'staff-password-reset',
                  body: {
                    'step': 'verify',
                    'email': emailCtrl.text.trim(),
                    'otp': otp,
                    'new_password': newPass,
                  },
                );
                final data = response.data;
                if (data is Map && data['error'] != null) {
                  if (mounted) _showToast(data['error'].toString(), isError: true);
                  return;
                }
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  _showToast('Password changed successfully. Please log in.', isError: false);
                }
              } on FunctionException catch (e) {
                final msg = (e.details is Map ? e.details['error'] : null) ??
                    'Incorrect or expired code.';
                if (mounted) _showToast(msg.toString(), isError: true);
              } catch (_) {
                if (mounted) _showToast('Failed to reset password. Try again.', isError: true);
              } finally {
                if (ctx.mounted) setS(() => sending = false);
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('Forgot Password',
                  style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 18)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: step == 1
                      ? [
                          const Text(
                            'A 6-digit reset code will be sent to the WhatsApp number '
                            'registered for this staff account.',
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            autofocus: true,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                          ),
                        ]
                      : [
                          Text(
                            'Enter the code sent to WhatsApp for ${emailCtrl.text.trim()}.',
                            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: otpCtrl,
                            keyboardType: TextInputType.number,
                            autofocus: true,
                            maxLength: 6,
                            decoration: const InputDecoration(
                              labelText: 'OTP Code',
                              counterText: '',
                              prefixIcon: Icon(Icons.sms_outlined),
                            ),
                          ),
                          TextField(
                            controller: newPassCtrl,
                            obscureText: obscureNew,
                            decoration: InputDecoration(
                              labelText: 'New Password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(obscureNew ? Icons.visibility_off : Icons.visibility),
                                onPressed: () => setS(() => obscureNew = !obscureNew),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: confirmCtrl,
                            obscureText: obscureConfirm,
                            decoration: InputDecoration(
                              labelText: 'Confirm Password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(obscureConfirm ? Icons.visibility_off : Icons.visibility),
                                onPressed: () => setS(() => obscureConfirm = !obscureConfirm),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: sending ? null : () => setS(() => step = 1),
                              child: const Text('Change email / resend code',
                                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12)),
                            ),
                          ),
                        ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: sending ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: sending ? null : (step == 1 ? requestOtp : verifyAndReset),
                  child: sending
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(step == 1 ? 'Send Code' : 'Reset Password'),
                ),
              ],
            );
          },
        );
      },
    );
    emailCtrl.dispose();
    otpCtrl.dispose();
    newPassCtrl.dispose();
    confirmCtrl.dispose();
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
              Text('Loading...', style: TextStyle(color: Colors.white70, fontFamily: 'Poppins')),
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
                      const Text('Log In to Your Account',
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
                          child: const Text('Forgot Password?',
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
                              : const Text('Log In'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text('Authorized staff only',
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