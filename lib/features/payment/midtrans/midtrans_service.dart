// lib/features/payment/midtrans/midtrans_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// Midtrans Service
// Responsible for:
//   1. Calling the midtrans-create-token Edge Function → getting a snap_token
//   2. Opening the Midtrans Snap UI:
//        • Web    → MidtransWebService (snap.js via dart:js_interop)
//        • Mobile → midtrans_sdk native
//   3. Handling the result: success / pending / failed
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

  // ── Initialization ──────────────────────────────────────────────────────────
  //
  // Web    → inject snap.js from the Midtrans CDN (via MidtransWebService)
  // Mobile → init the native SDK (midtrans_sdk)
  //
  // Already called in main.dart with a !kIsWeb guard for mobile.
  // For web, MidtransWebService can also lazy-init on the first pay() call.
  static Future<void> initialize({
    required String clientKey,
    required bool isProduction,
  }) async {
    if (kIsWeb) {
      // Web: preload snap.js so there's no delay when the user taps "Pay"
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
        merchantBaseUrl: '', // empty because we use the Edge Function
        enableLog: !isProduction,
      ),
    );

    // Log callback for debugging (not used to update the DB)
    _sdk!.setTransactionFinishedCallback((result) {
      debugPrint(
        '[Midtrans] callback: status=${result.status}, '
        'transactionId=${result.transactionId}, '
        'paymentType=${result.paymentType}, '
        'message=${result.message}',
      );
    });
  }

  // ── Create Snap Token via Edge Function ─────────────────────────────────────
  //
  // IMPORTANT: Midtrans REQUIRES gross_amount === sum(item_details.price * qty).
  // Previously `items` only contained menu entries (subtotal), while
  // `gross_amount` was sent from `order.totalAmount`, which already included
  // service charge, PB1/tax, & discount → causing a mismatch and the Edge
  // Function rejecting the request (400 Bad Request, error_messages:
  // "gross_amount is not equal to the sum of item_details").
  //
  // Fix: service charge, tax, & discount are now sent as their own
  // item_details entries, and gross_amount is computed from the sum of those
  // same item_details (not computed independently from order.totalAmount).
  // This guarantees the two values always stay in sync, including with
  // rupiah rounding differences.
  static Future<MidtransTokenResult> createSnapToken({
    required OrderModel order,
    required String branchId,
  }) async {
    try {
      final supabase = Supabase.instance.client;

      final items = <Map<String, dynamic>>[];

      // 1. Menu items (subtotal) — use the price already rounded per item
      //    to stay consistent with the integers sent to Midtrans.
      for (final item in order.items) {
        items.add({
          'id': item.menuItemId,
          'name': item.menuItemName,
          'price': item.unitPrice.round(),
          'quantity': item.quantity,
        });
      }

      // The "real" subtotal sent to Midtrans = sum of the items above.
      // Recomputed from `items` (not order.subtotal) so there's no rounding
      // gap between the value shown in the UI and the value sent.
      final itemsSubtotal = items.fold<int>(
        0,
        (sum, item) => sum + (item['price'] as int) * (item['quantity'] as int),
      );

      // 2. Service charge (3%) — only added if the value != 0
      final serviceCharge = (itemsSubtotal * 0.03).round();
      if (serviceCharge != 0) {
        items.add({
          'id': 'SERVICE_CHARGE',
          'name': 'Service Charge (3%)',
          'price': serviceCharge,
          'quantity': 1,
        });
      }

      // 3. PB1 / Tax (10%) — computed from subtotal + service charge,
      //    same as the formula in OrderModel.pb1Amount
      final pb1 = ((itemsSubtotal + serviceCharge) * 0.10).round();
      if (pb1 != 0) {
        items.add({
          'id': 'TAX_PB1',
          'name': 'PB1 / Tax (10%)',
          'price': pb1,
          'quantity': 1,
        });
      }

      // 3b. Extra dining time (>2 hours since served) — Rp 5,000/hour.
      final overtimeCharge = order.overtimeCharge;
      if (overtimeCharge > 0) {
        items.add({
          'id': 'OVERTIME_CHARGE',
          'name': 'Extra Dining Time',
          'price': overtimeCharge,
          'quantity': 1,
        });
      }

      // 4. Discount (if any) — sent as an item with a negative price.
      //    Midtrans supports a negative price to represent a discount.
      final discount = order.discountAmount.round();
      if (discount > 0) {
        items.add({
          'id': 'DISCOUNT',
          'name': 'Discount',
          'price': -discount,
          'quantity': 1,
        });
      }

      // gross_amount MUST be computed from exactly the same `items` sent
      // above, so it always stays in sync with Midtrans validation.
      final grossAmount = items.fold<int>(
        0,
        (sum, item) => sum + (item['price'] as int) * (item['quantity'] as int),
      );

      // IMPORTANT: Midtrans requires transaction_details.order_id to be
      // UNIQUE FOREVER per account — it cannot be reused even if the
      // previous transaction failed/is pending/expired (error: "order_id
      // has already been taken").
      //
      // Because of this we send TWO different ids to the Edge Function:
      //   - uniqueOrderId   → unique id per payment ATTEMPT, sent to
      //                       Midtrans as transaction_details.order_id
      //   - order.id        → the real UUID row in the `orders` table, used
      //                       by the Edge Function to look up/update the DB
      //                       (sent as internal_order_id)
      //
      // Every time createSnapToken() is called (including when the user
      // retries after a failed/cancelled payment), a new timestamp will
      // also create a new uniqueOrderId, so there's no collision in Midtrans.
      final uniqueOrderId =
          '${order.id}-${DateTime.now().millisecondsSinceEpoch}';

      final response = await supabase.functions.invoke(
        'midtrans-create-token',
        body: {
          'order_id': uniqueOrderId,
          'internal_order_id': order.id,
          'gross_amount': grossAmount,
          'customer_name': order.customerName ?? 'Customer',
          'customer_email': order.customerEmail ?? '',
          'customer_phone': order.customerPhone,
          'items': items,
        },
      );

      if (response.status != 200) {
        final errorData = response.data as Map<String, dynamic>?;
        return MidtransTokenResult.failure(
          errorData?['error'] as String? ?? 'Failed to get payment token',
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
        'Failed to connect to the server: ${e.details}',
      );
    } catch (e) {
      debugPrint('[Midtrans] createSnapToken error: $e');
      return MidtransTokenResult.failure('An error occurred: $e');
    }
  }

  // ── Open the Midtrans payment page ─────────────────────────────────────
  //
  // Web    → open the Snap popup via snap.js (MidtransWebService.pay)
  // Mobile → open the native Snap screen via midtrans_sdk
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
        'Midtrans SDK has not been initialized. Please contact technical support.',
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
      // Timeout doesn't mean failure — the user may still be processing VA/QRIS.
      return MidtransPaymentResult.pending(orderId: orderId);
    } catch (e) {
      debugPrint('[Midtrans] startPayment error: $e');
      return MidtransPaymentResult.failure('Failed to open the payment page: $e');
    }
  }

  // ── Full flow: create token + pay ────────────────────────────────────────
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

  // ── Check payment status from Supabase ───────────────────────────────────
  //
  // IMPORTANT: always check against our DB, not the SDK callback.
  // The DB is updated by the Midtrans webhook → the single source of truth.
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

  // ── Poll status until paid or timeout ──────────────────────────────────
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

  // ── Private: map SDK result → our model (mobile only) ───────────────────
  //
  // NOTE: midtrans_sdk only exposes status, transactionId, paymentType,
  // message — no orderId. We get orderId from our own context.
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
        'Payment $status. Please try again.',
      );
    }

    // Unrecognized status → treat as pending, verify via webhook
    return MidtransPaymentResult.pending(
      orderId: orderId,
      paymentType: result.paymentType,
    );
  }
}