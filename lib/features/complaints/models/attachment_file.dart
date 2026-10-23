import 'dart:typed_data';
import 'package:smartify/core/constants/app_constants.dart';

/// Representation of picked evidence attachment file
class AttachmentFile {
  final String name;
  final String path;
  final int sizeBytes;
  final Uint8List? bytes;

  const AttachmentFile({
    required this.name,
    required this.path,
    required this.sizeBytes,
    this.bytes,
  });

  String get extension {
    final parts = name.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : '';
  }

  String get mimeType {
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }

  bool get isImage => ['jpg', 'jpeg', 'png', 'webp'].contains(extension);
  bool get isPdf => extension == 'pdf';

  /// Returns null if valid, or an error message if invalid
  String? validate() {
    if (sizeBytes <= 0) {
      return 'The selected file is empty.';
    }
    if (sizeBytes > AppConstants.kMaxAttachmentSizeBytes) {
      const maxMb = AppConstants.kMaxAttachmentSizeBytes ~/ (1024 * 1024);
      return 'File size exceeds maximum allowed limit of ${maxMb}MB.';
    }
    if (!AppConstants.kAllowedExtensions.contains(extension)) {
      return 'Invalid file type ($extension). Allowed formats: ${AppConstants.kAllowedExtensions.join(", ")}.';
    }
    return null;
  }

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
