import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:develop/core/cloud/cloud_api_service.dart';
import 'package:develop/core/cloud/cloud_sync_models.dart';
import 'package:develop/core/cloud/cloud_sync_service.dart';
import 'package:develop/core/database/database_service.dart';
import 'package:develop/features/admin/employees/employees_service.dart';
import 'package:develop/features/auth/logic/auth_service.dart';
import 'package:develop/features/auth/logic/super_admin_service.dart';

class _FakeCloudApiService implements CloudApiService {
  _FakeCloudApiService({
    this.isOnline = true,
    this.sessionForLogin,
    this.rejectLogin = false,
    this.deleteShopResult = true,
  });

  bool isOnline;
  CloudAuthSession? sessionForLogin;
  bool rejectLogin;
  bool deleteShopResult;

  @override
  Future<CloudAuthSession?> authenticate({
    required String username,
    required String password,
    required String shopId,
  }) async {
    if (rejectLogin) return null;
    return sessionForLogin;
  }

  @override
  Future<void> logout(String authToken) async {}

  @override
  Future<bool> isNetworkAvailable() async => isOnline;

  @override
  Future<bool> uploadSyncItem(SyncQueueItem item, String authToken) async =>
      true;

  @override
  Future<List<Map<String, dynamic>>> downloadChanges({
    required String shopId,
    required String authToken,
    required DateTime sinceTime,
  }) async => const <Map<String, dynamic>>[];

  @override
  Future<Map<String, List<Map<String, dynamic>>>> getInitialSync({
    required String shopId,
    required String authToken,
  }) async => const <String, List<Map<String, dynamic>>>{};

  @override
  Future<bool> validateShopAccess({
    required String shopId,
    required String authToken,
  }) async => true;

  @override
  Future<List<Map<String, dynamic>>> listShops(String authToken) async =>
      const <Map<String, dynamic>>[];

  @override
  Future<bool> createShop({
    required String authToken,
    required Map<String, dynamic> shop,
  }) async => true;

  @override
  Future<bool> deleteShop({
    required String authToken,
    required String shopId,
  }) async => deleteShopResult;

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

void main() {
  setUp(() {
    DatabaseService.instance.resetForTesting();
    CloudSyncService.configure(
      apiService: _FakeCloudApiService(isOnline: false),
    );
  });

  group('AuthService', () {
    test('accepts super admin credentials with empty shop ID', () {
      final result = AuthService().login(
        username: 'admin',
        password: 'admin123',
        shopId: '',
      );

      expect(result.success, isTrue);
      expect(result.role, LoginRole.superAdmin);
      expect(result.message, 'Super admin login successful');
    });

    test('accepts active employee credentials for the correct shop', () {
      SuperAdminService.instance.createShop(
        ownerName: 'Owner',
        contact: '123',
        address: 'Address',
        shopId: 'AK123',
        username: 'shopadmin',
        password: 'shop123',
      );
      EmployeeManagementService.instance.createEmployee(
        shopId: 'AK123',
        username: 'employee1',
        password: 'emp123',
      );

      final result = AuthService().login(
        username: 'employee1',
        password: 'emp123',
        shopId: 'AK123',
      );

      expect(
        result.success,
        isTrue,
        reason: 'employee auth should succeed for matching shop',
      );
      expect(result.role, LoginRole.employee);
      expect(result.shopId, 'AK123');
    });

    test(
      'rejects employee login when shop ID does not match the employee record',
      () {
        SuperAdminService.instance.createShop(
          ownerName: 'Owner',
          contact: '123',
          address: 'Address',
          shopId: 'AK123',
          username: 'shopadmin',
          password: 'shop123',
        );
        EmployeeManagementService.instance.createEmployee(
          shopId: 'AK123',
          username: 'employee1',
          password: 'emp123',
        );

        final result = AuthService().login(
          username: 'employee1',
          password: 'emp123',
          shopId: 'ZZ999',
        );

        expect(result.success, isFalse);
        expect(result.role, isNull);
        expect(result.message, 'Invalid username, password, or Shop ID.');
      },
    );

    test('rejects invalid username or password', () {
      final result = AuthService().login(
        username: 'admin',
        password: 'wrongpass',
        shopId: '',
      );

      expect(result.success, isFalse);
      expect(result.message, 'Invalid username, password, or Shop ID.');
    });

    test('first login requires internet and local offline credentials are not implicitly trusted', () async {
      final result = await AuthService().loginAsync(
        username: 'shopadmin',
        password: 'shop123',
        shopId: 'AK123',
      );

      expect(result.success, isFalse);
      expect(result.role, isNull);
    });

    test(
      'successful online login creates a local offline credential for the shop',
      () async {
        CloudSyncService.configure(
          apiService: _FakeCloudApiService(
            isOnline: true,
            sessionForLogin: CloudAuthSession(
              userId: '42',
              username: 'shopadmin',
              shopId: 'AK123',
              role: 'admin',
              authToken: 'token-123',
              expiresAt: DateTime.now().add(const Duration(hours: 1)),
              createdAt: DateTime.now(),
            ),
          ),
        );

        final result = await AuthService().loginAsync(
          username: 'shopadmin',
          password: 'shop123',
          shopId: 'AK123',
        );

        expect(result.success, isTrue);
        expect(
          SuperAdminService.instance.findShopByCredentials(
            username: 'shopadmin',
            password: 'shop123',
            shopId: 'AK123',
          ),
          isNotNull,
        );
      },
    );

    test(
      'correct offline username and shop ID with the stored password logs in',
      () async {
        SuperAdminService.instance.upsertShopCredential(
          shopId: 'AK123',
          username: 'shopadmin',
          password: 'shop123',
        );
        CloudSyncService.configure(
          apiService: _FakeCloudApiService(isOnline: false),
        );

        final result = await AuthService().loginAsync(
          username: 'shopadmin',
          password: 'shop123',
          shopId: 'AK123',
        );

        expect(result.success, isTrue);
        expect(result.role, LoginRole.admin);
      },
    );

    test('wrong offline password fails without automatic login', () async {
      SuperAdminService.instance.upsertShopCredential(
        shopId: 'AK123',
        username: 'shopadmin',
        password: 'shop123',
      );
      CloudSyncService.configure(
        apiService: _FakeCloudApiService(isOnline: false),
      );

      final result = await AuthService().loginAsync(
        username: 'shopadmin',
        password: 'wrongpass',
        shopId: 'AK123',
      );

      expect(result.success, isFalse);
      expect(result.role, isNull);
    });

    test(
      'online server rejection does not fall back to stale SQLite credentials',
      () async {
        SuperAdminService.instance.upsertShopCredential(
          shopId: 'AK123',
          username: 'shopadmin',
          password: 'oldpass',
        );
        CloudSyncService.configure(
          apiService: _FakeCloudApiService(isOnline: true, rejectLogin: true),
        );

        final result = await AuthService().loginAsync(
          username: 'shopadmin',
          password: 'oldpass',
          shopId: 'AK123',
        );

        expect(result.success, isFalse);
        expect(
          SuperAdminService.instance.findShopByCredentials(
            username: 'shopadmin',
            password: 'oldpass',
            shopId: 'AK123',
          ),
          isNull,
        );
      },
    );

    test('cloud password change invalidates old offline credentials after reconnect', () async {
      SuperAdminService.instance.upsertShopCredential(
        shopId: 'AK123',
        username: 'shopadmin',
        password: 'oldpass',
      );
      CloudSyncService.configure(
        apiService: _FakeCloudApiService(
          isOnline: true,
          sessionForLogin: CloudAuthSession(
            userId: '42',
            username: 'shopadmin',
            shopId: 'AK123',
            role: 'admin',
            authToken: 'token-456',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
            createdAt: DateTime.now(),
          ),
        ),
      );

      final result = await AuthService().loginAsync(
        username: 'shopadmin',
        password: 'newpass',
        shopId: 'AK123',
      );

      expect(result.success, isTrue);
      expect(
        SuperAdminService.instance.findShopByCredentials(
          username: 'shopadmin',
          password: 'oldpass',
          shopId: 'AK123',
        ),
        isNull,
      );
      expect(
        SuperAdminService.instance.findShopByCredentials(
          username: 'shopadmin',
          password: 'newpass',
          shopId: 'AK123',
        ),
        isNotNull,
      );
    });

    test('credentials remain isolated between shops', () {
      SuperAdminService.instance.upsertShopCredential(
        shopId: 'AK123',
        username: 'shopadmin',
        password: 'shop123',
      );
      SuperAdminService.instance.upsertShopCredential(
        shopId: 'JB456',
        username: 'shopadmin',
        password: 'shop456',
      );

      expect(
        SuperAdminService.instance.findShopByCredentials(
          username: 'shopadmin',
          password: 'shop123',
          shopId: 'AK123',
        ),
        isNotNull,
      );
      expect(
        SuperAdminService.instance.findShopByCredentials(
          username: 'shopadmin',
          password: 'shop123',
          shopId: 'JB456',
        ),
        isNull,
      );
      expect(
        SuperAdminService.instance.findShopByCredentials(
          username: 'shopadmin',
          password: 'shop456',
          shopId: 'AK123',
        ),
        isNull,
      );
    });

    test('plaintext passwords are never stored in local SQLite', () {
      SuperAdminService.instance.upsertShopCredential(
        shopId: 'AK123',
        username: 'shopadmin',
        password: 'shop123',
      );

      final row = DatabaseService.instance.database.select(
        'SELECT password_hash FROM shops WHERE shop_id = ?',
        ['AK123'],
      ).first;

      expect(row['password_hash'], isNot('shop123'));
      expect(
        row['password_hash'],
        equals(DatabaseService.hashPassword('shop123')),
      );
    });

    test(
      'local password hashing matches the backend UTF-8 SHA-256 contract',
      () {
        final expected = sha256.convert(utf8.encode('admin123')).toString();

        expect(DatabaseService.hashPassword('admin123'), equals(expected));
      },
    );

    test('cloud deletion failure preserves local shop data', () async {
      SuperAdminService.instance.createShop(
        ownerName: 'Owner',
        contact: '123',
        address: 'Address',
        shopId: 'DELETE-001',
        username: 'shopadmin',
        password: 'shop123',
      );
      CloudSyncService.configure(
        apiService: _FakeCloudApiService(deleteShopResult: false),
      );
      CloudSyncService.instance.currentSession = CloudAuthSession(
        userId: 'super-user',
        username: 'admin',
        shopId: 'SUPER_ADMIN',
        role: 'super_admin',
        authToken: 'token',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        createdAt: DateTime.now(),
      );

      final result = await SuperAdminService.instance.deleteShop(
        shopId: 'DELETE-001',
      );

      expect(result.success, isFalse);
      expect(SuperAdminService.instance.shopExists('DELETE-001'), isTrue);
    });

    test('deleteShop refuses when super admin session is missing', () async {
      SuperAdminService.instance.createShop(
        ownerName: 'Owner',
        contact: '123',
        address: 'Address',
        shopId: 'DELETE-SESSION',
        username: 'shopadmin',
        password: 'shop123',
      );
      CloudSyncService.instance.currentSession = null;

      final result = await SuperAdminService.instance.deleteShop(
        shopId: 'DELETE-SESSION',
      );

      expect(result.success, isFalse);
      expect(result.message, 'You are not authorized to delete this shop.');
      expect(SuperAdminService.instance.shopExists('DELETE-SESSION'), isTrue);
    });

    test('successful cloud deletion removes local shop data', () async {
      SuperAdminService.instance.createShop(
        ownerName: 'Owner',
        contact: '123',
        address: 'Address',
        shopId: 'DELETE-002',
        username: 'shopadmin',
        password: 'shop123',
      );
      final now = DateTime.now().toIso8601String();
      DatabaseService.instance.database.execute(
        'INSERT INTO products (shop_id, name, quantity, reorder_level, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
        ['DELETE-002', 'Old Product', 1, 0, now, now],
      );
      CloudSyncService.configure(apiService: _FakeCloudApiService());
      CloudSyncService.instance.currentSession = CloudAuthSession(
        userId: 'super-user',
        username: 'admin',
        shopId: 'SUPER_ADMIN',
        role: 'super_admin',
        authToken: 'token',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        createdAt: DateTime.now(),
      );

      final result = await SuperAdminService.instance.deleteShop(
        shopId: 'DELETE-002',
      );

      expect(result.success, isTrue);
      expect(SuperAdminService.instance.shopExists('DELETE-002'), isFalse);
      expect(
        DatabaseService.instance.database.select(
          'SELECT id FROM products WHERE shop_id = ?',
          ['DELETE-002'],
        ),
        isEmpty,
      );
    });
  });
}
