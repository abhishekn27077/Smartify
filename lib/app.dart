import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartify/core/theme/app_theme.dart';
import 'package:smartify/features/admin/providers/admin_management_provider.dart';
import 'package:smartify/features/admin/screens/admin_control_center_screen.dart';
import 'package:smartify/features/admin/screens/admin_departments_screen.dart';
import 'package:smartify/features/analytics/providers/analytics_provider.dart';
import 'package:smartify/features/analytics/screens/analytics_dashboard_screen.dart';
import 'package:smartify/features/auth/providers/auth_provider.dart';
import 'package:smartify/features/auth/screens/login_screen.dart';
import 'package:smartify/features/authority/providers/authority_workflow_provider.dart';
import 'package:smartify/features/authority/screens/authority_dashboard_screen.dart';
import 'package:smartify/features/authority/screens/authority_escalations_screen.dart';
import 'package:smartify/features/authority/screens/authority_my_cases_screen.dart';
import 'package:smartify/features/complaints/providers/complaint_submission_provider.dart';
import 'package:smartify/features/complaints/screens/complaint_registration_screen.dart';
import 'package:smartify/features/escalation/providers/escalation_provider.dart';
import 'package:smartify/features/escalation/screens/admin_cutoff_review_screen.dart';
import 'package:smartify/features/home/screens/student_home_screen.dart';
import 'package:smartify/features/notifications/providers/notification_provider.dart';
import 'package:smartify/features/notifications/screens/notifications_screen.dart';
import 'package:smartify/features/profile/screens/profile_screen.dart';
import 'package:smartify/features/tracking/providers/student_tracking_provider.dart';
import 'package:smartify/features/tracking/screens/my_complaints_screen.dart';

/// SMARTIFY Root Application Widget
/// Configures high-level themes, responsive navigation, and provider dependency injection.
class SmartifyApp extends StatelessWidget {
  const SmartifyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
            create: (_) => AuthProvider()..initializeSession()),
        ChangeNotifierProvider(create: (_) => ComplaintSubmissionProvider()),
        ChangeNotifierProvider(create: (_) => StudentTrackingProvider()),
        ChangeNotifierProvider(create: (_) => AuthorityWorkflowProvider()),
        ChangeNotifierProvider(create: (_) => EscalationProvider()),
        ChangeNotifierProvider(create: (_) => AnalyticsProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => AdminManagementProvider()),
      ],
      child: MaterialApp(
        title: 'SMARTIFY',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.system,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: Consumer<AuthProvider>(
          builder: (context, auth, _) {
            if (auth.isLoading && !auth.isAuthenticated) {
              return const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(),
                ),
              );
            }
            if (!auth.isAuthenticated) {
              return const LoginScreen();
            }
            return const PortalNavigationShell();
          },
        ),
      ),
    );
  }
}

/// Navigation Shell facilitating role-aware testing across all SMARTIFY portal features
class PortalNavigationShell extends StatefulWidget {
  const PortalNavigationShell({super.key});

  @override
  State<PortalNavigationShell> createState() => _PortalNavigationShellState();
}

class _PortalNavigationShellState extends State<PortalNavigationShell> {
  int _currentIndex = 0;
  String _activeRole = '';

  void _navigateToIndex(int index) {
    if (mounted) {
      setState(() => _currentIndex = index);
    }
  }

  List<_NavDestinationItem> _getDestinationsForRole(
      String role, double screenWidth) {
    final isCompact = screenWidth < 600;
    if (role == 'admin') {
      return [
        _NavDestinationItem(
          screen: AdminControlCenterScreen(
            onNavigateToDepartments: () => _navigateToIndex(1),
            onNavigateToAnalytics: () => _navigateToIndex(2),
            onNavigateToGovernance: () => _navigateToIndex(3),
          ),
          label: isCompact ? 'Home' : 'Dashboard',
          icon: Icons.dashboard_outlined,
          selectedIcon: Icons.dashboard,
        ),
        _NavDestinationItem(
          screen: const AdminDepartmentsScreen(),
          label: isCompact ? 'Depts' : 'Departments',
          icon: Icons.apartment_outlined,
          selectedIcon: Icons.apartment,
        ),
        const _NavDestinationItem(
          screen: AnalyticsDashboardScreen(),
          label: 'Analytics',
          icon: Icons.insights_outlined,
          selectedIcon: Icons.insights,
        ),
        const _NavDestinationItem(
          screen: AdminCutoffReviewScreen(),
          label: 'Governance',
          icon: Icons.gavel_outlined,
          selectedIcon: Icons.gavel,
        ),
        const _NavDestinationItem(
          screen: NotificationsScreen(),
          label: 'Alerts',
          icon: Icons.notifications_none,
          selectedIcon: Icons.notifications,
          isAlerts: true,
        ),
        const _NavDestinationItem(
          screen: ProfileScreen(),
          label: 'Profile',
          icon: Icons.person_outline,
          selectedIcon: Icons.person,
        ),
      ];
    } else if (role == 'authority') {
      return [
        _NavDestinationItem(
          screen: AuthorityDashboardScreen(
            onNavigateToMyCases: () => _navigateToIndex(1),
            onNavigateToEscalations: () => _navigateToIndex(2),
          ),
          label: 'Queue',
          icon: Icons.inbox_outlined,
          selectedIcon: Icons.inbox,
        ),
        const _NavDestinationItem(
          screen: AuthorityMyCasesScreen(),
          label: 'My Cases',
          icon: Icons.assignment_ind_outlined,
          selectedIcon: Icons.assignment_ind,
        ),
        const _NavDestinationItem(
          screen: AuthorityEscalationsScreen(),
          label: 'Escalations',
          icon: Icons.trending_up,
          selectedIcon: Icons.trending_up,
        ),
        const _NavDestinationItem(
          screen: NotificationsScreen(),
          label: 'Alerts',
          icon: Icons.notifications_none,
          selectedIcon: Icons.notifications,
          isAlerts: true,
        ),
        const _NavDestinationItem(
          screen: ProfileScreen(),
          label: 'Profile',
          icon: Icons.person_outline,
          selectedIcon: Icons.person,
        ),
      ];
    } else {
      // Default: student role
      return [
        _NavDestinationItem(
          screen: StudentHomeScreen(
            onNavigateToComplaints: () => _navigateToIndex(1),
            onNavigateToSubmit: () => _navigateToIndex(2),
          ),
          label: 'Home',
          icon: Icons.home_outlined,
          selectedIcon: Icons.home,
        ),
        _NavDestinationItem(
          screen: const MyComplaintsScreen(),
          label: isCompact ? 'Grievances' : 'My Grievances',
          icon: Icons.assignment_outlined,
          selectedIcon: Icons.assignment,
        ),
        const _NavDestinationItem(
          screen: ComplaintRegistrationScreen(),
          label: 'Submit',
          icon: Icons.add_circle_outline,
          selectedIcon: Icons.add_circle,
        ),
        const _NavDestinationItem(
          screen: NotificationsScreen(),
          label: 'Alerts',
          icon: Icons.notifications_none,
          selectedIcon: Icons.notifications,
          isAlerts: true,
        ),
        const _NavDestinationItem(
          screen: ProfileScreen(),
          label: 'Profile',
          icon: Icons.person_outline,
          selectedIcon: Icons.person,
        ),
      ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final currentRole = auth.currentRole;
    final screenWidth = MediaQuery.of(context).size.width;

    if (_activeRole != currentRole) {
      _activeRole = currentRole;
      _currentIndex = 0;
    }

    final destinations = _getDestinationsForRole(currentRole, screenWidth);
    if (_currentIndex >= destinations.length) {
      _currentIndex = 0;
    }

    final notifProvider = context.watch<NotificationProvider>();
    final unread = notifProvider.unreadCount;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: destinations.map((d) => d.screen).toList(),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        destinations: destinations.map((item) {
          if (item.isAlerts) {
            return NavigationDestination(
              icon: Badge(
                isLabelVisible: unread > 0,
                label: Text(unread.toString()),
                child: Icon(item.icon),
              ),
              selectedIcon: Badge(
                isLabelVisible: unread > 0,
                label: Text(unread.toString()),
                child: Icon(item.selectedIcon),
              ),
              label: item.label,
            );
          }
          return NavigationDestination(
            icon: Icon(item.icon),
            selectedIcon: Icon(item.selectedIcon),
            label: item.label,
          );
        }).toList(),
      ),
    );
  }
}

class _NavDestinationItem {
  final Widget screen;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool isAlerts;

  const _NavDestinationItem({
    required this.screen,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.isAlerts = false,
  });
}
