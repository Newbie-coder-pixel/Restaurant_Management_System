import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';

class CustomerLoginScreen extends StatefulWidget {
  final VoidCallback onLoginSuccess;
  const CustomerLoginScreen({super.key, required this.onLoginSuccess});
  @override
  State<CustomerLoginScreen> createState() => _CustomerLoginScreenState();
}

class _CustomerLoginScreenState extends State<CustomerLoginScreen> {
  bool _loading = false;
  bool _obscure = true;
  bool _isSignUp = false;

  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  // ─── Translate Supabase errors → English ──────────────
  String _translateAuthError(String raw) {
    final msg = raw.toLowerCase();

    // Signup
    if (msg.contains('user already registered') ||
        msg.contains('email already') ||
        msg.contains('already been registered')) {
      return 'This email is already registered. Please log in or use another email.';
    }
    // Login
    if (msg.contains('invalid login credentials') ||
        msg.contains('invalid credentials') ||
        msg.contains('wrong password')) {
      return 'Incorrect email or password. Please check and try again.';
    }
    if (msg.contains('email not confirmed')) {
      return 'Email not confirmed yet. Check your inbox and click the verification link.';
    }
    if (msg.contains('too many requests') || msg.contains('rate limit')) {
      return 'Too many attempts. Please wait a few minutes and try again.';
    }
    // Password
    if (msg.contains('password should be') ||
        msg.contains('password must be') ||
        msg.contains('weak password')) {
      return 'Password is too weak. Use at least 6 characters.';
    }
    // Email format
    if (msg.contains('unable to validate email') ||
        msg.contains('invalid email')) {
      return 'Invalid email format. Please check your email address.';
    }
    // OTP
    if (msg.contains('token has expired') || msg.contains('otp expired')) {
      return 'The OTP code has expired. Please request a new code.';
    }
    if (msg.contains('token is invalid') ||
        msg.contains('invalid otp') ||
        msg.contains('invalid token')) {
      return 'Incorrect OTP code. Please check the code sent to your phone.';
    }
    if (msg.contains('phone') && msg.contains('already')) {
      return 'This phone number is already registered.';
    }
    // Network
    if (msg.contains('network') ||
        msg.contains('connection') ||
        msg.contains('timeout')) {
      return 'Connection problem. Check your internet and try again.';
    }
    if (msg.contains('server error') || msg.contains('500')) {
      return 'The server is having issues. Please try again shortly.';
    }
    // Fallback
    return 'An error occurred: $raw';
  }

  // ─── AUTH METHODS ──────────────────────────────────────────────
  Future<void> _signInGoogle() async {
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: '${Uri.base.origin}/#/customer',
      );
    } on AuthException catch (e) {
      _err(_translateAuthError(e.message));
    } catch (_) {
      _err('Google login failed. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitEmail() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();

    // Local validation before hitting the API
    if (_isSignUp && _nameCtrl.text.trim().isEmpty) {
      _err('Full name is required.');
      return;
    }
    if (_isSignUp) {
      final phone = _phoneCtrl.text.trim();
      if (phone.isEmpty) {
        _err('Phone number is required.');
        return;
      }
      // Validate Indonesian number format: 08xx / +628xx / 628xx
      final phoneRegex = RegExp(r'^(\+62|62|0)8[0-9]{8,11}$');
      if (!phoneRegex.hasMatch(phone.replaceAll(RegExp(r'\s|-'), ''))) {
        _err('Invalid phone number format. Example: 08123456789 or +6281234567890');
        return;
      }
    }
    if (email.isEmpty) {
      _err('Email is required.');
      return;
    }
    // Basic email format validation
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$',
    );
    if (!emailRegex.hasMatch(email)) {
      _err('Invalid email format. Example: name@gmail.com');
      return;
    }
    if (pass.isEmpty) {
      _err('Password is required.');
      return;
    }
    if (pass.length < 6) {
      _err('Password must be at least 6 characters.');
      return;
    }

    setState(() => _loading = true);
    try {
      if (_isSignUp) {
        // Normalize the phone number to +62 format
        String phone = _phoneCtrl.text.trim().replaceAll(RegExp(r'\s|-'), '');
        if (phone.startsWith('0')) phone = '+62${phone.substring(1)}';
        if (phone.startsWith('62') && !phone.startsWith('+')) phone = '+$phone';

        final res = await Supabase.instance.client.auth.signUp(
          email: email,
          password: pass,
          data: {
            'full_name': _nameCtrl.text.trim(),
            'phone_number': phone,
          },
        );
        // Save the phone number to the profiles table / update user if it already exists
        if (res.user != null) {
          try {
            await Supabase.instance.client
                .from('customers')
                .upsert({
                  'id': res.user!.id,
                  'full_name': _nameCtrl.text.trim(),
                  'phone_number': phone,
                  'email': email,
                  'created_at': DateTime.now().toIso8601String(),
                }, onConflict: 'id');
          } catch (_) {
            // The customers table might not exist yet; the number is still saved in auth metadata
          }
        }
        if (mounted) {
          _info('Account created successfully! Check your email to confirm. 📧');
        }
      } else {
        final res = await Supabase.instance.client.auth
            .signInWithPassword(email: email, password: pass);
        if (mounted && res.user != null) widget.onLoginSuccess();
      }
    } on AuthException catch (e) {
      if (mounted) _err(_translateAuthError(e.message));
    } catch (_) {
      if (mounted) _err('An error occurred. Check your internet connection.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─── FORGOT PASSWORD ─────────────────────────────────────────
  Future<void> _forgotPassword() async {
    final resetCtrl = TextEditingController(text: _emailCtrl.text.trim());

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        bool sending = false;
        return StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24)),
            title: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.accent, AppColors.primary]),
                  borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.lock_reset_outlined,
                    color: Colors.white, size: 22)),
              const SizedBox(width: 12),
              const Text('Forgot Password',
                  style: TextStyle(fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700, fontSize: 18)),
            ]),
            content: Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: Color(0xFFD97706), size: 20),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'We will send a password reset link to your email',
                            style: TextStyle(fontFamily: 'Poppins',
                                fontSize: 12, color: Color(0xFF92400E)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: resetCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autofocus: true,
                    style: const TextStyle(
                        fontFamily: 'Poppins', fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Email Address',
                      labelStyle: const TextStyle(fontFamily: 'Poppins',
                          fontSize: 12, color: AppColors.textSecondary),
                      hintText: 'example: name@email.com',
                      hintStyle: const TextStyle(fontFamily: 'Poppins',
                          fontSize: 13, color: AppColors.textHint),
                      prefixIcon: const Icon(Icons.email_outlined,
                          size: 20, color: AppColors.primary),
                      filled: true,
                      fillColor: AppColors.surfaceVariant,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppColors.primary, width: 2)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 16)),
                  ),
                ]),
            actions: [
              TextButton(
                onPressed: sending ? null : () => Navigator.pop(ctx),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                child: const Text('Cancel',
                    style: TextStyle(fontFamily: 'Poppins',
                        fontSize: 14, color: AppColors.textSecondary))),
              ElevatedButton(
                onPressed: sending
                    ? null
                    : () async {
                        final email = resetCtrl.text.trim();
                        if (email.isEmpty ||
                            !email.contains('@') ||
                            !email.contains('.')) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Enter a valid email.',
                                  style: TextStyle(fontFamily: 'Poppins')),
                              backgroundColor: AppColors.accent,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ));
                          return;
                        }
                        setS(() => sending = true);
                        try {
                          await Supabase.instance.client.auth
                              .resetPasswordForEmail(
                            email,
                            redirectTo:
                                '${Uri.base.origin}/#/customer/reset-password',
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            _info(
                              'Password reset link sent to $email. '
                              'Check your inbox or spam folder. 📧');
                          }
                        } on AuthException catch (e) {
                          if (mounted) {
                            _err(_translateAuthError(e.message));
                          }
                        } catch (_) {
                          if (mounted) {
                            _err('Failed to send email. Please try again.');
                          }
                        } finally {
                          if (ctx.mounted) setS(() => sending = false);
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12)),
                child: sending
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Send Reset Link',
                        style: TextStyle(fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600, fontSize: 14)),
              ),
            ],
          ),
        );
      },
    );
    resetCtrl.dispose();
  }

  // ─── SNACKBARS ─────────────────────────────────────────────────
  void _err(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.error_outline, color: Colors.white, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(m, style: const TextStyle(
          fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w500))),
      ]),
      backgroundColor: AppColors.accent,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  void _info(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(m, style: const TextStyle(
          fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w500))),
      ]),
      backgroundColor: const Color(0xFF10B981),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  // ─── BUILD ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _StripeBackgroundPainter())),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(32, 40, 32, 32),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: _buildForm(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Stack(
        alignment: Alignment.topRight,
        children: [
          Column(
            children: [
              const Text('Cita Rasa', textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 40,
                  fontWeight: FontWeight.w800, color: AppColors.primary,
                  letterSpacing: -0.5)),
              const SizedBox(height: 6),
              Text(_isSignUp ? 'Create your account' : 'Modern Indonesian Heritage',
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 15,
                  fontStyle: FontStyle.italic, color: AppColors.textSecondary)),
            ],
          ),
          const Icon(Icons.star_rounded, color: AppColors.border, size: 22),
        ],
      ),
      const SizedBox(height: 32),
      _emailForm(),
    ]);

  Widget _emailForm() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_isSignUp) ...[
        _field(ctrl: _nameCtrl, label: 'Full Name', hint: 'Enter your full name'),
        const SizedBox(height: 20),
        _field(ctrl: _phoneCtrl, label: 'Phone Number', hint: 'Example: 08123456789',
          type: TextInputType.phone),
        const SizedBox(height: 20),
      ],
      _field(ctrl: _emailCtrl, label: 'Email Address', hint: 'Enter your email',
        type: TextInputType.emailAddress),
      const SizedBox(height: 20),
      _field(ctrl: _passCtrl, label: 'Password', hint: 'Enter your password',
        obscure: _obscure,
        suffix: IconButton(
          icon: Icon(_obscure
            ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            size: 20, color: AppColors.textHint),
          onPressed: () => setState(() => _obscure = !_obscure))),
      if (!_isSignUp) ...[
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _forgotPassword,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Forgot password?',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                color: AppColors.textSecondary, fontWeight: FontWeight.w500))),
        ),
      ],
      const SizedBox(height: 28),
      _primaryBtn(
        label: _isSignUp ? 'Create Account' : 'Sign In', onTap: _submitEmail),
      const SizedBox(height: 24),
      const Row(children: [
        Expanded(child: Divider(color: AppColors.border, thickness: 1)),
        Padding(padding: EdgeInsets.symmetric(horizontal: 14),
          child: Text('or', style: TextStyle(fontFamily: 'Poppins',
            fontSize: 13, color: AppColors.textHint, fontWeight: FontWeight.w500))),
        Expanded(child: Divider(color: AppColors.border, thickness: 1)),
      ]),
      const SizedBox(height: 24),
      _outlineBtn(
        icon: SizedBox(width: 20, height: 20,
          child: CustomPaint(painter: _GoogleIconPainter())),
        label: 'Continue with Google', onTap: _signInGoogle),
      const SizedBox(height: 24),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _isSignUp ? 'Already have an account?' : 'New to Cita Rasa?',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 14,
              color: AppColors.textSecondary)),
          TextButton(
            onPressed: () => setState(() {
              _isSignUp = !_isSignUp;
              ScaffoldMessenger.of(context).clearSnackBars();
            }),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
            ),
            child: Text(
              _isSignUp ? 'Sign In' : 'Create an account',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 14,
                color: AppColors.primary, fontWeight: FontWeight.w700))),
        ],
      ),
    ]);

  Widget _field({
    required TextEditingController ctrl, required String label, required String hint,
    TextInputType type = TextInputType.text,
    bool obscure = false, Widget? suffix,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontFamily: 'Poppins', fontSize: 14,
        fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      const SizedBox(height: 8),
      TextField(
        controller: ctrl, keyboardType: type,
        obscureText: obscure,
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 15,
          color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 15,
            color: AppColors.textHint),
          suffixIcon: suffix,
          filled: true,
          fillColor: AppColors.surfaceVariant,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(color: AppColors.border, width: 1.5)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(color: AppColors.border, width: 1.5)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
        ),
      ),
    ]);

  Widget _primaryBtn({required String label, required VoidCallback onTap}) =>
    GestureDetector(
      onTap: _loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(child: _loading
          ? const SizedBox(width: 22, height: 22,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
          : Text(label, style: const TextStyle(fontFamily: 'Poppins',
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)))));

  Widget _outlineBtn({
    required Widget icon, required String label, required VoidCallback onTap,
  }) => GestureDetector(
    onTap: _loading ? null : onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 15),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.border, width: 1.5)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        icon, const SizedBox(width: 12),
        Text(label, style: const TextStyle(fontFamily: 'Poppins',
          fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primary)),
      ])));
}

class _StripeBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.footerBackground.withValues(alpha: 0.35);
    const stripeHeight = 6.0;
    const gap = 20.0;
    for (double y = 0; y < size.height; y += stripeHeight + gap) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, stripeHeight), paint);
    }
  }
  @override bool shouldRepaint(_) => false;
}

class _GoogleIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    for (final (color, start, sweep) in [
      (const Color(0xFF4285F4), -1.57, 3.14),
      (const Color(0xFFEA4335),  1.57, 1.57),
      (const Color(0xFF34A853),  3.14, 0.80),
      (const Color(0xFFFBBC05), -0.77, 0.80),
    ]) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), start, sweep, false,
        Paint()..color = color..strokeWidth = 3.5..style = PaintingStyle.stroke);
    }
  }
  @override bool shouldRepaint(_) => false;
}
