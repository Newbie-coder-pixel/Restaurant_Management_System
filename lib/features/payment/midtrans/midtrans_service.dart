// lib/features/payment/midtrans/midtrans_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// Midtrans Service
// Bertanggung jawab:
//   1. Panggil Edge Function midtrans-create-token → dapat snap_token
//   2. Buka Midtrans Snap UI:
//        • Web    → MidtransWebService (snap.js via dart:js_interop)
//        • Mobile → midtrans_sdk native
//   3. Handle result: success / pending / failed
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart' show BuildContext;
import 'package:midtrans_sdk/midtrans_sdk.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../shared/models/order_model.dart';
import '../models/midtrans_model.dart';

// Conditional import:
//   • Web    → midtrans_web_service.dart  (dart:js_interop + package:web)
//   • Mobile → midtrans_web_stub.dart     (no-op stub)
import 'midtrans_web_stub.dart'
    if (dart.library.js_interop) 'midtrans_web_service.dart';

class MidtransService {
  static MidtransSDK? _sdk;

  // ── Inisialisasi ──────────────────────────────────────────────────────────
  //
  // Web    → inject snap.js dari CDN Midtrans (via MidtransWebService)
  // Mobile → init native SDK (midtrans_sdk)
  //
  // Di main.dart sudah dipanggil dengan guard !kIsWeb untuk mobile.
  // Untuk web, MidtransWebService juga bisa lazy-init saat pay() pertama kali.
  static Future<void> initialize({
    required String clientKey,
    required bool isProduction,
  }) async {
    if (kIsWeb) {
      // Web: preload snap.js supaya tidak delay saat user klik "Bayar"
      await MidtransWebService.initialize(
        clientKey: clientKey,
        isProduction: isProduction,
      );
      return;
    }

    // Mobile: native SDK
    _sdk = await MidtransSDK.init(
      config: MidtransConfig(
        clientKey: clientKey,
        merchantBaseUrl: '', // kosong karena kita pakai Edge Function
        enableLog: !isProduction,
      ),
    );

    // Log callback untuk debugging (tidak dipakai untuk update DB)
    _sdk!.setTransactionFinishedCallback((result) {
      debugPrint(
        '[Midtrans] callback: status=${result.status}, '
        'transactionId=${result.transactionId}, '
        'paymentType=${result.paymentType}, '
        'message=${result.message}',
      );
    });
  }

  // ── Buat Snap Token via Edge Function ─────────────────────────────────────
  //
  // PENTING: Midtrans WAJIB gross_amount === sum(item_details.price * qty).
  // Sebelumnya `items` hanya berisi menu (subtotal), sedangkan `gross_amount`
  // dikirim dari `order.totalAmount` yang sudah termasuk service charge,
  // PB1/pajak, & diskon → menyebabkan mismatch dan Edge Function menolak
  // request (400 Bad Request, error_messages: "gross_amount is not equal to
  // the sum of item_details").
  //
  // Fix: service charge, pajak, & diskon ikut dikirim sebagai item_details
  // tersendiri, dan gross_amount dihitung dari penjumlahan item_details yang
  // sama (bukan dihitung independen dari order.totalAmount). Dengan begitu
  // dua nilai itu dijamin selalu sinkron, termasuk kalau ada selisih
  // pembulatan rupiah.
  static Future<MidtransTokenResult> createSnapToken({
    required OrderModel order,
    required String branchId,
  }) async {
    try {
      final supabase = Supabase.instance.client;

      final items = <Map<String, dynamic>>[];

      // 1. Item menu (subtotal) — pakai harga yang sudah dibulatkan per item
      //    supaya konsisten dengan integer yang dikirim ke Midtrans.
      for (final item in order.items) {
        items.add({
          'id': item.menuItemId,
          'name': item.menuItemName,
          'price': item.unitPrice.round(),
          'quantity': item.quantity,
        });
      }

      // Subtotal "riil" yang dikirim ke Midtrans = penjumlahan item di atas.
      // Dihitung ulang dari `items` (bukan order.subtotal) supaya tidak ada
      // celah pembulatan antara nilai yang ditampilkan di UI vs yang dikirim.
      final itemsSubtotal = items.fold<int>(
        0,
        (sum, item) => sum + (item['price'] as int) * (item['quantity'] as int),
      );

      // 2. Service charge (3%) — hanya ditambahkan kalau nilainya != 0
      final serviceCharge = (itemsSubtotal * 0.03).round();
      if (serviceCharge != 0) {
        items.add({
          'id': 'SERVICE_CHARGE',
          'name': 'Service Charge (3%)',
          'price': serviceCharge,
          'quantity': 1,
        });
      }

      // 3. PB1 / Pajak (10%) — dihitung dari subtotal + service charge,
      //    sama seperti rumus di OrderModel.pb1Amount
      final pb1 = ((itemsSubtotal + serviceCharge) * 0.10).round();
      if (pb1 != 0) {
        items.add({
          'id': 'TAX_PB1',
          'name': 'PB1 / Pajak (10%)',
          'price': pb1,
          'quantity': 1,
        });
      }

      // 4. Diskon (kalau ada) — dikirim sebagai item dengan harga negatif.
      //    Midtrans mendukung price negatif untuk merepresentasikan diskon.
      final discount = order.discountAmount.round();
      if (discount > 0) {
        items.add({
          'id': 'DISCOUNT',
          'name': 'Diskon',
          'price': -discount,
          'quantity': 1,
        });
      }

      // gross_amount WAJIB dihitung dari `items` yang sama persis dengan
      // yang dikirim di atas, supaya selalu sinkron dengan validasi Midtrans.
      final grossAmount = items.fold<int>(
        0,
        (sum, item) => sum + (item['price'] as int) * (item['quantity'] as int),
      );

      final response = await supabase.functions.invoke(
        'midtrans-create-token',
        body: {
          'order_id': order.id,
          'gross_amount': grossAmount,
          'customer_name': order.customerName ?? 'Pelanggan',
          'customer_email': order.customerEmail ?? '',
          'customer_phone': order.customerPhone,
          'items': items,
        },
      );

      if (response.status != 200) {
        final errorData = response.data as Map<String, dynamic>?;
        return MidtransTokenResult.failure(
          errorData?['error'] as String? ?? 'Gagal mendapatkan token pembayaran',
        );
      }

      final data = response.data as Map<String, dynamic>;
      return MidtransTokenResult.success(
        snapToken: data['snap_token'] as String,
        redirectUrl: data['redirect_url'] as String?,
        orderId: data['order_id'] as String,
      );
    } on FunctionException catch (e) {
      debugPrint('[Midtrans] Edge function error: $e');
      return MidtransTokenResult.failure(
        'Gagal terhubung ke server: ${e.details}',
      );
    } catch (e) {
      debugPrint('[Midtrans] createSnapToken error: $e');
      return MidtransTokenResult.failure('Terjadi kesalahan: $e');
    }
  }

  // ── Buka halaman pembayaran Midtrans ─────────────────────────────────────
  //
  // Web    → buka Snap popup via snap.js (MidtransWebService.pay)
  // Mobile → buka native Snap screen via midtrans_sdk
  static Future<MidtransPaymentResult> startPayment({
    required String snapToken,
    required String orderId,
  }) async {
    // ── Web path ────────────────────────────────────────────────────────────
    if (kIsWeb) {
      return MidtransWebService.pay(
        snapToken: snapToken,
        orderId: orderId,
        clientKey: AppConfig.midtransClientKey,
        isProduction: AppConfig.midtransIsProduction,
      );
    }

    // ── Mobile path ─────────────────────────────────────────────────────────
    if (_sdk == null) {
      return MidtransPaymentResult.failure(
        'Midtrans SDK belum diinisialisasi. Hubungi tim teknis.',
      );
    }

    try {
      final completer = Completer<TransactionResult>();

      _sdk!.setTransactionFinishedCallback((result) {
        if (!completer.isCompleted) completer.complete(result);
      });

      await _sdk!.startPaymentUiFlow(token: snapToken);

      final result = await completer.future.timeout(
        const Duration(minutes: 10),
      );
      return _mapSdkResult(result, orderId);
    } on TimeoutException {
      // Timeout bukan berarti gagal — user mungkin masih proses VA/QRIS.
      return MidtransPaymentResult.pending(orderId: orderId);
    } catch (e) {
      debugPrint('[Midtrans] startPayment error: $e');
      return MidtransPaymentResult.failure('Gagal membuka halaman pembayaran: $e');
    }
  }

  // ── Full flow: buat token + bayar ────────────────────────────────────────
  static Future<MidtransPaymentResult> processPayment({
    required BuildContext context,
    required OrderModel order,
    required String branchId,
  }) async {
    final tokenResult = await createSnapToken(
      order: order,
      branchId: branchId,
    );
    if (!tokenResult.success) {
      return MidtransPaymentResult.failure(tokenResult.errorMessage!);
    }
    return startPayment(
      snapToken: tokenResult.snapToken!,
      orderId: order.id,
    );
  }

  // ── Cek status pembayaran dari Supabase ───────────────────────────────────
  //
  // PENTING: selalu cek dari DB kita, bukan dari callback SDK.
  // DB diupdate oleh webhook Midtrans → sumber kebenaran tunggal.
  static Future<MidtransPaymentStatus> checkPaymentStatus(String orderId) async {
    try {
      final supabase = Supabase.instance.client;
      final res = await supabase
          .from('orders')
          .select('payment_status, status, midtrans_transaction_id')
          .eq('id', orderId)
          .single();

      switch (res['payment_status'] as String?) {
        case 'paid':
          return MidtransPaymentStatus.paid;
        case 'pending':
          return MidtransPaymentStatus.pending;
        case 'failed':
          return MidtransPaymentStatus.failed;
        case 'refunded':
          return MidtransPaymentStatus.refunded;
        default:
          return MidtransPaymentStatus.pending;
      }
    } catch (e) {
      debugPrint('[Midtrans] checkPaymentStatus error: $e');
      return MidtransPaymentStatus.unknown;
    }
  }

  // ── Poll status sampai paid atau timeout ──────────────────────────────────
  static Future<MidtransPaymentStatus> pollUntilPaid({
    required String orderId,
    Duration interval = const Duration(seconds: 3),
    int maxAttempts = 20,
  }) async {
    for (int i = 0; i < maxAttempts; i++) {
      await Future.delayed(interval);
      final status = await checkPaymentStatus(orderId);
      if (status == MidtransPaymentStatus.paid ||
          status == MidtransPaymentStatus.failed ||
          status == MidtransPaymentStatus.refunded) {
        return status;
      }
    }
    return MidtransPaymentStatus.pending;
  }

  // ── Private: map SDK result → model kita (mobile only) ───────────────────
  //
  // CATATAN: midtrans_sdk hanya expose status, transactionId, paymentType,
  // message — tidak ada orderId. Kita ambil orderId dari context kita sendiri.
  static MidtransPaymentResult _mapSdkResult(
    TransactionResult result,
    String orderId,
  ) {
    final status = result.status.toLowerCase();

    if (status.contains('cancel')) {
      return MidtransPaymentResult.cancelled();
    }
    if (status.contains('success') ||
        status.contains('settlement') ||
        status.contains('capture')) {
      return MidtransPaymentResult.success(
        transactionId: result.transactionId ?? '',
        paymentType: result.paymentType ?? '',
        orderId: orderId,
      );
    }
    if (status.contains('pending')) {
      return MidtransPaymentResult.pending(
        orderId: orderId,
        paymentType: result.paymentType,
      );
    }
    if (status.contains('deny') ||
        status.contains('expire') ||
        status.contains('fail') ||
        status.contains('invalid')) {
      return MidtransPaymentResult.failure(
        'Pembayaran $status. Silakan coba lagi.',
      );
    }

    // Status tidak dikenal → treat sebagai pending, cek via webhook
    return MidtransPaymentResult.pending(
      orderId: orderId,
      paymentType: result.paymentType,
    );
  }
}