import 'package:flutter/material.dart';

import '../core/auth/app_session.dart';
import '../core/theme/app_theme.dart';
import '../features/admin/dashboard/admin_dashboard.dart';
import '../features/admin/setup/folder_selection_screen.dart';
import '../features/auth/logic/auth_service.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/super_admin_dashboard.dart';
import '../features/employee/dashboard/employee_dashboard.dart';
import 'routes.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AK Mobile Shop POS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routes: {
        AppRoutes.login: (_) => const LoginScreen(),
        AppRoutes.superAdminDashboard: (_) => const SuperAdminDashboard(),
        AppRoutes.adminSetup: (context) {
          final shopId = ModalRoute.of(context)?.settings.arguments as String? ?? '';
          return FolderSelectionScreen(shopId: shopId);
        },
        AppRoutes.adminDashboard: (context) {
          final shopId = ModalRoute.of(context)?.settings.arguments as String? ?? '';
          return AdminDashboard(shopId: shopId);
        },
        AppRoutes.employeeDashboard: (context) {
          final shopId = ModalRoute.of(context)?.settings.arguments as String? ?? '';
          return EmployeeDashboard(shopId: shopId);
        },
      },
      onGenerateRoute: (settings) {
        final routeName = settings.name ?? '';
        final role = AppSession.instance.role;
        if (routeName == AppRoutes.adminDashboard && (role != LoginRole.admin.name || AppSession.instance.shopId == null)) {
          return MaterialPageRoute(builder: (_) => const LoginScreen());
        }
        if (routeName == AppRoutes.employeeDashboard && (role != LoginRole.employee.name || AppSession.instance.shopId == null)) {
          return MaterialPageRoute(builder: (_) => const LoginScreen());
        }
        return null;
      },
      initialRoute: AppRoutes.login,
    );
  }
}

class LogoutController {
  static void logout(BuildContext context) {
    AppSession.instance.clear();
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.login,
      (route) => false,
    );
  }
}
