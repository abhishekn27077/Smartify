/// SMARTIFY Admin User Profile Entity for staff, student, and role management
class AdminUserModel {
  final String id;
  final String email;
  final String fullName;
  final String role; // 'student', 'authority', 'admin'
  final String? departmentId;
  final String? departmentName;
  final String? authorityLevelId;
  final String? authorityLevelTitle;
  final int? authorityLevelNumber;
  final String? academicProgram;
  final String? registrationNumber;
  final bool isActive;
  final DateTime createdAt;

  const AdminUserModel({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    this.departmentId,
    this.departmentName,
    this.authorityLevelId,
    this.authorityLevelTitle,
    this.authorityLevelNumber,
    this.academicProgram,
    this.registrationNumber,
    this.isActive = true,
    required this.createdAt,
  });

  factory AdminUserModel.fromJson(Map<String, dynamic> json) {
    final dept = json['departments'] as Map<String, dynamic>?;
    final lvl = json['authority_levels'] as Map<String, dynamic>?;
    final designation = json['designation'] as String?;

    return AdminUserModel(
      id: json['id'] as String,
      email: json['email'] as String? ?? '',
      fullName: json['full_name'] as String? ?? 'Campus Member',
      role: json['role'] as String? ?? 'student',
      departmentId: json['department_id'] as String?,
      departmentName: dept != null ? dept['name'] as String? : null,
      authorityLevelId: json['authority_level_id'] as String?,
      authorityLevelTitle: (designation != null && designation.isNotEmpty)
          ? designation
          : (lvl != null ? lvl['title'] as String? : null),
      authorityLevelNumber: lvl != null ? (lvl['level_number'] as num?)?.toInt() : null,
      academicProgram: json['academic_program'] as String?,
      registrationNumber: json['registration_number'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  AdminUserModel copyWith({
    String? role,
    String? departmentId,
    String? departmentName,
    String? authorityLevelId,
    String? authorityLevelTitle,
    int? authorityLevelNumber,
    String? academicProgram,
    String? registrationNumber,
    bool? isActive,
  }) {
    return AdminUserModel(
      id: id,
      email: email,
      fullName: fullName,
      role: role ?? this.role,
      departmentId: departmentId ?? this.departmentId,
      departmentName: departmentName ?? this.departmentName,
      authorityLevelId: authorityLevelId ?? this.authorityLevelId,
      authorityLevelTitle: authorityLevelTitle ?? this.authorityLevelTitle,
      authorityLevelNumber: authorityLevelNumber ?? this.authorityLevelNumber,
      academicProgram: academicProgram ?? this.academicProgram,
      registrationNumber: registrationNumber ?? this.registrationNumber,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
    );
  }
}
