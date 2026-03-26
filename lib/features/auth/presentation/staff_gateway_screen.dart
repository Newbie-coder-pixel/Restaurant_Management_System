import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart';  // ✅ naik 3 level = lib/core/

// ─────────────────────────────────────────────────────────────
// GANTI KODE INI DENGAN KODE RAHASIA PILIHAN KAMU
// Jangan share ke customer!
// ─────────────────────────────────────────────────────────────
const String _kStaffAccessCode = 'RESTO2024STAFF';

class StaffGatewayScreen extends StatefulWidget {
  const StaffGatewayScreen({super.key});
  @override
  State<StaffGatewayScreen> createState() => _StaffGatewayScreenState();
}

class _StaffGatewayScreenState extends State<StaffGatewayScreen> {
  final _ctrl = TextEditingController();
  final _focusNode = FocusNode();
  bool _obscure = true;
  bool _error = false;
  int _attempts = 0;
  bool _locked = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    if (_locked) return;

    final input = _ctrl.text.trim().toUpperCase();
    if (input == _kStaffAccessCode.toUpperCase()) {
      // Benar → masuk ke login staff
      context.go(AppRoutes.login);
    } else {
      _attempts++;
      setState(() => _error = true);
      _ctrl.clear();

      // Kunci sementara setelah 5x salah
      if (_attempts >= 5) {
        setState(() => _locked = true);
        Future.delayed(const Duration(seconds: 30), () {
          if (mounted) setState(() { _locked = false; _attempts = 0; });
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE94560), Color(0xFFFF6B6B)]),
                  borderRadius: BorderRadius.circular(20)),
                child: const Icon(Icons.restaurant,
                  color: Colors.white, size: 36)),
              const SizedBox(height: 20),
              const Text('RestaurantOS',
                style: TextStyle(
                  fontFamily: 'Poppins', color: Colors.white,
                  fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text('Staff Access',
                style: TextStyle(
                  fontFamily: 'Poppins', color: Colors.white38,
                  fontSize: 13)),
              const SizedBox(height: 40),

              // Card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Kode Akses',
                      style: TextStyle(
                        fontFamily: 'Poppins', color: Colors.white70,
                        fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _ctrl,
                      focusNode: _focusNode,
                      obscureText: _obscure,
                      textCapitalization: TextCapitalization.characters,
                      onChanged: (_) => setState(() => _error = false),
                      onSubmitted: (_) => _submit(),
                      enabled: !_locked,
                      style: const TextStyle(
                        fontFamily: 'Poppins', color: Colors.white,
                        fontSize: 16, letterSpacing: 3,
                        fontWeight: FontWeight.w700),
                      decoration: InputDecoration(
                        hintText: '••••••••••',
                        hintStyle: const TextStyle(
                          color: Colors.white24, letterSpacing: 3),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: _error
                              ? const Color(0xFFE94560)
                              : Colors.white.withValues(alpha: 0.1))),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: _error
                              ? const Color(0xFFE94560)
                              : Colors.white.withValues(alpha: 0.1))),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: _error
                              ? const Color(0xFFE94560)
                              : const Color(0xFFE94560).withValues(alpha: 0.6))),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure ? Icons.visibility_off : Icons.visibility,
                            color: Colors.white38, size: 18),
                          onPressed: () =>
                            setState(() => _obscure = !_obscure))),
                    ),

                    if (_error) ...[
                      const SizedBox(height: 8),
                      Row(children: [
                        const Icon(Icons.error_outline,
                          color: Color(0xFFE94560), size: 14),
                        const SizedBox(width: 6),
                        Text(
                          _attempts >= 5
                            ? 'Terlalu banyak percobaan. Coba lagi dalam 30 detik.'
                            : 'Kode akses salah. Sisa percobaan: ${5 - _attempts}',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            color: Color(0xFFE94560), fontSize: 11)),
                      ]),
                    ],

                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _locked ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE94560),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.white12,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                          elevation: 0),
                        child: Text(
                          _locked ? 'Terkunci sementara...' : 'Masuk',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700, fontSize: 15)))),
                  ])),

              const SizedBox(height: 24),
              // Link ke customer page
              TextButton(
                onPressed: () => context.go(AppRoutes.customer),
                child: const Text('Saya pelanggan → Pesan & Reservasi',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white38, fontSize: 12))),
            ]))));
  }
}