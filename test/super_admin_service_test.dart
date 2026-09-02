import 'package:flutter_test/flutter_test.dart';
import 'package:develop/core/cloud/cloud_api_service.dart';
import 'package:develop/core/cloud/cloud_sync_models.dart';
import 'package:develop/core/cloud/cloud_sync_service.dart';
import 'package:develop/features/auth/logic/auth_service.dart';
import 'package:develop/features/auth/logic/super_admin_service.dart';

void main() {
  group('SuperAdminService', () {
    test('creates an active shop with a unique shop ID', () {
      final service = SuperAdminService();
      service.resetForTesting();

      final result = service.createShop(
        ownerName: 'Ali Khan',
        contact: '03001234567',
        address: 'Lahore Main Market',
        shopId: 'SHOP-001',
        username: 'shopadmin1',
        password: 'shoppass123',
      );

      expect(result.success, isTrue);
      expect(service.shops.length, 1);
      expect(service.shops.first.status, ShopStatus.active);
    });

    test('prevents duplicate shop IDs', () {
      final service = SuperAdminService();
      service.resetForTesting();

      service.createShop(
        ownerName: 'Ali Khan',
        contact: '03001234567',
        address: 'Lahore Main Market',
        shopId: 'SHOP-001',
        username: 'shopadmin1',
        password: 'shoppass123',
      );

      final result = service.createShop(
        ownerName: 'Zain Ahmed',
        contact: '03009876543',
        address: 'Karachi Clifton',
        shopId: 'SHOP-001',
        username: 'shopadmin2',
        password: 'shoppass123',
      );

      expect(result.success, isFalse);
      expect(result.message, 'Shop ID already exists');
      expect(service.shops.length, 1);
    });

    test('updates super admin credentials only when current credentials match', () {
      final service = SuperAdminService();
      service.resetForTesting();

      final result = service.updateSuperAdminCredentials(
        currentUsername: 'admin',
        currentPassword: 'admin123',
        newUsername: 'superadmin',
        newPassword: 'newpass123',
        confirmNewPassword: 'newpass123',
      );

      expect(result.success, isTrue);
      expect(service.superAdminUsername, 'superadmin');
      final loginResult = AuthService().login(
        username: 'superadmin',
        password: 'newpass123',
        shopId: '',
      );
      expect(loginResult.success, isTrue);
      expect(loginResult.role, LoginRole.superAdmin);
    });

    test('removes stale local shops that are no longer present in cloud', () async {
      final service = SuperAdminService();
      service.resetForTesting();

      service.createShop(
        ownerName: 'Old Owner',
        contact: '111',
        address: 'Old Address',
        shopId: 'SHOP-OLD',
        username: 'old-admin',
        password: 'old-pass',
      );
      service.createShop(
        ownerName: 'Current Owner',
        contact: '222',
        address: 'Current Address',
        shopId: 'SHOP-CURRENT',
        username: 'current-admin',
        password: 'current-pass',
      );

      final fakeApi = _FakeCloudApiService(
        shops: [
          {
            'shopId': 'SHOP-CURRENT',
            'ownerName': 'Current Owner',
            'contact': '222',
            'address': 'Current Address',
            'username': 'current-admin',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
            'updatedAt': DateTime.now().toUtc().toIso8601String(),
          },
        ],
      );
      CloudSyncService.configure(apiService: fakeApi);
      CloudSyncService.instance.currentSession = CloudAuthSession(
        userId: 'super-admin',
        username: 'admin',
        shopId: 'SUPER_ADMIN',
        role: 'super_admin',
        authToken: 'token-123',
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        createdAt: DateTime.now().toUtc(),
      );

      final refreshed = await service.refreshShopsFromCloud();

      expect(refreshed, 1);
      expect(service.shopExists('SHOP-CURRENT'), isTrue);
      expect(service.shopExists('SHOP-OLD'), isFalse);
    });
  });
}

class _FakeCloudApiService implements CloudApiService {
  _FakeCloudApiService({required this.shops});

  final List<Map<String, dynamic>> shops;

  @override
  Future<CloudAuthSession?> authenticate({
    required String username,
    required String password,
    required String shopId,
  }) async => null;

  @override
  Future<void> logout(String authToken) async {}

  @override
  Future<bool> isNetworkAvailable() async => true;

  @override
  Future<bool> uploadSyncItem(SyncQueueItem item, String authToken) async => true;

  @override
  Future<List<Map<String, dynamic>>> downloadChanges({
    required String shopId,
    required String authToken,
    required DateTime sinceTime,
  }) async => const [];

  @override
  Future<Map<String, List<Map<String, dynamic>>>> getInitialSync({
    required String shopId,
    required String authToken,
  }) async => const {};

  @override
  Future<bool> validateShopAccess({
    required String shopId,
    required String authToken,
  }) async => true;

  @override
  Future<List<Map<String, dynamic>>> listShops(String authToken) async => shops;

  @override
  Future<bool> createShop({
    required String authToken,
    required Map<String, dynamic> shop,
  }) async => true;

  @override
  Future<bool> deleteShop({
    required String authToken,
    required String shopId,
  }) async => true;

  @override
  Future<bool> registerDevice({
    required String shopId,
    required String userId,
    required String authToken,
    required DeviceRegistration device,
  }) async => true;

  @override
  Future<void> reportConflict(SyncConflict conflict, String authToken) async {}
}
