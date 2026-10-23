import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:smartify/core/theme/app_colors.dart';
import 'package:smartify/core/theme/app_spacing.dart';
import 'package:smartify/features/analytics/models/analytics_data_model.dart';

/// SMARTIFY Monthly Submission & Resolution Trend Chart
class MonthlyTrendBarChart extends StatelessWidget {
  final List<MonthlyTrendMetric> trends;

  const MonthlyTrendBarChart({super.key, required this.trends});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (trends.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text('No historical monthly trends available.')),
      );
    }

    final barGroups = <BarChartGroupData>[];
    for (int i = 0; i < trends.length; i++) {
      final t = trends[i];
      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: t.submittedCount.toDouble(),
              color: AppColors.primary,
              width: 10,
              borderRadius: BorderRadius.circular(3),
            ),
            BarChartRodData(
              toY: t.resolvedCount.toDouble(),
              color: AppColors.statusResolved,
              width: 10,
              borderRadius: BorderRadius.circular(3),
            ),
          ],
        ),
      );
    }

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
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              const Text(
                'Submission & Resolution Trends',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDot('Submitted', AppColors.primary),
                  const SizedBox(width: 12),
                  _buildDot('Resolved', AppColors.statusResolved),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.space20),
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                barGroups: barGroups,
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (val, meta) {
                        if (val == meta.max || val == meta.min) {
                          return const SizedBox.shrink();
                        }
                        if (val % 1 == 0 && val >= 0) {
                          return Text(
                            val.toInt().toString(),
                            style: TextStyle(
                              fontSize: 10,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.6),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (val, meta) {
                        final idx = val.toInt();
                        if (idx >= 0 && idx < trends.length) {
                          // Short month name (e.g. "May", "Jun")
                          final label = trends[idx].monthLabel.split(' ').first;
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 10,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.7),
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: theme.colorScheme.outline.withValues(alpha: 0.2),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot(String label, Color color) {
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
