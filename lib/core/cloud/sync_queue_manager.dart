library;

/// Manages the local sync queue for storing pending changes
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../database/database_service.dart';
import 'cloud_sync_models.dart';

class SyncQueueManager {
  SyncQueueManager() : _database = DatabaseService.instance;

  static final SyncQueueManager instance = SyncQueueManager();
  DatabaseService _database;
  static const String tableName = 'sync_queue';

  void refreshDatabase() {
    _database = DatabaseService.instance;
  }

  /// Initialize sync queue table
  void initializeTable() {
    _database.database.execute('''
      CREATE TABLE IF NOT EXISTS $tableName (
        id TEXT PRIMARY KEY,
        shop_id TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        operation TEXT NOT NULL CHECK (operation IN ('create', 'update', 'delete')),
        data TEXT NOT NULL,
        created_at TEXT NOT NULL,
        synced_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending' CHECK (sync_status IN ('pending', 'syncing', 'synced', 'failed')),
        error_message TEXT,
        retry_count INTEGER NOT NULL DEFAULT 0,
        UNIQUE(shop_id, entity_type, entity_id, operation)
      )
    ''');

    // Create index for efficient querying
    try {
      _database.database.execute(
        'CREATE INDEX IF NOT EXISTS idx_sync_queue_shop_status ON $tableName(shop_id, sync_status)',
      );
    } catch (_) {}
  }

  /// Add an item to the sync queue
  SyncQueueItem addToQueue({
    required String shopId,
    required String entityType,
    required String entityId,
    required String operation,
    required Map<String, dynamic> data,
  }) {
    final stableId = _stableQueueId(shopId, entityType, entityId, operation);
    final queueItem = SyncQueueItem(
      id: stableId,
      shopId: shopId,
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      data: data,
      createdAt: DateTime.now().toUtc(),
    );

    try {
      _database.database.execute(
        '''INSERT OR REPLACE INTO $tableName 
           (id, shop_id, entity_type, entity_id, operation, data, created_at, sync_status)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          queueItem.id,
          queueItem.shopId,
          queueItem.entityType,
          queueItem.entityId,
          queueItem.operation,
          _encodeJson(queueItem.data),
          queueItem.createdAt.toIso8601String(),
          queueItem.syncStatus,
        ],
      );
    } catch (e) {
      rethrow;
    }

    return queueItem;
  }

  /// Get all pending items for a shop
  List<SyncQueueItem> getPendingItems(String shopId) {
    final rows = _database.database.select(
      '''SELECT * FROM $tableName 
         WHERE shop_id = ? AND sync_status IN ('pending', 'failed')
         ORDER BY created_at ASC''',
      [shopId],
    );
    return rows.map(_itemFromRow).toList(growable: false);
  }

  /// Get a specific sync queue item
  SyncQueueItem? getItem(String itemId) {
    final rows = _database.database.select(
      'SELECT * FROM $tableName WHERE id = ?',
      [itemId],
    );
    return rows.isEmpty ? null : _itemFromRow(rows.first);
  }

  /// Mark an item as synced
  void markAsSynced(String itemId) {
    _database.database.execute(
      '''UPDATE $tableName 
         SET sync_status = 'synced', synced_at = ?, error_message = NULL, retry_count = 0
         WHERE id = ?''',
      [DateTime.now().toUtc().toIso8601String(), itemId],
    );
  }

  /// Mark an item as failed
  void markAsFailed(String itemId, String errorMessage) {
    final item = getItem(itemId);
    if (item != null) {
      _database.database.execute(
        '''UPDATE $tableName 
           SET sync_status = 'failed', error_message = ?, retry_count = retry_count + 1
           WHERE id = ?''',
        [errorMessage, itemId],
      );
    }
  }

  /// Mark an item as syncing
  void markAsSyncing(String itemId) {
    _database.database.execute(
      'UPDATE $tableName SET sync_status = ? WHERE id = ?',
      ['syncing', itemId],
    );
  }

  /// Get count of pending items
  int getPendingCount(String shopId) {
    final result = _database.database.select(
      'SELECT COUNT(*) as count FROM $tableName WHERE shop_id = ? AND sync_status = ?',
      [shopId, 'pending'],
    );
    return result.isNotEmpty ? result.first['count'] as int : 0;
  }

  /// Clear synced items older than specified days
  void clearSyncedItems({int olderThanDays = 7}) {
    final cutoffDate = DateTime.now().toUtc().subtract(Duration(days: olderThanDays));
    _database.database.execute(
      '''DELETE FROM $tableName 
         WHERE sync_status = 'synced' AND synced_at < ?''',
      [cutoffDate.toIso8601String()],
    );
  }

  /// Get sync statistics for a shop
  Map<String, int> getSyncStats(String shopId) {
    final rows = _database.database.select(
      '''SELECT sync_status, COUNT(*) as count FROM $tableName
         WHERE shop_id = ?
         GROUP BY sync_status''',
      [shopId],
    );

    final stats = <String, int>{
      'pending': 0,
      'syncing': 0,
      'synced': 0,
      'failed': 0,
    };

    for (final row in rows) {
      final status = row['sync_status'] as String;
      final count = row['count'] as int;
      if (stats.containsKey(status)) {
        stats[status] = count;
      }
    }

    return stats;
  }

  /// Remove a specific item from queue
  void removeItem(String itemId) {
    _database.database.execute(
      'DELETE FROM $tableName WHERE id = ?',
      [itemId],
    );
  }

  /// Clear all items for a shop (use with caution)
  void clearShopQueue(String shopId) {
    _database.database.execute(
      'DELETE FROM $tableName WHERE shop_id = ?',
      [shopId],
    );
  }

  void resetForTesting() {
    refreshDatabase();
    initializeTable();
    _database.database.execute('DELETE FROM $tableName');
  }

  String _stableQueueId(String shopId, String entityType, String entityId, String operation) {
    final seed = '$shopId|$entityType|$entityId|$operation';
    return sha256.convert(utf8.encode(seed)).toString();
  }

  SyncQueueItem _itemFromRow(Map<String, Object?> row) {
    return SyncQueueItem(
      id: row['id'] as String,
      shopId: row['shop_id'] as String,
      entityType: row['entity_type'] as String,
      entityId: row['entity_id'] as String,
      operation: row['operation'] as String,
      data: _decodeJson(row['data'] as String? ?? '{}'),
      createdAt: DateTime.parse(row['created_at'] as String),
      syncedAt: row['synced_at'] != null ? DateTime.parse(row['synced_at'] as String) : null,
      syncStatus: row['sync_status'] as String? ?? 'pending',
      errorMessage: row['error_message'] as String?,
      retryCount: row['retry_count'] as int? ?? 0,
    );
  }

  String _encodeJson(Map<String, dynamic> data) {
    return jsonEncode(data);
  }

  Map<String, dynamic> _decodeJson(String json) {
    if (json.isEmpty || json == '{}') return {};
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return {};
    } catch (_) {
      return {};
    }
  }
}
