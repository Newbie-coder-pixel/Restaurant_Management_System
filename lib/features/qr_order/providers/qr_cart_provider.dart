import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  final int preparationTimeMinutes; // ← TAMBAHAN untuk ML

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
    this.preparationTimeMinutes = 15, // default 15 menit
  });
}

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
  final String branchId;
  final String? customerName;
  final List<QrCartItem> items;
  final QrPaymentMethod? paymentMethod;

  const QrOrderSession({
    required this.tableId,
    this.tableName,
    required this.branchId,
    this.customerName,
    this.items = const [],
    this.paymentMethod,
  });

  QrOrderSession copyWith({
    String? tableId,
    String? tableName,
    String? branchId,
    String? customerName,
    List<QrCartItem>? items,
    QrPaymentMethod? paymentMethod,
  }) =>
      QrOrderSession(
        tableId: tableId ?? this.tableId,
        tableName: tableName ?? this.tableName,
        branchId: branchId ?? this.branchId,
        customerName: customerName ?? this.customerName,
        items: items ?? this.items,
        paymentMethod: paymentMethod ?? this.paymentMethod,
      );

  double get subtotal => items.fold(0, (sum, item) => sum + item.subtotal);
  double get taxAmount => subtotal * 0.11;
  double get totalAmount => subtotal + taxAmount;
  int get totalItems => items.fold(0, (sum, item) => sum + item.quantity);
  bool get isEmpty => items.isEmpty;
}

class QrCartNotifier extends StateNotifier<QrOrderSession> {
  QrCartNotifier({
    required String tableId,
    required String? tableName,
    required String branchId,
  }) : super(QrOrderSession(
          tableId: tableId,
          tableName: tableName,
          branchId: branchId,
        ));

  void addItem(MenuItem item) {
    final existing = state.items.indexWhere((i) => i.menuItem.id == item.id);
    if (existing >= 0) {
      final updated = List<QrCartItem>.from(state.items);
      updated[existing] =
          updated[existing].copyWith(quantity: updated[existing].quantity + 1);
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
        items:
            state.items.where((i) => i.menuItem.id != menuItemId).toList(),
      );
    }
  }

  void deleteItem(String menuItemId) {
    state = state.copyWith(
      items:
          state.items.where((i) => i.menuItem.id != menuItemId).toList(),
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
      branchId: state.branchId,
    );
  }

  int quantityOf(String menuItemId) {
    final idx =
        state.items.indexWhere((i) => i.menuItem.id == menuItemId);
    return idx >= 0 ? state.items[idx].quantity : 0;
  }
}

final qrCartProvider = StateNotifierProvider.family<QrCartNotifier,
    QrOrderSession, ({String tableId, String? tableName, String branchId})>(
  (ref, arg) => QrCartNotifier(
    tableId: arg.tableId,
    tableName: arg.tableName,
    branchId: arg.branchId,
  ),
);

final activeQrTableProvider =
    StateProvider<({String tableId, String? tableName, String branchId})>(
  (ref) => (tableId: '', tableName: null, branchId: ''),
);

final activeQrCartProvider = Provider<QrOrderSession>((ref) {
  final table = ref.watch(activeQrTableProvider);
  return ref.watch(qrCartProvider(table));
});

final activeQrCartNotifierProvider = Provider<QrCartNotifier>((ref) {
  final table = ref.watch(activeQrTableProvider);
  return ref.read(qrCartProvider(table).notifier);
});