import 'package:flutter/material.dart';

import '../../../app/app.dart';
import 'super_admin_panel.dart';

class SuperAdminDashboard extends StatelessWidget {
  const SuperAdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return SuperAdminPanel(
      onLogout: () => LogoutController.logout(context),
    );
  }
}
