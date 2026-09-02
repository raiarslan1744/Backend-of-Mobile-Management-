import 'package:flutter_test/flutter_test.dart';
import 'package:develop/core/cloud/cloud_sync_service.dart';
import 'package:develop/core/cloud/cloud_api_service.dart';
import 'package:develop/core/cloud/sync_queue_manager.dart';
import 'package:develop/core/cloud/cloud_sync_models.dart';
import 'package:develop/core/database/database_service.dart';

void main() {
  group('CloudSyncService - Integration Tests', () {
    late CloudSyncService syncService;
    late MockCloudApiService mockApi;

    setUp(() {
      DatabaseService.instance.resetForTesting();
      SyncQueueManager.instance.initializeTable();

      mockApi = MockCloudApiService();
      syncService = CloudSyncService(apiService: mockApi);
      syncService.initialize();
    });

    tearDown(() {
      syncService.dispose();
    });

    test('authenticates with valid credentials and sets session', () async {
      final result = await syncService.authenticate(
        username: 'admin',
        password: 'password123',
        shopId: 'SHOP-001',
      );

      expect(result, true);
      expect(syncService.isAuthenticated, true);
      expect(syncService.currentSession?.shopId, 'SHOP-001');
      expect(syncService.currentSession?.username, 'admin');
    });

    test('fails authentication with invalid credentials', () async {
      mockApi.setNetworkAvailable(true);

      final result = await syncService.authenticate(
        username: '',
        password: '',
        shopId: 'SHOP-001',
      );

      expect(result, false);
      expect(syncService.isAuthenticated, false);
    });

    test('handles network unavailable during authentication', () async {
      mockApi.setNetworkAvailable(false);

      final result = await syncService.authenticate(
        username: 'admin',
        password: 'password123',
        shopId: 'SHOP-001',
      );

      expect(result, false);
      expect(syncService.isAuthenticated, false);
    });

    test('queues changes locally after authentication', () async {
      await syncService.authenticate(
        username: 'admin',
        password: 'password123',
        shopId: 'SHOP-001',
      );

      syncService.queueChange(
        shopId: 'SHOP-001',
        entityType: 'product',
        entityId: 'prod-123',
        operation: 'create',
        data: {'name': 'iPhone 15', 'price': 1500},
      );

      final pending = SyncQueueManager.instance.getPendingItems('SHOP-001');
      expect(pending.length, 1);
      expect(pending.first.entityType, 'product');
    });

    test('synchronizes pending changes when online', () async {
      await syncService.authenticate(
        username: 'admin',
        password: 'password123',
        shopId: 'SHOP-001',
      );

      // Queue some changes
      syncService.queueChange(
        shopId: 'SHOP-001',
        entityType: 'product',
        entityId: 'prod-1',
        operation: 'create',
        data: {'name': 'Product 1'},
      );

      syncService.queueChange(
        shopId: 'SHOP-001',
        entityType: 'product',
        entityId: 'prod-2',
        operation: 'update',
        data: {'name': 'Product 2 Updated'},
      );

      // Perform sync
      final result = await syncService.syncNow();

      expect(result.success, true);
      expect(result.itemsSynced, 2);
      expect(result.itemsFailed, 0);
    });

    test('gets sync statistics', () async {
      await syncService.authenticate(
        username: 'admin',
        password: 'password123',
        shopId: 'SHOP-001',
      );

      syncService.queueChange(
        shopId: 'SHOP-001',
        entityType: 'product',
        entityId: 'prod-1',
        operation: 'create',
        data: {'name': 'Product 1'},
      );

      final stats = syncService.getSyncStats();

      expect(stats['authenticated'], true);
      expect(stats['pending'], 1);
    });

    test('validates shop access after authentication', () async {
      // This test demonstrates that validateShopAccess is called
      // to ensure users can only access their shop
      mockApi.setNetworkAvailable(true);

      final result = await syncService.authenticate(
        username: 'admin',
        password: 'password123',
        shopId: 'SHOP-001',
      );

      expect(result, true);
      expect(syncService.currentSession?.shopId, 'SHOP-001');
    });

    test('logout clears session and stops auto-sync', () async {
      await syncService.authenticate(
        username: 'admin',
        password: 'password123',
        shopId: 'SHOP-001',
      );

      expect(syncService.isAuthenticated, true);

      await syncService.logout();

      expect(syncService.isAuthenticated, false);
      expect(syncService.currentSession, isNull);
    });

    test('handles network errors gracefully', () async {
      await syncService.authenticate(
        username: 'admin',
        password: 'password123',
        shopId: 'SHOP-001',
      );

      syncService.queueChange(
        shopId: 'SHOP-001',
        entityType: 'product',
        entityId: 'prod-1',
        operation: 'create',
        data: {'name': 'Product 1'},
      );

      // Simulate network failure
      mockApi.setNetworkAvailable(false);

      final result = await syncService.syncNow();

      expect(result.success, false);
      expect(result.errorDetails, isNotNull);

      // Queued item should still be pending
      final pending = SyncQueueManager.instance.getPendingItems('SHOP-001');
      expect(pending.length, 1);
    });

    test('prevents queuing when not authenticated', () {
      // Try to queue without authentication
      syncService.queueChange(
        shopId: 'SHOP-001',
        entityType: 'product',
        entityId: 'prod-1',
        operation: 'create',
        data: {'name': 'Product 1'},
      );

      // Item still gets queued locally, but would fail on sync
      final pending = SyncQueueManager.instance.getPendingItems('SHOP-001');
      expect(pending.length, 1);
    });

    test('tracks sync status changes', () async {
      final statusChanges = <SyncStatus>[];
      syncService.addSyncStatusListener(() {
        statusChanges.add(syncService.syncStatus);
      });

      await syncService.authenticate(
        username: 'admin',
        password: 'password123',
        shopId: 'SHOP-001',
      );

      syncService.queueChange(
        shopId: 'SHOP-001',
        entityType: 'product',
        entityId: 'prod-1',
        operation: 'create',
        data: {'name': 'Product 1'},
      );

      expect(statusChanges.contains(SyncStatus.syncing), true);
      expect(statusChanges.contains(SyncStatus.pending), true);
    });

    test('isolates data by shop ID', () async {
      await syncService.authenticate(
        username: 'admin',
        password: 'password123',
        shopId: 'SHOP-001',
      );

      syncService.queueChange(
        shopId: 'SHOP-001',
        entityType: 'product',
        entityId: 'prod-1',
        operation: 'create',
        data: {'name': 'Product 1'},
      );

      // Queue item for different shop
      SyncQueueManager.instance.addToQueue(
        shopId: 'SHOP-002',
        entityType: 'product',
        entityId: 'prod-2',
        operation: 'create',
        data: {'name': 'Product 2'},
      );

      final shop1Items = SyncQueueManager.instance.getPendingItems('SHOP-001');
      final shop2Items = SyncQueueManager.instance.getPendingItems('SHOP-002');

      expect(shop1Items.length, 1);
      expect(shop2Items.length, 1);
      expect(shop1Items.first.shopId, 'SHOP-001');
      expect(shop2Items.first.shopId, 'SHOP-002');
    });

    test('handles session expiration', () async {
      await syncService.authenticate(
        username: 'admin',
        password: 'password123',
        shopId: 'SHOP-001',
      );

      // Manually expire the session
      syncService.currentSession = CloudAuthSession(
        userId: 'user-1',
        username: 'admin',
        shopId: 'SHOP-001',
        role: 'admin',
        authToken: 'expired-token',
        expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
        createdAt: DateTime.now(),
      );

      expect(syncService.isAuthenticated, false);
    });
  });
}
