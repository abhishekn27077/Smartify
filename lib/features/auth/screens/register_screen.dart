import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartify/core/theme/app_colors.dart';
import 'package:smartify/core/theme/app_spacing.dart';
import 'package:smartify/core/widgets/app_text_field.dart';
import 'package:smartify/core/widgets/primary_button.dart';
import 'package:smartify/features/auth/providers/auth_provider.dart';

/// SMARTIFY Student Registration Screen
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String _selectedProgram = 'MCA';

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Passwords do not match.'),
            backgroundColor: AppColors.error),
      );
      return;
    }

    final auth = context.read<AuthProvider>();
    final success = await auth.register(
      _emailController.text.trim(),
      _passwordController.text,
      _nameController.text.trim(),
      academicProgram: _selectedProgram,
    );

    if (success && mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Registration successful!'),
            backgroundColor: AppColors.success),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Registration',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.space24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Create Your Student Account',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
                ),
                const SizedBox(height: 6),
                Text(
                  'Per campus policy, all initial registrations are created as Student accounts.',
                  style: TextStyle(
                      fontSize: 12,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.7)),
                ),
                const SizedBox(height: AppSpacing.space24),
                AppTextField(
                  label: 'Full Legal Name',
                  hintText: 'e.g. Aarav Patel',
                  isRequired: true,
                  controller: _nameController,
                ),
                const SizedBox(height: AppSpacing.space16),
                AppTextField(
                  label: 'Campus Institutional Email',
                  hintText: 'student@campus.edu',
                  isRequired: true,
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: AppSpacing.space16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Academic Program',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Text(
                          ' *',
                          style: TextStyle(
                            color: AppColors.error,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedProgram,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusSmall),
                          borderSide:
                              BorderSide(color: theme.colorScheme.outline),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'MCA',
                          child: Text('Master of Computer Applications (MCA)'),
                        ),
                        DropdownMenuItem(
                          value: 'MBA',
                          child: Text('Master of Business Administration (MBA)'),
                        ),
                        DropdownMenuItem(
                          value: 'M.Com',
                          child: Text('Master of Commerce (M.Com)'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedProgram = val);
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.space16),
                AppTextField(
                  label: 'Password',
                  hintText: 'At least 8 characters',
                  isRequired: true,
                  controller: _passwordController,
                  obscureText: true,
                ),
                const SizedBox(height: AppSpacing.space16),
                AppTextField(
                  label: 'Confirm Password',
                  hintText: 'Re-enter password',
                  isRequired: true,
                  controller: _confirmPasswordController,
                  obscureText: true,
                ),
                const SizedBox(height: AppSpacing.space24),
                if (auth.errorMessage != null) ...[
                  Text(auth.errorMessage!,
                      style: const TextStyle(
                          color: AppColors.error, fontSize: 12)),
                  const SizedBox(height: AppSpacing.space16),
                ],
                PrimaryButton(
                  text: 'REGISTER ACCOUNT',
                  isLoading: auth.isLoading,
                  onPressed: _handleRegister,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
