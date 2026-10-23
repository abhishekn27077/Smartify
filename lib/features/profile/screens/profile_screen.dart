import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartify/core/theme/app_colors.dart';
import 'package:smartify/core/theme/app_spacing.dart';
import 'package:smartify/core/widgets/state_views.dart';
import 'package:smartify/features/auth/providers/auth_provider.dart';

/// SMARTIFY User Profile Screen
/// Displays authenticated session profile with full state handling (Loading, Empty, Error, Success).
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Profile',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
      ),
      body: SafeArea(
        child: Builder(
          builder: (context) {
            // 1. Loading State
            if (auth.isLoading) {
              return _buildLoadingState();
            }

            // 2. Error State (if any auth error occurred)
            if (auth.errorMessage != null) {
              return Padding(
                padding: const EdgeInsets.all(AppSpacing.space16),
                child: Column(
                  children: [
                    FeedbackBanner(
                      message: auth.errorMessage!,
                      isError: true,
                    ),
                    const SizedBox(height: AppSpacing.space24),
                    OutlinedButton(
                      onPressed: () => auth.logout(),
                      child: const Text('Return to Login'),
                    ),
                  ],
                ),
              );
            }

            // 3. Empty / Unauthenticated State
            final user = auth.currentUser;
            if (user == null || !auth.isAuthenticated) {
              return const StateEmptyView(
                title: 'No Active Session',
                subtitle:
                    'Please sign in with your institutional credentials to access your profile.',
                icon: Icons.account_circle_outlined,
              );
            }

            // 4. Success State (Authenticated User View)
            final name = user.fullName;
            final email = user.email;
            final role = user.role;
            final dept = user.departmentName ??
                (role == 'student'
                    ? 'Student Body'
                    : (role == 'admin'
                        ? 'Central Governance'
                        : 'Department Officer'));
            final level = user.authorityLevelTitle ??
                (role == 'authority'
                    ? 'Authorized Officer'
                    : (role == 'admin' ? 'Campus Administrator' : 'None'));

            return SingleChildScrollView(
              padding: const EdgeInsets.only(
                left: AppSpacing.space16,
                right: AppSpacing.space16,
                top: AppSpacing.space16,
                bottom: 88.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Avatar
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: AppColors.primary,
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'U',
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space12),

                  Text(
                    name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    email,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 8),

                  Chip(
                    label: Text(
                      role.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    backgroundColor: role == 'admin'
                        ? AppColors.primary
                        : (role == 'authority'
                            ? AppColors.secondary
                            : AppColors.outline),
                  ),
                  const SizedBox(height: AppSpacing.space24),

                  // Account Details Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.space16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusMedium),
                      border: Border.all(color: theme.colorScheme.outline),
                    ),
                    child: Column(
                      children: [
                        _buildRow('Department', dept, theme),
                        const Divider(height: 20),
                        _buildRow(
                            role == 'student'
                                ? 'Academic Program'
                                : 'Designation / Tier',
                            role == 'student'
                                ? (user.academicProgram != null
                                    ? '${user.academicProgram} Student'
                                    : 'Student')
                                : level,
                            theme),
                        const Divider(height: 20),
                        _buildRow(
                            'Campus Member ID',
                            user.registrationNumber ??
                                (user.id.length > 16
                                    ? '${user.id.substring(0, 16)}...'
                                    : user.id),
                            theme),
                        const Divider(height: 20),
                        _buildRow('Account Status',
                            'Active Institutional Member', theme),
                        const Divider(height: 20),
                        _buildRow(
                            'Security Scope',
                            role == 'admin'
                                ? 'Administrative access governed by institutional permissions'
                                : (role == 'authority'
                                    ? 'Department authority governed by tier permissions'
                                    : 'Student access governed by institutional policies'),
                            theme),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space24),

                  // Server-Authoritative Security Invariant Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.space16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusMedium),
                      border: Border.all(color: theme.colorScheme.outline),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.verified_user_rounded,
                            color: AppColors.primary, size: 24),
                        const SizedBox(width: AppSpacing.space12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Role: ${role.toUpperCase()} • $dept',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Data access is strictly governed by institutional role permissions. Privileges are verified securely on every request.',
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

                  const SizedBox(height: AppSpacing.space32),

                  OutlinedButton.icon(
                    icon: const Icon(Icons.logout, size: 16),
                    label: const Text('Sign Out'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error),
                    onPressed: () => _showSignOutDialog(context, auth),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Padding(
      padding: EdgeInsets.all(AppSpacing.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(height: 20),
          Center(
            child: StateLoadingShimmer(
              height: 80,
              width: 80,
              borderRadius: 40,
            ),
          ),
          SizedBox(height: 16),
          StateLoadingShimmer(height: 20, width: 140),
          SizedBox(height: 8),
          StateLoadingShimmer(height: 14, width: 200),
          SizedBox(height: 24),
          StateLoadingShimmer(height: 180),
        ],
      ),
    );
  }

  void _showSignOutDialog(BuildContext context, AuthProvider auth) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text(
          'Are you sure you want to end your current session and sign out of SMARTIFY?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              auth.logout();
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value, ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            softWrap: true,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}
