import 'package:flutter_test/flutter_test.dart';
import 'package:smartify/core/utils/date_validator.dart';
import 'package:smartify/features/complaints/models/attachment_file.dart';
import 'package:smartify/features/complaints/models/complaint_draft_model.dart';

void main() {
  group('Date Boundary Validation [Today - 7 days, Today]', () {
    final fixedToday = DateTime(2026, 10, 12, 12, 0, 0);

    test('Today is valid', () {
      final result = DateValidator.validateIncidentDate(
        DateTime(2026, 10, 12),
        referenceDate: fixedToday,
      );
      expect(result, isNull);
    });

    test('3 days ago is valid', () {
      final result = DateValidator.validateIncidentDate(
        DateTime(2026, 10, 9),
        referenceDate: fixedToday,
      );
      expect(result, isNull);
    });

    test('Oldest permitted boundary (exactly 7 days ago) is valid', () {
      final result = DateValidator.validateIncidentDate(
        DateTime(2026, 10, 5),
        referenceDate: fixedToday,
      );
      expect(result, isNull);
    });

    test('One day too old (8 days ago) is rejected', () {
      final result = DateValidator.validateIncidentDate(
        DateTime(2026, 10, 4),
        referenceDate: fixedToday,
      );
      expect(result, isNotNull);
      expect(result, contains('cannot be older than 7 calendar days'));
    });

    test('Future date (tomorrow) is rejected', () {
      final result = DateValidator.validateIncidentDate(
        DateTime(2026, 10, 13),
        referenceDate: fixedToday,
      );
      expect(result, isNotNull);
      expect(result, contains('Future dates are not allowed'));
    });

    test('Null date is rejected', () {
      final result =
          DateValidator.validateIncidentDate(null, referenceDate: fixedToday);
      expect(result, isNotNull);
    });
  });

  group('Attachment Validation & Security', () {
    test('Allowed image formats pass validation', () {
      const allowedJpg = AttachmentFile(
        name: 'evidence.jpg',
        path: '/tmp/evidence.jpg',
        sizeBytes: 1024 * 1024, // 1MB
      );
      expect(allowedJpg.validate(), isNull);
      expect(allowedJpg.isImage, isTrue);

      const allowedPdf = AttachmentFile(
        name: 'memo.pdf',
        path: '/tmp/memo.pdf',
        sizeBytes: 2 * 1024 * 1024, // 2MB
      );
      expect(allowedPdf.validate(), isNull);
      expect(allowedPdf.isPdf, isTrue);
    });

    test('File exceeding 10MB limit is rejected', () {
      const oversized = AttachmentFile(
        name: 'large_video.png',
        path: '/tmp/large_video.png',
        sizeBytes: 11 * 1024 * 1024, // 11MB
      );
      expect(oversized.validate(), contains('exceeds maximum allowed limit'));
    });

    test('Disallowed file types are rejected', () {
      const scriptFile = AttachmentFile(
        name: 'exploit.sh',
        path: '/tmp/exploit.sh',
        sizeBytes: 500,
      );
      expect(scriptFile.validate(), contains('Invalid file type'));

      const executable = AttachmentFile(
        name: 'payload.exe',
        path: '/tmp/payload.exe',
        sizeBytes: 2000,
      );
      expect(executable.validate(), contains('Invalid file type'));
    });
  });

  group('Complaint Draft Form Validation', () {
    final validDate = DateValidator.getLatestPermittedDate();

    test('Valid draft passes validation', () {
      final draft = ComplaintDraftModel(
        title: 'Water leakage in Lab 4',
        description:
            'Persistent water leakage near the power server racks for the last 2 days.',
        category: 'Campus Infrastructure',
        departmentId: 'dept-infra-uuid',
        incidentDate: validDate,
      );
      expect(draft.validate(), isNull);
    });

    test('Title shorter than 5 chars is rejected', () {
      final draft = ComplaintDraftModel(
        title: 'Leak',
        description:
            'Persistent water leakage near the power server racks for the last 2 days.',
        category: 'Campus Infrastructure',
        departmentId: 'dept-infra-uuid',
        incidentDate: validDate,
      );
      expect(draft.validate(), contains('Title must be at least 5 characters'));
    });

    test('Description shorter than 20 chars is rejected', () {
      final draft = ComplaintDraftModel(
        title: 'Water leakage in Lab 4',
        description: 'Water is leaking.',
        category: 'Campus Infrastructure',
        departmentId: 'dept-infra-uuid',
        incidentDate: validDate,
      );
      expect(draft.validate(),
          contains('Description must be at least 20 characters'));
    });

    test('Empty category or department is rejected', () {
      final draftNoCat = ComplaintDraftModel(
        title: 'Water leakage in Lab 4',
        description:
            'Persistent water leakage near the power server racks for the last 2 days.',
        category: '',
        departmentId: 'dept-infra-uuid',
        incidentDate: validDate,
      );
      expect(draftNoCat.validate(),
          contains('Please select a grievance category'));

      final draftNoDept = ComplaintDraftModel(
        title: 'Water leakage in Lab 4',
        description:
            'Persistent water leakage near the power server racks for the last 2 days.',
        category: 'Campus Infrastructure',
        departmentId: '',
        incidentDate: validDate,
      );
      expect(draftNoDept.validate(),
          contains('Please select the relevant campus department'));
    });
  });
}
