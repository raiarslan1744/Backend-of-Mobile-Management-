import 'package:flutter_test/flutter_test.dart';
import 'package:develop/core/database/database_service.dart';
import 'package:develop/features/admin/inventory/inventory_service.dart';
import 'package:develop/features/admin/management/admin_management_service.dart';
import 'package:develop/features/admin/reports/reports_service.dart';

void main() {
  test('reports read completed sales, repairs, and debt without printing', () {
    DatabaseService.instance.resetForTesting();
    const shopId = 'REPORT-SHOP';
    final inventory = InventoryService();
    final management = AdminManagementService();
    final reports = ReportsService();

    expect(inventory.addMobile(shopId: shopId, name: 'Report Phone', color: 'Black', imei1: 'REPORT-IMEI', buyPrice: 100, sellPrice: 150, condition: 'new'), isNull);
    final mobile = inventory.findMobileByImei(shopId, 'REPORT-IMEI')!;
    final cart = SharedCart.instance;
    cart.clear();
    cart.addMobile(shopId, mobile);
    expect(inventory.completeSale(shopId: shopId, cart: List<CartLine>.from(cart.lines), customerName: 'Sara', customerPhone: '0300', customerAddress: 'Lahore'), isNull);
    cart.clear();

    expect(management.addRepair(shopId: shopId, name: 'Screen Repair', cost: 50, charge: 100), isNotNull);
    final debtor = management.addDebtor(shopId: shopId, name: 'Ali', phone: '0311', address: 'Karachi')!;
    expect(management.addDebt(debtorId: debtor.id, item: 'Cable', amount: 25), isNull);
    expect(management.addPayment(debtorId: debtor.id, amount: 10), isNull);

    final all = reports.reports(shopId);
    expect(all.map((item) => item.type), containsAll(<String>['Mobile Sale', 'Repair', 'Debt']));
    expect(reports.reports(shopId, type: 'Mobile Sale').single.person, 'Sara');
    expect(reports.reports(shopId, search: 'REPORT-IMEI'), hasLength(1));
    expect(reports.reports(shopId, type: 'Debt'), hasLength(2));
  });
}
