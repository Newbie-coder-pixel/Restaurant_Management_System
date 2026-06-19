// lib/features/payment/midtrans/midtrans_web_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// Implementasi WEB untuk pembayaran Midtrans via Snap.js
//
// File ini HANYA dikompilasi di web (dart.library.js_interop tersedia).
// Di Android/iOS, midtrans_web_stub.dart yang dipakai.
//
// Alur:
//   1. initialize() → inject snap.js dari CDN Midtrans + helper JS wrapper
//   2. pay()        → panggil window._rmsSnapPay() → buka Snap popup
//   3. Snap callback (onSuccess/onPending/onError/onClose) → resolve Future
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe'; // getProperty / setProperty pada JSObject
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;
import '../models/midtrans_model.dart';

// ── JS Interop: cek apakah snap.js sudah dimuat (window.snap tersedia) ────────
@JS('snap')
external JSAny? get _snapGlobal;

// ── JS Interop: panggil helper wrapper yang kita inject ───────────────────────
// Wrapper ini membungkus window.snap.pay() agar bisa dipanggil dari Dart
// dengan JSFunction sebagai callback.
@JS('_rmsSnapPay')
external void _rmsSnapPay(
  String token,
  JSFunction onSuccess,
  JSFunction onPending,
  JSFunction onError,
  JSFunction onClose,
);

// ─────────────────────────────────────────────────────────────────────────────
class MidtransWebService {
  static bool _scriptLoaded = false;
  static bool _helperInjected = false;
  static Completer<void>? _loadCompleter;

  // ── Inisialisasi: inject snap.js + JS helper ke DOM ──────────────────────
  //
  // Dipanggil dari MidtransService.initialize() saat platform web.
  // Aman dipanggil berkali-kali — idempotent.
  static Future<void> initialize({
    required String clientKey,
    required bool isProduction,
  }) async {
    // 1. Inject helper JS dulu (synchronous, tidak perlu tunggu load event)
    if (!_helperInjected) {
      _injectHelperScript();
      _helperInjected = true;
    }

    // 2. Kalau snap.js sudah dimuat sebelumnya, selesai
    if (_scriptLoaded) return;

    // 3. Kalau sedang loading (concurrent calls), tunggu yang sedang jalan
    if (_loadCompleter != null && !_loadCompleter!.isCompleted) {
      return _loadCompleter!.future;
    }

    _loadCompleter = Completer<void>();

    final baseUrl = isProduction
        ? 'https://app.midtrans.com'
        : 'https://app.sandbox.midtrans.com';

    // Buat tag <script src="...snap.js" data-client-key="...">
    final script =
        web.document.createElement('script') as web.HTMLScriptElement;
    script.src = '$baseUrl/snap/snap.js';
    script.setAttribute('data-client-key', clientKey);

    // Load success
    script.addEventListener(
      'load',
      ((web.Event _) {
        _scriptLoaded = true;
        debugPrint('[MidtransWeb] snap.js berhasil dimuat dari $baseUrl');
        if (!(_loadCompleter?.isCompleted ?? true)) {
          _loadCompleter!.complete();
        }
      }).toJS,
    );

    // Load error
    script.addEventListener(
      'error',
      ((web.Event _) {
        debugPrint('[MidtransWeb] Gagal memuat snap.js dari $baseUrl');
        if (!(_loadCompleter?.isCompleted ?? true)) {
          _loadCompleter!.completeError(
            Exception(
                'Gagal memuat Snap.js. Periksa koneksi internet dan refresh.'),
          );
        }
      }).toJS,
    );

    // Ganti placeholder (dari index.html) atau append ke <head>
    final placeholder =
        web.document.getElementById('midtrans-snap-script-placeholder');
    if (placeholder != null) {
      placeholder.parentNode?.replaceChild(script, placeholder);
    } else {
      (web.document.head ?? web.document.body)?.append(script);
    }

    // Tunggu snap.js selesai dimuat (maks. 15 detik)
    try {
      await _loadCompleter!.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException(
            '[MidtransWeb] Timeout memuat snap.js (15 detik)',
          );
        },
      );
    } catch (e) {
      _scriptLoaded = false;
      _loadCompleter = null;
      rethrow;
    }
  }

  // ── Inject JS helper: membungkus window.snap.pay() ───────────────────────
  //
  // Kenapa perlu wrapper?
  //   dart:js_interop tidak bisa langsung pass Dart closure sebagai property
  //   object literal ke snap.pay(token, { onSuccess: fn, ... }).
  //   Jadi kita definisikan window._rmsSnapPay() di JS, dan dari Dart kita
  //   panggil itu dengan JSFunction arguments — jauh lebih bersih.
  static void _injectHelperScript() {
    const helperCode = r'''
window._rmsSnapPay = function(token, onSuccess, onPending, onError, onClose) {
  if (!window.snap || typeof window.snap.pay !== 'function') {
    if (typeof onError === 'function') {
      onError({ status_message: 'Snap.js belum siap. Coba refresh halaman.' });
    }
    return;
  }
  try {
    window.snap.pay(token, {
      onSuccess: onSuccess,
      onPending: onPending,
      onError:   onError,
      onClose:   onClose
    });
  } catch (e) {
    if (typeof onError === 'function') {
      onError({ status_message: 'Gagal membuka halaman pembayaran: ' + String(e) });
    }
  }
};
''';

    final helperScript =
        web.document.createElement('script') as web.HTMLScriptElement;
    helperScript.text = helperCode;
    (web.document.head ?? web.document.body)?.append(helperScript);
    debugPrint('[MidtransWeb] Helper script _rmsSnapPay injected');
  }

  // ── Buka Snap UI dan tunggu hasilnya ─────────────────────────────────────
  //
  // Return: MidtransPaymentResult (success / pending / failure / cancelled)
  // Timeout 15 menit — VA transfer bisa butuh beberapa menit.
  static Future<MidtransPaymentResult> pay({
    required String snapToken,
    required String orderId,
    required String clientKey,
    required bool isProduction,
  }) async {
    // Lazy init: kalau snap.js belum dimuat, muat dulu
    if (!_scriptLoaded || _snapGlobal == null) {
      try {
        await initialize(clientKey: clientKey, isProduction: isProduction);
      } catch (e) {
        debugPrint('[MidtransWeb] Gagal init saat pay(): $e');
        return MidtransPaymentResult.failure(
          'Gagal memuat halaman pembayaran. Periksa koneksi dan coba refresh.',
        );
      }
    }

    // Sanity check: window.snap harus tersedia setelah load
    if (_snapGlobal == null) {
      return MidtransPaymentResult.failure(
        'Snap.js tidak tersedia. Coba refresh halaman.',
      );
    }

    final completer = Completer<MidtransPaymentResult>();

    try {
      _rmsSnapPay(
        snapToken,

        // onSuccess — pembayaran berhasil (kartu kredit, GoPay, QRIS confirmed)
        ((JSAny? resultJs) {
          if (completer.isCompleted) return;
          completer.complete(
            MidtransPaymentResult.success(
              transactionId: _readProp(resultJs, 'transaction_id') ?? '',
              paymentType: _readProp(resultJs, 'payment_type') ?? '',
              orderId: orderId,
            ),
          );
        }).toJS,

        // onPending — butuh konfirmasi lanjut (VA, QRIS belum scan)
        ((JSAny? resultJs) {
          if (completer.isCompleted) return;
          completer.complete(
            MidtransPaymentResult.pending(
              orderId: orderId,
              paymentType: _readProp(resultJs, 'payment_type'),
            ),
          );
        }).toJS,

        // onError — pembayaran ditolak / expired / error
        ((JSAny? resultJs) {
          if (completer.isCompleted) return;
          final msg = _readProp(resultJs, 'status_message') ??
              'Pembayaran gagal. Silakan coba lagi.';
          completer.complete(MidtransPaymentResult.failure(msg));
        }).toJS,

        // onClose — user tutup popup Snap tanpa selesaikan pembayaran
        (() {
          if (completer.isCompleted) return;
          completer.complete(MidtransPaymentResult.cancelled());
        }).toJS,
      );
    } catch (e) {
      debugPrint('[MidtransWeb] _rmsSnapPay error: $e');
      return MidtransPaymentResult.failure(
        'Gagal membuka halaman pembayaran: $e',
      );
    }

    // Tunggu salah satu callback dipanggil Snap (maks. 15 menit)
    return completer.future.timeout(
      const Duration(minutes: 15),
      onTimeout: () => MidtransPaymentResult.pending(orderId: orderId),
    );
  }

  // ── Helper: baca string property dari JS result object ───────────────────
  static String? _readProp(JSAny? jsValue, String key) {
    if (jsValue == null) return null;
    try {
      final obj = jsValue as JSObject;
      final val = obj.getProperty<JSAny?>(key.toJS);
      if (val == null) return null;
      if (val.isA<JSString>()) return (val as JSString).toDart;
      // Fallback untuk tipe lain (number, dll)
      final dartVal = val.dartify();
      return dartVal?.toString();
    } catch (e) {
      debugPrint('[MidtransWeb] _readProp("$key") error: $e');
      return null;
    }
  }
}