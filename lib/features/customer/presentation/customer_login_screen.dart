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
                    colors: [AppColors.accent, AppColors.primaryLight]),
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
                          fontSize: 12, color: Color(0xFF6B7280)),
                      hintText: 'example: name@email.com',
                      hintStyle: const TextStyle(fontFamily: 'Poppins',
                          fontSize: 13, color: Colors.grey),
                      prefixIcon: const Icon(Icons.email_outlined,
                          size: 20, color: AppColors.primaryLight),
                      filled: true,
                      fillColor: const Color(0xFFF9FAFB),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppColors.primaryLight, width: 2)),
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
                        fontSize: 14, color: Color(0xFF6B7280)))),
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
                  backgroundColor: AppColors.primaryLight,
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
    final w = MediaQuery.of(context).size.width;
    if (w >= 900) return _buildDesktop();
    if (w >= 600) return _buildTablet();
    return _buildMobile();
  }

  Widget _buildDesktop() => Scaffold(
    backgroundColor: Colors.white,
    body: Row(children: [
      Expanded(flex: 5, child: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [AppColors.accent, AppColors.primary, AppColors.primaryLight])),
        child: Stack(children: [
          Positioned.fill(child: CustomPaint(painter: _DotPatternPainter())),
          Positioned(
            top: 40,
            right: 40,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.language, color: Colors.white70, size: 16),
                  SizedBox(width: 8),
                  Text('EN', style: TextStyle(fontFamily: 'Poppins', color: Colors.white70)),
                ],
              ),
            ),
          ),
          Padding(padding: const EdgeInsets.all(60),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 52, height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.accent, AppColors.primaryLight]),
                    borderRadius: BorderRadius.circular(16)),
                  child: const Icon(Icons.restaurant, color: Colors.white, size: 28)),
                const SizedBox(width: 14),
                const Text('RestaurantOS', style: TextStyle(fontFamily: 'Poppins',
                  color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
              ]),
              const Spacer(),
              const Text('Reservations &\nOnline Ordering',
                style: TextStyle(fontFamily: 'Poppins', color: Colors.white,
                  fontSize: 54, fontWeight: FontWeight.w800, height: 1.1,
                  letterSpacing: -0.5)),
              const SizedBox(height: 24),
              const Text(
                'Enjoy the convenience of ordering food\n'
                'and reserving your favorite table\n'
                'anytime, anywhere.',
                style: TextStyle(fontFamily: 'Poppins',
                  color: Colors.white70, fontSize: 16, height: 1.7)),
              const SizedBox(height: 48),
              Wrap(spacing: 12, runSpacing: 12, children: [
                _pill('🍽️ Full menu'), _pill('📅 Easy reservations'),
                _pill('📦 Track orders'), _pill('🤖 AI Chatbot'),
                _pill('💳 Digital payments'),
              ]),
              const Spacer(),
              const Text('© 2026 RestaurantOS', style: TextStyle(
                fontFamily: 'Poppins', color: Colors.white24, fontSize: 12)),
            ])),
        ]))),
      Expanded(flex: 4, child: Container(
        color: const Color(0xFFF8F9FA),
        child: Center(child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: _buildForm()))))),
    ]));

  Widget _pill(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.white.withValues(alpha: 0.2))),
    child: Text(label, style: const TextStyle(fontFamily: 'Poppins',
      color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)));

  Widget _buildTablet() => Scaffold(
    backgroundColor: const Color(0xFFF0F2F5),
    body: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Container(
        width: 560, padding: const EdgeInsets.all(48),
        decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 60, offset: const Offset(0, 12))]),
        child: Column(children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.accent, AppColors.primaryLight]),
              borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.restaurant, color: Colors.white, size: 28)),
          const SizedBox(height: 20),
          const Text('RestaurantOS', style: TextStyle(fontFamily: 'Poppins',
            fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.primary)),
          const SizedBox(height: 32),
          _buildForm(),
        ])))));

  Widget _buildMobile() => Scaffold(
    backgroundColor: const Color(0xFFF8F9FA),
    body: SafeArea(child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 32),
      child: Column(children: [
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.accent, AppColors.primaryLight]),
            borderRadius: BorderRadius.circular(20)),
          child: const Icon(Icons.restaurant, color: Colors.white, size: 34)),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 20,
              offset: const Offset(0, 4),
            )],
          ),
          child: _buildForm(),
        ),
      ]))));

  Widget _buildForm() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Welcome', textAlign: TextAlign.center,
        style: TextStyle(fontFamily: 'Poppins', fontSize: 28,
          fontWeight: FontWeight.w800, color: AppColors.primary, letterSpacing: -0.5)),
      const SizedBox(height: 8),
      const Text('Log in to continue to your account',
        textAlign: TextAlign.center,
        style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
          color: Color(0xFF6B7280), height: 1.5)),
      const SizedBox(height: 32),
      _socialBtn(
        icon: SizedBox(width: 22, height: 22,
          child: CustomPaint(painter: _GoogleIconPainter())),
        label: 'Continue with Google', onTap: _signInGoogle),
      const SizedBox(height: 28),
      const Row(children: [
        Expanded(child: Divider(color: Color(0xFFE5E7EB), thickness: 1)),
        Padding(padding: EdgeInsets.symmetric(horizontal: 14),
          child: Text('or', style: TextStyle(fontFamily: 'Poppins',
            fontSize: 13, color: Color(0xFF9CA3AF), fontWeight: FontWeight.w500))),
        Expanded(child: Divider(color: Color(0xFFE5E7EB), thickness: 1)),
      ]),
      const SizedBox(height: 28),
      _emailForm(),
    ]);

  Widget _emailForm() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_isSignUp) ...[
        _field(ctrl: _nameCtrl, hint: 'Full name', icon: Icons.person_outline),
        const SizedBox(height: 14),
        _phoneField(),
        const SizedBox(height: 14),
      ],
      _field(ctrl: _emailCtrl, hint: 'Email Address',
        icon: Icons.email_outlined, type: TextInputType.emailAddress),
      const SizedBox(height: 14),
      _field(ctrl: _passCtrl, hint: 'Password',
        icon: Icons.lock_outline, obscure: _obscure,
        suffix: IconButton(
          icon: Icon(_obscure
            ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            size: 20, color: const Color(0xFF9CA3AF)),
          onPressed: () => setState(() => _obscure = !_obscure))),
      const SizedBox(height: 24),
      _primaryBtn(
        label: _isSignUp ? 'Create Account' : 'Log In', onTap: _submitEmail),
      const SizedBox(height: 16),
      // Forgot password — only shown in login mode
      if (!_isSignUp)
        Center(
          child: TextButton(
            onPressed: _forgotPassword,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            child: const Text('Forgot password?',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                color: AppColors.accent, fontWeight: FontWeight.w600))),
        ),
      const SizedBox(height: 8),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _isSignUp ? 'Already have an account?' : "Don't have an account?",
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 14,
              color: Color(0xFF6B7280))),
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
              _isSignUp ? 'Log In' : 'Sign Up',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 14,
                color: AppColors.primaryLight, fontWeight: FontWeight.w700))),
        ],
      ),
    ]);

  Widget _phoneField() => TextField(
    controller: _phoneCtrl,
    keyboardType: TextInputType.phone,
    style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
    decoration: InputDecoration(
      labelText: 'Phone Number',
      labelStyle: const TextStyle(fontFamily: 'Poppins',
          fontSize: 12, color: Color(0xFF6B7280)),
      hintText: 'Example: 08123456789',
      hintStyle: const TextStyle(
          fontFamily: 'Poppins', fontSize: 13, color: Color(0xFF9CA3AF)),
      prefixIcon: const Icon(Icons.phone_outlined,
          size: 20, color: AppColors.primaryLight),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 1.5)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 1.5)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primaryLight, width: 2)),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16)));

  Widget _socialBtn({
    required Widget icon, required String label, required VoidCallback onTap,
  }) => GestureDetector(
    onTap: _loading ? null : onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 8, offset: const Offset(0, 2))]),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        icon, const SizedBox(width: 12),
        Text(label, style: const TextStyle(fontFamily: 'Poppins',
          fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primary)),
      ])));

  Widget _field({
    required TextEditingController ctrl, required String hint,
    required IconData icon, TextInputType type = TextInputType.text,
    bool obscure = false, bool enabled = true, Widget? suffix,
  }) => TextField(
    controller: ctrl, keyboardType: type,
    obscureText: obscure, enabled: enabled,
    style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
    decoration: InputDecoration(
      labelText: hint,
      labelStyle: const TextStyle(fontFamily: 'Poppins',
          fontSize: 12, color: Color(0xFF6B7280)),
      prefixIcon: Icon(icon, size: 20, color: AppColors.primaryLight),
      suffixIcon: suffix,
      filled: true,
      fillColor: enabled ? Colors.white : const Color(0xFFF9FAFB),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 1.5)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 1.5)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primaryLight, width: 2)),
      disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16)));

  Widget _primaryBtn({required String label, required VoidCallback onTap}) =>
    GestureDetector(
      onTap: _loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.primaryLight]),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(
            color: AppColors.primaryLight.withValues(alpha: 0.3),
            blurRadius: 16, offset: const Offset(0, 6))]),
        child: Center(child: _loading
          ? const SizedBox(width: 24, height: 24,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
          : Text(label, style: const TextStyle(fontFamily: 'Poppins',
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700,
              letterSpacing: 0.5)))));
}

class _DotPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..style = PaintingStyle.fill;
    const spacing = 32.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 2, paint);
      }
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