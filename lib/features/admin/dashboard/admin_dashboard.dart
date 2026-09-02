import 'package:flutter/material.dart';

import '../../../core/database/database_service.dart';
import '../employees/employees_page.dart';
import '../inventory/inventory_pages.dart';
import '../inventory/mobile_models_page.dart';
import '../inventory/suppliers_page.dart';
import '../management/admin_management_pages.dart';
import '../reports/reports_page.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key, required this.shopId});

  final String shopId;

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
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
              child: SidebarContent(
                selectedPage: _selectedPage,
                onNavigate: (page) => setState(() => _selectedPage = page),
                onLogout: () => Navigator.of(context).pushNamedAndRemoveUntil(
                  '/login',
                  (route) => false,
                ),
              ),
            ),
            Expanded(
              child: _selectedPage == 'Mobile Inventory'
                  ? MobileModelsPage(shopId: widget.shopId)
                  : _selectedPage == 'Suppliers'
                      ? SuppliersPage(shopId: widget.shopId)
                      : _selectedPage == 'Accessories Inventory'
                          ? AccessoriesInventoryPage(shopId: widget.shopId)
                          : _selectedPage == 'Repairs'
                              ? RepairsPage(shopId: widget.shopId)
                              : _selectedPage == 'Backup'
                                  ? BackupPage(shopId: widget.shopId)
                                  : _selectedPage == 'Debt'
                                      ? DebtPage(shopId: widget.shopId)
                                      : _selectedPage == 'Settings'
                                          ? SettingsPage(shopId: widget.shopId)
                                          : _selectedPage == 'Reports'
                                              ? ReportsPage(key: ValueKey(_reportDate), shopId: widget.shopId, initialDate: _reportDate)
                                              : _selectedPage == 'Employees'
                                                  ? EmployeesPage(shopId: widget.shopId)
                                                  : DashboardContent(shopId: widget.shopId, onQuickAction: _handleQuickAction),
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
      case 'Add Product':
        _chooseInventoryForm(title: 'Add Product');
        break;
      case 'New Purchase':
        _chooseInventoryForm(title: 'New Purchase');
        break;
      case 'Add Repair':
        setState(() => _selectedPage = 'Repairs');
        break;
      case 'Daily Report':
        setState(() {
          _reportDate = DateTime.now();
          _selectedPage = 'Reports';
        });
        break;
    }
  }

  Future<void> _chooseInventoryForm({required String title}) async {
    final accessoriesMode = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: const Text('Choose the inventory type.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Add Mobile')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add Accessory')),
        ],
      ),
    );
    if (!mounted || accessoriesMode == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AddInventoryDialog(
        shopId: widget.shopId,
        accessoriesMode: accessoriesMode,
        onSaved: () {},
      ),
    );
  }
}

class SidebarContent extends StatelessWidget {
  const SidebarContent({super.key, this.onLogout, this.onNavigate, this.selectedPage = 'Dashboard'});

  final VoidCallback? onLogout;
  final ValueChanged<String>? onNavigate;
  final String selectedPage;

  @override
  Widget build(BuildContext context) {
    const navItems = <String>[
      'Dashboard',
      'Mobile Inventory',
      'Suppliers',
      'Accessories Inventory',
      'Repairs',
      'Backup',
      'Debt',
      'Settings',
      'Reports',
      'Employees',
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Text(
                'AK',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MOBILE SHOP',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      letterSpacing: 0.8,
                    ),
                  ),
                  Text(
                    'MANAGEMENT SYSTEM',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'MAIN',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 11,
              letterSpacing: 1.2,
            ),
          ),
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
                icon: Icon(
                  _iconForItem(item),
                  color: selectedPage == item ? Colors.white : Colors.white70,
                  size: 18,
                ),
                label: Text(
                  item,
                  style: TextStyle(
                    color: selectedPage == item ? Colors.white : Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: onLogout ?? () {},
              icon: const Icon(Icons.logout, color: Colors.white70),
              label: const Text(
                'Logout',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.dark_mode, color: Colors.white70),
              label: const Text(
                'Dark Mode',
                style: TextStyle(color: Colors.white70),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white24),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
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
      case 'Employees':
        return Icons.badge_outlined;
      case 'Sales (POS)':
        return Icons.point_of_sale_outlined;
      case 'Purchases':
        return Icons.shopping_cart_outlined;
      case 'IMEI Management':
        return Icons.sim_card_outlined;
      case 'Repairs':
        return Icons.build_outlined;
      case 'Customers':
        return Icons.people_alt_outlined;
      case 'Suppliers':
        return Icons.local_shipping_outlined;
      case 'Expenses':
        return Icons.receipt_long_outlined;
      case 'Orders':
        return Icons.list_alt_outlined;
      case 'Settings':
        return Icons.settings_outlined;
      case 'Backup & Restore':
        return Icons.backup_outlined;
      default:
        return Icons.circle_outlined;
    }
  }
}

class DashboardContent extends StatefulWidget {
  const DashboardContent({super.key, required this.shopId, this.onQuickAction});

  final String shopId;
  final ValueChanged<String>? onQuickAction;

  @override
  State<DashboardContent> createState() => _DashboardContentState();
}

class _DashboardContentState extends State<DashboardContent> {
  String _selectedPeriod = 'Daily';

  String get _profitLabel {
    switch (_selectedPeriod) {
      case 'Daily':
        return 'Profit Today';
      case 'Weekly':
        return 'Profit This Week';
      case 'Monthly':
        return 'Profit This Month';
      default:
        return 'Total Profit';
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = DatabaseService.instance.dashboardStats(widget.shopId, period: _selectedPeriod);
    final statCards = [
      StatCard(label: 'Total Sales', value: _formatCurrency(stats.totalSales), change: 'From recorded sales', color: const Color(0xFFE7E3FF), icon: Icons.shopping_bag_outlined),
      StatCard(label: 'Total Purchases', value: _formatCurrency(stats.totalPurchases), change: 'From recorded purchases', color: const Color(0xFFE3F4E6), icon: Icons.shopping_cart_outlined),
      StatCard(label: _profitLabel, value: _formatCurrency(stats.totalProfit), change: 'Sales minus purchase cost', color: const Color(0xFFF8EED8), icon: Icons.pie_chart_rounded),
      LowStockCard(count: stats.lowStockItems),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final stackedLayout = constraints.maxWidth < 1200;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(26),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Dashboard',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: const Color(0xFF1D2941),
                          fontWeight: FontWeight.w700,
                          fontSize: 30,
                        ),
                      ),
                    ),
                    Container(
                      width: 200,
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E7EF)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedPeriod,
                          isExpanded: true,
                          icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF69758E)),
                          items: const [
                            DropdownMenuItem(value: 'Daily', child: Text('Daily')),
                            DropdownMenuItem(value: 'Weekly', child: Text('Weekly')),
                            DropdownMenuItem(value: 'Monthly', child: Text('Monthly')),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _selectedPeriod = value);
                            }
                          },
                          style: const TextStyle(color: Color(0xFF69758E), fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Welcome back, Arslan! Here\'s what\'s happening with your business today.',
                  style: TextStyle(color: Color(0xFF6A7283), fontSize: 15),
                ),
                const SizedBox(height: 18),
                if (stackedLayout)
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: statCards.map((card) => SizedBox(width: 250, child: card)).toList(),
                  )
                else
                  Row(
                    children: [
                      for (var i = 0; i < statCards.length; i++) ...[
                        Expanded(child: statCards[i]),
                        if (i < statCards.length - 1) const SizedBox(width: 16),
                      ],
                    ],
                  ),
                const SizedBox(height: 24),
                if (stackedLayout)
                  Column(
                    children: [
                      _salesOverviewCard(stats),
                      const SizedBox(height: 18),
                      _salesByCategoryCard(stats),
                      const SizedBox(height: 18),
                      _recentSalesCard(stats),
                      const SizedBox(height: 18),
                      _inventoryCards(stats),
                    ],
                  )
                else
                  Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 2, child: _salesOverviewCard(stats)),
                          const SizedBox(width: 18),
                          Expanded(child: _salesByCategoryCard(stats)),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 2, child: _recentSalesCard(stats)),
                          const SizedBox(width: 18),
                          Expanded(child: _lowStockCard(stats)),
                          const SizedBox(width: 18),
                          Expanded(child: QuickActionsGrid(onAction: widget.onQuickAction)),
                        ],
                      ),
                    ],
                  ),
                const SizedBox(height: 32),
                const Align(
                  alignment: Alignment.center,
                  child: Text(
                    '© 2024 AK Development. All rights reserved.',
                    style: TextStyle(color: Color(0xFF6A7283), fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _salesOverviewCard(DashboardStats stats) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE7ECF3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Expanded(child: Text('Sales Overview', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1D2941)))),
            SizedBox(width: 10),
            Text('This Week', style: TextStyle(color: Color(0xFF4C5A74), fontSize: 12)),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 230,
          child: CustomPaint(painter: SalesChartPainter(values: stats.salesByCategory), child: const SizedBox.expand()),
        ),
      ],
    ),
  );

  Widget _salesByCategoryCard(DashboardStats stats) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE7ECF3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Sales by Category', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1D2941))),
        const SizedBox(height: 18),
        Center(
          child: SizedBox(
            height: 170,
            width: 170,
            child: CustomPaint(painter: DonutChartPainter(breakdown: stats.categoryBreakdown)),
          ),
        ),
        const SizedBox(height: 14),
        CategoryLegend(breakdown: stats.categoryBreakdown),
      ],
    ),
  );

  Widget _recentSalesCard(DashboardStats stats) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE7ECF3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text('Recent Sales', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1D2941))),
            Text('View All', style: TextStyle(color: Color(0xFF4E53F8), fontSize: 13)),
          ],
        ),
        const SizedBox(height: 12),
        RecentSalesList(sales: stats.recentSales),
      ],
    ),
  );

  Widget _lowStockCard(DashboardStats stats) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE7ECF3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text('Low Stock Items', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1D2941))),
            Text('View All', style: TextStyle(color: Color(0xFF4E53F8), fontSize: 13)),
          ],
        ),
        const SizedBox(height: 12),
        StockList(stocks: stats.stockItems),
      ],
    ),
  );

  Widget _inventoryCards(DashboardStats stats) => Column(
    children: [
      _recentSalesCard(stats),
      const SizedBox(height: 18),
      _lowStockCard(stats),
      const SizedBox(height: 18),
      QuickActionsGrid(onAction: widget.onQuickAction),
    ],
  );
}

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value, required this.change, required this.color, required this.icon});

  final String label;
  final String value;
  final String change;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE7ECF3)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFF1D2941)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Color(0xFF68738B), fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF1D2941),
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  change,
                  style: const TextStyle(color: Color(0xFF2E9D62), fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class LowStockCard extends StatelessWidget {
  const LowStockCard({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE7ECF3)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFF7E7E5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.local_mall_outlined, color: Color(0xFF1D2941)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Low Stock Items',
                  style: TextStyle(color: Color(0xFF68738B), fontSize: 13),
                ),
                const SizedBox(height: 6),
                Text(
                  '$count',
                  style: const TextStyle(
                    color: Color(0xFF1D2941),
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatCurrency(double amount) {
  return 'PKR ${amount.toStringAsFixed(0)}';
}

class SalesChartPainter extends CustomPainter {
  const SalesChartPainter({required this.values});

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF7F72F5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final fillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x807F72F5), Color(0x00FFFFFF)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final line = Path();
    final maximum = values.fold<double>(0, (maximum, value) => value > maximum ? value : maximum);
    final points = maximum == 0
        ? [
            Offset(10, size.height / 2),
            Offset(size.width - 10, size.height / 2),
          ]
        : List<Offset>.generate(values.length, (index) {
            final x = 10 + (size.width - 20) * index / (values.length - 1);
            final y = size.height - 20 - (values[index] / maximum) * (size.height - 40);
            return Offset(x, y);
          });

    line.moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      line.lineTo(point.dx, point.dy);
    }

    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(fill, fillPaint);
    canvas.drawPath(line, paint);

    final gridPaint = Paint()
      ..color = const Color(0xFFE9EDF5)
      ..strokeWidth = 1;
    for (var i = 0; i <= 5; i++) {
      final y = (size.height / 5) * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class DonutChartPainter extends CustomPainter {
  const DonutChartPainter({required this.breakdown});

  final CategoryBreakdown breakdown;

  @override
  void paint(Canvas canvas, Size size) {
    final colors = [
      const Color(0xFF7C8DF4),
      const Color(0xFF57C3A9),
      const Color(0xFFF6C667),
      const Color(0xFFF09AA8),
    ];
    final data = [
      breakdown.mobile,
      breakdown.accessories,
      breakdown.repair,
      breakdown.debtRecovery,
    ];
    final total = data.fold<double>(0, (sum, value) => sum + value);
    double startAngle = -90 * (3.141592653589793 / 180);
    final radius = size.width / 2;
    final center = Offset(size.width / 2, size.height / 2);

    if (total <= 0) {
      final backgroundPaint = Paint()..color = const Color(0xFFE8ECF4);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 10),
        -90 * (3.141592653589793 / 180),
        2 * 3.141592653589793,
        false,
        backgroundPaint..style = PaintingStyle.stroke..strokeWidth = 20,
      );
    } else {
      for (var i = 0; i < colors.length; i++) {
        final sweepAngle = total <= 0
            ? 0.0
            : (data[i] / total) * 2 * 3.141592653589793;
        final paint = Paint()
          ..color = colors[i]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 20
          ..strokeCap = StrokeCap.round;
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius - 10),
          startAngle,
          sweepAngle,
          false,
          paint,
        );
        startAngle += sweepAngle;
      }
    }

    final innerPaint = Paint()..color = Colors.white;
    canvas.drawCircle(center, radius - 30, innerPaint);

    final textPainter = TextPainter(
      text: TextSpan(
        text: '${total.toStringAsFixed(0)}\nPKR',
        style: const TextStyle(
          color: Color(0xFF1D2941),
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(center.dx - textPainter.width / 2, center.dy - textPainter.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class CategoryLegend extends StatelessWidget {
  const CategoryLegend({super.key, required this.breakdown});

  final CategoryBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Mobile', breakdown.mobile, const Color(0xFF7C8DF4)),
      ('Accessories', breakdown.accessories, const Color(0xFF57C3A9)),
      ('Repair', breakdown.repair, const Color(0xFFF6C667)),
      ('Debt Recovery', breakdown.debtRecovery, const Color(0xFFF09AA8)),
    ];

    final total = breakdown.total;

    return Column(
      children: items.map((item) {
        final percent = total <= 0 ? 0 : ((item.$2 / total) * 100);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: item.$3,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(item.$1, style: const TextStyle(color: Color(0xFF39455D), fontSize: 12)),
              ),
              Text('${percent.toStringAsFixed(0)}%', style: const TextStyle(color: Color(0xFF39455D), fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class RecentSalesList extends StatelessWidget {
  const RecentSalesList({super.key, this.sales = const []});

  final List<DashboardSale> sales;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: sales.map((sale) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF0F7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.phone_iphone, color: Color(0xFF1D2941)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sale.productName,
                      style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1D2941), fontSize: 13),
                    ),
                    Text(
                      sale.imei == null ? 'No IMEI recorded' : 'IMEI: ${sale.imei}',
                      style: const TextStyle(color: Color(0xFF6A7283), fontSize: 11),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatCurrency(sale.amount),
                    style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF1D2941), fontSize: 13),
                  ),
                  Text(
                    sale.soldAt.toLocal().toString(),
                    style: const TextStyle(color: Color(0xFF6A7283), fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class StockList extends StatelessWidget {
  const StockList({super.key, this.stocks = const []});

  final List<DashboardStock> stocks;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: stocks.map((stock) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF0F7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.phone_iphone, color: Color(0xFF1D2941)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stock.productName,
                      style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1D2941), fontSize: 13),
                    ),
                    Text(
                      'Stock: ${stock.quantity}',
                      style: const TextStyle(color: Color(0xFF6A7283), fontSize: 11),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF6A7283)),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class QuickActionsGrid extends StatelessWidget {
  const QuickActionsGrid({super.key, this.onAction, this.actions});

  final ValueChanged<String>? onAction;
  final Set<String>? actions;

  @override
  Widget build(BuildContext context) {
    final allActions = [
      ('New Sale', Icons.shopping_cart, const Color(0xFFE8F2F8)),
      ('Add Product', Icons.add, const Color(0xFFE7F6EA)),
      ('New Purchase', Icons.card_giftcard, const Color(0xFFE8EAFB)),
      ('Add Repair', Icons.build, const Color(0xFFEFF3D6)),
      ('Daily Report', Icons.assessment, const Color(0xFFEAF4F5)),
    ];
    final visibleActions = actions == null
        ? allActions
        : allActions.where((action) => actions!.contains(action.$1)).toList();

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.2,
      children: visibleActions.map((action) {
        return InkWell(
          onTap: onAction == null ? null : () => onAction!(action.$1),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: action.$3,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE7ECF3)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(action.$2, color: const Color(0xFF1D2941), size: 28),
                const SizedBox(height: 10),
                Text(
                  action.$1,
                  style: const TextStyle(
                    color: Color(0xFF1D2941),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
