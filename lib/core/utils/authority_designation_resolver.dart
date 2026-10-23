/// SMARTIFY Authority Designation & Title Resolver
/// Generates context-specific, professional academic designations based on tier and department.
class AuthorityDesignationResolver {
  const AuthorityDesignationResolver._();

  /// Resolves the authentic designation for an authority tier and department context
  static String resolveDesignation({
    required int levelNumber,
    String? departmentCode,
    String? departmentName,
    String? fallbackTitle,
  }) {
    final code = (departmentCode ?? '').toUpperCase().trim();
    final name = (departmentName ?? '').toLowerCase().trim();

    if (levelNumber == 1) {
      if (code == 'HOSTEL' || name.contains('hostel')) {
        return 'Level 1 — Hostel Warden';
      }
      if (code == 'IT' ||
          name.contains('library') ||
          name.contains('services')) {
        return 'Level 1 — IT Officer';
      }
      if (code == 'FIN' ||
          name.contains('finance') ||
          name.contains('account')) {
        return 'Level 1 — Accounts Officer';
      }
      if (code == 'INFRA' ||
          name.contains('infra') ||
          name.contains('facilit')) {
        return 'Level 1 — Campus Facility Officer';
      }
      // Academic departments: MCA, MBA, M.Com, etc.
      return 'Level 1 — Faculty / Department Officer';
    }

    if (levelNumber == 2) {
      return 'Level 2 — Head of Department (HoD)';
    }

    if (levelNumber == 3) {
      if (code == 'MBA' ||
          name.contains('mba') ||
          name.contains('management')) {
        return 'Level 3 — Dean of Management Studies (MBA)';
      }
      if (code == 'MCA' || name.contains('mca') || name.contains('computer')) {
        return 'Level 3 — Dean of Academic Affairs (MCA)';
      }
      if (code == 'MCOM' ||
          name.contains('m.com') ||
          name.contains('commerce')) {
        return 'Level 3 — Dean of Commerce (M.Com)';
      }
      if (fallbackTitle != null && fallbackTitle.isNotEmpty) {
        return fallbackTitle.replaceAll(': ', ' — ');
      }
      return 'Level 3 — Dean / Academic Dean';
    }

    if (levelNumber == 4) {
      return 'Level 4 — Principal / Campus Ombudsman Board';
    }

    if (fallbackTitle != null && fallbackTitle.isNotEmpty) {
      return fallbackTitle.replaceAll(': ', ' — ');
    }
    return 'Level $levelNumber Authority';
  }
}
