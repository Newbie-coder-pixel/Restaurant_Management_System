import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  // ─── Terjemahan error Supabase → Bahasa Indonesia ──────────────
  String _translateAuthError(String raw) {
    final msg = raw.toLowerCase();

    // Signup
    if (msg.contains('user already registered') ||
        msg.contains('email already') ||
        msg.contains('already been registered')) {
      return 'Email ini sudah terdaftar. Silakan masuk atau gunakan email lain.';
    }
    // Login
    if (msg.contains('invalid login credentials') ||
        msg.contains('invalid credentials') ||
        msg.contains('wrong password')) {
      return 'Email atau password salah. Periksa kembali dan coba lagi.';
    }
    if (msg.contains('email not confirmed')) {
      return 'Email belum dikonfirmasi. Cek inbox kamu dan klik link verifikasi.';
    }
    if (msg.contains('too many requests') || msg.contains('rate limit')) {
      return 'Terlalu banyak percobaan. Tunggu beberapa menit lalu coba lagi.';
    }
    // Password
    if (msg.contains('password should be') ||
        msg.contains('password must be') ||
        msg.contains('weak password')) {
      return 'Password terlalu lemah. Gunakan minimal 6 karakter.';
    }
    // Email format
    if (msg.contains('unable to validate email') ||
        msg.contains('invalid email')) {
      return 'Format email tidak valid. Periksa kembali alamat emailmu.';
    }
    // OTP
    if (msg.contains('token has expired') || msg.contains('otp expired')) {
      return 'Kode OTP sudah kedaluwarsa. Minta kode baru.';
    }
    if (msg.contains('token is invalid') ||
        msg.contains('invalid otp') ||
        msg.contains('invalid token')) {
      return 'Kode OTP salah. Periksa kembali kode yang dikirim ke HP kamu.';
    }
    if (msg.contains('phone') && msg.contains('already')) {
      return 'Nomor HP ini sudah terdaftar.';
    }
    // Network
    if (msg.contains('network') ||
        msg.contains('connection') ||
        msg.contains('timeout')) {
      return 'Koneksi bermasalah. Periksa internet kamu dan coba lagi.';
    }
    if (msg.contains('server error') || msg.contains('500')) {
      return 'Server sedang bermasalah. Coba lagi dalam beberapa saat.';
    }
    // Fallback
    return 'Terjadi kesalahan: $raw';
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
      _err('Login Google gagal. Coba lagi.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitEmail() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();

    // Validasi lokal sebelum hit API
    if (_isSignUp && _nameCtrl.text.trim().isEmpty) {
      _err('Nama lengkap wajib diisi.');
      return;
    }
    if (_isSignUp) {
      final phone = _phoneCtrl.text.trim();
      if (phone.isEmpty) {
        _err('Nomor telepon wajib diisi.');
        return;
      }
      // Validasi format nomor Indonesia: 08xx / +628xx / 628xx
      final phoneRegex = RegExp(r'^(\+62|62|0)8[0-9]{8,11}$');
      if (!phoneRegex.hasMatch(phone.replaceAll(RegExp(r'\s|-'), ''))) {
        _err('Format nomor telepon tidak valid. Contoh: 08123456789 atau +6281234567890');
        return;
      }
    }
    if (email.isEmpty) {
      _err('Email wajib diisi.');
      return;
    }
    // Validasi format email dasar
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$',
    );
    if (!emailRegex.hasMatch(email)) {
      _err('Format email tidak valid. Contoh: nama@gmail.com');
      return;
    }
    // Whitelist domain email valid — komprehensif berdasarkan data global & Indonesia
    final domain = email.split('@').last.toLowerCase();
    const validDomains = {
      // ── Google ─────────────────────────────────────────────
      'gmail.com',
      'googlemail.com',
      // ── Microsoft ──────────────────────────────────────────
      'outlook.com',
      'outlook.co.id',
      'outlook.co.uk',
      'outlook.de',
      'outlook.fr',
      'outlook.it',
      'outlook.jp',
      'outlook.com.au',
      'hotmail.com',
      'hotmail.co.uk',
      'hotmail.co.id',
      'hotmail.fr',
      'hotmail.it',
      'hotmail.de',
      'hotmail.es',
      'hotmail.com.ar',
      'hotmail.com.br',
      'hotmail.com.au',
      'hotmail.be',
      'hotmail.nl',
      'live.com',
      'live.co.uk',
      'live.com.au',
      'live.nl',
      'live.fr',
      'live.de',
      'live.it',
      'live.be',
      'live.co.za',
      'msn.com',
      // ── Yahoo ──────────────────────────────────────────────
      'yahoo.com',
      'yahoo.co.id',
      'yahoo.co.uk',
      'yahoo.co.in',
      'yahoo.co.jp',
      'yahoo.co.au',
      'yahoo.com.ar',
      'yahoo.com.br',
      'yahoo.com.mx',
      'yahoo.com.ph',
      'yahoo.com.sg',
      'yahoo.fr',
      'yahoo.de',
      'yahoo.it',
      'yahoo.es',
      'yahoo.ca',
      'yahoo.gr',
      'ymail.com',
      'rocketmail.com',
      // ── Apple ──────────────────────────────────────────────
      'icloud.com',
      'me.com',
      'mac.com',
      // ── Privacy / Secure ───────────────────────────────────
      'protonmail.com',
      'proton.me',
      'pm.me',
      'tutanota.com',
      'tuta.io',
      'tutamail.com',
      'fastmail.com',
      'fastmail.fm',
      'hey.com',
      // ── Global lainnya ─────────────────────────────────────
      'aol.com',
      'aim.com',
      'zoho.com',
      'zohomail.com',
      'mail.com',
      'email.com',
      'post.com',
      'usa.com',
      'gmx.com',
      'gmx.net',
      'gmx.de',
      'gmx.us',
      'gmx.at',
      'gmx.ch',
      'web.de',
      'freenet.de',
      't-online.de',
      '1und1.de',
      'yandex.com',
      'yandex.ru',
      'mail.ru',
      'inbox.ru',
      'bk.ru',
      'list.ru',
      'internet.ru',
      'rediffmail.com',
      // ── Asia Pasifik ───────────────────────────────────────
      '163.com',
      '126.com',
      'qq.com',
      'sina.com',
      'sina.cn',
      'naver.com',
      'daum.net',
      'hanmail.net',
      'wp.pl',
      'o2.pl',
      'interia.pl',
      // ── ISP / Telecom global ───────────────────────────────
      'comcast.net',
      'att.net',
      'sbcglobal.net',
      'verizon.net',
      'bellsouth.net',
      'cox.net',
      'charter.net',
      'earthlink.net',
      'roadrunner.com',
      'optonline.net',
      'btinternet.com',
      'virginmedia.com',
      'sky.com',
      'orange.fr',
      'sfr.fr',
      'free.fr',
      'laposte.net',
      'libero.it',
      'virgilio.it',
      'tin.it',
      'alice.it',
      'terra.com.br',
      'bol.com.br',
      'uol.com.br',
      'ig.com.br',
      'telenet.be',
      'skynet.be',
      // ── Indonesia — domain resmi ───────────────────────────
      'go.id',
      'ac.id',
      'sch.id',
      'co.id',
      'net.id',
      'or.id',
      'web.id',
      'my.id',
      'biz.id',
      'mil.id',
      'desa.id',
      // ── Indonesia — universitas negeri ─────────────────────
      'ui.ac.id',
      'student.ui.ac.id',
      'ugm.ac.id',
      'mail.ugm.ac.id',
      'itb.ac.id',
      'student.itb.ac.id',
      'its.ac.id',
      'student.its.ac.id',
      'unair.ac.id',
      'student.unair.ac.id',
      'ipb.ac.id',
      'apps.ipb.ac.id',
      'undip.ac.id',
      'student.undip.ac.id',
      'apps.undip.ac.id',
      'upi.edu',
      'student.upi.edu',
      'uny.ac.id',
      'student.uny.ac.id',
      'unhas.ac.id',
      'uns.ac.id',
      'student.uns.ac.id',
      'unpad.ac.id',
      'student.unpad.ac.id',
      'ub.ac.id',
      'student.ub.ac.id',
      'unibraw.ac.id',
      'unila.ac.id',
      'unsri.ac.id',
      'unram.ac.id',
      'unud.ac.id',
      'undiksha.ac.id',
      'unmul.ac.id',
      'untan.ac.id',
      // ── Indonesia — universitas swasta ─────────────────────
      'binus.ac.id',
      'binus.edu',
      'student.binus.ac.id',
      'gunadarma.ac.id',
      'student.gunadarma.ac.id',
      'trisakti.ac.id',
      'atmajaya.ac.id',
      'uajy.ac.id',
      'atma.ac.id',
      'president.ac.id',
      'student.president.ac.id',
      'umn.ac.id',
      'student.umn.ac.id',
      'mercubuana.ac.id',
      'student.mercubuana.ac.id',
      'uii.ac.id',
      'students.uii.ac.id',
      'unika.ac.id',
      'uph.edu',
      'untar.ac.id',
      'petra.ac.id',
      'student.petra.ac.id',
      'ubaya.ac.id',
      'umm.ac.id',
      'stiki.ac.id',
      'isbi.ac.id',
      'isi.ac.id',
      // ── Indonesia — politeknik & sekolah tinggi ────────────
      'polinema.ac.id',
      'pens.ac.id',
      'tel.ac.id',
      'student.tel.ac.id',
      'poliban.ac.id',
      'polmed.ac.id',
      'poltekkes-denpasar.ac.id',
    };

    // Cek exact domain ATAU suffix (misal: staff.ui.ac.id → valid karena berakhir .ui.ac.id)
    final isValid = validDomains.contains(domain) ||
        validDomains.any((d) => domain.endsWith('.$d'));
    if (!isValid) {
      _err('Domain email tidak dikenali. Gunakan email dari provider resmi (Gmail, Yahoo, Outlook, iCloud, dll) atau email institusi (.ac.id / .go.id).');
      return;
    }
    if (pass.isEmpty) {
      _err('Password wajib diisi.');
      return;
    }
    if (pass.length < 6) {
      _err('Password minimal 6 karakter.');
      return;
    }

    setState(() => _loading = true);
    try {
      if (_isSignUp) {
        // Normalisasi nomor telepon ke format +62
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
        // Simpan nomor telepon ke tabel profiles / update user jika sudah ada
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
            // Tabel customers mungkin belum ada, nomor tetap tersimpan di auth metadata
          }
        }
        if (mounted) {
          _info('Akun berhasil dibuat! Cek email untuk konfirmasi. 📧');
        }
      } else {
        final res = await Supabase.instance.client.auth
            .signInWithPassword(email: email, password: pass);
        if (mounted && res.user != null) widget.onLoginSuccess();
      }
    } on AuthException catch (e) {
      if (mounted) _err(_translateAuthError(e.message));
    } catch (_) {
      if (mounted) _err('Terjadi kesalahan. Periksa koneksi internet kamu.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─── FORGOT PASSWORD ───────────────────────────────────────────
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
                    colors: [Color(0xFFE94560), Color(0xFFFF6B6B)]),
                  borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.lock_reset_outlined,
                    color: Colors.white, size: 22)),
              const SizedBox(width: 12),
              const Text('Lupa Password',
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
                            'Kami akan mengirimkan link reset password ke email Anda',
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
                      labelText: 'Alamat Email',
                      labelStyle: const TextStyle(fontFamily: 'Poppins',
                          fontSize: 12, color: Color(0xFF6B7280)),
                      hintText: 'contoh: nama@email.com',
                      hintStyle: const TextStyle(fontFamily: 'Poppins',
                          fontSize: 13, color: Colors.grey),
                      prefixIcon: const Icon(Icons.email_outlined,
                          size: 20, color: Color(0xFF0F3460)),
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
                          borderSide: const BorderSide(color: Color(0xFF0F3460), width: 2)),
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
                child: const Text('Batal',
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
                              content: const Text('Masukkan email yang valid.',
                                  style: TextStyle(fontFamily: 'Poppins')),
                              backgroundColor: const Color(0xFFE94560),
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
                              'Link reset password dikirim ke $email. '
                              'Cek inbox atau folder spam kamu. 📧');
                          }
                        } on AuthException catch (e) {
                          if (mounted) {
                            _err(_translateAuthError(e.message));
                          }
                        } catch (_) {
                          if (mounted) {
                            _err('Gagal mengirim email. Coba lagi.');
                          }
                        } finally {
                          if (ctx.mounted) setS(() => sending = false);
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F3460),
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
                    : const Text('Kirim Link Reset',
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
      backgroundColor: const Color(0xFFE94560),
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
          colors: [Color(0xFF0D1B2A), Color(0xFF1A1A2E), Color(0xFF0F3460)])),
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
                  Text('ID', style: TextStyle(fontFamily: 'Poppins', color: Colors.white70)),
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
                      colors: [Color(0xFFE94560), Color(0xFFFF6B6B)]),
                    borderRadius: BorderRadius.circular(16)),
                  child: const Icon(Icons.restaurant, color: Colors.white, size: 28)),
                const SizedBox(width: 14),
                const Text('RestaurantOS', style: TextStyle(fontFamily: 'Poppins',
                  color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
              ]),
              const Spacer(),
              const Text('Reservasi &\nPesanan Online',
                style: TextStyle(fontFamily: 'Poppins', color: Colors.white,
                  fontSize: 54, fontWeight: FontWeight.w800, height: 1.1,
                  letterSpacing: -0.5)),
              const SizedBox(height: 24),
              const Text(
                'Nikmati kemudahan memesan makanan\n'
                'dan reservasi meja favorit kamu\n'
                'kapan saja, di mana saja.',
                style: TextStyle(fontFamily: 'Poppins',
                  color: Colors.white70, fontSize: 16, height: 1.7)),
              const SizedBox(height: 48),
              Wrap(spacing: 12, runSpacing: 12, children: [
                _pill('🍽️ Menu lengkap'), _pill('📅 Reservasi mudah'),
                _pill('📦 Lacak pesanan'), _pill('🤖 AI Chatbot'),
                _pill('💳 Pembayaran digital'),
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
                colors: [Color(0xFFE94560), Color(0xFFFF6B6B)]),
              borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.restaurant, color: Colors.white, size: 28)),
          const SizedBox(height: 20),
          const Text('RestaurantOS', style: TextStyle(fontFamily: 'Poppins',
            fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
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
              colors: [Color(0xFFE94560), Color(0xFFFF6B6B)]),
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
      const Text('Selamat Datang', textAlign: TextAlign.center,
        style: TextStyle(fontFamily: 'Poppins', fontSize: 28,
          fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E), letterSpacing: -0.5)),
      const SizedBox(height: 8),
      const Text('Masuk untuk melanjutkan ke akun Anda',
        textAlign: TextAlign.center,
        style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
          color: Color(0xFF6B7280), height: 1.5)),
      const SizedBox(height: 32),
      _socialBtn(
        icon: SizedBox(width: 22, height: 22,
          child: CustomPaint(painter: _GoogleIconPainter())),
        label: 'Lanjutkan dengan Google', onTap: _signInGoogle),
      const SizedBox(height: 28),
      const Row(children: [
        Expanded(child: Divider(color: Color(0xFFE5E7EB), thickness: 1)),
        Padding(padding: EdgeInsets.symmetric(horizontal: 14),
          child: Text('atau', style: TextStyle(fontFamily: 'Poppins',
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
        _field(ctrl: _nameCtrl, hint: 'Nama lengkap', icon: Icons.person_outline),
        const SizedBox(height: 14),
        _phoneField(),
        const SizedBox(height: 14),
      ],
      _field(ctrl: _emailCtrl, hint: 'Alamat Email',
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
        label: _isSignUp ? 'Buat Akun' : 'Masuk', onTap: _submitEmail),
      const SizedBox(height: 16),
      // Lupa password — hanya tampil saat mode login
      if (!_isSignUp)
        Center(
          child: TextButton(
            onPressed: _forgotPassword,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            child: const Text('Lupa password?',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                color: Color(0xFFE94560), fontWeight: FontWeight.w600))),
        ),
      const SizedBox(height: 8),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _isSignUp ? 'Sudah punya akun?' : 'Belum punya akun?',
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
              _isSignUp ? 'Masuk' : 'Daftar',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 14,
                color: Color(0xFF0F3460), fontWeight: FontWeight.w700))),
        ],
      ),
    ]);

  Widget _phoneField() => TextField(
    controller: _phoneCtrl,
    keyboardType: TextInputType.phone,
    style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
    decoration: InputDecoration(
      labelText: 'Nomor Telepon',
      labelStyle: const TextStyle(fontFamily: 'Poppins',
          fontSize: 12, color: Color(0xFF6B7280)),
      hintText: 'Contoh: 08123456789',
      hintStyle: const TextStyle(
          fontFamily: 'Poppins', fontSize: 13, color: Color(0xFF9CA3AF)),
      prefixIcon: const Icon(Icons.phone_outlined,
          size: 20, color: Color(0xFF0F3460)),
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
          borderSide: const BorderSide(color: Color(0xFF0F3460), width: 2)),
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
          fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
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
      prefixIcon: Icon(icon, size: 20, color: const Color(0xFF0F3460)),
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
          borderSide: const BorderSide(color: Color(0xFF0F3460), width: 2)),
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
            colors: [Color(0xFF1A1A2E), Color(0xFF0F3460)]),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(
            color: const Color(0xFF0F3460).withValues(alpha: 0.3),
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