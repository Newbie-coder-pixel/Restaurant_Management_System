import 'package:flutter/material.dart';

enum TableStatus { available, occupied, reserved, cleaning }
enum TableShape { round, square, rectangle }

extension TableStatusExt on TableStatus {
  String get label {
    switch (this) {
      case TableStatus.available: return 'Available';
      case TableStatus.occupied:  return 'Occupied';
      case TableStatus.reserved:  return 'Reserved';
      case TableStatus.cleaning:  return 'Cleaning';
    }
  }
  Color get color {
    switch (this) {
      case TableStatus.available: return const Color(0xFF4CAF50);
      case TableStatus.occupied:  return const Color(0xFFE94560);
      case TableStatus.reserved:  return const Color(0xFFFF9800);
      case TableStatus.cleaning:  return const Color(0xFF2196F3);
    }
  }
  static TableStatus fromString(String s) =>
    TableStatus.values.firstWhere((e) => e.name == s, orElse: () => TableStatus.available);
}

class TableModel {
  final String id;
  final String branchId;
  final String tableNumber;
  final int capacity;
  final TableStatus status;
  final TableShape shape;
  final double positionX;
  final double positionY;
  final int floorLevel;
  final bool isMergeable;
  final String? notes;
  // ── IMPROVEMENT: add updatedAt for the occupied timer ──
  final DateTime? updatedAt;
  // Set when a customer flags via the QR ordering gate that this table's
  // real-world state doesn't match its status. See
  // supabase/migrations/20260803040000_table_status_gate_and_anon_lockdown.sql.
  final DateTime? customerReportedAt;

  const TableModel({
    required this.id, required this.branchId, required this.tableNumber,
    required this.capacity, required this.status, required this.shape,
    required this.positionX, required this.positionY, required this.floorLevel,
    required this.isMergeable, this.notes,
    this.updatedAt, // ← NEW
    this.customerReportedAt,
  });

  factory TableModel.fromJson(Map<String, dynamic> j) => TableModel(
    id: j['id'], branchId: j['branch_id'], tableNumber: j['table_number'],
    capacity: j['capacity'] ?? 4,
    status: TableStatusExt.fromString(j['status'] ?? 'available'),
    shape: TableShape.values.firstWhere(
      (e) => e.name == (j['shape'] ?? 'square'), orElse: () => TableShape.square),
    positionX: (j['position_x'] ?? 0).toDouble(),
    positionY: (j['position_y'] ?? 0).toDouble(),
    floorLevel: j['floor_level'] ?? 1,
    isMergeable: j['is_mergeable'] ?? true,
    notes: j['notes'],
    // ── IMPROVEMENT: read updated_at from the database ──
    updatedAt: j['updated_at'] != null
        ? DateTime.tryParse(j['updated_at'])?.toLocal()
        : null,
    customerReportedAt: j['customer_reported_at'] != null
        ? DateTime.tryParse(j['customer_reported_at'])?.toLocal()
        : null,
  );

  Map<String, dynamic> toJson() => {
    'branch_id': branchId, 'table_number': tableNumber, 'capacity': capacity,
    'status': status.name, 'shape': shape.name, 'position_x': positionX,
    'position_y': positionY, 'floor_level': floorLevel,
    'is_mergeable': isMergeable, 'notes': notes,
  };

  TableModel copyWith({TableStatus? status, double? positionX, double? positionY}) =>
    TableModel(
      id: id, branchId: branchId, tableNumber: tableNumber,
      capacity: capacity, shape: shape, floorLevel: floorLevel,
      isMergeable: isMergeable, notes: notes,
      updatedAt: updatedAt, // ← BARU
      customerReportedAt: customerReportedAt,
      status: status ?? this.status,
      positionX: positionX ?? this.positionX,
      positionY: positionY ?? this.positionY,
    );
}