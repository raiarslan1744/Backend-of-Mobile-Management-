import 'package:flutter_test/flutter_test.dart';
import 'package:develop/core/auth/app_session.dart';
import 'package:develop/core/database/database_service.dart';
import 'package:develop/features/admin/inventory/inventory_service.dart';

void main() {
  test('tracks mobile devices by IMEI and deducts accessory stock on sale', () {
    DatabaseService.instance.resetForTesting();
    final service = InventoryService();
    const shopId = 'SHOP-INVENTORY';

    expect(service.addMobile(shopId: shopId, name: 'Test Phone', color: 'Black', imei1: '111', condition: 'new', buyPrice: 100), isNull);
    expect(service.addMobile(shopId: shopId, name: 'Duplicate Phone', color: 'White', imei1: '111', condition: 'new'), isNotNull);
    expect(service.addAccessory(shopId: shopId, name: 'Case', buyPrice: 5, quantity: 2), isNull);

    final device = service.findMobileByImei(shopId, '111')!;
    final accessory = service.accessories(shopId).single;
    final cart = SharedCart.instance;
    cart.clear();
    cart.addMobile(shopId, device);
    cart.addAccessory(shopId, accessory);

    final mobileLine = cart.lines.firstWhere((line) => line.isMobile);
    mobileLine.salePrice = 150;
    final accessoryLine = cart.lines.firstWhere((line) => !line.isMobile);
    accessoryLine.salePrice = 10;
    accessoryLine.quantity = 2;

    expect(service.completeSale(shopId: shopId, cart: List<CartLine>.from(cart.lines), customerName: 'Customer', customerPhone: '0300', customerAddress: 'Address'), isNull);
    cart.clear();
    expect(service.findMobileByImei(shopId, '111'), isNull);
    expect(service.accessories(shopId), isEmpty);
    expect(service.totalMobileStockValue(shopId), 0);
    expect(service.totalAccessoriesStockValue(shopId), 0);
    expect(DatabaseService.instance.dashboardStats(shopId).totalProfit, 60);
  });

  test('calculates current stock value separately for mobile and accessories inventory', () {
    DatabaseService.instance.resetForTesting();
    final service = InventoryService();
    const shopId = 'SHOP-STOCK';

    expect(service.addMobile(shopId: shopId, name: 'iPhone 13', color: 'Blue', imei1: 'M-100', condition: 'new', buyPrice: 100000), isNull);
    expect(service.addMobile(shopId: shopId, name: 'Samsung S24', color: 'Black', imei1: 'M-200', condition: 'new', buyPrice: 150000), isNull);
    expect(service.addAccessory(shopId: shopId, name: 'Type-C Cable', buyPrice: 100, quantity: 10), isNull);
    expect(service.addAccessory(shopId: shopId, name: 'Charger', buyPrice: 250, quantity: 4), isNull);

    expect(service.totalMobileStockValue(shopId), 250000);
    expect(service.totalAccessoriesStockValue(shopId), 2000);
  });

  test('computes real category totals and counts only debt repayments as recovered', () {
    DatabaseService.instance.resetForTesting();
    final service = InventoryService();
    const shopId = 'SHOP-CATEGORY';

    expect(DatabaseService.instance.dashboardStats(shopId).categoryBreakdown.mobile, 0);
    expect(DatabaseService.instance.dashboardStats(shopId).categoryBreakdown.accessories, 0);
    expect(DatabaseService.instance.dashboardStats(shopId).categoryBreakdown.repair, 0);
    expect(DatabaseService.instance.dashboardStats(shopId).categoryBreakdown.debtRecovery, 0);

    expect(service.addMobile(shopId: shopId, name: 'Mobile 1', color: 'Black', imei1: 'A100', condition: 'new', buyPrice: 100, sellPrice: 300), isNull);
    final mobile = service.findMobileByImei(shopId, 'A100')!;
    final mobileResult = service.completeSale(
      shopId: shopId,
      cart: [CartLine.mobile(mobile)],
      customerName: 'Alice',
      customerPhone: '0101',
      customerAddress: 'Street 1',
    );
    expect(mobileResult, isNull);

    expect(service.addAccessory(shopId: shopId, name: 'Charger', buyPrice: 20, sellPrice: 60, quantity: 1), isNull);
    final accessory = service.accessories(shopId).single;
    final accessoryResult = service.completeSale(
      shopId: shopId,
      cart: [CartLine.accessory(accessory)],
      customerName: 'Bob',
      customerPhone: '0202',
      customerAddress: 'Street 2',
    );
    expect(accessoryResult, isNull);

    final db = DatabaseService.instance.database;
    final now = DateTime.now().toUtc().toIso8601String();
    db.execute('INSERT INTO debtors (shop_id, customer_name, phone, address, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)', [shopId, 'Debt Customer', '0900', 'Debt Street', now, now]);
    final debtorId = db.select('SELECT id FROM debtors WHERE shop_id = ? AND customer_name = ?', [shopId, 'Debt Customer']).first['id'] as int;
    db.execute('INSERT INTO repairs (shop_id, name, cost, charge, profit, created_at) VALUES (?, ?, ?, ?, ?, ?)', [shopId, 'Screen fix', 80, 140, 60, now]);
    db.execute('INSERT INTO debt_transactions (debtor_id, item, amount, type, created_at) VALUES (?, ?, ?, ?, ?)', [debtorId, 'Loan', 1000, 'debt', now]);
    db.execute('INSERT INTO debt_transactions (debtor_id, item, amount, type, created_at) VALUES (?, ?, ?, ?, ?)', [debtorId, 'Repayment', 300, 'payment', now]);

    final stats = DatabaseService.instance.dashboardStats(shopId);
    expect(stats.categoryBreakdown.mobile, 300);
    expect(stats.categoryBreakdown.accessories, 60);
    expect(stats.categoryBreakdown.repair, 140);
    expect(stats.categoryBreakdown.debtRecovery, 300);
  });

  test('soft deletes products without removing historical sales and supports edit stock updates', () {
    DatabaseService.instance.resetForTesting();
    AppSession.instance.update(role: 'admin', shopId: 'SHOP-DELETE', username: 'admin', userId: 1);
    final service = InventoryService();
    const shopId = 'SHOP-DELETE';

    expect(service.addMobile(shopId: shopId, name: 'Delete Phone', color: '', imei1: 'DEL-001', condition: 'new', buyPrice: 400), isNull);
    expect(service.addAccessory(shopId: shopId, name: 'Delete Cable', buyPrice: 25, quantity: 5), isNull);

    final mobile = service.findMobileByImei(shopId, 'DEL-001')!;
    final accessory = service.accessories(shopId).single;
    expect(service.completeSale(shopId: shopId, cart: [CartLine.mobile(mobile)], customerName: 'Customer', customerPhone: '0300', customerAddress: 'Street'), isNull);
    expect(service.deleteMobile(shopId: shopId, mobileId: mobile.id), isNull);
    expect(service.deleteAccessory(shopId: shopId, accessoryId: accessory.id), isNull);

    expect(service.mobileDevices(shopId), isEmpty);
    expect(service.accessories(shopId), isEmpty);
    expect(DatabaseService.instance.database.select('SELECT COUNT(*) AS count FROM sales WHERE shop_id = ?', [shopId]).first['count'], 1);

    final updatedAccessory = service.accessories(shopId, includeDeleted: true).single;
    expect(updatedAccessory.quantity, 5);
    expect(service.updateAccessory(shopId: shopId, accessoryId: accessory.id, name: 'Delete Cable', buyPrice: 40, quantity: 12, picturePath: null), isNull);
    expect(service.totalAccessoriesStockValue(shopId), 480);
  });

  test('mobile colour is optional and low stock excludes mobiles', () {
    DatabaseService.instance.resetForTesting();
    AppSession.instance.update(role: 'admin', shopId: 'SHOP-LOW', username: 'admin', userId: 1);
    final service = InventoryService();
    const shopId = 'SHOP-LOW';

    expect(service.addMobile(shopId: shopId, name: 'No Colour Phone', color: '', imei1: 'NO-COLOR-01', condition: 'new', buyPrice: 250), isNull);
    final mobile = service.findMobileByImei(shopId, 'NO-COLOR-01')!;
    expect(mobile.color, isNull);
    expect(DatabaseService.instance.dashboardStats(shopId).lowStockItems, 0);

    expect(service.addAccessory(shopId: shopId, name: 'Accessory', buyPrice: 50, quantity: 1), isNull);
    expect(DatabaseService.instance.dashboardStats(shopId).lowStockItems, 0);
  });
}
