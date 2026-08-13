import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import '../providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with TickerProviderStateMixin {
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool _obscure = true;

  // Card fade/slide-in on first mount, matching the customer login screen.
  late final AnimationController _entranceCtrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 650));
    _fade = CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOutCubic));
    _entranceCtrl.forward();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _entranceCtrl.dispose();
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

  // Full-bleed photo backdrop with a warm scrim, matching the customer
  // login screen so both apps share the same modern look.
  Widget _buildBackdrop() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset('assets/images/staff_login_background.jpg', fit: BoxFit.cover),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.primary.withValues(alpha: 0.55),
                Colors.black.withValues(alpha: 0.45),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _field({
    required TextEditingController ctrl, required String label, required String hint,
    required IconData icon,
    TextInputType type = TextInputType.text,
    bool obscure = false, Widget? suffix,
    ValueChanged<String>? onSubmitted,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
        fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      const SizedBox(height: 8),
      TextField(
        controller: ctrl, keyboardType: type,
        obscureText: obscure,
        onSubmitted: onSubmitted,
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 15,
          color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 14,
            color: AppColors.textHint),
          prefixIcon: Icon(icon, size: 20, color: AppColors.textSecondary),
          suffixIcon: suffix,
          filled: true,
          fillColor: AppColors.surfaceVariant,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.8)),
        ),
      ),
    ]);

  Widget _buildAuthCard(BuildContext context, AuthState authState) {
    final loading = _isSubmitting || authState.isLoading;
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Container(
          padding: const EdgeInsets.fromLTRB(32, 40, 32, 32),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.08),
                blurRadius: 40,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 56, height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.accent],
                        begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.restaurant_menu_rounded, color: Colors.white, size: 26),
                ),
              ),
              const SizedBox(height: 16),
              const Text('RestaurantOS',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 24,
                      fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              const Text('Sign in to manage your branch',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 13.5,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 28),
              _field(ctrl: _emailCtrl, label: 'Email Address', hint: 'Enter your staff email',
                type: TextInputType.emailAddress, icon: Icons.email_outlined),
              const SizedBox(height: 18),
              _field(ctrl: _passCtrl, label: 'Password', hint: 'Enter your password',
                obscure: _obscure, icon: Icons.lock_outline_rounded,
                onSubmitted: (_) => _handleLogin(),
                suffix: IconButton(
                  icon: Icon(_obscure
                    ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    size: 20, color: AppColors.textHint),
                  onPressed: () => setState(() => _obscure = !_obscure))),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: _Pressable(
                  onTap: loading ? null : _forgotPassword,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text('Forgot password?',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                        color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _Pressable(
                onTap: loading ? null : _handleLogin,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.accent],
                        begin: Alignment.centerLeft, end: Alignment.centerRight),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.35),
                          blurRadius: 16, offset: const Offset(0, 8)),
                    ],
                  ),
                  child: Center(child: loading
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                    : const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Sign In', style: TextStyle(fontFamily: 'Poppins',
                              color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                        ],
                      ))),
              ),
              const SizedBox(height: 20),
              const Text('Authorized staff only',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: AppColors.textHint)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    // Already logged in but staff still loading → show splash
    if (authState.isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.primary,
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
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(child: _buildBackdrop()),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: _buildAuthCard(context, authState),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Tap-scale wrapper used by every button/link on this screen for a snappier,
// more tactile feel than a bare GestureDetector.
class _Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _Pressable({required this.child, required this.onTap});

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _pressed = true),
      onTapUp: widget.onTap == null ? null : (_) => setState(() => _pressed = false),
      onTapCancel: widget.onTap == null ? null : () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: widget.child,
      ),
    );
  }
}