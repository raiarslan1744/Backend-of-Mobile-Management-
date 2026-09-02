import 'package:flutter/material.dart';

import '../../../core/database/database_service.dart';
import '../../admin/dashboard/admin_dashboard.dart';
import '../../admin/inventory/inventory_pages.dart';
import '../../admin/reports/reports_page.dart';

class EmployeeDashboard extends StatefulWidget {
  const EmployeeDashboard({super.key, required this.shopId});

  final String shopId;

  @override
  State<EmployeeDashboard> createState() => _EmployeeDashboardState();
}

class _EmployeeDashboardState extends State<EmployeeDashboard> {
  String _selectedPage = 'Dashboard';
  DateTime? _reportDate;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width > 1100;

    return Scaffold(
      body: Container(
        color: const Color(0xFFF5F5F5),
        child: Row(
          children: [
            Container(
              width: isWide ? 240 : 190,
              color: const Color(0xFF1A2336),
              child: EmployeeSidebar(
                selectedPage: _selectedPage,
                onNavigate: (page) => setState(() => _selectedPage = page),
                onLogout: () => Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false),
              ),
            ),
            Expanded(
              child: _selectedPage == 'Mobile Inventory'
                  ? MobileInventoryPage(shopId: widget.shopId, isEmployee: true)
                  : _selectedPage == 'Accessories Inventory'
                      ? AccessoriesInventoryPage(shopId: widget.shopId, isEmployee: true)
                      : _selectedPage == 'Reports'
                            ? ReportsPage(key: ValueKey(_reportDate), shopId: widget.shopId, initialDate: _reportDate)
                          : EmployeeDashboardContent(shopId: widget.shopId, onQuickAction: _handleQuickAction),
            ),
          ],
        ),
      ),
    );
  }

  void _handleQuickAction(String action) {
    switch (action) {
      case 'New Sale':
        setState(() => _selectedPage = 'Mobile Inventory');
        break;
      case 'Daily Report':
        setState(() {
          _reportDate = DateTime.now();
          _selectedPage = 'Reports';
        });
        break;
    }
  }
}

class EmployeeSidebar extends StatelessWidget {
  const EmployeeSidebar({super.key, this.onLogout, this.onNavigate, this.selectedPage = 'Dashboard'});

  final VoidCallback? onLogout;
  final ValueChanged<String>? onNavigate;
  final String selectedPage;

  @override
  Widget build(BuildContext context) {
    const navItems = <String>['Dashboard', 'Mobile Inventory', 'Accessories Inventory', 'Reports'];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Text('AK', style: TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.bold)),
              SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('MOBILE SHOP', style: TextStyle(color: Colors.white, fontSize: 14, letterSpacing: 0.8)),
                  Text('EMPLOYEE', style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 0.5)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text('MAIN', style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1.2)),
          const SizedBox(height: 8),
          ...navItems.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextButton.icon(
                onPressed: () => onNavigate?.call(item),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  alignment: Alignment.centerLeft,
                ),
                icon: Icon(_iconForItem(item), color: selectedPage == item ? Colors.white : Colors.white70, size: 18),
                label: Text(item, style: TextStyle(color: selectedPage == item ? Colors.white : Colors.white70, fontSize: 14)),
              ),
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: onLogout ?? () {},
              icon: const Icon(Icons.logout, color: Colors.white70),
              label: const Text('Logout', style: TextStyle(color: Colors.white70)),
            ),
          ),
        ],
      ),
    );
  }

  static IconData _iconForItem(String item) {
    switch (item) {
      case 'Dashboard':
        return Icons.dashboard_outlined;
      case 'Mobile Inventory':
        return Icons.inventory_2_outlined;
      case 'Accessories Inventory':
        return Icons.headset_mic_outlined;
      case 'Reports':
        return Icons.assessment_outlined;
      default:
        return Icons.circle_outlined;
    }
  }
}

class EmployeeDashboardContent extends StatelessWidget {
  const EmployeeDashboardContent({super.key, required this.shopId, this.onQuickAction});

  final String shopId;
  final ValueChanged<String>? onQuickAction;

  @override
  Widget build(BuildContext context) {
    final stats = DatabaseService.instance.dashboardStats(shopId);

    return Padding(
      padding: const EdgeInsets.all(26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Employee Dashboard', style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: const Color(0xFF1D2941), fontWeight: FontWeight.w700, fontSize: 30)),
          const SizedBox(height: 12),
          const Text('Today’s sales and stock visibility for your shop.', style: TextStyle(color: Color(0xFF6A7283))),
          const SizedBox(height: 24),
          Wrap(
            spacing: 18,
            runSpacing: 18,
            children: [
              _statCard('Total Sales', 'PKR ${stats.totalSales.toStringAsFixed(0)}', Icons.payments_outlined),
              _statCard('Today', 'PKR ${stats.totalSales.toStringAsFixed(0)}', Icons.today_outlined),
              _statCard('Products', '${stats.totalProducts}', Icons.inventory_outlined),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: 460,
            child: QuickActionsGrid(
              actions: const {'New Sale', 'Daily Report'},
              onAction: onQuickAction,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E7EF)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFE9E4FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFF4E2BCB)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Color(0xFF6A7283), fontSize: 12)),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF1D2941))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
