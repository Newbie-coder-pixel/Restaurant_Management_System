// lib/features/multi_branch/models/transfer_stock_model.dart

enum TransferStatus { pending, received, cancelled }

extension TransferStatusX on TransferStatus {
  String get name => switch (this) {
        TransferStatus.pending  => 'pending',
        TransferStatus.received => 'received',
        TransferStatus.cancelled => 'cancelled',
      };

  String get label => switch (this) {
        TransferStatus.pending   => 'Menunggu Konfirmasi',
        TransferStatus.received  => 'Diterima',
        TransferStatus.cancelled => 'Dibatalkan',
      };

  static TransferStatus fromString(String? s) => switch (s) {
        'received'  => TransferStatus.received,
        'cancelled' => TransferStatus.cancelled,
        _           => TransferStatus.pending,
      };
}

class TransferStockModel {
  final String id;
  final String fromBranchId;
  final String toBranchId;
  final String itemId;
  final double quantity;
  final TransferStatus status;
  final String? requestedBy;   // staff id
  final String? approvedBy;    // staff id
  final DateTime createdAt;
  final DateTime? receivedAt;

  // Join fields (opsional, diisi saat fetch dengan select)
  final String? itemName;
  final String? itemUnit;
  final String? fromBranchName;
  final String? toBranchName;
  final String? requestedByName;
  final String? approvedByName;

  const TransferStockModel({
    required this.id,
    required this.fromBranchId,
    required this.toBranchId,
    required this.itemId,
    required this.quantity,
    required this.status,
    this.requestedBy,
    this.approvedBy,
    required this.createdAt,
    this.receivedAt,
    this.itemName,
    this.itemUnit,
    this.fromBranchName,
    this.toBranchName,
    this.requestedByName,
    this.approvedByName,
  });

  factory TransferStockModel.fromMap(Map<String, dynamic> map) {
    return TransferStockModel(
      id:           map['id'] as String,
      fromBranchId: map['from_branch_id'] as String,
      toBranchId:   map['to_branch_id'] as String,
      itemId:       map['item_id'] as String,
      quantity:     (map['quantity'] as num).toDouble(),
      status:       TransferStatusX.fromString(map['status'] as String?),
      requestedBy:  map['requested_by'] as String?,
      approvedBy:   map['approved_by'] as String?,
      createdAt:    DateTime.parse(map['created_at'] as String),
      receivedAt:   map['received_at'] != null
                      ? DateTime.parse(map['received_at'] as String)
                      : null,
      // Join fields
      itemName:          map['item_name'] as String?,
      itemUnit:          map['item_unit'] as String?,
      fromBranchName:    map['from_branch_name'] as String?,
      toBranchName:      map['to_branch_name'] as String?,
      requestedByName:   map['requested_by_name'] as String?,
      approvedByName:    map['approved_by_name'] as String?,
    );
  }

  Map<String, dynamic> toInsertMap() => {
    'from_branch_id': fromBranchId,
    'to_branch_id':   toBranchId,
    'item_id':        itemId,
    'quantity':       quantity,
    'status':         'pending',
    'requested_by':   requestedBy,
  };
}