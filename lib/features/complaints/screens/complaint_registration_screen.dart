import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartify/core/constants/app_constants.dart';
import 'package:smartify/core/theme/app_spacing.dart';
import 'package:smartify/core/widgets/app_text_field.dart';
import 'package:smartify/core/widgets/primary_button.dart';
import 'package:smartify/core/widgets/restricted_date_picker.dart';
import 'package:smartify/core/widgets/state_views.dart';
import 'package:smartify/features/auth/providers/auth_provider.dart';
import 'package:smartify/features/complaints/models/complaint_category_model.dart';
import 'package:smartify/features/complaints/providers/complaint_submission_provider.dart';
import 'package:smartify/features/complaints/screens/submission_confirmation_screen.dart';
import 'package:smartify/features/complaints/widgets/attachment_picker_tile.dart';

/// SMARTIFY Student Grievance Registration Screen
/// Form adheres to institutional routing rules, 7-day incident window, and single-attachment limits.
class ComplaintRegistrationScreen extends StatefulWidget {
  const ComplaintRegistrationScreen({super.key});

  @override
  State<ComplaintRegistrationScreen> createState() =>
      _ComplaintRegistrationScreenState();
}

class _ComplaintRegistrationScreenState
    extends State<ComplaintRegistrationScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<AuthProvider>().currentUser;
      context.read<ComplaintSubmissionProvider>().loadDepartments(
            studentProgram: user?.academicProgram,
          );
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final user = context.read<AuthProvider>().currentUser;
    final provider = context.read<ComplaintSubmissionProvider>();
    final success = await provider.submitComplaint(
      studentProgram: user?.academicProgram,
    );

    if (success && mounted) {
      final result = provider.submissionResult;
      if (result != null) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SubmissionConfirmationScreen(result: result),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<ComplaintSubmissionProvider>();
    final user = context.watch<AuthProvider>().currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Register Grievance',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: theme.colorScheme.outline, height: 1),
        ),
      ),
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(AppSpacing.space16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Reference & Escalation Preview Header
                Container(
                  padding: const EdgeInsets.all(AppSpacing.space12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer
                        .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.shield_outlined,
                          color: theme.colorScheme.primary, size: 24),
                      const SizedBox(width: AppSpacing.space12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Institutional Redressal Protocol',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Assigned to Level 1. Tracking ID issued upon submission.',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.space20),

                // 2. Category Selection
                Text(
                  'Grievance Category *',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.space8),
                Wrap(
                  spacing: AppSpacing.space8,
                  runSpacing: AppSpacing.space8,
                  children:
                      ComplaintCategoryModel.predefinedCategories.map((cat) {
                    final isSelected = provider.category == cat.title;
                    return ChoiceChip(
                      label: Text(cat.title),
                      selected: isSelected,
                      selectedColor: theme.colorScheme.primary,
                      labelStyle: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : theme.colorScheme.onSurface,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w400,
                        fontSize: 12,
                      ),
                      onSelected: (_) => provider.selectCategory(
                        cat,
                        studentProgram: user?.academicProgram,
                      ),
                    );
                  }).toList(),
                ),

                if (provider.category.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.space16),
                  // Subcategory Selection Dropdown
                  Builder(
                    builder: (_) {
                      final selectedCatModel = ComplaintCategoryModel
                          .predefinedCategories
                          .where((c) => c.title == provider.category)
                          .firstOrNull;
                      final subCats = selectedCatModel?.subCategories ?? [];

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'What type of problem is this? (Issue Area)',
                            style: theme.textTheme.titleMedium?.copyWith(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: AppSpacing.space8),
                          DropdownButtonFormField<String>(
                            initialValue: provider.subCategory,
                            decoration: const InputDecoration(
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12)),
                            items: subCats
                                .map((sc) => DropdownMenuItem(
                                    value: sc,
                                    child: Text(sc,
                                        style: const TextStyle(fontSize: 13))))
                                .toList(),
                            onChanged: provider.selectSubCategory,
                          ),
                        ],
                      );
                    },
                  ),
                ],

                const SizedBox(height: AppSpacing.space20),

                // 3. Derived Responsible Department (Read-Only Confirmation Card)
                Text(
                  'Responsible Department (Authoritative Routing)',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: AppSpacing.space8),
                if (provider.isLoadingDepartments)
                  const StateLoadingShimmer(height: 52)
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.space12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusMedium),
                      border: Border.all(
                          color:
                              theme.colorScheme.primary.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.domain_rounded,
                              size: 20, color: theme.colorScheme.primary),
                        ),
                        const SizedBox(width: AppSpacing.space12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                provider.selectedDepartment != null
                                    ? '${provider.selectedDepartment!.name} (${provider.selectedDepartment!.code})'
                                    : 'Select Category to Route',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Grievance will route directly to ${provider.selectedDepartment?.name ?? "Department"} Level 1 for initial triage.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: AppSpacing.space20),

                // 4. Restricted Date Picker [Today - 7 days, Today]
                RestrictedDatePicker(
                  selectedDate: provider.incidentDate,
                  onDateSelected: provider.selectIncidentDate,
                  errorText: provider.dateError,
                ),

                const SizedBox(height: AppSpacing.space20),

                // 5. Title Field
                AppTextField(
                  label: 'Grievance Title',
                  isRequired: true,
                  controller: _titleController,
                  hintText: 'e.g., WiFi connection problem',
                  maxLength: AppConstants.kMaxTitleLength,
                  errorText: provider.titleError,
                  onChanged: provider.setTitle,
                ),

                const SizedBox(height: AppSpacing.space16),

                // 6. Detailed Description Field
                AppTextField(
                  label: 'Detailed Description',
                  isRequired: true,
                  controller: _descriptionController,
                  hintText:
                      'Explain what happened, where it happened, and how it affected you...',
                  minLines: 4,
                  maxLines: 8,
                  errorText: provider.descriptionError,
                  onChanged: provider.setDescription,
                ),

                const SizedBox(height: AppSpacing.space20),

                // 7. Optional Evidence Attachment Tile
                AttachmentPickerTile(
                  attachment: provider.attachment,
                  onAttachmentChanged: provider.setAttachment,
                  errorText: provider.attachmentError,
                ),

                const SizedBox(height: AppSpacing.space24),

                // 8. Error Banner if submission failed
                if (provider.submissionError != null) ...[
                  FeedbackBanner(
                    message: provider.submissionError!,
                    isError: true,
                    onRetry: provider.isFormValid ? _handleSubmit : null,
                    onDismiss: provider.clearError,
                  ),
                  const SizedBox(height: AppSpacing.space16),
                ],

                // 9. Primary Submission Button
                PrimaryButton(
                  text: 'SUBMIT GRIEVANCE',
                  icon: Icons.send_rounded,
                  isLoading: provider.isSubmitting,
                  onPressed: (provider.isFormValid && !provider.isSubmitting)
                      ? _handleSubmit
                      : null,
                ),

                SizedBox(
                  height: AppSpacing.space32 +
                      (MediaQuery.of(context).viewInsets.bottom > 0
                          ? AppSpacing.space24
                          : 0),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
