import 'package:flutter/foundation.dart';

enum QrOrderStatus {
  pending,
  confirmed,
  preparing,
  ready,
  completed,
  cancelled;

  String get label {
    switch (this) {
      case QrOrderStatus.pending:
        return 'Menunggu Konfirmasi';
      case QrOrderStatus.confirmed:
        return 'Dikonfirmasi';
      case QrOrderStatus.preparing:
        return 'Sedang Dimasak';
      case QrOrderStatus.ready:
        return 'Siap Disajikan';
      case QrOrderStatus.completed:
        return 'Selesai';
      case QrOrderStatus.cancelled:
        return 'Dibatalkan';
    }
  }

  String get emoji {
    switch (this) {
      case QrOrderStatus.pending:
        return '⏳';
      case QrOrderStatus.confirmed:
        return '✅';
      case QrOrderStatus.preparing:
        return '👨‍🍳';
      case QrOrderStatus.ready:
        return '🍽️';
      case QrOrderStatus.completed:
        return '🎉';
      case QrOrderStatus.cancelled:
        return '❌';
    }
  }

  int get stepIndex {
    switch (this) {
      case QrOrderStatus.pending:
        return 0;
      case QrOrderStatus.confirmed:
        return 1;
      case QrOrderStatus.preparing:
        return 2;
      case QrOrderStatus.ready:
        return 3;
      case QrOrderStatus.completed:
        return 4;
      case QrOrderStatus.cancelled:
        return -1;
    }
  }

  /// Progress 0.0 – 1.0 untuk LinearProgressIndicator di tracker screen
  double get progress {
    switch (this) {
      case QrOrderStatus.pending:
        return 0.0;
      case QrOrderStatus.confirmed:
        return 0.25;
      case QrOrderStatus.preparing:
        return 0.5;
      case QrOrderStatus.ready:
        return 0.75;
      case QrOrderStatus.completed:
        return 1.0;
      case QrOrderStatus.cancelled:
        return 0.0;
    }
  }
}

enum QrPaymentStatus { unpaid, paid, refunded }

@immutable
class QrOrderItemModel {
  final String menuItemId;
  final String menuItemName;
  final double price;
  final int quantity;
  final String? notes;
  final String? imageUrl;

  const QrOrderItemModel({
    required this.menuItemId,
    required this.menuItemName,
    required this.price,
    required this.quantity,
    this.notes,
    this.imageUrl,
  });

  double get subtotal => price * quantity;

  factory QrOrderItemModel.fromMap(Map<String, dynamic> map) =>
      QrOrderItemModel(
        menuItemId: map['menu_item_id'] as String,
        menuItemName: map['menu_item_name'] as String,
        price: (map['price'] as num).toDouble(),
        quantity: map['quantity'] as int,
        notes: map['notes'] as String?,
        imageUrl: map['image_url'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'menu_item_id': menuItemId,
        'menu_item_name': menuItemName,
        'price': price,
        'quantity': quantity,
        if (notes != null) 'notes': notes,
        if (imageUrl != null) 'image_url': imageUrl,
      };
}

@immutable
class QrOrderModel {
  final String id;
  final String queueNumber;
  final String tableId;
  final String tableName;
  final String customerName;
  final List<QrOrderItemModel> items;
  final double totalAmount;
  final QrOrderStatus status;
  final QrPaymentStatus paymentStatus;
  final String paymentMethod; // 'kasir' | 'qris'
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? branchId;
  final String? notes;

  const QrOrderModel({
    required this.id,
    required this.queueNumber,
    required this.tableId,
    required this.tableName,
    required this.customerName,
    required this.items,
    required this.totalAmount,
    required this.status,
    required this.paymentStatus,
    required this.paymentMethod,
    required this.createdAt,
    this.updatedAt,
    this.branchId,
    this.notes,
  });

  factory QrOrderModel.fromMap(Map<String, dynamic> map) => QrOrderModel(
        id: map['id'] as String,
        queueNumber: map['queue_number'] as String,
        tableId: map['table_id'] as String,
        tableName: map['table_name'] as String,
        customerName: map['customer_name'] as String,
        items: (map['items'] as List<dynamic>)
            .map((e) => QrOrderItemModel.fromMap(e as Map<String, dynamic>))
            .toList(),
        totalAmount: (map['total_amount'] as num).toDouble(),
        status: QrOrderStatus.values.firstWhere(
          (s) => s.name == map['status'],
          orElse: () => QrOrderStatus.pending,
        ),
        paymentStatus: QrPaymentStatus.values.firstWhere(
          (s) => s.name == map['payment_status'],
          orElse: () => QrPaymentStatus.unpaid,
        ),
        paymentMethod: map['payment_method'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: map['updated_at'] != null
            ? DateTime.parse(map['updated_at'] as String)
            : null,
        branchId: map['branch_id'] as String?,
        notes: map['notes'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'queue_number': queueNumber,
        'table_id': tableId,
        'table_name': tableName,
        'customer_name': customerName,
        'items': items.map((i) => i.toMap()).toList(),
        'total_amount': totalAmount,
        'status': status.name,
        'payment_status': paymentStatus.name,
        'payment_method': paymentMethod,
        'created_at': createdAt.toIso8601String(),
        if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
        if (branchId != null) 'branch_id': branchId,
        if (notes != null) 'notes': notes,
      };

  QrOrderModel copyWith({QrOrderStatus? status, QrPaymentStatus? paymentStatus}) =>
      QrOrderModel(
        id: id,
        queueNumber: queueNumber,
        tableId: tableId,
        tableName: tableName,
        customerName: customerName,
        items: items,
        totalAmount: totalAmount,
        status: status ?? this.status,
        paymentStatus: paymentStatus ?? this.paymentStatus,
        paymentMethod: paymentMethod,
        createdAt: createdAt,
        updatedAt: updatedAt,
        branchId: branchId,
        notes: notes,
      );

  /// Apakah order ini masih bisa ditrack (belum selesai/cancel)
  bool get isActive =>
      status != QrOrderStatus.completed && status != QrOrderStatus.cancelled;

  /// Progress 0.0 – 1.0 untuk progress indicator
  double get progress => status.progress;
}