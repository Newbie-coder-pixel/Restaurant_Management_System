// lib/features/payment/models/midtrans_model.dart
// ─────────────────────────────────────────────────────────────────────────────
// Model for all results from the Midtrans payment flow
// ─────────────────────────────────────────────────────────────────────────────

// ── Payment status from DB / webhook ──────────────────────────────────────
enum MidtransPaymentStatus {
  paid,
  pending,
  failed,
  refunded,
  cancelled,
  unknown,
}

extension MidtransPaymentStatusExt on MidtransPaymentStatus {
  String get label {
    switch (this) {
      case MidtransPaymentStatus.paid:      return 'Paid';
      case MidtransPaymentStatus.pending:   return 'Awaiting Payment';
      case MidtransPaymentStatus.failed:    return 'Failed';
      case MidtransPaymentStatus.refunded:  return 'Refunded';
      case MidtransPaymentStatus.cancelled: return 'Cancelled';
      case MidtransPaymentStatus.unknown:   return 'Unknown';
    }
  }

  bool get isTerminal =>
      this == MidtransPaymentStatus.paid ||
      this == MidtransPaymentStatus.failed ||
      this == MidtransPaymentStatus.refunded ||
      this == MidtransPaymentStatus.cancelled;
}

// ── Result from the midtrans-create-token Edge Function ───────────────────────────
class MidtransTokenResult {
  final bool success;
  final String? snapToken;
  final String? redirectUrl;
  final String? orderId;
  final String? errorMessage;

  const MidtransTokenResult._({
    required this.success,
    this.snapToken,
    this.redirectUrl,
    this.orderId,
    this.errorMessage,
  });

  factory MidtransTokenResult.success({
    required String snapToken,
    String? redirectUrl,
    required String orderId,
  }) =>
      MidtransTokenResult._(
        success: true,
        snapToken: snapToken,
        redirectUrl: redirectUrl,
        orderId: orderId,
      );

  factory MidtransTokenResult.failure(String message) =>
      MidtransTokenResult._(success: false, errorMessage: message);
}

// ── Result from startPayment (after the user finishes on the Snap page) ────────────
enum MidtransPaymentResultType { success, pending, failed, cancelled }

class MidtransPaymentResult {
  final MidtransPaymentResultType type;
  final String? transactionId;
  final String? paymentType;
  final String? orderId;
  final String? errorMessage;

  const MidtransPaymentResult._({
    required this.type,
    this.transactionId,
    this.paymentType,
    this.orderId,
    this.errorMessage,
  });

  factory MidtransPaymentResult.success({
    required String transactionId,
    required String paymentType,
    required String orderId,
  }) =>
      MidtransPaymentResult._(
        type: MidtransPaymentResultType.success,
        transactionId: transactionId,
        paymentType: paymentType,
        orderId: orderId,
      );

  factory MidtransPaymentResult.pending({
    required String orderId,
    String? paymentType,
  }) =>
      MidtransPaymentResult._(
        type: MidtransPaymentResultType.pending,
        orderId: orderId,
        paymentType: paymentType,
      );

  factory MidtransPaymentResult.failure(String message) =>
      MidtransPaymentResult._(
        type: MidtransPaymentResultType.failed,
        errorMessage: message,
      );

  factory MidtransPaymentResult.cancelled() =>
      const MidtransPaymentResult._(type: MidtransPaymentResultType.cancelled);

  bool get isSuccess => type == MidtransPaymentResultType.success;
  bool get isPending => type == MidtransPaymentResultType.pending;
  bool get isFailed => type == MidtransPaymentResultType.failed;
  bool get isCancelled => type == MidtransPaymentResultType.cancelled;

  /// Needs polling? True if the user has confirmed but the status is still pending
  /// (e.g.: paying via QRIS / VA, webhook not received yet)
  bool get needsPolling =>
      type == MidtransPaymentResultType.pending ||
      type == MidtransPaymentResultType.success;
}

// ── Midtrans payment method label → display name ─────────────────────────
class MidtransPaymentMethod {
  static String label(String paymentType) {
    switch (paymentType.toLowerCase()) {
      case 'credit_card':   return 'Credit/Debit Card';
      case 'bca_va':        return 'BCA Virtual Account Transfer';
      case 'bni_va':        return 'BNI Virtual Account Transfer';
      case 'bri_va':        return 'BRI Virtual Account Transfer';
      case 'mandiri_bill':  return 'Mandiri Bill Payment';
      case 'permata_va':    return 'Permata Virtual Account';
      case 'other_va':      return 'Virtual Account Transfer';
      case 'bank_transfer': return 'Bank Transfer';
      case 'gopay':         return 'GoPay';
      case 'shopeepay':     return 'ShopeePay';
      case 'qris':          return 'QRIS';
      case 'akulaku':       return 'Akulaku PayLater';
      case 'kredivo':       return 'Kredivo';
      case 'indomaret':     return 'Indomaret';
      case 'alfamart':      return 'Alfamart';
      default:              return paymentType;
    }
  }

  static String icon(String paymentType) {
    switch (paymentType.toLowerCase()) {
      case 'credit_card':   return '💳';
      case 'gopay':         return '🟢';
      case 'shopeepay':     return '🟠';
      case 'qris':          return '📱';
      case 'indomaret':
      case 'alfamart':      return '🏪';
      default:              return '🏦';
    }
  }
}
