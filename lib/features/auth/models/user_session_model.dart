/// SMARTIFY Authenticated User Session Model
class UserSessionModel {
  final String id;
  final String email;
  final String fullName;
  final String role; // 'student', 'authority', 'admin'
  final String? departmentId;
  final String? departmentName;
  final String? authorityLevelId;
  final String? authorityLevelTitle;
  final int? authorityLevelNumber;
  final String? academicProgram; // 'MCA', 'MBA', 'M.Com'
  final String? registrationNumber;
  final String? avatarUrl;

  const UserSessionModel({
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
    this.avatarUrl,
  });

  bool get isStudent => role == 'student';
  bool get isAuthority => role == 'authority';
  bool get isAdmin => role == 'admin';

  factory UserSessionModel.fromJson(Map<String, dynamic> json) {
    final dept = json['departments'] as Map<String, dynamic>?;
    final lvl = json['authority_levels'] as Map<String, dynamic>?;
    final designation = json['designation'] as String?;

    return UserSessionModel(
      id: json['id'] as String,
      email: json['email'] as String? ?? '',
      fullName: (json['full_name'] as String? ?? 'Campus Member')
          .replaceAll(RegExp(r'\s*\([^)]*\)$'), '')
          .trim(),
      role: json['role'] as String? ?? 'student',
      departmentId: json['department_id'] as String?,
      departmentName: dept != null ? dept['name'] as String? : null,
      authorityLevelId: json['authority_level_id'] as String?,
      authorityLevelTitle: (designation != null && designation.isNotEmpty)
          ? designation
          : (lvl != null ? lvl['title'] as String? : null),
      authorityLevelNumber:
          lvl != null ? (lvl['level_number'] as num?)?.toInt() : null,
      academicProgram: json['academic_program'] as String?,
      registrationNumber: json['registration_number'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  UserSessionModel copyWith({
    String? role,
    String? departmentId,
    String? departmentName,
    String? authorityLevelId,
    String? authorityLevelTitle,
    int? authorityLevelNumber,
    String? academicProgram,
    String? registrationNumber,
  }) {
    return UserSessionModel(
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
      avatarUrl: avatarUrl,
    );
  }
}
