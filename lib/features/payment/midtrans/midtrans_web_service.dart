// lib/features/payment/midtrans/midtrans_web_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// WEB implementation for Midtrans payments via Snap.js
//
// This file is ONLY compiled on web (dart.library.js_interop available).
// On Android/iOS, midtrans_web_stub.dart is used instead.
//
// Flow:
//   1. initialize() → inject snap.js from the Midtrans CDN + a JS helper wrapper
//   2. pay()        → call window._rmsSnapPay() → open the Snap popup
//   3. Snap callback (onSuccess/onPending/onError/onClose) → resolve the Future
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe'; // getProperty / setProperty on JSObject
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;
import '../models/midtrans_model.dart';

// ── JS Interop: check whether snap.js has been loaded (window.snap available) ────────
@JS('snap')
external JSAny? get _snapGlobal;

// ── JS Interop: call the helper wrapper we injected ───────────────────────────
// This wrapper wraps window.snap.pay() so it can be called from Dart
// with a JSFunction as the callback.
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

  // ── Initialization: inject snap.js + JS helper into the DOM ──────────────────────
  //
  // Called from MidtransService.initialize() on the web platform.
  // Safe to call multiple times — idempotent.
  static Future<void> initialize({
    required String clientKey,
    required bool isProduction,
  }) async {
    // 1. Inject the helper JS first (synchronous, no need to wait for the load event)
    if (!_helperInjected) {
      _injectHelperScript();
      _helperInjected = true;
    }

    // 2. If snap.js was already loaded previously, we're done
    if (_scriptLoaded) return;

    // 3. If it's currently loading (concurrent calls), wait for that to finish
    if (_loadCompleter != null && !_loadCompleter!.isCompleted) {
      return _loadCompleter!.future;
    }

    _loadCompleter = Completer<void>();

    final baseUrl = isProduction
        ? 'https://app.midtrans.com'
        : 'https://app.sandbox.midtrans.com';

    // Create a <script src="...snap.js" data-client-key="..."> tag
    final script =
        web.document.createElement('script') as web.HTMLScriptElement;
    script.src = '$baseUrl/snap/snap.js';
    script.setAttribute('data-client-key', clientKey);
    // NOTE: DO NOT set the 'crossorigin' attribute here.
    // If set, the browser will load this script in CORS mode and require
    // the server to send an Access-Control-Allow-Origin header. Midtrans's
    // snap.js server does NOT send that header (this script is designed to
    // be loaded via a regular <script> tag, not via fetch()/CORS), so the
    // request would be blocked by the browser with a CORS error and
    // snap.js would fail to load entirely.

    // Load success
    script.addEventListener(
      'load',
      ((web.Event _) {
        _scriptLoaded = true;
        debugPrint('[MidtransWeb] snap.js loaded successfully from $baseUrl');
        if (!(_loadCompleter?.isCompleted ?? true)) {
          _loadCompleter!.complete();
        }
      }).toJS,
    );

    // Load error
    script.addEventListener(
      'error',
      ((web.Event _) {
        debugPrint('[MidtransWeb] Failed to load snap.js from $baseUrl');
        if (!(_loadCompleter?.isCompleted ?? true)) {
          _loadCompleter!.completeError(
            Exception(
                'Failed to load Snap.js. Check your internet connection and refresh.'),
          );
        }
      }).toJS,
    );

    // Replace the placeholder (from index.html) or append to <head>
    final placeholder =
        web.document.getElementById('midtrans-snap-script-placeholder');
    if (placeholder != null) {
      placeholder.parentNode?.replaceChild(script, placeholder);
    } else {
      (web.document.head ?? web.document.body)?.append(script);
    }

    // Wait for snap.js to finish loading (max. 15 seconds)
    try {
      await _loadCompleter!.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException(
            '[MidtransWeb] Timeout loading snap.js (15 seconds)',
          );
        },
      );
    } catch (e) {
      _scriptLoaded = false;
      _loadCompleter = null;
      rethrow;
    }
  }

  // ── Inject JS helper: wraps window.snap.pay() ───────────────────────
  //
  // Why do we need a wrapper?
  //   dart:js_interop cannot directly pass a Dart closure as an object
  //   literal property to snap.pay(token, { onSuccess: fn, ... }).
  //   So we define window._rmsSnapPay() in JS, and call it from Dart
  //   with JSFunction arguments — much cleaner.
  static void _injectHelperScript() {
    const helperCode = r'''
window._rmsSnapPay = function(token, onSuccess, onPending, onError, onClose) {
  if (!window.snap || typeof window.snap.pay !== 'function') {
    if (typeof onError === 'function') {
      onError({ status_message: 'Snap.js is not ready yet. Try refreshing the page.' });
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
      onError({ status_message: 'Failed to open the payment page: ' + String(e) });
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

  // ── Open the Snap UI and wait for the result ─────────────────────────────
  //
  // Return: MidtransPaymentResult (success / pending / failure / cancelled)
  // 15-minute timeout — VA transfers can take a few minutes.
  static Future<MidtransPaymentResult> pay({
    required String snapToken,
    required String orderId,
    required String clientKey,
    required bool isProduction,
  }) async {
    // Lazy init: if snap.js hasn't been loaded yet, load it first
    if (!_scriptLoaded || _snapGlobal == null) {
      try {
        await initialize(clientKey: clientKey, isProduction: isProduction);
      } catch (e) {
        debugPrint('[MidtransWeb] Failed to init during pay(): $e');
        return MidtransPaymentResult.failure(
          'Failed to load the payment page. Check your connection and try refreshing.',
        );
      }
    }

    // Sanity check: window.snap must be available after loading
    if (_snapGlobal == null) {
      return MidtransPaymentResult.failure(
        'Snap.js is not available. Try refreshing the page.',
      );
    }

    final completer = Completer<MidtransPaymentResult>();

    try {
      _rmsSnapPay(
        snapToken,

        // onSuccess — payment successful (credit card, GoPay, QRIS confirmed)
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

        // onPending — needs further confirmation (VA, QRIS not scanned yet)
        ((JSAny? resultJs) {
          if (completer.isCompleted) return;
          completer.complete(
            MidtransPaymentResult.pending(
              orderId: orderId,
              paymentType: _readProp(resultJs, 'payment_type'),
            ),
          );
        }).toJS,

        // onError — payment declined / expired / error
        ((JSAny? resultJs) {
          if (completer.isCompleted) return;
          final msg = _readProp(resultJs, 'status_message') ??
              'Payment failed. Please try again.';
          completer.complete(MidtransPaymentResult.failure(msg));
        }).toJS,

        // onClose — user closed the Snap popup without completing payment
        (() {
          if (completer.isCompleted) return;
          completer.complete(MidtransPaymentResult.cancelled());
        }).toJS,
      );
    } catch (e) {
      debugPrint('[MidtransWeb] _rmsSnapPay error: $e');
      return MidtransPaymentResult.failure(
        'Failed to open the payment page: $e',
      );
    }

    // Wait for one of the Snap callbacks to be called (max. 15 minutes)
    return completer.future.timeout(
      const Duration(minutes: 15),
      onTimeout: () => MidtransPaymentResult.pending(orderId: orderId),
    );
  }

  // ── Helper: read a string property from the JS result object ───────────────────
  static String? _readProp(JSAny? jsValue, String key) {
    if (jsValue == null) return null;
    try {
      final obj = jsValue as JSObject;
      final val = obj.getProperty<JSAny?>(key.toJS);
      if (val == null) return null;
      if (val.isA<JSString>()) return (val as JSString).toDart;
      // Fallback for other types (number, etc.)
      final dartVal = val.dartify();
      return dartVal?.toString();
    } catch (e) {
      debugPrint('[MidtransWeb] _readProp("$key") error: $e');
      return null;
    }
  }
}