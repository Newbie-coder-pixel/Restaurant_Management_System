enum OrderStatus { new_, created, preparing, ready, served, cancelled, paid }

/// Batas waktu makan gratis setelah makanan disajikan, sebelum kena
/// biaya kelebihan waktu (table turnover charge).
const Duration kMaxDineInDuration = Duration(hours: 2);

/// Biaya kelebihan waktu per jam (atau kelipatannya) setelah kMaxDineInDuration.
const int kOvertimeChargePerHour = 5000;

/// Hitung biaya kelebihan waktu makan berdasarkan waktu makanan disajikan.
/// Dipakai bersama oleh [OrderModel], kartu meja, dan alur pembayaran supaya
/// rumusnya selalu sinkron di seluruh aplikasi.
int calculateOvertimeCharge(DateTime? servedAt, {DateTime? now}) {
  if (servedAt == null) return 0;
  final elapsed = (now ?? DateTime.now()).difference(servedAt);
  final overMinutes = elapsed.inMinutes - kMaxDineInDuration.inMinutes;
  if (overMinutes <= 0) return 0;
  final overHours = (overMinutes / 60).ceil();
  return overHours * kOvertimeChargePerHour;
}

enum OrderSource { dineIn, online, takeaway }

enum OrderItemStatus { pending, preparing, ready, served, cancelled }

extension OrderStatusExt on OrderStatus {
  String get label {
    switch (this) {
      case OrderStatus.new_:      return 'Baru (Internal)';
      case OrderStatus.created:   return 'Baru (QR)';
      case OrderStatus.preparing: return 'Dimasak';
      case OrderStatus.ready:     return 'Siap';
      case OrderStatus.served:    return 'Disajikan';
      case OrderStatus.cancelled: return 'Dibatalkan';
      case OrderStatus.paid:      return 'Lunas';
    }
  }

  /// Nilai yang benar-benar disimpan ke database
  String get dbValue {
    switch (this) {
      case OrderStatus.new_:    return 'new';
      case OrderStatus.created: return 'created';
      default:                  return name;
    }
  }

  static OrderStatus fromString(String s) {
    final lower = s.toLowerCase().trim();
    switch (lower) {
      case 'new':       return OrderStatus.new_;
      case 'created':   return OrderStatus.created;
      case 'preparing': return OrderStatus.preparing;
      case 'ready':     return OrderStatus.ready;
      case 'served':    return OrderStatus.served;
      case 'paid':      return OrderStatus.paid;
      case 'cancelled': return OrderStatus.cancelled;
      default:          return OrderStatus.new_;
    }
  }
}

extension OrderSourceExt on OrderSource {
  /// Nilai yang benar-benar disimpan ke database (snake_case)
  String get dbValue {
    switch (this) {
      case OrderSource.dineIn:   return 'dine_in';
      case OrderSource.online:   return 'online';
      case OrderSource.takeaway: return 'takeaway';
    }
  }
}

OrderSource _orderSourceFromString(String s) {
  const map = {
    'dine_in':  OrderSource.dineIn,
    'dinein':   OrderSource.dineIn,
    'online':   OrderSource.online,
    'takeaway': OrderSource.takeaway,
  };
  return map[s.toLowerCase()] ?? OrderSource.dineIn;
}

// ==================== ORDER ITEM ====================
class OrderItem {
  final String id;
  final String orderId;
  final String menuItemId;
  final String menuItemName;
  final int quantity;
  final double unitPrice;

  // FIX Bug 2: simpan nilai DB mentah, expose getter yang tervalidasi
  final double _subtotalFromDb;

  final OrderItemStatus status;
  final String? specialRequests;
  final DateTime? sentToKitchenAt;
  final String? inventoryItemId;

  const OrderItem({
    required this.id,
    required this.orderId,
    required this.menuItemId,
    required this.menuItemName,
    required this.quantity,
    required this.unitPrice,
    required double subtotal,
    required this.status,
    this.specialRequests,
    this.sentToKitchenAt,
    this.inventoryItemId,
  }) : _subtotalFromDb = subtotal;

  /// Subtotal yang dihitung ulang dari quantity × unitPrice.
  double get calculatedSubtotal => quantity * unitPrice;

  /// Subtotal yang dipakai untuk semua kalkulasi:
  /// pakai nilai DB kalau valid (> 0), fallback ke kalkulasi lokal.
  /// Ini melindungi dari data korup di DB tanpa membuang nilai yang benar.
  double get subtotal =>
      _subtotalFromDb > 0 ? _subtotalFromDb : calculatedSubtotal;

  factory OrderItem.fromJson(Map<String, dynamic> j) => OrderItem(
        id: j['id'] ?? '',
        orderId: j['order_id'] ?? '',
        menuItemId: j['menu_item_id'] ?? '',
        menuItemName: j['menu_item_name'] ?? j['menu_items']?['name'] ?? '',
        quantity: j['quantity'] ?? 1,
        unitPrice: (j['unit_price'] ?? 0).toDouble(),
        subtotal: (j['subtotal'] ?? 0).toDouble(),
        status: OrderItemStatus.values.firstWhere(
          (e) => e.name == (j['status'] ?? 'pending'),
          orElse: () => OrderItemStatus.pending,
        ),
        specialRequests: j['special_requests'] ?? j['notes'],
        sentToKitchenAt: j['sent_to_kitchen_at'] != null
            ? DateTime.parse(j['sent_to_kitchen_at'])
            : null,
        inventoryItemId: j['inventory_item_id'],
      );
}

// ==================== ORDER MODEL ====================
class OrderModel {
  final String id;
  final String branchId;
  final String? tableId;
  final String? tableNumber;
  final String orderNumber;
  final OrderStatus status;
  final OrderSource source;
  final String? orderType;
  final String? customerName;
  final double discountAmount;
  final String? notes;
  final List<OrderItem> items;
  final DateTime createdAt;
  final DateTime? servedAt;
  final int? estimatedPrepMinutes; // hasil prediksi ML
  final bool billRequested;
  final DateTime? billRequestedAt;
  final String? customerPhone;
  final String? customerEmail;
  final String? queueNumber;

  // FIX Bug 1: simpan total dari DB sebagai fallback kalau items kosong
  final double _totalAmountFromDb;
  final double _subtotalFromDb;
  final double _taxAmountFromDb;

  // Kalkulasi dari items (sumber kebenaran utama)
  double get subtotal => items.isNotEmpty
      ? items.fold(0.0, (sum, item) => sum + item.subtotal)
      : _subtotalFromDb; // fallback ke nilai DB

  double get pb1Amount => (subtotal + serviceChargeAmount) * 0.10;
  double get serviceChargeAmount => subtotal * 0.03;
  double get taxAmount => pb1Amount + serviceChargeAmount;

  /// Total yang dipakai di seluruh app.
  /// Prioritas: kalkulasi dari items → fallback ke total_amount dari DB.
  /// Mencegah Rp 0 di cashier screen saat join order_items gagal.
  double get totalAmount {
    if (items.isNotEmpty) {
      return subtotal + taxAmount - discountAmount;
    }
    // Fallback: pakai nilai DB kalau items tidak ter-load
    if (_totalAmountFromDb > 0) return _totalAmountFromDb;
    // Last resort: estimasi dari subtotal DB + 13% - diskon
    if (_subtotalFromDb > 0) {
      return _subtotalFromDb * 1.13 - discountAmount;
    }
    return 0.0;
  }

  /// Biaya kelebihan waktu makan (Rp), dihitung dari [servedAt].
  /// 0 kalau makanan belum disajikan atau belum melewati kMaxDineInDuration.
  int get overtimeCharge => calculateOvertimeCharge(servedAt);

  bool get isOvertime => overtimeCharge > 0;

  /// Total akhir yang harus dibayar, termasuk biaya kelebihan waktu (kalau ada).
  double get totalAmountWithOvertime => totalAmount + overtimeCharge;

  /// True kalau totalAmount berasal dari fallback DB, bukan dari items.
  /// Berguna untuk UI yang perlu menampilkan indikator "data mungkin tidak lengkap".
  bool get isTotalEstimated => items.isEmpty && _totalAmountFromDb <= 0 && _subtotalFromDb > 0;

  OrderModel({
    required this.id,
    required this.branchId,
    this.tableId,
    this.tableNumber,
    required this.orderNumber,
    required this.status,
    required this.source,
    this.orderType,
    this.customerName,
    this.discountAmount = 0.0,
    this.notes,
    this.items = const [],
    required this.createdAt,
    this.servedAt,
    this.estimatedPrepMinutes,
    this.billRequested = false,
    this.billRequestedAt,
    this.customerPhone,
    this.customerEmail,
    this.queueNumber,
    double totalAmountFromDb = 0.0,
    double subtotalFromDb = 0.0,
    double taxAmountFromDb = 0.0,
  })  : _totalAmountFromDb = totalAmountFromDb,
        _subtotalFromDb = subtotalFromDb,
        _taxAmountFromDb = taxAmountFromDb;

  factory OrderModel.fromJson(Map<String, dynamic> j) {
    final itemsList = j['order_items'] != null
        ? (j['order_items'] as List)
            .map((i) => OrderItem.fromJson(i as Map<String, dynamic>))
            .toList()
        : <OrderItem>[];

    // FIX Bug 4: gunakan createdAt dari DB kalau ada, jangan fallback ke now()
    // karena itu akan merusak sorting history. Pakai epoch sebagai sentinel.
    final createdAtRaw = j['created_at'] as String?;
    final createdAt = createdAtRaw != null
        ? DateTime.tryParse(createdAtRaw) ?? DateTime.fromMillisecondsSinceEpoch(0)
        : DateTime.fromMillisecondsSinceEpoch(0);

    return OrderModel(
      id: j['id'] ?? '',
      branchId: j['branch_id'] ?? '',
      tableId: j['table_id'],
      tableNumber: j['restaurant_tables']?['table_number'],
      orderNumber: j['order_number'] ?? j['queue_number'] ?? 'UNKNOWN',
      status: OrderStatusExt.fromString(j['status'] ?? 'created'),
      source: _orderSourceFromString(j['source'] ?? 'dine_in'),
      orderType: j['order_type'] as String?,
      customerName: j['customer_name'],
      discountAmount: (j['discount_amount'] ?? 0).toDouble(),
      notes: j['notes'],
      items: itemsList,
      createdAt: createdAt,
      servedAt: j['served_at'] != null
          ? DateTime.tryParse(j['served_at'] as String)
          : null,
      estimatedPrepMinutes: (j['estimated_prep_minutes'] as num?)?.toInt(),
      billRequested: (j['bill_requested'] as bool?) ?? false,
      billRequestedAt: j['bill_requested_at'] != null
          ? DateTime.tryParse(j['bill_requested_at'] as String)
          : null,
      customerPhone: j['customer_phone'] as String?,
      customerEmail: j['customer_email'] as String?,
      queueNumber: j['queue_number'] as String?,
      // FIX Bug 1: baca nilai finansial dari DB sebagai fallback
      totalAmountFromDb: (j['total_amount'] ?? 0).toDouble(),
      subtotalFromDb: (j['subtotal'] ?? 0).toDouble(),
      taxAmountFromDb: (j['tax_amount'] ?? 0).toDouble(),
    );
  }

  /// Buat salinan dengan field tertentu yang diubah.
  /// Berguna untuk optimistic update status tanpa re-fetch dari DB.
  OrderModel copyWith({
    String? id,
    String? branchId,
    String? tableId,
    String? tableNumber,
    String? orderNumber,
    OrderStatus? status,
    OrderSource? source,
    String? orderType,
    String? customerName,
    double? discountAmount,
    String? notes,
    List<OrderItem>? items,
    DateTime? createdAt,
    DateTime? servedAt,
    int? estimatedPrepMinutes,
    bool? billRequested,
    DateTime? billRequestedAt,
    String? customerPhone,
    String? customerEmail,
    String? queueNumber,
  }) {
    return OrderModel(
      id: id ?? this.id,
      branchId: branchId ?? this.branchId,
      tableId: tableId ?? this.tableId,
      tableNumber: tableNumber ?? this.tableNumber,
      orderNumber: orderNumber ?? this.orderNumber,
      status: status ?? this.status,
      source: source ?? this.source,
      orderType: orderType ?? this.orderType,
      customerName: customerName ?? this.customerName,
      discountAmount: discountAmount ?? this.discountAmount,
      notes: notes ?? this.notes,
      items: items ?? this.items,
      createdAt: createdAt ?? this.createdAt,
      servedAt: servedAt ?? this.servedAt,
      estimatedPrepMinutes: estimatedPrepMinutes ?? this.estimatedPrepMinutes,
      billRequested: billRequested ?? this.billRequested,
      billRequestedAt: billRequestedAt ?? this.billRequestedAt,
      customerPhone: customerPhone ?? this.customerPhone,
      customerEmail: customerEmail ?? this.customerEmail,
      queueNumber: queueNumber ?? this.queueNumber,
      totalAmountFromDb: _totalAmountFromDb,
      subtotalFromDb: _subtotalFromDb,
      taxAmountFromDb: _taxAmountFromDb,
    );
  }
}