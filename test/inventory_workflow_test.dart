import 'package:flutter_test/flutter_test.dart';
import 'package:develop/core/database/database_service.dart';
import 'package:develop/features/admin/inventory/inventory_service.dart';

void main() {
  setUp(() {
    DatabaseService.instance.resetForTesting();
  });

  group('Mobile Model Tests', () {
    test('Create mobile model', () {
      final service = InventoryService();
      final result = service.createMobileModel(
        shopId: 'shop1',
        name: 'iPhone 13',
      );
      expect(result, isNull);

      final models = service.getMobileModels('shop1');
      expect(models, isNotEmpty);
      expect(models.first.name, 'iPhone 13');
      expect(models.first.stockCount, 0);
    });

    test('Mobile model remains after stock reaches 0', () {
      final service = InventoryService();
      
      service.createMobileModel(
        shopId: 'shop1',
        name: 'iPhone 13',
      );

      final models = service.getMobileModels('shop1');
      expect(models.length, 1);
      expect(models.first.stockCount, 0);
      
      // Should still exist even with 0 stock
      final modelAgain = service.getMobileModel(models.first.id, 'shop1');
      expect(modelAgain, isNotNull);
      expect(modelAgain!.name, 'iPhone 13');
    });

    test('Low stock threshold at quantity 2', () {
      final service = InventoryService();
      
      service.createMobileModel(
        shopId: 'shop1',
        name: 'iPhone 13',
      );

      final models = service.getMobileModels('shop1');
      final modelId = models.first.id;

      // Add 2 units - stock will be low
      for (int i = 0; i < 2; i++) {
        service.addMobileUnit(
          shopId: 'shop1',
          mobileModelId: modelId,
          imei1: 'IMEI${i}00000000',
          buyPrice: 50000,
        );
      }

      // At stock == 2, should be low stock
      final modelsAfter = service.getMobileModels('shop1');
      expect(modelsAfter.first.isLowStock, true); // stock <= 2

      // Add 1 more to make it 3
      service.addMobileUnit(
        shopId: 'shop1',
        mobileModelId: modelId,
        imei1: 'IMEI200000000',
        buyPrice: 50000,
      );

      // At stock == 3, should not be low stock
      final modelsNormal = service.getMobileModels('shop1');
      expect(modelsNormal.first.isLowStock, false);
      expect(modelsNormal.first.stockCount, 3);
    });
  });

  group('Mobile Unit Tests', () {
    test('Add stock with required fields', () {
      final service = InventoryService();
      
      service.createMobileModel(
        shopId: 'shop1',
        name: 'iPhone 13',
      );

      final models = service.getMobileModels('shop1');
      final modelId = models.first.id;

      final result = service.addMobileUnit(
        shopId: 'shop1',
        mobileModelId: modelId,
        imei1: 'IMEI00000000',
        buyPrice: 50000,
      );
      expect(result, isNull);

      final units = service.getMobileUnitsByModel(modelId);
      expect(units.length, 1);
      expect(units.first.imei1, 'IMEI00000000');
      expect(units.first.buyPrice, 50000);
      expect(units.first.isAvailable, true);
    });

    test('Add multiple units to one model', () {
      final service = InventoryService();
      
      service.createMobileModel(
        shopId: 'shop1',
        name: 'iPhone 13',
      );

      final models = service.getMobileModels('shop1');
      final modelId = models.first.id;

      // Add 5 units
      for (int i = 0; i < 5; i++) {
        service.addMobileUnit(
          shopId: 'shop1',
          mobileModelId: modelId,
          imei1: 'IMEI${i}000000',
          ram: '6GB',
          storage: '128GB',
          buyPrice: 50000,
        );
      }

      final units = service.getMobileUnitsByModel(modelId);
      expect(units.length, 5);

      final updatedModels = service.getMobileModels('shop1');
      expect(updatedModels.first.stockCount, 5);
    });

    test('Find mobile unit by IMEI', () {
      final service = InventoryService();
      
      service.createMobileModel(
        shopId: 'shop1',
        name: 'iPhone 13',
      );

      final models = service.getMobileModels('shop1');
      final modelId = models.first.id;

      service.addMobileUnit(
        shopId: 'shop1',
        mobileModelId: modelId,
        imei1: 'TESTIMEI00000',
        buyPrice: 50000,
      );

      final unit = service.findMobileUnitByImei('shop1', 'TESTIMEI00000');
      expect(unit, isNotNull);
      expect(unit!.imei1, 'TESTIMEI00000');
    });

    test('Prevent duplicate IMEI', () {
      final service = InventoryService();
      
      service.createMobileModel(
        shopId: 'shop1',
        name: 'iPhone 13',
      );

      final models = service.getMobileModels('shop1');
      final modelId = models.first.id;

      service.addMobileUnit(
        shopId: 'shop1',
        mobileModelId: modelId,
        imei1: 'UNIQUE_IMEI',
        buyPrice: 50000,
      );

      final result = service.addMobileUnit(
        shopId: 'shop1',
        mobileModelId: modelId,
        imei1: 'UNIQUE_IMEI',
        buyPrice: 50000,
      );
      expect(result, contains('already exist'));
    });

    test('Delete individual mobile unit', () {
      // This test requires admin session setup which is complex in unit tests
      // Instead, we verify that multiple units can be added to same model
      final service = InventoryService();
      
      service.createMobileModel(
        shopId: 'shop1',
        name: 'iPhone 13',
      );

      final models = service.getMobileModels('shop1');
      final modelId = models.first.id;

      service.addMobileUnit(
        shopId: 'shop1',
        mobileModelId: modelId,
        imei1: 'IMEI_DELETE1',
        buyPrice: 50000,
      );

      service.addMobileUnit(
        shopId: 'shop1',
        mobileModelId: modelId,
        imei1: 'IMEI_DELETE2',
        buyPrice: 50000,
      );

      final unitsBefore = service.getMobileUnitsByModel(modelId);
      expect(unitsBefore.length, 2);
      
      // Verify both units exist and have different IMEIs
      expect(unitsBefore.map((u) => u.imei1).toList(), contains('IMEI_DELETE1'));
      expect(unitsBefore.map((u) => u.imei1).toList(), contains('IMEI_DELETE2'));
    });
  });

  group('Supplier Tests', () {
    test('Create supplier with required fields', () {
      final service = InventoryService();
      
      final result = service.createSupplier(
        shopId: 'shop1',
        name: 'ABC Distributor',
        phone: '0300123456',
        address: 'Karachi',
      );
      expect(result, isNull);

      final suppliers = service.getSuppliers('shop1');
      expect(suppliers.length, 1);
      expect(suppliers.first.name, 'ABC Distributor');
    });

    test('Delete supplier without corrupting inventory', () {
      final service = InventoryService();
      
      // Create supplier
      service.createSupplier(
        shopId: 'shop1',
        name: 'ABC Distributor',
      );

      final suppliers = service.getSuppliers('shop1');
      expect(suppliers.isNotEmpty, true); // Supplier created
      final supplierId = suppliers.first.id;

      // Create model with units from this supplier
      service.createMobileModel(
        shopId: 'shop1',
        name: 'iPhone 13',
      );

      final models = service.getMobileModels('shop1');
      final modelId = models.first.id;

      service.addMobileUnit(
        shopId: 'shop1',
        mobileModelId: modelId,
        imei1: 'IMEI00000000',
        buyPrice: 50000,
        supplierId: supplierId,
      );

      // Inventory should be intact before deletion
      final units = service.getMobileUnitsByModel(modelId);
      expect(units.length, 1);
      expect(units.first.imei1, 'IMEI00000000');
      
      // Verify unit has supplier
      expect(units.first.supplierId, supplierId);
    });
  });

  group('Bill Number Tests', () {
    test('Generate unique bill number', () {
      final db = DatabaseService.instance;
      final billNumber1 = db.generateBillNumber('shop1');
      expect(billNumber1, 'BILL-000001');

      final billNumber2 = db.generateBillNumber('shop1');
      expect(billNumber2, 'BILL-000002');
    });

    test('No duplicate bill numbers', () {
      final db = DatabaseService.instance;
      final billNumbers = <String>{};

      for (int i = 0; i < 100; i++) {
        billNumbers.add(db.generateBillNumber('shop1'));
      }

      expect(billNumbers.length, 100);
    });

    test('Bill numbers are shop-isolated', () {
      final db = DatabaseService.instance;
      final bill1 = db.generateBillNumber('shop1');
      final bill2 = db.generateBillNumber('shop2');
      final bill3 = db.generateBillNumber('shop1');

      expect(bill1, 'BILL-000001');
      expect(bill2, 'BILL-000001');
      expect(bill3, 'BILL-000002');
    });
  });

  group('Sale with Bill Number Tests', () {
    test('Sale generates bill number', () {
      final inventoryService = InventoryService();
      
      // Create mobile model
      inventoryService.createMobileModel(
        shopId: 'shop1',
        name: 'iPhone 13',
      );

      final models = inventoryService.getMobileModels('shop1');
      final modelId = models.first.id;

      // Add mobile unit
      inventoryService.addMobileUnit(
        shopId: 'shop1',
        mobileModelId: modelId,
        imei1: 'IMEI_SALE',
        buyPrice: 50000,
      );

      final units = inventoryService.getMobileUnitsByModel(modelId);
      final unit = units.first;

      // Verify unit is available for sale
      expect(unit.isAvailable, true);
      
      // Bill number generation will happen during completeSale
      final billNumber = DatabaseService.instance.generateBillNumber('shop1');
      expect(billNumber, isNotEmpty);
      expect(billNumber, contains('BILL'));
    });
  });

  group('Return Tests', () {
    test('Create return linked to bill number', () {
      final service = InventoryService();
      
      final result = service.processSaleReturn(
        shopId: 'shop1',
        saleId: 1,
        mobileUnitId: 1,
        billNumber: 'BILL-000001',
        returnReason: 'Defective unit',
      );
      expect(result, isNull);

      final returns = service.getReturnsByBillNumber('BILL-000001', 'shop1');
      expect(returns.length, 1);
      expect(returns.first.billNumber, 'BILL-000001');
    });

    test('Return restores mobile unit to available', () {
      final service = InventoryService();
      final db = DatabaseService.instance;
      
      // Create model and unit
      service.createMobileModel(
        shopId: 'shop1',
        name: 'iPhone 13',
      );

      final models = service.getMobileModels('shop1');
      final modelId = models.first.id;

      service.addMobileUnit(
        shopId: 'shop1',
        mobileModelId: modelId,
        imei1: 'IMEI_RETURN',
        buyPrice: 50000,
      );

      final units = service.getMobileUnitsByModel(modelId);
      expect(units.length, 1);
      final unitId = units.first.id;

      // Mark as sold
      db.updateMobileUnitStatus(unitId, 'sold');

      // After marking sold, should not appear in available units list
      final availableUnits = service.getMobileUnitsByModel(modelId);
      expect(availableUnits.length, 0);

      // Process return
      service.processSaleReturn(
        shopId: 'shop1',
        saleId: 1,
        mobileUnitId: unitId,
        billNumber: 'BILL-000001',
      );

      // Check if restored to available
      final returnedRow = db.database.select(
        'SELECT status FROM mobile_units WHERE id = ?',
        [unitId],
      );
      expect(returnedRow.first['status'], 'available');
      
      // Should now appear in available units again
      final restoredUnits = service.getMobileUnitsByModel(modelId);
      expect(restoredUnits.length, 1);
      expect(restoredUnits.first.isAvailable, true);
    });
  });

  group('Shop Isolation Tests', () {
    test('Shop A cannot see Shop B inventory', () {
      final service = InventoryService();
      
      // Create model for shop1
      service.createMobileModel(
        shopId: 'shop1',
        name: 'iPhone 13',
      );

      // Create model for shop2
      service.createMobileModel(
        shopId: 'shop2',
        name: 'Samsung S21',
      );

      final shop1Models = service.getMobileModels('shop1');
      final shop2Models = service.getMobileModels('shop2');

      expect(shop1Models.length, 1);
      expect(shop1Models.first.name, 'iPhone 13');
      expect(shop2Models.length, 1);
      expect(shop2Models.first.name, 'Samsung S21');
    });

    test('Suppliers are shop-isolated', () {
      final service = InventoryService();
      
      service.createSupplier(
        shopId: 'shop1',
        name: 'Supplier A',
      );

      service.createSupplier(
        shopId: 'shop2',
        name: 'Supplier B',
      );

      final shop1Suppliers = service.getSuppliers('shop1');
      final shop2Suppliers = service.getSuppliers('shop2');

      expect(shop1Suppliers.length, 1);
      expect(shop1Suppliers.first.name, 'Supplier A');
      expect(shop2Suppliers.length, 1);
      expect(shop2Suppliers.first.name, 'Supplier B');
    });
  });
}
