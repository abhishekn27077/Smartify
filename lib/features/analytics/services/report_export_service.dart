import 'dart:io';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:smartify/core/utils/app_date_time_utils.dart';
import 'package:smartify/features/analytics/models/analytics_data_model.dart';
import 'package:smartify/features/tracking/models/grievance_model.dart';

/// SMARTIFY Report Export Service
/// Implements secure, formula-injection-safe CSV export and formatted PDF report generation.
class ReportExportService {
  /// Sanitize cell values against CSV/Spreadsheet Formula Injection (DDE / Command Injection)
  /// If a value starts with '=', '+', '-', '@', '\t', or '\r', prefix it with a single quote "'"
  static String sanitizeCsvCell(String value) {
    if (value.isEmpty) return value;
    if (value.startsWith('=') ||
        value.startsWith('+') ||
        value.startsWith('-') ||
        value.startsWith('@') ||
        value.startsWith('\t') ||
        value.startsWith('\r')) {
      return "'$value";
    }
    final trimmed = value.trim();
    if (trimmed.startsWith('=') ||
        trimmed.startsWith('+') ||
        trimmed.startsWith('-') ||
        trimmed.startsWith('@')) {
      return "'$trimmed";
    }
    return trimmed;
  }

  /// Generates a CSV string with formula injection defenses
  static String generateComplaintsCsv(List<GrievanceModel> complaints) {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
    final incidentFormat = DateFormat('yyyy-MM-dd');

    final rows = <List<dynamic>>[];

    // CSV Header Row
    rows.add([
      'Tracking Reference',
      'Title',
      'Category',
      'Department',
      'Incident Date',
      'Logged At (Local)',
      'Current Tier',
      'Status',
      'Priority',
      'Cutoff Paused',
      'Assigned Authority',
      'Resolved At (Local)',
      'Resolution Memo'
    ]);

    // Data Rows with cell-by-cell sanitation
    for (final c in complaints) {
      rows.add([
        sanitizeCsvCell(c.trackingNumber),
        sanitizeCsvCell(c.title),
        sanitizeCsvCell(c.category),
        sanitizeCsvCell(c.departmentName),
        incidentFormat.format(c.incidentDate),
        dateFormat.format(c.createdAt.toLocal()),
        sanitizeCsvCell(c.currentAuthorityLevelTitle),
        c.status.code,
        c.priority,
        c.isCutoffPaused ? 'YES' : 'NO',
        sanitizeCsvCell(c.assignedAuthorityName ?? 'Unassigned Pool'),
        c.resolvedAt != null
            ? dateFormat.format(c.resolvedAt!.toLocal())
            : 'N/A',
        sanitizeCsvCell(c.resolutionNotes ?? ''),
      ]);
    }

    return const ListToCsvConverter().convert(rows);
  }

  /// Exports complaints to CSV file on the device
  static Future<File> exportComplaintsToCsvFile(
      List<GrievanceModel> complaints) async {
    final csvContent = generateComplaintsCsv(complaints);
    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File('${dir.path}/smartify_complaints_$timestamp.csv');
    return await file.writeAsString(csvContent);
  }

  /// Generates a professional PDF report document
  static Future<File> generatePdfReport({
    required AnalyticsDataModel analytics,
    required List<GrievanceModel> sampleComplaints,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) => [
          // Header
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('SMARTIFY',
                      style: const pw.TextStyle(
                          fontSize: 24,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.teal800)),
                  pw.Text('Campus Grievance Management System',
                      style: const pw.TextStyle(
                          fontSize: 12, color: PdfColors.grey700)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('OFFICIAL AUDIT REPORT',
                      style: const pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.indigo800)),
                  pw.Text(
                      'Generated: ${AppDateTimeUtils.formatLocalDateTime(DateTime.now())}',
                      style: const pw.TextStyle(
                          fontSize: 8, color: PdfColors.grey600)),
                ],
              ),
            ],
          ),
          pw.Divider(thickness: 1.5, color: PdfColors.teal700),
          pw.SizedBox(height: 8),

          // Period Scope
          pw.Text(
            'Reporting Window: ${AppDateTimeUtils.formatLocalDate(analytics.periodStart)} - ${AppDateTimeUtils.formatLocalDate(analytics.periodEnd)}',
            style: const pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey800),
          ),
          pw.SizedBox(height: 12),

          // KPI Summary Cards Table
          pw.Text('1. Executive Redressal Metrics',
              style: const pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.teal900)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: [
              'Total Submitted',
              'Resolved',
              'Resolution Rate',
              'Paused (20d)',
              'Overdue / Breached',
              'Avg Days to Resolve'
            ],
            data: [
              [
                analytics.totalSubmitted.toString(),
                analytics.totalResolved.toString(),
                '${analytics.resolutionRate.toStringAsFixed(1)}%',
                analytics.totalPaused.toString(),
                analytics.overdueCount.toString(),
                AppDateTimeUtils.formatAverageResolution(
                  analytics.totalResolved,
                  analytics.averageResolutionDays,
                ),
              ]
            ],
            headerStyle: const pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
                fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.teal700),
            cellAlignment: pw.Alignment.center,
            cellStyle: const pw.TextStyle(fontSize: 9),
          ),
          pw.SizedBox(height: 16),

          // Department Distribution Table
          pw.Text('2. Department Grievance Breakdown',
              style: const pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.teal900)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: [
              'Code',
              'Department Name',
              'Total Lodged',
              'Resolved',
              'Paused'
            ],
            data: analytics.departmentDistribution
                .map((d) => [
                      d.code,
                      d.name,
                      d.totalComplaints.toString(),
                      d.resolvedCount.toString(),
                      d.pausedCount.toString(),
                    ])
                .toList(),
            headerStyle: const pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
                fontSize: 9),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.indigo700),
            cellStyle: const pw.TextStyle(fontSize: 8),
          ),
          pw.SizedBox(height: 16),

          // Authority Workload Table
          if (analytics.authorityWorkload.isNotEmpty) ...[
            pw.Text('3. Authority Workload & Triage Caseload',
                style: const pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.teal900)),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headers: [
                'Authority Official',
                'Department',
                'Tier Level',
                'Active Caseload',
                'Resolved'
              ],
              data: analytics.authorityWorkload
                  .map((w) => [
                        w.fullName,
                        w.departmentName,
                        w.authorityLevelTitle,
                        w.activeCaseload.toString(),
                        w.resolvedCount.toString(),
                      ])
                  .toList(),
              headerStyle: const pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                  fontSize: 9),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.blueGrey800),
              cellStyle: const pw.TextStyle(fontSize: 8),
            ),
            pw.SizedBox(height: 16),
          ],

          // Recent Complaints Audit Sample
          if (sampleComplaints.isNotEmpty) ...[
            pw.Text('4. Recent Grievances Audit Extract',
                style: const pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.teal900)),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headers: ['Ref ID', 'Title', 'Department', 'Status', 'Logged At'],
              data: sampleComplaints
                  .take(8)
                  .map((c) => [
                        c.trackingNumber,
                        c.title.length > 25
                            ? '${c.title.substring(0, 22)}...'
                            : c.title,
                        c.departmentCode,
                        c.status.label,
                        AppDateTimeUtils.formatLocalDate(c.createdAt),
                      ])
                  .toList(),
              headerStyle: const pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                  fontSize: 8),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey700),
              cellStyle: const pw.TextStyle(fontSize: 8),
            ),
          ],

          pw.SizedBox(height: 24),
          pw.Divider(thickness: 0.5, color: PdfColors.grey400),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('SMARTIFY Institutional Governance Audit',
                  style: const pw.TextStyle(
                      fontSize: 8, color: PdfColors.grey600)),
              pw.Text('Confidential • For Internal Administrative Use Only',
                  style: const pw.TextStyle(
                      fontSize: 8, color: PdfColors.grey600)),
            ],
          ),
        ],
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File('${dir.path}/smartify_audit_report_$timestamp.pdf');
    return await file.writeAsBytes(await pdf.save());
  }
}
