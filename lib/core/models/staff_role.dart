// lib/core/models/staff_role.dart

enum StaffRole {
  superadmin,
  manager,
  cashier,
  waiter,
  kitchen,
  host;

  String get displayName {
    switch (this) {
      case StaffRole.superadmin: return 'Super Admin';
      case StaffRole.manager: return 'Manager';
      case StaffRole.cashier: return 'Kasir';
      case StaffRole.waiter: return 'Pelayan';
      case StaffRole.kitchen: return 'Dapur';
      case StaffRole.host: return 'Host';
    }
  }

  static StaffRole fromString(String value) {
    return StaffRole.values.firstWhere(
      (e) => e.name == value,
      orElse: () => StaffRole.waiter,
    );
  }
}

// lib/core/models/staff_model.dart
class StaffModel {
  final String id;
  final String? userId;
  final String? branchId;
  final String fullName;
  final String email;
  final String? phone;
  final StaffRole role;
  final bool isActive;
  final String? avatarUrl;
  final DateTime createdAt;

  const StaffModel({
    required this.id,
    this.userId,
    this.branchId,
    required this.fullName,
    required this.email,
    this.phone,
    required this.role,
    this.isActive = true,
    this.avatarUrl,
    required this.createdAt,
  });

  factory StaffModel.fromJson(Map<String, dynamic> json) {
    return StaffModel(
      id: json['id'],
      userId: json['user_id'],
      branchId: json['branch_id'],
      fullName: json['full_name'],
      email: json['email'],
      phone: json['phone'],
      role: StaffRole.fromString(json['role']),
      isActive: json['is_active'] ?? true,
      avatarUrl: json['avatar_url'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'branch_id': branchId,
    'full_name': fullName,
    'email': email,
    'phone': phone,
    'role': role.name,
    'is_active': isActive,
    'avatar_url': avatarUrl,
  };
}