// lib/features/payment/models/midtrans_model.dart
// ─────────────────────────────────────────────────────────────────────────────
// Model untuk semua hasil dari alur pembayaran Midtrans
// ─────────────────────────────────────────────────────────────────────────────

// ── Status pembayaran dari DB / webhook ──────────────────────────────────────
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
      case MidtransPaymentStatus.paid:      return 'Lunas';
      case MidtransPaymentStatus.pending:   return 'Menunggu Pembayaran';
      case MidtransPaymentStatus.failed:    return 'Gagal';
      case MidtransPaymentStatus.refunded:  return 'Dikembalikan';
      case MidtransPaymentStatus.cancelled: return 'Dibatalkan';
      case MidtransPaymentStatus.unknown:   return 'Tidak Diketahui';
    }
  }

  bool get isTerminal =>
      this == MidtransPaymentStatus.paid ||
      this == MidtransPaymentStatus.failed ||
      this == MidtransPaymentStatus.refunded ||
      this == MidtransPaymentStatus.cancelled;
}

// ── Hasil dari Edge Function midtrans-create-token ───────────────────────────
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

// ── Hasil dari startPayment (setelah user selesai di halaman Snap) ────────────
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

  /// Perlu polling? True kalau user sudah konfirmasi tapi status masih pending
  /// (contoh: bayar QRIS / VA, webhook belum masuk)
  bool get needsPolling =>
      type == MidtransPaymentResultType.pending ||
      type == MidtransPaymentResultType.success;
}

// ── Label metode pembayaran Midtrans → nama tampilan ─────────────────────────
class MidtransPaymentMethod {
  static String label(String paymentType) {
    switch (paymentType.toLowerCase()) {
      case 'credit_card':   return 'Kartu Kredit/Debit';
      case 'bca_va':        return 'Transfer BCA Virtual Account';
      case 'bni_va':        return 'Transfer BNI Virtual Account';
      case 'bri_va':        return 'Transfer BRI Virtual Account';
      case 'mandiri_bill':  return 'Mandiri Bill Payment';
      case 'permata_va':    return 'Permata Virtual Account';
      case 'other_va':      return 'Transfer Virtual Account';
      case 'bank_transfer': return 'Transfer Bank';
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
