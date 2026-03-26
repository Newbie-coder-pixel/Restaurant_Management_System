import 'package:flutter_riverpod/flutter_riverpod.dart';

class CartItem {
  final String menuItemId;
  final String name;
  final double price;
  final String? imageUrl;
  int quantity;
  String? notes;

  CartItem({
    required this.menuItemId,
    required this.name,
    required this.price,
    this.imageUrl,
    this.quantity = 1,
    this.notes,
  });

  double get subtotal => price * quantity;

  CartItem copyWith({int? quantity, String? notes}) => CartItem(
    menuItemId: menuItemId,
    name: name,
    price: price,
    imageUrl: imageUrl,
    quantity: quantity ?? this.quantity,
    notes: notes ?? this.notes,
  );
}

class CartState {
  final List<CartItem> items;
  final String? branchId;
  final String? branchName;
  final String? tableNotes; // meja / nama tamu untuk takeaway

  const CartState({
    this.items = const [],
    this.branchId,
    this.branchName,
    this.tableNotes,
  });

  double get subtotal => items.fold(0, (s, i) => s + i.subtotal);
  double get tax => subtotal * 0.11;
  double get total => subtotal + tax;
  int get itemCount => items.fold(0, (s, i) => s + i.quantity);
  bool get isEmpty => items.isEmpty;

  CartState copyWith({
    List<CartItem>? items,
    String? branchId,
    String? branchName,
    String? tableNotes,
  }) => CartState(
    items: items ?? this.items,
    branchId: branchId ?? this.branchId,
    branchName: branchName ?? this.branchName,
    tableNotes: tableNotes ?? this.tableNotes,
  );
}

class CartNotifier extends StateNotifier<CartState> {
  CartNotifier() : super(const CartState());

  void setBranch(String branchId, String branchName) {
    // Jika ganti branch, clear cart
    if (state.branchId != null && state.branchId != branchId) {
      state = CartState(branchId: branchId, branchName: branchName);
    } else {
      state = state.copyWith(branchId: branchId, branchName: branchName);
    }
  }

  void addItem(CartItem item) {
    final existing = state.items.indexWhere((i) => i.menuItemId == item.menuItemId);
    if (existing >= 0) {
      final updated = List<CartItem>.from(state.items);
      updated[existing] = updated[existing].copyWith(
        quantity: updated[existing].quantity + 1);
      state = state.copyWith(items: updated);
    } else {
      state = state.copyWith(items: [...state.items, item]);
    }
  }

  void removeItem(String menuItemId) {
    final updated = state.items.where((i) => i.menuItemId != menuItemId).toList();
    state = state.copyWith(items: updated);
  }

  void updateQuantity(String menuItemId, int qty) {
    if (qty <= 0) { removeItem(menuItemId); return; }
    final updated = List<CartItem>.from(state.items);
    final idx = updated.indexWhere((i) => i.menuItemId == menuItemId);
    if (idx >= 0) updated[idx] = updated[idx].copyWith(quantity: qty);
    state = state.copyWith(items: updated);
  }

  void updateNotes(String menuItemId, String? notes) {
    final updated = List<CartItem>.from(state.items);
    final idx = updated.indexWhere((i) => i.menuItemId == menuItemId);
    if (idx >= 0) updated[idx] = updated[idx].copyWith(notes: notes);
    state = state.copyWith(items: updated);
  }

  void setTableNotes(String? notes) => state = state.copyWith(tableNotes: notes);

  void clear() => state = CartState(
    branchId: state.branchId, branchName: state.branchName);
}

final cartProvider = StateNotifierProvider<CartNotifier, CartState>(
  (ref) => CartNotifier());