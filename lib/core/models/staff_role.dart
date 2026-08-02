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
      case StaffRole.cashier: return 'Cashier';
      case StaffRole.waiter: return 'Waiter';
      case StaffRole.kitchen: return 'Kitchen';
      case StaffRole.host: return 'Host';
    }
  }

  String get accessDescription {
    switch (this) {
      case StaffRole.superadmin: return 'Full access to all features & all branches';
      case StaffRole.manager:    return 'Reports, menu, inventory, staff, & operations';
      case StaffRole.cashier:    return 'Cashier, orders, & menu viewing';
      case StaffRole.waiter:     return 'Manage orders & view tables';
      case StaffRole.kitchen:    return 'Kitchen Display System (KDS)';
      case StaffRole.host:       return 'Table management & reservations';
    }
  }

  List<String> get accessFeatures {
    switch (this) {
      case StaffRole.superadmin:
        return ['Reports & Analytics', 'Table Management', 'Reservations', 'Order',
                'Cashier & Payment', 'Kitchen (KDS)', 'Menu', 'Inventory',
                'Staff', 'Multi Branch', 'AI Chatbot'];
      case StaffRole.manager:
        return ['Reports & Analytics', 'Table Management', 'Reservations', 'Order',
                'Cashier & Payment', 'Menu', 'Inventory', 'Staff', 'AI Chatbot'];
      case StaffRole.cashier:
        return ['Cashier & Payment', 'Order', 'Menu'];
      case StaffRole.waiter:
        return ['Order', 'Table Management'];
      case StaffRole.kitchen:
        return ['Kitchen (KDS)'];
      case StaffRole.host:
        return ['Table Management', 'Reservations'];
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