import 'package:flutter_test/flutter_test.dart';
import 'package:develop/core/cloud/sync_queue_manager.dart';
import 'package:develop/core/database/database_service.dart';

void main() {
  group('SyncQueueManager', () {
    setUp(() {
      DatabaseService.instance.resetForTesting();
      SyncQueueManager.instance.initializeTable();
    });

    test('adds item to queue successfully', () {
      final item = SyncQueueManager.instance.addToQueue(
        shopId: 'SHOP-001',
        entityType: 'product',
        entityId: 'prod-123',
        operation: 'create',
        data: {'name': 'iPhone 15', 'price': 1200},
      );

      expect(item.shopId, 'SHOP-001');
      expect(item.entityType, 'product');
      expect(item.operation, 'create');
      expect(item.data['name'], 'iPhone 15');
    });

    test('retrieves pending items for a shop', () {
      SyncQueueManager.instance.addToQueue(
        shopId: 'SHOP-001',
        entityType: 'product',
        entityId: 'prod-1',
        operation: 'create',
        data: {'name': 'Product 1'},
      );

      SyncQueueManager.instance.addToQueue(
        shopId: 'SHOP-001',
        entityType: 'product',
        entityId: 'prod-2',
        operation: 'update',
        data: {'name': 'Product 2'},
      );

      SyncQueueManager.instance.addToQueue(
        shopId: 'SHOP-002',
        entityType: 'product',
        entityId: 'prod-3',
        operation: 'create',
        data: {'name': 'Product 3'},
      );

      final pending = SyncQueueManager.instance.getPendingItems('SHOP-001');

      expect(pending.length, 2);
      expect(pending.every((item) => item.shopId == 'SHOP-001'), true);
      expect(pending.every((item) => item.syncStatus == 'pending'), true);
    });

    test('marks item as synced', () {
      final item = SyncQueueManager.instance.addToQueue(
        shopId: 'SHOP-001',
        entityType: 'product',
        entityId: 'prod-123',
        operation: 'create',
        data: {'name': 'iPhone 15'},
      );

      SyncQueueManager.instance.markAsSynced(item.id);

      final synced = SyncQueueManager.instance.getItem(item.id);
      expect(synced?.syncStatus, 'synced');
      expect(synced?.syncedAt, isNotNull);
    });

    test('marks item as failed with error message', () {
      final item = SyncQueueManager.instance.addToQueue(
        shopId: 'SHOP-001',
        entityType: 'product',
        entityId: 'prod-123',
        operation: 'create',
        data: {'name': 'iPhone 15'},
      );

      const errorMsg = 'Network timeout';
      SyncQueueManager.instance.markAsFailed(item.id, errorMsg);

      final failed = SyncQueueManager.instance.getItem(item.id);
      expect(failed?.syncStatus, 'failed');
      expect(failed?.errorMessage, errorMsg);
      expect(failed?.retryCount, 1);
    });

    test('gets pending count for shop', () {
      SyncQueueManager.instance.addToQueue(
        shopId: 'SHOP-001',
        entityType: 'product',
        entityId: 'prod-1',
        operation: 'create',
        data: {},
      );

      SyncQueueManager.instance.addToQueue(
        shopId: 'SHOP-001',
        entityType: 'product',
        entityId: 'prod-2',
        operation: 'update',
        data: {},
      );

      final count = SyncQueueManager.instance.getPendingCount('SHOP-001');
      expect(count, 2);
    });

    test('gets sync statistics for shop', () {
      final item1 = SyncQueueManager.instance.addToQueue(
        shopId: 'SHOP-001',
        entityType: 'product',
        entityId: 'prod-1',
        operation: 'create',
        data: {},
      );

      final item2 = SyncQueueManager.instance.addToQueue(
        shopId: 'SHOP-001',
        entityType: 'product',
        entityId: 'prod-2',
        operation: 'update',
        data: {},
      );

      SyncQueueManager.instance.markAsSynced(item1.id);
      SyncQueueManager.instance.markAsFailed(item2.id, 'Error');

      final stats = SyncQueueManager.instance.getSyncStats('SHOP-001');

      expect(stats['pending'], 0);
      expect(stats['synced'], 1);
      expect(stats['failed'], 1);
    });

    test('removes item from queue', () {
      final item = SyncQueueManager.instance.addToQueue(
        shopId: 'SHOP-001',
        entityType: 'product',
        entityId: 'prod-123',
        operation: 'create',
        data: {},
      );

      SyncQueueManager.instance.removeItem(item.id);

      final removed = SyncQueueManager.instance.getItem(item.id);
      expect(removed, isNull);
    });

    test('clears shop queue', () {
      SyncQueueManager.instance.addToQueue(
        shopId: 'SHOP-001',
        entityType: 'product',
        entityId: 'prod-1',
        operation: 'create',
        data: {},
      );

      SyncQueueManager.instance.addToQueue(
        shopId: 'SHOP-001',
        entityType: 'product',
        entityId: 'prod-2',
        operation: 'create',
        data: {},
      );

      SyncQueueManager.instance.clearShopQueue('SHOP-001');

      final pending = SyncQueueManager.instance.getPendingItems('SHOP-001');
      expect(pending.isEmpty, true);
    });

    test('prevents duplicate entity updates in same operation', () {
      final item1 = SyncQueueManager.instance.addToQueue(
        shopId: 'SHOP-001',
        entityType: 'product',
        entityId: 'prod-123',
        operation: 'update',
        data: {'price': 1000},
      );

      final item2 = SyncQueueManager.instance.addToQueue(
        shopId: 'SHOP-001',
        entityType: 'product',
        entityId: 'prod-123',
        operation: 'update',
        data: {'price': 1200},
      );

      // Second add should replace the first due to UNIQUE constraint
      expect(item1.id, item2.id);

      final pending = SyncQueueManager.instance.getPendingItems('SHOP-001');
      expect(pending.length, 1);
      expect(pending.first.data['price'], 1200);
    });
  });
}
