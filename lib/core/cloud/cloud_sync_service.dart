library;

/// Main cloud synchronization service
///
/// Orchestrates all cloud sync operations including authentication,
/// data synchronization, conflict resolution, and offline queuing.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../database/database_service.dart';
import 'cloud_sync_models.dart';
import 'cloud_api_service.dart';
import 'sync_queue_manager.dart';
import 'conflict_resolver.dart';

class CloudSyncService {
  CloudSyncService({CloudApiService? apiService})
    : _apiService =
          apiService ??
          RestCloudApiService(baseUrl: AppConfig.normalizedApiBaseUrl);

  static CloudSyncService? _instance;
  static CloudSyncService get instance => _instance ??= CloudSyncService();

  static void configure({CloudApiService? apiService}) {
    _instance?.dispose();
    _instance = CloudSyncService(
      apiService:
          apiService ??
          RestCloudApiService(baseUrl: AppConfig.normalizedApiBaseUrl),
    );
  }

  final CloudApiService _apiService;
  final SyncQueueManager _queueManager = SyncQueueManager.instance;
  final ConflictResolver _conflictResolver = ConflictResolver();
  final DatabaseService _database = DatabaseService.instance;

  SyncStatus _syncStatus = SyncStatus.offline;
  Timer? _autoSyncTimer;
  final List<VoidCallback> _syncStatusListeners = [];
  bool _disposed = false;

  /// Stream for sync status changes
  final _syncStatusController = StreamController<SyncStatus>.broadcast();

  Stream<SyncStatus> get syncStatusStream => _syncStatusController.stream;

  SyncStatus get syncStatus => _syncStatus;

  CloudAuthSession? currentSession;

  bool get isAuthenticated =>
      currentSession != null && !currentSession!.isExpired;

  CloudApiService get apiService => _apiService;

  /// Initialize cloud sync service
  void initialize() {
    if (_disposed) {
      return;
    }
    _queueManager.initializeTable();
    _startAutoSync();
  }

  /// Authenticate with cloud backend
  Future<bool> authenticate({
    required String username,
    required String password,
    required String shopId,
  }) async {
    try {
      _updateSyncStatus(SyncStatus.syncing);

      final session = await _apiService.authenticate(
        username: username,
        password: password,
        shopId: shopId,
      );

      if (session == null) {
        _updateSyncStatus(SyncStatus.offline);
        return false;
      }

      currentSession = session;

      if (session.role == 'super_admin') {
        currentSession = session;
        _updateSyncStatus(SyncStatus.synced);
        return true;
      }

      // Validate shop access
      final hasAccess = await _apiService.validateShopAccess(
        shopId: shopId,
        authToken: session.authToken,
      );

      if (!hasAccess) {
        await _apiService.logout(session.authToken);
        currentSession = null;
        _updateSyncStatus(SyncStatus.offline);
        return false;
      }

      // Cloud authentication is complete before synchronization begins. A
      // temporary sync failure must not turn valid credentials into a 401-like
      // login result.
      try {
        final hasLocalData = _hasLocalData(shopId);
        if (!hasLocalData) {
          await _performInitialSync(shopId, session);
        } else {
          await _performSync(shopId, session);
        }
        _updateSyncStatus(SyncStatus.synced);
      } catch (error) {
        if (kDebugMode) {
          debugPrint('Cloud sync after authentication failed category=sync_error');
        }
        _updateSyncStatus(SyncStatus.error);
      }
      _startAutoSync();
      return true;
    } catch (e) {
      if (e is CloudAuthException) {
        rethrow;
      }
      if (kDebugMode) {
        print('Authentication error: $e');
      }
      _updateSyncStatus(SyncStatus.offline);
      return false;
    }
  }

  /// Logout from cloud
  Future<void> logout() async {
    try {
      if (currentSession != null) {
        await _apiService.logout(currentSession!.authToken);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Logout error: $e');
      }
    } finally {
      currentSession = null;
      _stopAutoSync();
      _updateSyncStatus(SyncStatus.offline);
    }
  }

  /// Queue a local change for synchronization
  void queueChange({
    required String shopId,
    required String entityType,
    required String entityId,
    required String operation,
    required Map<String, dynamic> data,
  }) {
    _queueManager.addToQueue(
      shopId: shopId,
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      data: data,
    );

    _updateSyncStatus(SyncStatus.pending);

    if (kDebugMode) {
      print('Queued $operation on $entityType/$entityId');
    }
  }

  /// Perform manual sync
  Future<SyncResult> syncNow() async {
    if (!isAuthenticated) {
      return SyncResult(
        success: false,
        message: 'Not authenticated',
        errorDetails: 'No active session',
      );
    }

    try {
      _updateSyncStatus(SyncStatus.syncing);

      final shopId = currentSession!.shopId;
      final result = await _performSync(shopId, currentSession!);

      if (result.success) {
        _updateSyncStatus(SyncStatus.synced);
      } else if (_queueManager.getPendingCount(shopId) > 0) {
        _updateSyncStatus(SyncStatus.pending);
      } else {
        _updateSyncStatus(SyncStatus.synced);
      }

      return result;
    } catch (e) {
      _updateSyncStatus(SyncStatus.error);
      return SyncResult(
        success: false,
        message: 'Sync failed',
        errorDetails: e.toString(),
      );
    }
  }

  /// Get current sync statistics
  Map<String, dynamic> getSyncStats() {
    if (!isAuthenticated) {
      return {'status': 'offline', 'authenticated': false};
    }

    final stats = _queueManager.getSyncStats(currentSession!.shopId);
    return {
      'status': syncStatus.toString(),
      'authenticated': true,
      'pending': stats['pending'] ?? 0,
      'syncing': stats['syncing'] ?? 0,
      'synced': stats['synced'] ?? 0,
      'failed': stats['failed'] ?? 0,
      'total':
          (stats['pending'] ?? 0) +
          (stats['syncing'] ?? 0) +
          (stats['synced'] ?? 0) +
          (stats['failed'] ?? 0),
    };
  }

  /// Perform initial sync for new device
  Future<void> _performInitialSync(
    String shopId,
    CloudAuthSession session,
  ) async {
    try {
      final initialData = await _apiService.getInitialSync(
        shopId: shopId,
        authToken: session.authToken,
      );

      // Store all initial data in local database
      for (final entry in initialData.entries) {
        final entityType = entry.key;
        final records = entry.value;

        for (final record in records) {
          // Import each record type appropriately
          _importCloudRecord(shopId, entityType, record);
        }
      }

      if (kDebugMode) {
        print('Initial sync completed for shop $shopId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Initial sync error: $e');
      }
      rethrow;
    }
  }

  /// Perform regular sync of changes
  Future<SyncResult> _performSync(
    String shopId,
    CloudAuthSession session,
  ) async {
    try {
      int itemsSynced = 0;
      int itemsFailed = 0;
      final conflicts = <SyncConflict>[];

      // Upload pending changes
      final pendingItems = _queueManager.getPendingItems(shopId);

      for (final item in pendingItems) {
        try {
          _queueManager.markAsSyncing(item.id);

          final success = await _apiService.uploadSyncItem(
            item,
            session.authToken,
          );

          if (success) {
            _queueManager.markAsSynced(item.id);
            itemsSynced++;
          } else {
            _queueManager.markAsFailed(item.id, 'Upload failed');
            itemsFailed++;
          }
        } catch (e) {
          _queueManager.markAsFailed(item.id, e.toString());
          itemsFailed++;
        }
      }

      // Download remote changes
      final lastSyncTime = DateTime.now().subtract(const Duration(hours: 24));
      final remoteChanges = await _apiService.downloadChanges(
        shopId: shopId,
        authToken: session.authToken,
        sinceTime: lastSyncTime,
      );

      // Process remote changes
      for (final change in remoteChanges) {
        try {
          final entityType = change['_type'] as String?;
          final entityId = change['_id'] as String?;

          if (entityType == null || entityId == null) continue;

          // Check for conflicts
          final localRecord = _getLocalRecord(shopId, entityType, entityId);
          if (localRecord != null) {
            final conflict = _conflictResolver.detectConflict(
              shopId: shopId,
              entityType: entityType,
              entityId: entityId,
              localData: localRecord,
              remoteData: change,
            );

            if (conflict != null) {
              conflicts.add(conflict);
              // Resolve conflict
              final resolution = _conflictResolver.resolveConflict(conflict);
              if (resolution != null) {
                _importCloudRecord(shopId, entityType, resolution);
              }
              continue;
            }
          }

          _importCloudRecord(shopId, entityType, change);
        } catch (e) {
          if (kDebugMode) {
            print('Error processing remote change: $e');
          }
        }
      }

      return SyncResult(
        success: itemsFailed == 0,
        message: 'Sync completed',
        itemsSynced: itemsSynced,
        itemsFailed: itemsFailed,
        conflicts: conflicts,
      );
    } catch (e) {
      return SyncResult(
        success: false,
        message: 'Sync failed',
        errorDetails: e.toString(),
      );
    }
  }

  /// Import a cloud record into local database
  void _importCloudRecord(
    String shopId,
    String entityType,
    Map<String, dynamic> data,
  ) {
    final tableName = _tableNameForEntity(entityType);
    if (tableName == null) {
      if (kDebugMode) {
        print('No local table mapping for entity: $entityType');
      }
      return;
    }

    final normalized = Map<String, dynamic>.from(data);
    final modelId =
        _extractRecordId(normalized) ??
        normalized['entity_id'] ??
        normalized['id'];
    if (modelId == null) {
      return;
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final row = _normalizeRecordForEntity(shopId, entityType, normalized, now);
    final upsertSql = _upsertSqlForTable(tableName, row);
    if (upsertSql == null) {
      return;
    }

    final values = upsertSql.values;
    try {
      _database.database.execute(upsertSql.sql, values);
    } catch (e) {
      if (kDebugMode) {
        print('Failed to import $entityType into $tableName: $e');
      }
    }
  }

  /// Get local record for conflict detection
  Map<String, dynamic>? _getLocalRecord(
    String shopId,
    String entityType,
    String entityId,
  ) {
    final tableName = _tableNameForEntity(entityType);
    if (tableName == null) return null;

    try {
      final idColumn = _idColumnForTable(tableName);
      final rows = _database.database.select(
        'SELECT * FROM $tableName WHERE shop_id = ? AND $idColumn = ?',
        [shopId, entityId],
      );
      if (rows.isEmpty) return null;
      return Map<String, dynamic>.from(rows.first);
    } catch (_) {
      return null;
    }
  }

  String? _tableNameForEntity(String entityType) {
    final normalized = entityType.trim().toLowerCase();
    final tableMap = {
      'product': 'products',
      'products': 'products',
      'sale': 'sales',
      'sales': 'sales',
      'customer': 'customers',
      'customers': 'customers',
      'employee': 'employees',
      'employees': 'employees',
      'repair': 'repairs',
      'repairs': 'repairs',
      'debtor': 'debtors',
      'debtors': 'debtors',
      'debt_transaction': 'debt_transactions',
      'debt_transactions': 'debt_transactions',
      'accessory': 'accessories',
      'accessories': 'accessories',
      'mobile_device': 'mobile_devices',
      'mobile_devices': 'mobile_devices',
      'mobile_model': 'mobile_models',
      'mobile_models': 'mobile_models',
      'mobile_unit': 'mobile_units',
      'mobile_units': 'mobile_units',
      'supplier': 'suppliers',
      'suppliers': 'suppliers',
      'return': 'returns',
      'returns': 'returns',
      'purchase': 'purchases',
      'purchases': 'purchases',
    };
    return tableMap[normalized];
  }

  String _idColumnForTable(String tableName) {
    switch (tableName) {
      case 'products':
      case 'customers':
      case 'sales':
      case 'employees':
      case 'repairs':
      case 'debtors':
      case 'debt_transactions':
      case 'accessories':
      case 'mobile_devices':
      case 'mobile_models':
      case 'mobile_units':
      case 'suppliers':
      case 'returns':
      case 'purchases':
        return 'id';
      default:
        return 'id';
    }
  }

  Object? _extractRecordId(Map<String, dynamic> data) {
    for (final key in ['id', '_id', 'entity_id', 'entityId']) {
      final value = data[key];
      if (value != null) return value;
    }
    return null;
  }

  int? _normalizeLocalIdForTable(String tableName, dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      final parsed = int.tryParse(trimmed);
      if (parsed != null) return parsed;
      return trimmed.hashCode.abs() % 2147483647;
    }
    return value.hashCode.abs() % 2147483647;
  }

  Map<String, dynamic> _normalizeRecordForEntity(
    String shopId,
    String entityType,
    Map<String, dynamic> source,
    String now,
  ) {
    final tableName = _tableNameForEntity(entityType);
    final permittedColumns = _permittedColumnsForTable(tableName);
    final normalized = <String, dynamic>{
      'shop_id': shopId,
      'updated_at': now,
      'created_at': now,
    };

    final idValue = _extractRecordId(source);
    if (idValue != null && tableName != null) {
      final normalizedId = _normalizeLocalIdForTable(tableName, idValue);
      if (normalizedId != null) {
        normalized['id'] = normalizedId;
      }
    }

    source.forEach((key, value) {
      final cleanKey = key.trim();
      if (cleanKey == '_id' ||
          cleanKey == 'entity_id' ||
          cleanKey == 'entityId' ||
          cleanKey == 'id') {
        final normalizedId = _normalizeLocalIdForTable(tableName ?? '', value);
        if (normalizedId != null) {
          normalized['id'] = normalizedId;
        }
        return;
      }
      if (cleanKey == 'shop_id' || cleanKey == 'shopId') {
        normalized['shop_id'] = shopId;
        return;
      }
      if (cleanKey == 'updated_at' || cleanKey == 'updatedAt') {
        normalized['updated_at'] = value ?? now;
        return;
      }
      if (cleanKey == 'created_at' || cleanKey == 'createdAt') {
        normalized['created_at'] = value ?? now;
        return;
      }
      if (cleanKey.startsWith('_') ||
          cleanKey == 'entityType' ||
          cleanKey == 'operation') {
        return;
      }
      if (permittedColumns.isNotEmpty && !permittedColumns.contains(cleanKey)) {
        return;
      }
      normalized[cleanKey] = value;
    });

    if (!normalized.containsKey('created_at')) {
      normalized['created_at'] = now;
    }
    if (!normalized.containsKey('updated_at')) {
      normalized['updated_at'] = now;
    }
    if (tableName == 'products' &&
        !normalized.containsKey('name') &&
        source.containsKey('name')) {
      normalized['name'] = source['name'];
    }

    if (tableName == 'sales' && normalized.containsKey('imei')) {
      normalized['imei'] ??= 'unknown';
    }
    return normalized;
  }

  Set<String> _permittedColumnsForTable(String? tableName) {
    switch (tableName) {
      case 'products':
        return {
          'id',
          'shop_id',
          'name',
          'quantity',
          'reorder_level',
          'created_at',
          'updated_at',
        };
      case 'customers':
        return {'id', 'shop_id', 'name', 'contact', 'address', 'created_at'};
      case 'purchases':
        return {
          'id',
          'shop_id',
          'product_id',
          'product_name',
          'quantity',
          'total_cost',
          'purchased_at',
        };
      case 'sales':
        return {
          'id',
          'shop_id',
          'product_id',
          'product_name',
          'quantity',
          'selling_total',
          'purchase_total',
          'imei',
          'sold_at',
          'customer_name',
          'customer_phone',
          'customer_address',
          'employee_id',
          'employee_name',
          'created_at',
          'updated_at',
        };
      case 'employees':
        return {
          'id',
          'shop_id',
          'username',
          'password_hash',
          'status',
          'created_at',
          'updated_at',
        };
      case 'mobile_devices':
        return {
          'id',
          'shop_id',
          'name',
          'picture_path',
          'color',
          'imei1',
          'imei2',
          'ram',
          'storage',
          'condition',
          'source_customer_name',
          'source_cnic',
          'source_phone',
          'source_address',
          'source_cnic_picture',
          'buy_price',
          'sell_price',
          'status',
          'created_at',
          'updated_at',
        };
      case 'mobile_models':
        return {'id', 'shop_id', 'name', 'image', 'created_at', 'updated_at'};
      case 'mobile_units':
        return {
          'id',
          'shop_id',
          'mobile_model_id',
          'imei_1',
          'imei_2',
          'buy_price',
          'ram',
          'storage',
          'supplier_id',
          'status',
          'created_at',
          'updated_at',
        };
      case 'suppliers':
        return {'id', 'shop_id', 'name', 'phone', 'address', 'notes', 'created_at', 'updated_at'};
      case 'returns':
        return {'id', 'shop_id', 'sale_id', 'sale_item_id', 'mobile_unit_id', 'bill_number', 'returned_at', 'return_reason', 'created_at', 'updated_at'};
      case 'accessories':
        return {
          'id',
          'shop_id',
          'name',
          'picture_path',
          'buy_price',
          'sell_price',
          'status',
          'created_at',
          'updated_at',
        };
      case 'repairs':
        return {'id', 'shop_id', 'name', 'status', 'created_at', 'updated_at'};
      case 'debtors':
        return {
          'id',
          'shop_id',
          'name',
          'amount',
          'status',
          'created_at',
          'updated_at',
        };
      case 'debt_transactions':
        return {
          'id',
          'shop_id',
          'debtor_id',
          'amount',
          'description',
          'created_at',
          'updated_at',
        };
      default:
        return <String>{};
    }
  }

  ({String sql, List<Object?> values})? _upsertSqlForTable(
    String tableName,
    Map<String, dynamic> row,
  ) {
    final columns = row.keys.toList();
    final placeholders = columns.map((_) => '?').join(', ');
    final updates = columns
        .map((column) => '$column = excluded.$column')
        .join(', ');
    final values = columns.map((column) => row[column]).toList();

    final sql =
        'INSERT INTO $tableName (${columns.join(', ')}) VALUES ($placeholders) ON CONFLICT(id) DO UPDATE SET $updates';
    return (sql: sql, values: values);
  }

  /// Check if device has local data for shop
  bool _hasLocalData(String shopId) {
    try {
      const tables = [
        'shops', 'products', 'customers', 'purchases', 'sales', 'employees',
        'mobile_devices', 'mobile_models', 'mobile_units', 'accessories',
        'repairs', 'debtors', 'shop_settings',
      ];
      for (final table in tables) {
        final rows = _database.database.select(
          'SELECT 1 FROM $table WHERE shop_id = ? LIMIT 1',
          [shopId],
        );
        if (rows.isNotEmpty) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Start auto-sync timer
  void _startAutoSync() {
    if (_disposed) {
      return;
    }
    _stopAutoSync();
    _autoSyncTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      if (_disposed || !isAuthenticated) {
        return;
      }
      await syncNow();
    });
  }

  /// Stop auto-sync timer
  void _stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
  }

  /// Update sync status and notify listeners
  void _updateSyncStatus(SyncStatus status) {
    if (_syncStatus != status) {
      _syncStatus = status;
      _syncStatusController.add(status);
      for (final listener in _syncStatusListeners) {
        listener();
      }
    }
  }

  /// Add sync status listener
  void addSyncStatusListener(VoidCallback listener) {
    _syncStatusListeners.add(listener);
  }

  /// Remove sync status listener
  void removeSyncStatusListener(VoidCallback listener) {
    _syncStatusListeners.remove(listener);
  }

  /// Dispose resources
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _stopAutoSync();
    _syncStatusListeners.clear();
    _syncStatusController.close();
  }
}
