import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─── MenuItem (local model for QR order flow) ─────────────────────────────────
// Defined here to avoid dependency on the internal menu feature domain layer.

class MenuItem {
  final String id;
  final String name;
  final String description;
  final double price;
  final String categoryId;
  final String categoryName;
  final String? imageUrl;
  final bool isAvailable;
  final int sortOrder;

  const MenuItem({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.categoryId,
    required this.categoryName,
    this.imageUrl,
    this.isAvailable = true,
    this.sortOrder = 0,
  });
}

// ─── Models ───────────────────────────────────────────────────────────────────

class QrCartItem {
  final MenuItem menuItem;
  final int quantity;
  final String? notes;

  const QrCartItem({
    required this.menuItem,
    required this.quantity,
    this.notes,
  });

  QrCartItem copyWith({int? quantity, String? notes}) => QrCartItem(
        menuItem: menuItem,
        quantity: quantity ?? this.quantity,
        notes: notes ?? this.notes,
      );

  double get subtotal => menuItem.price * quantity;
}

enum QrPaymentMethod { kasir, qris }

class QrOrderSession {
  final String tableId;
  final String? tableName;
  final String? customerName;
  final List<QrCartItem> items;
  final QrPaymentMethod? paymentMethod;

  const QrOrderSession({
    required this.tableId,
    this.tableName,
    this.customerName,
    this.items = const [],
    this.paymentMethod,
  });

  QrOrderSession copyWith({
    String? tableId,
    String? tableName,
    String? customerName,
    List<QrCartItem>? items,
    QrPaymentMethod? paymentMethod,
  }) =>
      QrOrderSession(
        tableId: tableId ?? this.tableId,
        tableName: tableName ?? this.tableName,
        customerName: customerName ?? this.customerName,
        items: items ?? this.items,
        paymentMethod: paymentMethod ?? this.paymentMethod,
      );

  double get totalAmount =>
      items.fold(0, (sum, item) => sum + item.subtotal);

  int get totalItems =>
      items.fold(0, (sum, item) => sum + item.quantity);

  bool get isEmpty => items.isEmpty;
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class QrCartNotifier extends StateNotifier<QrOrderSession> {
  QrCartNotifier(String tableId, String? tableName)
      : super(QrOrderSession(tableId: tableId, tableName: tableName));

  void addItem(MenuItem item) {
    final existing = state.items.indexWhere((i) => i.menuItem.id == item.id);
    if (existing >= 0) {
      final updated = List<QrCartItem>.from(state.items);
      updated[existing] = updated[existing]
          .copyWith(quantity: updated[existing].quantity + 1);
      state = state.copyWith(items: updated);
    } else {
      state = state.copyWith(
        items: [...state.items, QrCartItem(menuItem: item, quantity: 1)],
      );
    }
  }

  void removeItem(String menuItemId) {
    final existing =
        state.items.indexWhere((i) => i.menuItem.id == menuItemId);
    if (existing < 0) return;
    final current = state.items[existing];
    if (current.quantity > 1) {
      final updated = List<QrCartItem>.from(state.items);
      updated[existing] = current.copyWith(quantity: current.quantity - 1);
      state = state.copyWith(items: updated);
    } else {
      state = state.copyWith(
        items: state.items.where((i) => i.menuItem.id != menuItemId).toList(),
      );
    }
  }

  void deleteItem(String menuItemId) {
    state = state.copyWith(
      items: state.items.where((i) => i.menuItem.id != menuItemId).toList(),
    );
  }

  void updateNotes(String menuItemId, String notes) {
    final updated = state.items.map((i) {
      if (i.menuItem.id == menuItemId) return i.copyWith(notes: notes);
      return i;
    }).toList();
    state = state.copyWith(items: updated);
  }

  void setCustomerInfo({required String name}) {
    state = state.copyWith(customerName: name);
  }

  void setPaymentMethod(QrPaymentMethod method) {
    state = state.copyWith(paymentMethod: method);
  }

  void clearCart() {
    state = QrOrderSession(
      tableId: state.tableId,
      tableName: state.tableName,
    );
  }

  int quantityOf(String menuItemId) {
    final idx = state.items.indexWhere((i) => i.menuItem.id == menuItemId);
    return idx >= 0 ? state.items[idx].quantity : 0;
  }
}

// ─── Providers ────────────────────────────────────────────────────────────────

// Keyed by tableId so multiple tables can coexist if needed
final qrCartProvider = StateNotifierProvider.family<QrCartNotifier,
    QrOrderSession, ({String tableId, String? tableName})>(
  (ref, arg) => QrCartNotifier(arg.tableId, arg.tableName),
);

// Convenience: active table session (set when navigating from QR scan)
final activeQrTableProvider = StateProvider<({String tableId, String? tableName})>(
  (ref) => (tableId: '', tableName: null),
);

// Derived: active cart session
final activeQrCartProvider = Provider<QrOrderSession>((ref) {
  final table = ref.watch(activeQrTableProvider);
  return ref.watch(qrCartProvider(table));
});

final activeQrCartNotifierProvider =
    Provider<QrCartNotifier>((ref) {
  final table = ref.watch(activeQrTableProvider);
  return ref.read(qrCartProvider(table).notifier);
});