/// SMARTIFY Aggregated Grievance Analytics Model
class AnalyticsDataModel {
  final DateTime periodStart;
  final DateTime periodEnd;
  final int totalSubmitted;
  final int totalResolved;
  final int totalPending;
  final int totalUnderReview;
  final int totalInProgress;
  final int totalPaused;
  final int totalEscalated;
  final int totalRejected;
  final int overdueCount;
  final double averageResolutionDays;
  final List<DepartmentMetric> departmentDistribution;
  final List<CategoryMetric> categoryDistribution;
  final List<MonthlyTrendMetric> monthlyTrends;
  final List<AuthorityWorkloadMetric> authorityWorkload;

  const AnalyticsDataModel({
    required this.periodStart,
    required this.periodEnd,
    required this.totalSubmitted,
    required this.totalResolved,
    required this.totalPending,
    required this.totalUnderReview,
    required this.totalInProgress,
    required this.totalPaused,
    required this.totalEscalated,
    required this.totalRejected,
    required this.overdueCount,
    required this.averageResolutionDays,
    required this.departmentDistribution,
    required this.categoryDistribution,
    required this.monthlyTrends,
    required this.authorityWorkload,
  });

  /// Resolution rate percentage
  double get resolutionRate =>
      totalSubmitted > 0 ? (totalResolved / totalSubmitted) * 100.0 : 0.0;

  factory AnalyticsDataModel.fromJson(Map<String, dynamic> json) {
    final deptList = (json['department_distribution'] as List<dynamic>?) ?? [];
    final catList = (json['category_distribution'] as List<dynamic>?) ?? [];
    final trendList = (json['monthly_trends'] as List<dynamic>?) ?? [];
    final workList = (json['authority_workload'] as List<dynamic>?) ?? [];

    return AnalyticsDataModel(
      periodStart: DateTime.parse(json['period_start'] as String),
      periodEnd: DateTime.parse(json['period_end'] as String),
      totalSubmitted: json['total_submitted'] as int? ?? 0,
      totalResolved: json['total_resolved'] as int? ?? 0,
      totalPending: json['total_pending'] as int? ?? 0,
      totalUnderReview: json['total_under_review'] as int? ?? 0,
      totalInProgress: json['total_in_progress'] as int? ?? 0,
      totalPaused: json['total_paused'] as int? ?? 0,
      totalEscalated: json['total_escalated'] as int? ?? 0,
      totalRejected: json['total_rejected'] as int? ?? 0,
      overdueCount: json['overdue_count'] as int? ?? 0,
      averageResolutionDays:
          (json['average_resolution_days'] as num?)?.toDouble() ?? 0.0,
      departmentDistribution: deptList
          .map((d) => DepartmentMetric.fromJson(d as Map<String, dynamic>))
          .toList(),
      categoryDistribution: catList
          .map((c) => CategoryMetric.fromJson(c as Map<String, dynamic>))
          .toList(),
      monthlyTrends: trendList
          .map((t) => MonthlyTrendMetric.fromJson(t as Map<String, dynamic>))
          .toList(),
      authorityWorkload: workList
          .map((w) =>
              AuthorityWorkloadMetric.fromJson(w as Map<String, dynamic>))
          .toList(),
    );
  }
}

class DepartmentMetric {
  final String id;
  final String name;
  final String code;
  final int totalComplaints;
  final int resolvedCount;
  final int pausedCount;

  const DepartmentMetric({
    required this.id,
    required this.name,
    required this.code,
    required this.totalComplaints,
    required this.resolvedCount,
    required this.pausedCount,
  });

  factory DepartmentMetric.fromJson(Map<String, dynamic> json) {
    return DepartmentMetric(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'General',
      code: json['code'] as String? ?? 'GEN',
      totalComplaints: json['total_complaints'] as int? ?? 0,
      resolvedCount: json['resolved_count'] as int? ?? 0,
      pausedCount: json['paused_count'] as int? ?? 0,
    );
  }
}

class CategoryMetric {
  final String category;
  final int count;

  const CategoryMetric({required this.category, required this.count});

  factory CategoryMetric.fromJson(Map<String, dynamic> json) {
    return CategoryMetric(
      category: json['category'] as String? ?? 'General',
      count: json['count'] as int? ?? 0,
    );
  }
}

class MonthlyTrendMetric {
  final String monthLabel;
  final int submittedCount;
  final int resolvedCount;

  const MonthlyTrendMetric({
    required this.monthLabel,
    required this.submittedCount,
    required this.resolvedCount,
  });

  factory MonthlyTrendMetric.fromJson(Map<String, dynamic> json) {
    return MonthlyTrendMetric(
      monthLabel: json['month_label'] as String? ?? '',
      submittedCount: json['submitted_count'] as int? ?? 0,
      resolvedCount: json['resolved_count'] as int? ?? 0,
    );
  }
}

class AuthorityWorkloadMetric {
  final String id;
  final String fullName;
  final String departmentName;
  final String authorityLevelTitle;
  final int activeCaseload;
  final int resolvedCount;

  const AuthorityWorkloadMetric({
    required this.id,
    required this.fullName,
    required this.departmentName,
    required this.authorityLevelTitle,
    required this.activeCaseload,
    required this.resolvedCount,
  });

  factory AuthorityWorkloadMetric.fromJson(Map<String, dynamic> json) {
    return AuthorityWorkloadMetric(
      id: json['id'] as String? ?? '',
      fullName: json['full_name'] as String? ?? 'Authority Member',
      departmentName: json['department_name'] as String? ?? 'Campus Dept',
      authorityLevelTitle:
          json['authority_level_title'] as String? ?? 'Level 1',
      activeCaseload: json['active_caseload'] as int? ?? 0,
      resolvedCount: json['resolved_count'] as int? ?? 0,
    );
  }
}
