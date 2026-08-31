import 'package:test/test.dart';

import '../bin/server.dart';

void main() {
  group('super admin config', () {
    test('reads the current production environment values and rejects empty credentials', () {
      final config = resolveSuperAdminCredentials({
        'SUPER_ADMIN_USERNAME': 'render-admin',
        'SUPER_ADMIN_PASSWORD': 'very-secret-render-password',
      });

      expect(config.username, 'render-admin');
      expect(config.password, 'very-secret-render-password');

      expect(
        () => resolveSuperAdminCredentials({
          'SUPER_ADMIN_USERNAME': '',
          'SUPER_ADMIN_PASSWORD': 'very-secret-render-password',
        }),
        throwsA(isA<StateError>()),
      );

      expect(
        () => resolveSuperAdminCredentials({
          'SUPER_ADMIN_USERNAME': 'render-admin',
          'SUPER_ADMIN_PASSWORD': '',
        }),
        throwsA(isA<StateError>()),
      );
    });

    test('shop cleanup targets all shop-specific records and credentials', () {
      final tables = getShopCleanupTableOrder();

      expect(tables, containsAll([
        'sync_records',
        'products',
        'sales',
        'customers',
        'employees',
        'repairs',
        'debtors',
        'debt_transactions',
        'accessories',
        'mobile_devices',
        'purchases',
        'devices',
        'sessions',
        'users',
        'shops',
      ]));
    });
  });
}
