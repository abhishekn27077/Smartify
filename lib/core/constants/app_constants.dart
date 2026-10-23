/// SMARTIFY Application Constants
class AppConstants {
  AppConstants._();

  /// Maximum retrospective calendar days for incident dates
  static const int kMaxRetrospectiveDays = 7;

  /// Campus grievance cutoff limit before freezing automated escalations
  static const int kCutoffDays = 20;

  /// Attachment size constraint: 10 Megabytes in bytes
  static const int kMaxAttachmentSizeBytes = 10 * 1024 * 1024;

  /// Allowed attachment file extensions
  static const List<String> kAllowedExtensions = [
    'jpg',
    'jpeg',
    'png',
    'webp',
    'pdf',
  ];

  /// Title length bounds
  static const int kMinTitleLength = 5;
  static const int kMaxTitleLength = 200;

  /// Description minimum length
  static const int kMinDescriptionLength = 20;

  /// Private Supabase Storage bucket name for complaint attachments
  static const String kComplaintStorageBucket = 'complaint-attachments';
}
