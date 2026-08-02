// lib/features/payment/midtrans/midtrans_web_stub.dart
// ─────────────────────────────────────────────────────────────────────────────
// STUB — used when compiling for Android / iOS / Desktop.
// Provides the same interface as midtrans_web_service.dart so the
// conditional import in midtrans_service.dart works correctly.
//
// Conditional import (in midtrans_service.dart):
//   import 'midtrans_web_stub.dart'
//       if (dart.library.js_interop) 'midtrans_web_service.dart';
//
// On mobile platforms, this file is selected → every method just returns.
// On web, this file is never compiled; midtrans_web_service.dart is used instead.
// ─────────────────────────────────────────────────────────────────────────────

import '../models/midtrans_model.dart';

class MidtransWebService {
  // Does nothing on non-web platforms.
  static Future<void> initialize({
    required String clientKey,
    required bool isProduction,
  }) async {}

  // Never called on mobile because midtrans_service.dart already uses the
  // native SDK (midtrans_sdk) for non-web platforms.
  static Future<MidtransPaymentResult> pay({
    required String snapToken,
    required String orderId,
    required String clientKey,
    required bool isProduction,
  }) async {
    return MidtransPaymentResult.failure(
      'Web payment is not available on this platform. Please use the mobile app.',
    );
  }
}