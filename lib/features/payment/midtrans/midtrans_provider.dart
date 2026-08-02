// lib/features/payment/midtrans/midtrans_provider.dart
// ─────────────────────────────────────────────────────────────────────────────
// Riverpod Provider for the Midtrans payment flow
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
  creatingToken,   // requesting a snap_token from the Edge Function
  waitingPayment,  // user is on the Midtrans Snap page
  polling,         // waiting for the webhook (VA / QRIS can be slow)
  done,
}

class MidtransState {
  final MidtransFlowStep step;
  final String? snapToken;
  final String? orderId;
  final String? errorMessage;
  final MidtransPaymentResult? result;
  final MidtransPaymentStatus? confirmedStatus; // from the DB after the webhook

  // Polling progress (0.0 – 1.0)
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

  // ── Cancellation token ────────────────────────────────────────────────────
  //
  // IMPORTANT: without this, calling reset() while polling is in progress
  // does NOT actually stop the loop in _startPolling(). The loop keeps
  // running in the background and overwrites the `state` that was just
  // reset, so the "Checking payment status..." overlay can suddenly
  // reappear even after the user has closed it.
  //
  // Every call to pay()/reset() increments _activeRequestId. Code that is
  // currently running (resumed after a previous await) holds its own
  // requestId and always checks whether it still matches _activeRequestId
  // before continuing/writing state. If it no longer matches → it means
  // a new process has reset/cancelled it → stop immediately.
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
    // New request → the old token (if any) becomes stale & its loop will
    // stop on its own at the next requestId check.
    final requestId = ++_activeRequestId;

    state = state.copyWith(
      step: MidtransFlowStep.creatingToken,
      clearError: true,
      orderId: order.id,
    );

    // 1. Create the Snap token
    final tokenResult = await MidtransService.createSnapToken(
      order: order,
      branchId: branchId,
    );

    // If it has been reset/cancelled while waiting for the token → stop,
    // don't write state again (prevents the overlay from suddenly reappearing).
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

    // 2. Open the Snap UI — blocks until the user finishes/closes it
    final payResult = await MidtransService.startPayment(
      snapToken: tokenResult.snapToken!,
      orderId: order.id,
    );

    if (requestId != _activeRequestId) return;

    state = state.copyWith(result: payResult);

    if (payResult.isCancelled) {
      // User closed the page without paying
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

    // 3. Poll the DB — for success/pending, wait for the webhook to update the DB
    //    (don't rely on the SDK callback for status updates)
    if (payResult.needsPolling) {
      await _startPolling(
        requestId: requestId,
        orderId: order.id,
        onStatusConfirmed: onStatusConfirmed,
      );
    }
  }

  // ── Polling: check the DB every 3 seconds until paid/failed ────────────────────
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

      // Already reset/cancelled (e.g. user clicked "Close" in the overlay) →
      // stop the loop now, don't write state again.
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
          errorMessage: 'Payment ${dbStatus.label.toLowerCase()}',
        );
        onStatusConfirmed?.call(dbStatus);
        return;
      }
    }

    // Polling timeout — payment may still be pending (VA not yet transferred)
    state = state.copyWith(
      step: MidtransFlowStep.done,
      confirmedStatus: MidtransPaymentStatus.pending,
    );
    onStatusConfirmed?.call(MidtransPaymentStatus.pending);
  }

  // ── Manual status check ("Check Status" button in the UI) ────────────────────────
  Future<void> checkStatus(String orderId) async {
    state = state.copyWith(step: MidtransFlowStep.polling, clearError: true);
    final status = await MidtransService.checkPaymentStatus(orderId);
    state = state.copyWith(
      step: MidtransFlowStep.done,
      confirmedStatus: status,
    );
  }

  void reset() {
    // Increment requestId → any pay()/_startPolling() still running in the
    // background will stop on its own at the next check, and won't
    // overwrite the state that was just reset here.
    _activeRequestId++;
    _pollingTimer?.cancel();
    state = const MidtransState();
  }

  void clearError() => state = state.copyWith(clearError: true);
}

// ─────────────────────────────────────────────────────────────────────────────
// PROVIDERS
// ─────────────────────────────────────────────────────────────────────────────

// Provider per order (family by orderId) so state doesn't get mixed up
final midtransProvider =
    StateNotifierProvider.family<MidtransNotifier, MidtransState, String>(
  (ref, orderId) => MidtransNotifier(),
);

// Global provider for a single active session (CashierScreen)
final activeMidtransProvider =
    StateNotifierProvider<MidtransNotifier, MidtransState>(
  (ref) => MidtransNotifier(),
);