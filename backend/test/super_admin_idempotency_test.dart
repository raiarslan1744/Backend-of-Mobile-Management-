import 'package:test/test.dart';

import '../bin/server.dart';

void main() {
  group('super admin idempotency', () {
    test('empty database creates a new Super Admin user record', () {
      final result = resolveSuperAdminUserAction(const []);
      expect(result.shouldInsert, isTrue);
      expect(result.existingUserId, isNull);
    });

    test('existing Super Admin user reuses the stable record instead of inserting a duplicate', () {
      final result = resolveSuperAdminUserAction([
        {'id': 'user-123', 'role': 'super_admin', 'shop_id': 'SUPER_ADMIN'},
      ]);
      expect(result.shouldInsert, isFalse);
      expect(result.existingUserId, 'user-123');
    });

    test('environment credentials are authoritative', () {
      final config = resolveSuperAdminCredentials({
        'SUPER_ADMIN_USERNAME': 'render-admin',
        'SUPER_ADMIN_PASSWORD': 'new-password-123',
      });
      expect(config.username, 'render-admin');
      expect(config.password, 'new-password-123');
    });
  });
}
