import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';

class CustomerLoginScreen extends StatefulWidget {
  final VoidCallback onLoginSuccess;
  const CustomerLoginScreen({super.key, required this.onLoginSuccess});
  @override
  State<CustomerLoginScreen> createState() => _CustomerLoginScreenState();
}

class _CustomerLoginScreenState extends State<CustomerLoginScreen>
    with TickerProviderStateMixin {
  bool _loading = false;
  bool _obscure = true;
  bool _isSignUp = false;

  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  // Card fade/slide-in on first mount — a small motion touch that makes the
  // page feel alive instead of a static template.
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
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _entranceCtrl.dispose();
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
          Positioned.fill(child: _buildBackdrop()),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: _buildCard(showHeader: true, compactHeader: false),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Full-bleed photo backdrop with a warm scrim so the centered card stays
  // readable regardless of how bright/busy the photo is underneath it.
  Widget _buildBackdrop() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset('assets/images/login_background.jpg', fit: BoxFit.cover),
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

  Widget _buildCard({required bool showHeader, required bool compactHeader}) {
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
          child: _buildForm(showHeader: showHeader, compact: compactHeader),
        ),
      ),
    );
  }

  Widget _buildForm({required bool showHeader, required bool compact}) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (showHeader) ...[
        if (!compact) ...[
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
              child: const Icon(Icons.restaurant_rounded, color: Colors.white, size: 26),
            ),
          ),
          const SizedBox(height: 16),
        ],
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Column(
            key: ValueKey(_isSignUp),
            children: [
              Text(_isSignUp ? 'Create your account' : 'Welcome back',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 24,
                      fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              Text(
                _isSignUp
                    ? 'Sign up to start ordering and booking tables'
                    : 'Sign in to continue to your account',
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 13.5,
                    color: AppColors.textSecondary)),
            ],
          ),
        ),
        const SizedBox(height: 28),
      ],
      _emailForm(),
    ]);

  Widget _emailForm() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AnimatedSize(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
        alignment: Alignment.topCenter,
        child: !_isSignUp
            ? const SizedBox.shrink()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _field(
                      ctrl: _nameCtrl,
                      label: 'Full Name',
                      hint: 'Enter your full name',
                      icon: Icons.person_outline_rounded),
                  const SizedBox(height: 18),
                  _field(
                      ctrl: _phoneCtrl,
                      label: 'Phone Number',
                      hint: 'Example: 08123456789',
                      type: TextInputType.phone,
                      icon: Icons.phone_outlined),
                  const SizedBox(height: 18),
                ],
              ),
      ),
      _field(ctrl: _emailCtrl, label: 'Email Address', hint: 'Enter your email',
        type: TextInputType.emailAddress, icon: Icons.email_outlined),
      const SizedBox(height: 18),
      _field(ctrl: _passCtrl, label: 'Password', hint: 'Enter your password',
        obscure: _obscure, icon: Icons.lock_outline_rounded,
        suffix: IconButton(
          icon: Icon(_obscure
            ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            size: 20, color: AppColors.textHint),
          onPressed: () => setState(() => _obscure = !_obscure))),
      if (!_isSignUp) ...[
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: _Pressable(
            onTap: _forgotPassword,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text('Forgot password?',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                  color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
            ),
          ),
        ),
      ],
      const SizedBox(height: 24),
      _primaryBtn(
        label: _isSignUp ? 'Create Account' : 'Sign In', onTap: _submitEmail),
      const SizedBox(height: 22),
      const Row(children: [
        Expanded(child: Divider(color: AppColors.border, thickness: 1)),
        Padding(padding: EdgeInsets.symmetric(horizontal: 14),
          child: Text('or', style: TextStyle(fontFamily: 'Poppins',
            fontSize: 13, color: AppColors.textHint, fontWeight: FontWeight.w500))),
        Expanded(child: Divider(color: AppColors.border, thickness: 1)),
      ]),
      const SizedBox(height: 22),
      _outlineBtn(
        icon: SizedBox(width: 20, height: 20,
          child: CustomPaint(painter: _GoogleIconPainter())),
        label: 'Continue with Google', onTap: _signInGoogle),
      const SizedBox(height: 22),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _isSignUp ? 'Already have an account?' : 'New to Restaurant?',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 14,
              color: AppColors.textSecondary)),
          _Pressable(
            onTap: () => setState(() {
              _isSignUp = !_isSignUp;
              ScaffoldMessenger.of(context).clearSnackBars();
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                _isSignUp ? 'Sign In' : 'Create an account',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 14,
                  color: AppColors.primary, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    ]);

  Widget _field({
    required TextEditingController ctrl, required String label, required String hint,
    required IconData icon,
    TextInputType type = TextInputType.text,
    bool obscure = false, Widget? suffix,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
        fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      const SizedBox(height: 8),
      TextField(
        controller: ctrl, keyboardType: type,
        obscureText: obscure,
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

  Widget _primaryBtn({required String label, required VoidCallback onTap}) =>
    _Pressable(
      onTap: _loading ? null : onTap,
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
        child: Center(child: _loading
          ? const SizedBox(width: 22, height: 22,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: const TextStyle(fontFamily: 'Poppins',
                    color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
              ],
            ))));

  Widget _outlineBtn({
    required Widget icon, required String label, required VoidCallback onTap,
  }) => _Pressable(
    onTap: _loading ? null : onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 15),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1.5)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        icon, const SizedBox(width: 12),
        Text(label, style: const TextStyle(fontFamily: 'Poppins',
          fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      ])));
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
