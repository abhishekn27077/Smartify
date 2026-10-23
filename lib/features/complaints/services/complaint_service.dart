import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smartify/core/constants/app_constants.dart';
import 'package:smartify/core/errors/failures.dart';
import 'package:smartify/features/complaints/models/attachment_file.dart';
import 'package:smartify/features/complaints/models/complaint_draft_model.dart';
import 'package:smartify/features/complaints/models/complaint_submission_result.dart';
import 'package:smartify/features/complaints/models/department_model.dart';

/// SMARTIFY Complaint Backend Service
/// Executes Supabase database transactions and private Storage uploads.
class ComplaintService {
  final SupabaseClient? _client;

  ComplaintService({SupabaseClient? client}) : _client = client;

  SupabaseClient get client {
    if (_client != null) return _client!;
    try {
      return Supabase.instance.client;
    } catch (_) {
      throw const AuthFailure(
          'Supabase client is not initialized. Please verify configuration.');
    }
  }

  /// Fetches active departments from public.departments with institutional fallback
  Future<List<DepartmentModel>> fetchActiveDepartments() async {
    try {
      final response = await client
          .from('departments')
          .select('id, name, code, description, is_active')
          .eq('is_active', true)
          .order('name');

      final list = (response as List<dynamic>)
          .map((item) => DepartmentModel.fromJson(item as Map<String, dynamic>))
          .toList();

      if (list.isNotEmpty) return list;
    } catch (_) {
      // Fallback to institutional default seeds if database table is not yet populated
    }

    return _fallbackDepartments;
  }

  /// Fetches the Level 1 starting authority level
  Future<String> fetchLevelOneAuthorityId() async {
    try {
      final response = await client
          .from('authority_levels')
          .select('id')
          .eq('level_number', 1)
          .maybeSingle();

      if (response != null && response['id'] != null) {
        return response['id'] as String;
      }
    } catch (_) {
      // If table is unseeded, handle gracefully
    }
    // Default fallback UUID if unseeded
    return '094a8af0-ab75-421f-bdfc-2fa6763340f6';
  }

  /// Registers a new grievance and uploads optional evidence
  Future<ComplaintSubmissionResult> submitComplaint(
      ComplaintDraftModel draft) async {
    final validationError = draft.validate();
    if (validationError != null) {
      throw ValidationFailure(validationError);
    }

    final currentUser = client.auth.currentUser;
    if (currentUser == null) {
      throw const AuthFailure(
          'Authentication required. Only authenticated students can register grievances.');
    }

    // 1. Fetch starting tier ID (Level 1)
    final startingLevelId = await fetchLevelOneAuthorityId();

    // 2. Prepare payload
    final incidentDateStr =
        '${draft.incidentDate.year.toString().padLeft(4, '0')}-'
        '${draft.incidentDate.month.toString().padLeft(2, '0')}-'
        '${draft.incidentDate.day.toString().padLeft(2, '0')}';

    final categoryFull =
        draft.subCategory != null && draft.subCategory!.isNotEmpty
            ? '${draft.category} (${draft.subCategory})'
            : draft.category;

    final insertPayload = <String, dynamic>{
      'student_id': currentUser.id,
      'department_id': draft.departmentId,
      'current_authority_level_id': startingLevelId,
      'title': draft.title.trim(),
      'description': draft.description.trim(),
      'category': categoryFull,
      'incident_date': incidentDateStr,
      'status': 'PENDING',
    };

    if (draft.academicProgram != null && draft.academicProgram!.isNotEmpty) {
      insertPayload['academic_program'] = draft.academicProgram;
    }

    Map<String, dynamic> insertedRow;
    try {
      final result = await client
          .from('complaints')
          .insert(insertPayload)
          .select()
          .single();

      insertedRow = result;
    } on PostgrestException catch (e) {
      throw DatabaseFailure(e.message, code: e.code);
    } catch (e) {
      throw DatabaseFailure('Failed to register complaint: ${e.toString()}');
    }

    final complaintId = insertedRow['id'] as String;
    String? uploadedPath;

    // 3. Upload evidence attachment to private Storage bucket if provided
    if (draft.attachment != null) {
      try {
        uploadedPath = await _uploadAttachment(
          complaintId: complaintId,
          attachment: draft.attachment!,
          userId: currentUser.id,
        );
      } catch (storageError) {
        // Attachment upload failure does not delete the complaint, but warns the user
        throw StorageUploadFailure(
          'Grievance registered as ${insertedRow['tracking_number']}, but evidence upload failed: $storageError',
        );
      }
    }

    return ComplaintSubmissionResult.fromJson(
      insertedRow,
      attachmentUrl: uploadedPath,
    );
  }

  /// Private storage uploader restricted to complaints/{id}/{filename}
  Future<String> _uploadAttachment({
    required String complaintId,
    required AttachmentFile attachment,
    required String userId,
  }) async {
    final storagePath = 'complaints/$complaintId/${attachment.name}';

    if (attachment.bytes != null) {
      await client.storage
          .from(AppConstants.kComplaintStorageBucket)
          .uploadBinary(
            storagePath,
            attachment.bytes!,
            fileOptions: FileOptions(
              contentType: attachment.mimeType,
              upsert: true,
            ),
          );
    } else {
      final file = File(attachment.path);
      await client.storage.from(AppConstants.kComplaintStorageBucket).upload(
            storagePath,
            file,
            fileOptions: FileOptions(
              contentType: attachment.mimeType,
              upsert: true,
            ),
          );
    }

    // Record metadata row in public.complaint_attachments
    await client.from('complaint_attachments').insert({
      'complaint_id': complaintId,
      'uploader_id': userId,
      'file_path': storagePath,
      'file_name': attachment.name,
      'file_type': attachment.mimeType,
      'file_size_bytes': attachment.sizeBytes,
    });

    return storagePath;
  }

  static final List<DepartmentModel> _fallbackDepartments = [
    const DepartmentModel(
      id: '53f56adf-ffb8-46ca-ab62-35777bd2e3b9',
      name: 'Department of MCA',
      code: 'MCA',
      description:
          'Master of Computer Applications - Academic & Curriculum Affairs',
    ),
    const DepartmentModel(
      id: '67042d0f-c806-405d-be7b-5bab63f33270',
      name: 'Department of MBA',
      code: 'MBA',
      description:
          'Master of Business Administration - Academic & Curriculum Affairs',
    ),
    const DepartmentModel(
      id: 'bd8cd808-1bc2-4f39-afa5-00c40020c756',
      name: 'Department of M.Com',
      code: 'MCOM',
      description: 'Master of Commerce - Academic & Curriculum Affairs',
    ),
    const DepartmentModel(
      id: '1c0a8b2e-2e31-4454-9bdf-49cad1773053',
      name: 'Academic Affairs',
      code: 'ACAD',
      description:
          'Curriculum, lectures, examinations, evaluation and faculty grievances',
    ),
    const DepartmentModel(
      id: '38ff3afe-2f87-4acb-a676-084922565029',
      name: 'Hostel & Residential Life',
      code: 'HOSTEL',
      description:
          'Hostel accommodation, hygiene, mess food quality and warden concerns',
    ),
    const DepartmentModel(
      id: '170e47da-c64c-46b1-bf8b-a25e1462f295',
      name: 'Infrastructure & Campus Facilities',
      code: 'INFRA',
      description:
          'Classrooms, labs, water supply, electricity and campus upkeep',
    ),
    const DepartmentModel(
      id: '75c16d97-37ab-40c1-aeb0-b803a684f15f',
      name: 'Accounts & Finance',
      code: 'FIN',
      description: 'Tuition fees, scholarships, refunds and student billing',
    ),
    const DepartmentModel(
      id: 'eebdf098-b215-4461-abe0-7565d44af61e',
      name: 'Library & IT Services',
      code: 'IT',
      description:
          'Campus Wi-Fi, computer labs, library books and digital portal access',
    ),
  ];
}
