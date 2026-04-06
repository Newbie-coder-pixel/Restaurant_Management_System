import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/qr_order_repository.dart';
// MenuItem sudah didefinisikan di qr_cart_provider — re-export dari sini
// supaya file lain cukup import qr_menu_provider saja jika perlu.
export 'qr_cart_provider.dart' show MenuItem;

// ─── State class untuk menu ───────────────────────────────────────────────────

class QrMenuState {
  final List<Map<String, dynamic>> rawItems;
  final bool isLoading;
  final String? error;

  const QrMenuState({
    this.rawItems = const [],
    this.isLoading = false,
    this.error,
  });

  QrMenuState copyWith({
    List<Map<String, dynamic>>? rawItems,
    bool? isLoading,
    String? error,
  }) {
    return QrMenuState(
      rawItems: rawItems ?? this.rawItems,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  bool get hasError => error != null;
  bool get isEmpty => rawItems.isEmpty;
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class QrMenuNotifier extends StateNotifier<QrMenuState> {
  final QrOrderRepository _repo;

  QrMenuNotifier(this._repo) : super(const QrMenuState());

  Future<void> loadMenu(String branchId) async {
    if (branchId.isEmpty) {
      state = state.copyWith(
        error: 'Branch ID tidak valid',
        isLoading: false,
      );
      return;
    }

    state = state.copyWith(isLoading: true, error: null);

    try {
      final items = await _repo.fetchMenuByBranch(branchId);
      state = state.copyWith(rawItems: items, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        error: e.toString(),
        isLoading: false,
      );
    }
  }

  void reset() => state = const QrMenuState();
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final qrMenuProvider =
    StateNotifierProvider.family<QrMenuNotifier, QrMenuState, String>(
  (ref, branchId) {
    final notifier = QrMenuNotifier(ref.read(qrOrderRepositoryProvider));
    notifier.loadMenu(branchId);
    return notifier;
  },
);