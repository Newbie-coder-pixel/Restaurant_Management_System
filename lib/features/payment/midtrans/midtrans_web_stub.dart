// lib/features/payment/midtrans/midtrans_web_stub.dart
// ─────────────────────────────────────────────────────────────────────────────
// STUB — dipakai saat compile di Android / iOS / Desktop.
// Memberikan interface yang sama dengan midtrans_web_service.dart supaya
// conditional import di midtrans_service.dart bisa bekerja.
//
// Conditional import (di midtrans_service.dart):
//   import 'midtrans_web_stub.dart'
//       if (dart.library.js_interop) 'midtrans_web_service.dart';
//
// Pada platform mobile, file ini yang dipilih → semua method langsung return.
// Pada web, file ini tidak pernah dikompilasi; midtrans_web_service.dart yang dipakai.
// ─────────────────────────────────────────────────────────────────────────────

import '../models/midtrans_model.dart';

class MidtransWebService {
  // Tidak melakukan apa-apa di platform non-web.
  static Future<void> initialize({
    required String clientKey,
    required bool isProduction,
  }) async {}

  // Tidak pernah dipanggil di mobile karena midtrans_service.dart
  // sudah pakai native SDK (midtrans_sdk) untuk platform non-web.
  static Future<MidtransPaymentResult> pay({
    required String snapToken,
    required String orderId,
    required String clientKey,
    required bool isProduction,
  }) async {
    return MidtransPaymentResult.failure(
      'Web payment tidak tersedia di platform ini. Gunakan aplikasi mobile.',
    );
  }
}