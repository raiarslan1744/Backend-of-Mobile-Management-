import 'package:flutter_test/flutter_test.dart';
import 'package:develop/core/cloud/conflict_resolver.dart';
import 'package:develop/core/cloud/cloud_sync_models.dart';

void main() {
  group('ConflictResolver', () {
    final resolver = ConflictResolver();

    test('detects conflict when both local and remote were modified', () {
      final now = DateTime.now().toUtc();

      final localData = {
        'id': 'prod-123',
        'name': 'iPhone 15',
        'price': 1500,
        'updated_at': now.toIso8601String(),
      };

      final remoteData = {
        'id': 'prod-123',
        'name': 'iPhone 15 Pro',
        'price': 1800,
        'updated_at': now.subtract(const Duration(minutes: 30)).toIso8601String(),
      };

      final conflict = resolver.detectConflict(
        shopId: 'SHOP-001',
        entityType: 'product',
        entityId: 'prod-123',
        localData: localData,
        remoteData: remoteData,
      );

      expect(conflict, isNotNull);
      expect(conflict!.localData['price'], 1500);
      expect(conflict.remoteData['price'], 1800);
    });

    test('returns null when data is unchanged', () {
      final time = DateTime.now().toUtc();

      final data = {
        'id': 'prod-123',
        'name': 'iPhone 15',
        'price': 1500,
        'updated_at': time.toIso8601String(),
      };

      final conflict = resolver.detectConflict(
        shopId: 'SHOP-001',
        entityType: 'product',
        entityId: 'prod-123',
        localData: data,
        remoteData: data,
      );

      expect(conflict, isNull);
    });

    test('resolves conflict with server-wins strategy', () {
      final now = DateTime.now().toUtc();

      final conflict = SyncConflict(
        id: 'conflict-1',
        shopId: 'SHOP-001',
        entityType: 'product',
        entityId: 'prod-123',
        localData: {'name': 'Local Name', 'price': 1000},
        remoteData: {'name': 'Remote Name', 'price': 2000},
        localUpdatedAt: now.subtract(const Duration(hours: 1)),
        remoteUpdatedAt: now,
        detectedAt: now,
      );

      final resolved = resolver.resolveConflict(conflict);

      expect(resolved, isNotNull);
      expect(resolved!['name'], 'Remote Name');
      expect(resolved['price'], 2000);
      expect(conflict.resolution, ConflictResolutionStrategy.serverWins);
    });

    test('resolves conflict with client-wins strategy', () {
      final now = DateTime.now().toUtc();

      final conflict = SyncConflict(
        id: 'conflict-1',
        shopId: 'SHOP-001',
        entityType: 'product',
        entityId: 'prod-123',
        localData: {'name': 'Local Name', 'price': 1000},
        remoteData: {'name': 'Remote Name', 'price': 2000},
        localUpdatedAt: now,
        remoteUpdatedAt: now.subtract(const Duration(hours: 1)),
        detectedAt: now,
      );

      final resolved = resolver.resolveConflict(conflict);

      expect(resolved, isNotNull);
      expect(resolved!['name'], 'Local Name');
      expect(resolved['price'], 1000);
      expect(conflict.resolution, ConflictResolutionStrategy.clientWins);
    });

    test('attempts merge when possible', () {
      final now = DateTime.now().toUtc();

      final conflict = SyncConflict(
        id: 'conflict-1',
        shopId: 'SHOP-001',
        entityType: 'product',
        entityId: 'prod-123',
        localData: {
          'id': 'prod-123',
          'name': 'iPhone 15',
          'stock': 50,
          'local_only_field': 'value1',
          'updated_at': now.toIso8601String(),
        },
        remoteData: {
          'id': 'prod-123',
          'name': 'iPhone 15',
          'stock': 40,
          'remote_only_field': 'value2',
          'updated_at': now.toIso8601String(),
        },
        localUpdatedAt: now,
        remoteUpdatedAt: now,
        detectedAt: now,
      );

      final resolved = resolver.resolveConflict(conflict);

      expect(resolved, isNotNull);
      expect(resolved!['local_only_field'], 'value1');
      expect(resolved['remote_only_field'], 'value2');
    });

    test('handles numeric field conflicts in merge', () {
      final now = DateTime.now().toUtc();

      final conflict = SyncConflict(
        id: 'conflict-1',
        shopId: 'SHOP-001',
        entityType: 'inventory',
        entityId: 'inv-123',
        localData: {'quantity': 100, 'price': 1000},
        remoteData: {'quantity': 80, 'price': 1000},
        localUpdatedAt: now,
        remoteUpdatedAt: now,
        detectedAt: now,
      );

      final resolved = resolver.resolveConflict(conflict);

      expect(resolved, isNotNull);
      // For quantities, should use max
      expect(resolved!['quantity'], 100);
    });

    test('detects local is newer', () {
      final remoteTime = DateTime.now().toUtc().subtract(const Duration(hours: 1));
      final localTime = DateTime.now().toUtc();

      final conflict = SyncConflict(
        id: 'conflict-1',
        shopId: 'SHOP-001',
        entityType: 'product',
        entityId: 'prod-123',
        localData: {'updated_at': localTime.toIso8601String()},
        remoteData: {'updated_at': remoteTime.toIso8601String()},
        localUpdatedAt: localTime,
        remoteUpdatedAt: remoteTime,
        detectedAt: DateTime.now(),
      );

      expect(conflict.isLocalNewer, true);
    });

    test('detects remote is newer', () {
      final localTime = DateTime.now().toUtc().subtract(const Duration(hours: 1));
      final remoteTime = DateTime.now().toUtc();

      final conflict = SyncConflict(
        id: 'conflict-1',
        shopId: 'SHOP-001',
        entityType: 'product',
        entityId: 'prod-123',
        localData: {'updated_at': localTime.toIso8601String()},
        remoteData: {'updated_at': remoteTime.toIso8601String()},
        localUpdatedAt: localTime,
        remoteUpdatedAt: remoteTime,
        detectedAt: DateTime.now(),
      );

      expect(conflict.isLocalNewer, false);
    });
  });
}
