// lib/features/payment/midtrans/midtrans_provider.dart
// ─────────────────────────────────────────────────────────────────────────────
// Riverpod Provider untuk alur pembayaran Midtrans
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/order_model.dart';
import '../models/midtrans_model.dart';
import 'midtrans_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// STATE
// ─────────────────────────────────────────────────────────────────────────────

enum MidtransFlowStep {
  idle,
  creatingToken,   // sedang minta snap_token ke Edge Function
  waitingPayment,  // user ada di halaman Snap Midtrans
  polling,         // menunggu webhook (VA / QRIS bisa lambat)
  done,
}

class MidtransState {
  final MidtransFlowStep step;
  final String? snapToken;
  final String? orderId;
  final String? errorMessage;
  final MidtransPaymentResult? result;
  final MidtransPaymentStatus? confirmedStatus; // dari DB setelah webhook

  // Progress polling (0.0 – 1.0)
  final int pollingAttempt;
  final int maxPollingAttempts;

  const MidtransState({
    this.step = MidtransFlowStep.idle,
    this.snapToken,
    this.orderId,
    this.errorMessage,
    this.result,
    this.confirmedStatus,
    this.pollingAttempt = 0,
    this.maxPollingAttempts = 20,
  });

  double get pollingProgress =>
      maxPollingAttempts > 0 ? pollingAttempt / maxPollingAttempts : 0;

  bool get isLoading =>
      step == MidtransFlowStep.creatingToken ||
      step == MidtransFlowStep.polling;

  bool get isSuccess =>
      confirmedStatus == MidtransPaymentStatus.paid;

  bool get isPending =>
      confirmedStatus == MidtransPaymentStatus.pending ||
      step == MidtransFlowStep.polling;

  MidtransState copyWith({
    MidtransFlowStep? step,
    String? snapToken,
    String? orderId,
    String? errorMessage,
    bool clearError = false,
    MidtransPaymentResult? result,
    MidtransPaymentStatus? confirmedStatus,
    int? pollingAttempt,
    int? maxPollingAttempts,
  }) {
    return MidtransState(
      step: step ?? this.step,
      snapToken: snapToken ?? this.snapToken,
      orderId: orderId ?? this.orderId,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      result: result ?? this.result,
      confirmedStatus: confirmedStatus ?? this.confirmedStatus,
      pollingAttempt: pollingAttempt ?? this.pollingAttempt,
      maxPollingAttempts: maxPollingAttempts ?? this.maxPollingAttempts,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NOTIFIER
// ─────────────────────────────────────────────────────────────────────────────

class MidtransNotifier extends StateNotifier<MidtransState> {
  MidtransNotifier() : super(const MidtransState());

  Timer? _pollingTimer;

  // ── Token pembatalan ────────────────────────────────────────────────────
  //
  // PENTING: tanpa ini, memanggil reset() saat polling sedang berjalan
  // TIDAK benar-benar menghentikan loop di _startPolling(). Loop akan terus
  // jalan di background dan menimpa balik `state` yang sudah di-reset, jadi
  // overlay "Mengecek status pembayaran..." bisa muncul lagi tiba-tiba
  // walau user sudah menutupnya.
  //
  // Setiap pemanggilan pay()/reset() menaikkan _activeRequestId. Kode yang
  // sedang berjalan (hasil await sebelumnya) menyimpan requestId miliknya
  // sendiri dan selalu cek apakah masih cocok dengan _activeRequestId
  // sebelum melanjutkan/menulis state. Kalau sudah tidak cocok → berarti
  // sudah di-reset/dibatalkan oleh proses baru → langsung berhenti.
  int _activeRequestId = 0;

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  // ── Full flow: token + UI + polling ──────────────────────────────────────
  Future<void> pay({
    required OrderModel order,
    required String branchId,
    void Function(MidtransPaymentStatus status)? onStatusConfirmed,
  }) async {
    // Request baru → token lama (kalau ada) jadi basi & loop-nya akan
    // berhenti sendiri di pengecekan requestId berikutnya.
    final requestId = ++_activeRequestId;

    state = state.copyWith(
      step: MidtransFlowStep.creatingToken,
      clearError: true,
      orderId: order.id,
    );

    // 1. Buat Snap token
    final tokenResult = await MidtransService.createSnapToken(
      order: order,
      branchId: branchId,
    );

    // Kalau sudah di-reset/dibatalkan selama menunggu token → hentikan,
    // jangan tulis state lagi (mencegah overlay muncul lagi tiba-tiba).
    if (requestId != _activeRequestId) return;

    if (!tokenResult.success) {
      state = state.copyWith(
        step: MidtransFlowStep.idle,
        errorMessage: tokenResult.errorMessage,
      );
      return;
    }

    state = state.copyWith(
      step: MidtransFlowStep.waitingPayment,
      snapToken: tokenResult.snapToken,
    );

    // 2. Buka Snap UI — blocking sampai user selesai/tutup
    final payResult = await MidtransService.startPayment(
      snapToken: tokenResult.snapToken!,
      orderId: order.id,
    );

    if (requestId != _activeRequestId) return;

    state = state.copyWith(result: payResult);

    if (payResult.isCancelled) {
      // User tutup halaman tanpa bayar
      state = state.copyWith(
        step: MidtransFlowStep.idle,
        confirmedStatus: MidtransPaymentStatus.cancelled,
      );
      onStatusConfirmed?.call(MidtransPaymentStatus.cancelled);
      return;
    }

    if (payResult.isFailed) {
      state = state.copyWith(
        step: MidtransFlowStep.idle,
        errorMessage: payResult.errorMessage,
        confirmedStatus: MidtransPaymentStatus.failed,
      );
      onStatusConfirmed?.call(MidtransPaymentStatus.failed);
      return;
    }

    // 3. Polling DB — untuk success/pending, tunggu webhook update DB
    //    (jangan rely pada callback SDK untuk update status)
    if (payResult.needsPolling) {
      await _startPolling(
        requestId: requestId,
        orderId: order.id,
        onStatusConfirmed: onStatusConfirmed,
      );
    }
  }

  // ── Polling: cek DB setiap 3 detik sampai paid/failed ────────────────────
  Future<void> _startPolling({
    required int requestId,
    required String orderId,
    void Function(MidtransPaymentStatus)? onStatusConfirmed,
    int maxAttempts = 20,
  }) async {
    state = state.copyWith(
      step: MidtransFlowStep.polling,
      pollingAttempt: 0,
      maxPollingAttempts: maxAttempts,
    );

    for (int i = 1; i <= maxAttempts; i++) {
      await Future.delayed(const Duration(seconds: 3));

      // Sudah di-reset/dibatalkan (mis. user klik "Tutup" di overlay) →
      // hentikan loop sekarang, jangan tulis state lagi.
      if (!mounted || requestId != _activeRequestId) return;

      state = state.copyWith(pollingAttempt: i);

      final dbStatus = await MidtransService.checkPaymentStatus(orderId);

      if (!mounted || requestId != _activeRequestId) return;

      if (dbStatus == MidtransPaymentStatus.paid) {
        state = state.copyWith(
          step: MidtransFlowStep.done,
          confirmedStatus: MidtransPaymentStatus.paid,
        );
        onStatusConfirmed?.call(MidtransPaymentStatus.paid);
        return;
      }

      if (dbStatus == MidtransPaymentStatus.failed ||
          dbStatus == MidtransPaymentStatus.cancelled) {
        state = state.copyWith(
          step: MidtransFlowStep.idle,
          confirmedStatus: dbStatus,
          errorMessage: 'Pembayaran ${dbStatus.label.toLowerCase()}',
        );
        onStatusConfirmed?.call(dbStatus);
        return;
      }
    }

    // Timeout polling — bayar mungkin masih pending (VA belum ditransfer)
    state = state.copyWith(
      step: MidtransFlowStep.done,
      confirmedStatus: MidtransPaymentStatus.pending,
    );
    onStatusConfirmed?.call(MidtransPaymentStatus.pending);
  }

  // ── Manual cek status (tombol "Cek Status" di UI) ────────────────────────
  Future<void> checkStatus(String orderId) async {
    state = state.copyWith(step: MidtransFlowStep.polling, clearError: true);
    final status = await MidtransService.checkPaymentStatus(orderId);
    state = state.copyWith(
      step: MidtransFlowStep.done,
      confirmedStatus: status,
    );
  }

  void reset() {
    // Naikkan requestId → pay()/_startPolling() yang masih berjalan di
    // background akan berhenti sendiri di pengecekan berikutnya, tidak
    // akan menimpa balik state yang baru saja di-reset ini.
    _activeRequestId++;
    _pollingTimer?.cancel();
    state = const MidtransState();
  }

  void clearError() => state = state.copyWith(clearError: true);
}

// ─────────────────────────────────────────────────────────────────────────────
// PROVIDERS
// ─────────────────────────────────────────────────────────────────────────────

// Provider per order (family by orderId) agar state tidak bercampur
final midtransProvider =
    StateNotifierProvider.family<MidtransNotifier, MidtransState, String>(
  (ref, orderId) => MidtransNotifier(),
);

// Provider global untuk satu sesi aktif (CashierScreen)
final activeMidtransProvider =
    StateNotifierProvider<MidtransNotifier, MidtransState>(
  (ref) => MidtransNotifier(),
);