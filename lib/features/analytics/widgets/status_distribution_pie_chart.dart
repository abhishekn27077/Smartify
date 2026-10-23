import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:smartify/core/theme/app_colors.dart';
import 'package:smartify/core/theme/app_spacing.dart';
import 'package:smartify/features/analytics/models/analytics_data_model.dart';

/// SMARTIFY Complaint Status Distribution Chart
class StatusDistributionPieChart extends StatelessWidget {
  final AnalyticsDataModel analytics;

  const StatusDistributionPieChart({super.key, required this.analytics});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final total = analytics.totalSubmitted;
    if (total == 0) {
      return const SizedBox(
        height: 180,
        child: Center(child: Text('No complaints recorded for this period.')),
      );
    }

    final sections = <PieChartSectionData>[
      if (analytics.totalResolved > 0)
        PieChartSectionData(
          color: AppColors.statusResolved,
          value: analytics.totalResolved.toDouble(),
          title: '${((analytics.totalResolved / total) * 100).toInt()}%',
          radius: 45,
          titleStyle: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      if (analytics.totalPending > 0)
        PieChartSectionData(
          color: AppColors.statusPending,
          value: analytics.totalPending.toDouble(),
          title: '${((analytics.totalPending / total) * 100).toInt()}%',
          radius: 45,
          titleStyle: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      if (analytics.totalUnderReview > 0)
        PieChartSectionData(
          color: AppColors.statusUnderReview,
          value: analytics.totalUnderReview.toDouble(),
          title: '${((analytics.totalUnderReview / total) * 100).toInt()}%',
          radius: 45,
          titleStyle: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      if (analytics.totalInProgress > 0)
        PieChartSectionData(
          color: AppColors.statusInProgress,
          value: analytics.totalInProgress.toDouble(),
          title: '${((analytics.totalInProgress / total) * 100).toInt()}%',
          radius: 45,
          titleStyle: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      if (analytics.totalEscalated > 0)
        PieChartSectionData(
          color: AppColors.statusEscalated,
          value: analytics.totalEscalated.toDouble(),
          title: '${((analytics.totalEscalated / total) * 100).toInt()}%',
          radius: 45,
          titleStyle: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      if (analytics.totalPaused > 0)
        PieChartSectionData(
          color: AppColors.statusCutoffPaused,
          value: analytics.totalPaused.toDouble(),
          title: '${((analytics.totalPaused / total) * 100).toInt()}%',
          radius: 45,
          titleStyle: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      if (analytics.totalRejected > 0)
        PieChartSectionData(
          color: AppColors.statusRejected,
          value: analytics.totalRejected.toDouble(),
          title: '${((analytics.totalRejected / total) * 100).toInt()}%',
          radius: 45,
          titleStyle: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.space16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Resolution Status Breakdown',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: AppSpacing.space16),
          SizedBox(
            height: 180,
            child: PieChart(
              PieChartData(
                sections: sections,
                centerSpaceRadius: 36,
                sectionsSpace: 2,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.space12),
          // Legend
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _buildLegend('Resolved (${analytics.totalResolved})',
                  AppColors.statusResolved),
              _buildLegend('Pending (${analytics.totalPending})',
                  AppColors.statusPending),
              _buildLegend('Under Review (${analytics.totalUnderReview})',
                  AppColors.statusUnderReview),
              _buildLegend('In Progress (${analytics.totalInProgress})',
                  AppColors.statusInProgress),
              _buildLegend('Escalated (${analytics.totalEscalated})',
                  AppColors.statusEscalated),
              _buildLegend('Paused 20d (${analytics.totalPaused})',
                  AppColors.statusCutoffPaused),
              _buildLegend('Rejected (${analytics.totalRejected})',
                  AppColors.statusRejected),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegend(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500)),
      ],
    );
  }
}
