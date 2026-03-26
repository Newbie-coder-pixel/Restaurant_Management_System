import '../../../core/models/staff_role.dart';

class StaffMember {
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

  const StaffMember({
    required this.id, this.userId, this.branchId,
    required this.fullName, required this.email, this.phone,
    required this.role, required this.isActive, this.avatarUrl,
    required this.createdAt,
  });

  factory StaffMember.fromJson(Map<String, dynamic> j) => StaffMember(
    id: j['id'], userId: j['user_id'], branchId: j['branch_id'],
    fullName: j['full_name'], email: j['email'], phone: j['phone'],
    role: StaffRole.fromString(j['role'] ?? 'waiter'),
    isActive: j['is_active'] ?? true, avatarUrl: j['avatar_url'],
    createdAt: DateTime.parse(j['created_at']),
  );

  Map<String, dynamic> toJson() => {
    'branch_id': branchId, 'full_name': fullName, 'email': email,
    'phone': phone, 'role': role.name, 'is_active': isActive,
  };
}