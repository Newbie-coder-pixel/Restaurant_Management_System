import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CustomerLoginScreen extends StatefulWidget {
  final VoidCallback onLoginSuccess;
  const CustomerLoginScreen({super.key, required this.onLoginSuccess});
  @override
  State<CustomerLoginScreen> createState() => _CustomerLoginScreenState();
}

class _CustomerLoginScreenState extends State<CustomerLoginScreen> {
  int  _tab     = 0;
  bool _loading = false;
  bool _obscure = true;
  bool _isSignUp = false;
  bool _otpSent  = false;

  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  final _nameCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _otpCtrl   = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose(); _passCtrl.dispose();
    _nameCtrl.dispose();  _phoneCtrl.dispose(); _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _signInGoogle() async {
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: '${Uri.base.origin}/#/customer');
    } catch (e) { _err('Login Google gagal: $e'); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _signInApple() async {
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: '${Uri.base.origin}/#/customer');
    } catch (e) { _err('Login Apple gagal: $e'); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _submitEmail() async {
    final email = _emailCtrl.text.trim();
    final pass  = _passCtrl.text.trim();
    if (email.isEmpty || pass.isEmpty) { _err('Email dan password wajib diisi'); return; }
    setState(() => _loading = true);
    try {
      if (_isSignUp) {
        await Supabase.instance.client.auth.signUp(
          email: email, password: pass,
          data: {'full_name': _nameCtrl.text.trim()});
        if (mounted) _info('Cek email untuk konfirmasi 📧');
      } else {
        final res = await Supabase.instance.client.auth
            .signInWithPassword(email: email, password: pass);
        if (mounted && res.user != null) widget.onLoginSuccess();
      }
    } on AuthException catch (e) { _err(e.message);
    } catch (_) { _err('Terjadi kesalahan, coba lagi');
    } finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _sendOtp() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) { _err('Nomor HP wajib diisi'); return; }
    final norm = phone.startsWith('0') ? '+62${phone.substring(1)}' : phone;
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.signInWithOtp(phone: norm);
      if (mounted) { setState(() => _otpSent = true); _info('OTP dikirim ke $norm'); }
    } on AuthException catch (e) { _err(e.message);
    } finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _verifyOtp() async {
    final phone = _phoneCtrl.text.trim();
    final otp   = _otpCtrl.text.trim();
    if (otp.length < 6) { _err('Masukkan 6 digit OTP'); return; }
    final norm = phone.startsWith('0') ? '+62${phone.substring(1)}' : phone;
    setState(() => _loading = true);
    try {
      final res = await Supabase.instance.client.auth
          .verifyOTP(phone: norm, token: otp, type: OtpType.sms);
      if (mounted && res.user != null) widget.onLoginSuccess();
    } on AuthException catch (e) { _err(e.message);
    } finally { if (mounted) setState(() => _loading = false); }
  }

  void _err(String m) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(m, style: const TextStyle(fontFamily: 'Poppins')),
      backgroundColor: const Color(0xFFE94560),
      behavior: SnackBarBehavior.floating));

  void _info(String m) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(m, style: const TextStyle(fontFamily: 'Poppins')),
      backgroundColor: const Color(0xFF4CAF50),
      behavior: SnackBarBehavior.floating));

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w >= 900) return _buildDesktop();
    if (w >= 600) return _buildTablet();
    return _buildMobile();
  }

  // ── DESKTOP: split 2 kolom ──────────────────────────────────
  Widget _buildDesktop() => Scaffold(
    backgroundColor: Colors.white,
    body: Row(children: [
      // Kiri: hero panel
      Expanded(flex: 5, child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF0D1B2A), Color(0xFF1A1A2E), Color(0xFF0F3460)])),
        child: Stack(children: [
          Positioned.fill(child: CustomPaint(painter: _DotPatternPainter())),
          Padding(
            padding: const EdgeInsets.all(60),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Logo bar
                Row(children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE94560), Color(0xFFFF6B6B)]),
                      borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.restaurant,
                      color: Colors.white, size: 24)),
                  const SizedBox(width: 12),
                  const Text('RestaurantOS', style: TextStyle(
                    fontFamily: 'Poppins', color: Colors.white,
                    fontSize: 20, fontWeight: FontWeight.w700)),
                ]),
                const Spacer(),
                // Headline besar
                const Text('Reservasi &\nPesanan Online',
                  style: TextStyle(fontFamily: 'Poppins',
                    color: Colors.white, fontSize: 52,
                    fontWeight: FontWeight.w800, height: 1.1)),
                const SizedBox(height: 20),
                const Text(
                  'Nikmati kemudahan memesan makanan\n'
                  'dan reservasi meja favorit kamu\n'
                  'kapan saja, di mana saja.',
                  style: TextStyle(fontFamily: 'Poppins',
                    color: Colors.white60, fontSize: 16, height: 1.7)),
                const SizedBox(height: 40),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  _pill('🍽️ Menu lengkap'),
                  _pill('📅 Reservasi mudah'),
                  _pill('📦 Lacak pesanan'),
                  _pill('🤖 AI Chatbot'),
                ]),
                const Spacer(),
                const Text('© 2026 RestaurantOS',
                  style: TextStyle(fontFamily: 'Poppins',
                    color: Colors.white24, fontSize: 12)),
              ])),
        ]))),
      // Kanan: form
      Expanded(flex: 4, child: Container(
        color: const Color(0xFFF8F9FA),
        child: Center(child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: _buildForm()))))),
    ]));

  Widget _pill(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withValues(alpha: 0.2))),
    child: Text(label, style: const TextStyle(fontFamily: 'Poppins',
      color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)));

  // ── TABLET: card putih di tengah ────────────────────────────
  Widget _buildTablet() => Scaffold(
    backgroundColor: const Color(0xFFEEF0F3),
    body: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Container(
        width: 540,
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 40, offset: const Offset(0, 8))]),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFE94560), Color(0xFFFF6B6B)]),
                borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.restaurant, color: Colors.white, size: 22)),
            const SizedBox(width: 10),
            const Text('RestaurantOS', style: TextStyle(
              fontFamily: 'Poppins', fontSize: 18,
              fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
          ]),
          const SizedBox(height: 32),
          _buildForm(),
        ])))));

  // ── MOBILE: full screen ─────────────────────────────────────
  Widget _buildMobile() => Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
      child: Column(children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFE94560), Color(0xFFFF6B6B)]),
            borderRadius: BorderRadius.circular(18)),
          child: const Icon(Icons.restaurant, color: Colors.white, size: 30)),
        const SizedBox(height: 16),
        _buildForm(),
      ]))));

  // ── FORM KONTEN ─────────────────────────────────────────────
  Widget _buildForm() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Selamat Datang 👋',
        textAlign: TextAlign.center,
        style: TextStyle(fontFamily: 'Poppins', fontSize: 24,
          fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E))),
      const SizedBox(height: 6),
      const Text('Masuk untuk melihat reservasi & riwayat pesanan',
        textAlign: TextAlign.center,
        style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
          color: Color(0xFF6B7280), height: 1.5)),
      const SizedBox(height: 28),
      _socialBtn(
        icon: SizedBox(width: 20, height: 20,
          child: CustomPaint(painter: _GoogleIconPainter())),
        label: 'Lanjutkan dengan Google', onTap: _signInGoogle),
      const SizedBox(height: 10),
      _socialBtn(
        icon: const Icon(Icons.apple, size: 20, color: Color(0xFF1A1A2E)),
        label: 'Lanjutkan dengan Apple', onTap: _signInApple),
      const SizedBox(height: 24),
      const Row(children: [
        Expanded(child: Divider(color: Color(0xFFE5E7EB))),
        Padding(padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text('atau', style: TextStyle(fontFamily: 'Poppins',
            fontSize: 12, color: Color(0xFF9CA3AF)))),
        Expanded(child: Divider(color: Color(0xFFE5E7EB))),
      ]),
      const SizedBox(height: 20),
      _buildTabSelector(),
      const SizedBox(height: 20),
      IndexedStack(index: _tab, children: [_emailForm(), _phoneForm()]),
    ]);

  Widget _buildTabSelector() => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: const Color(0xFFE5E7EB),
      borderRadius: BorderRadius.circular(10)),
    child: Row(children: [
      Expanded(child: _tabItem('Email', 0)),
      Expanded(child: _tabItem('No. HP / OTP', 1)),
    ]));

  Widget _tabItem(String label, int idx) {
    final active = _tab == idx;
    return GestureDetector(
      onTap: () => setState(() { _tab = idx; _otpSent = false; }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: active ? [BoxShadow(
            color: Colors.black.withValues(alpha: 0.06), blurRadius: 4)] : null),
        child: Text(label, textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            color: active ? const Color(0xFF1A1A2E) : const Color(0xFF6B7280)))));
  }

  Widget _emailForm() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_isSignUp) ...[
        _field(ctrl: _nameCtrl, hint: 'Nama lengkap', icon: Icons.person_outline),
        const SizedBox(height: 10),
      ],
      _field(ctrl: _emailCtrl, hint: 'Email',
        icon: Icons.email_outlined, type: TextInputType.emailAddress),
      const SizedBox(height: 10),
      _field(ctrl: _passCtrl, hint: 'Password',
        icon: Icons.lock_outline, obscure: _obscure,
        suffix: IconButton(
          icon: Icon(_obscure
            ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            size: 18, color: Colors.grey),
          onPressed: () => setState(() => _obscure = !_obscure))),
      const SizedBox(height: 18),
      _primaryBtn(label: _isSignUp ? 'Buat Akun' : 'Masuk', onTap: _submitEmail),
      const SizedBox(height: 14),
      GestureDetector(
        onTap: () => setState(() => _isSignUp = !_isSignUp),
        child: Text(
          _isSignUp ? 'Sudah punya akun? Masuk' : 'Belum punya akun? Daftar',
          textAlign: TextAlign.center,
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
            color: Color(0xFF0F3460), fontWeight: FontWeight.w500))),
    ]);

  Widget _phoneForm() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _field(ctrl: _phoneCtrl, hint: 'Nomor HP (081234567890)',
        icon: Icons.phone_outlined, type: TextInputType.phone,
        enabled: !_otpSent),
      if (_otpSent) ...[
        const SizedBox(height: 10),
        _field(ctrl: _otpCtrl, hint: '6 digit kode OTP',
          icon: Icons.security_outlined, type: TextInputType.number),
      ],
      const SizedBox(height: 18),
      _primaryBtn(
        label: _otpSent ? 'Verifikasi OTP' : 'Kirim OTP',
        onTap: _otpSent ? _verifyOtp : _sendOtp),
      if (_otpSent) ...[
        const SizedBox(height: 14),
        GestureDetector(
          onTap: () => setState(() { _otpSent = false; _otpCtrl.clear(); }),
          child: const Text('Ganti nomor / kirim ulang',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
              color: Color(0xFF0F3460), fontWeight: FontWeight.w500))),
      ],
    ]);

  Widget _socialBtn({required Widget icon, required String label, required VoidCallback onTap}) =>
    GestureDetector(
      onTap: _loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6, offset: const Offset(0, 2))]),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          icon, const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontFamily: 'Poppins',
            fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF1A1A2E))),
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
      hintText: hint,
      hintStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Colors.grey),
      prefixIcon: Icon(icon, size: 18, color: const Color(0xFF6B7280)),
      suffixIcon: suffix,
      filled: true,
      fillColor: enabled ? Colors.white : const Color(0xFFF9F9F9),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF0F3460), width: 1.5)),
      disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)));

  Widget _primaryBtn({required String label, required VoidCallback onTap}) =>
    GestureDetector(
      onTap: _loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A1A2E), Color(0xFF0F3460)]),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(
            color: const Color(0xFF1A1A2E).withValues(alpha: 0.3),
            blurRadius: 12, offset: const Offset(0, 4))]),
        child: Center(child: _loading
          ? const SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
          : Text(label, style: const TextStyle(fontFamily: 'Poppins',
              color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)))));
}

class _DotPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..style = PaintingStyle.fill;
    const spacing = 28.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.5, paint);
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
        Paint()..color = color..strokeWidth = 3..style = PaintingStyle.stroke);
    }
  }
  @override bool shouldRepaint(_) => false;
}