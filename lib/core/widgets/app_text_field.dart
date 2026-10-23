import 'package:flutter/material.dart';
import 'package:smartify/core/theme/app_spacing.dart';

/// SMARTIFY Accessible Styled Form Text Field
class AppTextField extends StatelessWidget {
  final String label;
  final String? hintText;
  final String? helperText;
  final String? errorText;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final int maxLines;
  final int? minLines;
  final int? maxLength;
  final TextInputType keyboardType;
  final bool isRequired;
  final bool obscureText;
  final FormFieldValidator<String>? validator;
  final Widget? prefixIcon;
  final Widget? suffixIcon;

  const AppTextField({
    super.key,
    required this.label,
    this.hintText,
    this.helperText,
    this.errorText,
    this.controller,
    this.onChanged,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.keyboardType = TextInputType.text,
    this.isRequired = false,
    this.obscureText = false,
    this.validator,
    this.prefixIcon,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (isRequired)
              Text(
                ' *',
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.space8),
        Semantics(
          textField: true,
          label: label,
          hint: hintText,
          child: TextFormField(
            controller: controller,
            onChanged: onChanged,
            validator: validator,
            obscureText: obscureText,
            maxLines: obscureText ? 1 : maxLines,
            minLines: obscureText ? 1 : minLines,
            maxLength: maxLength,
            keyboardType: keyboardType,
            decoration: InputDecoration(
              hintText: hintText,
              helperText: helperText,
              errorText: errorText,
              prefixIcon: prefixIcon,
              suffixIcon: suffixIcon,
            ),
          ),
        ),
      ],
    );
  }
}
