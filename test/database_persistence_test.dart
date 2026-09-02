import 'package:flutter_test/flutter_test.dart';
import 'package:develop/features/auth/logic/auth_service.dart';
import 'package:develop/features/auth/logic/super_admin_service.dart';

void main() {
  test('keeps credentials, shops, and status across fresh service instances', () {
    final service = SuperAdminService.instance;
    service.resetForTesting();

    final createResult = service.createShop(
      ownerName: 'Ali Khan',
      contact: '03001234567',
      address: 'Lahore',
      shopId: 'PERSIST-001',
      username: 'shopadmin',
      password: 'shop123',
    );
    expect(createResult.success, isTrue);

    final freshService = SuperAdminService();
    expect(freshService.shops.map((shop) => shop.shopId), contains('PERSIST-001'));

    final credentialResult = freshService.updateSuperAdminCredentials(
      currentUsername: 'admin',
      currentPassword: 'admin123',
      newUsername: 'savedadmin',
      newPassword: 'savedpass',
      confirmNewPassword: 'savedpass',
    );
    expect(credentialResult.success, isTrue);
    expect(
      AuthService().login(username: 'savedadmin', password: 'savedpass', shopId: '').role,
      LoginRole.superAdmin,
    );

    freshService.toggleShopStatus(shopId: 'PERSIST-001');
    expect(
      AuthService().login(username: 'shopadmin', password: 'shop123', shopId: 'PERSIST-001').message,
      'This shop has been suspended. Please contact the Super Admin.',
    );

    freshService.toggleShopStatus(shopId: 'PERSIST-001');
    expect(
      AuthService().login(username: 'shopadmin', password: 'shop123', shopId: 'PERSIST-001').success,
      isTrue,
    );
  });
}