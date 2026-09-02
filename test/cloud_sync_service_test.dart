import 'package:flutter_test/flutter_test.dart';
import 'package:develop/core/cloud/cloud_api_service.dart';
import 'package:develop/core/cloud/cloud_sync_service.dart';
import 'package:develop/core/database/database_service.dart';
import 'package:develop/core/cloud/sync_queue_manager.dart';

void main() {
  group('CloudSyncService current API', () {
    late CloudSyncService service;
    late MockCloudApiService api;

    setUp(() {
      DatabaseService.instance.resetForTesting();
      SyncQueueManager.instance.initializeTable();
      api = MockCloudApiService();
      service = CloudSyncService(apiService: api);
      service.initialize();
    });

    tearDown(() {
      service.dispose();
    });

    test('authenticates valid credentials for the matching shop', () async {
      final success = await service.authenticate(
        username: 'admin',
        password: 'password123',
        shopId: 'SHOP-001',
      );

      expect(success, isTrue);
      expect(service.isAuthenticated, isTrue);
      expect(service.currentSession?.shopId, 'SHOP-001');
    });

    test('rejects invalid credentials and leaves no active session', () async {
      final success = await service.authenticate(
        username: '',
        password: '',
        shopId: 'SHOP-001',
      );

      expect(success, isFalse);
      expect(service.isAuthenticated, isFalse);
      expect(service.currentSession, isNull);
    });

    test('queues local work for a shop and syncs it when online', () async {
      final success = await service.authenticate(
        username: 'admin',
        password: 'password123',
        shopId: 'SHOP-001',
      );

      expect(success, isTrue);

      service.queueChange(
        shopId: 'SHOP-001',
        entityType: 'product',
        entityId: 'prod-1',
        operation: 'create',
        data: {'name': 'Product 1'},
      );

      final pending = SyncQueueManager.instance.getPendingItems('SHOP-001');
      expect(pending.length, 1);
      expect(pending.first.entityType, 'product');

      final result = await service.syncNow();
      expect(result.success, isTrue);
      expect(result.itemsSynced, 1);
    });
  });
}
