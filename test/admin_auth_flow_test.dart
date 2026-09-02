import 'package:flutter_test/flutter_test.dart';
import 'package:develop/features/auth/logic/auth_service.dart';
import 'package:develop/features/auth/logic/super_admin_service.dart';

void main() {
  group('Admin login flow', () {
    test('allows active shop admin login with username, shop ID and password', () {
      final service = SuperAdminService.instance;
      service.resetForTesting();
      service.createShop(
        ownerName: 'Ali Khan',
        contact: '03001234567',
        address: 'Lahore',
        shopId: 'SHOP-001',
        username: 'shopadmin',
        password: 'shop123',
      );

      final result = AuthService().login(
        username: 'shopadmin',
        password: 'shop123',
        shopId: 'SHOP-001',
      );

      expect(result.success, isTrue);
      expect(result.role, LoginRole.admin);
    });

    test('blocks suspended shop admin login', () {
      final service = SuperAdminService.instance;
      service.resetForTesting();
      service.createShop(
        ownerName: 'Ali Khan',
        contact: '03001234567',
        address: 'Lahore',
        shopId: 'SHOP-002',
        username: 'shopadmin2',
        password: 'shop123',
      );
      service.toggleShopStatus(shopId: 'SHOP-002');

      final result = AuthService().login(
        username: 'shopadmin2',
        password: 'shop123',
        shopId: 'SHOP-002',
      );

      expect(result.success, isFalse);
      expect(result.message, 'This shop has been suspended. Please contact the Super Admin.');
    });
  });
}
