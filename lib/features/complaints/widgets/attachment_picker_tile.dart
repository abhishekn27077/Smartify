import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:smartify/core/constants/app_constants.dart';
import 'package:smartify/core/theme/app_colors.dart';
import 'package:smartify/core/theme/app_spacing.dart';
import 'package:smartify/features/complaints/models/attachment_file.dart';

/// SMARTIFY Attachment Picker Tile
/// Allows students to pick optional evidence files (images or PDFs <= 10MB).
class AttachmentPickerTile extends StatelessWidget {
  final AttachmentFile? attachment;
  final ValueChanged<AttachmentFile?> onAttachmentChanged;
  final String? errorText;

  const AttachmentPickerTile({
    super.key,
    required this.attachment,
    required this.onAttachmentChanged,
    this.errorText,
  });

  Future<void> _pickFile(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: AppConstants.kAllowedExtensions,
        allowMultiple: false,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final platformFile = result.files.first;
        final file = AttachmentFile(
          name: platformFile.name,
          path: platformFile.path ?? '',
          sizeBytes: platformFile.size,
          bytes: platformFile.bytes,
        );

        final validationError = file.validate();
        if (validationError != null) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(validationError),
                backgroundColor: AppColors.error,
              ),
            );
          }
          return;
        }

        onAttachmentChanged(file);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open file selector: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Evidence Attachment (Optional)',
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              'Max: 10MB',
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.space8),
        if (attachment == null)
          Semantics(
            button: true,
            label:
                'Attach photo or document evidence. Allowed types: jpg, png, webp, pdf up to 10MB.',
            child: InkWell(
              onTap: () => _pickFile(context),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
              child: Container(
                height: 72,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                  border: Border.all(
                    color: errorText != null
                        ? theme.colorScheme.error
                        : theme.colorScheme.outline,
                    style: BorderStyle.solid,
                    width: 1.2,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.space8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer
                            .withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.upload_file_outlined,
                          color: theme.colorScheme.primary, size: 22),
                    ),
                    const SizedBox(width: AppSpacing.space12),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Upload photo or PDF document',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          'Formats: JPG, PNG, WEBP, PDF',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(AppSpacing.space12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
              border: Border.all(color: theme.colorScheme.outline),
            ),
            child: Row(
              children: [
                if (attachment!.isImage && attachment!.bytes != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                    child: Image.memory(
                      attachment!.bytes!,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.space8),
                    decoration: BoxDecoration(
                      color: (attachment!.isImage
                              ? AppColors.primary
                              : AppColors.secondary)
                          .withValues(alpha: 0.1),
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusSmall),
                    ),
                    child: Icon(
                      attachment!.isImage
                          ? Icons.image_outlined
                          : Icons.picture_as_pdf_outlined,
                      color: attachment!.isImage
                          ? AppColors.primary
                          : AppColors.secondary,
                      size: 24,
                    ),
                  ),
                const SizedBox(width: AppSpacing.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        attachment!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${attachment!.extension.toUpperCase()} • ${attachment!.formattedSize}',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                Semantics(
                  button: true,
                  label: 'Remove attachment ${attachment!.name}',
                  child: IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    color: AppColors.error,
                    tooltip: 'Remove Attachment',
                    onPressed: () => onAttachmentChanged(null),
                  ),
                ),
              ],
            ),
          ),
        if (errorText != null) ...[
          const SizedBox(height: 4),
          Text(errorText!,
              style: TextStyle(color: theme.colorScheme.error, fontSize: 12)),
        ],
      ],
    );
  }
}
