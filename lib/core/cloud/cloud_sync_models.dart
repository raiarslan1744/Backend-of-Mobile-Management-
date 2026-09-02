library;

/// Cloud synchronization models and enums for AK Mobile Shop Management System
///
/// This file defines the data structures used for synchronizing shop data
/// across multiple devices via a cloud backend.

enum SyncStatus {
  /// Data is synced with cloud
  synced,

  /// Currently synchronizing with cloud
  syncing,

  /// Device is offline
  offline,

  /// Local changes waiting to sync
  pending,

  /// Sync encountered an error
  error,
}

enum ConflictResolutionStrategy {
  /// Server data wins (discard local changes)
  serverWins,

  /// Local data wins (upload local changes)
  clientWins,

  /// Merge changes if possible
  merge,

  /// Manual review required
  manual,
}

/// Represents a single change to be synchronized
class SyncQueueItem {
  SyncQueueItem({
    required this.id,
    required this.shopId,
    required this.entityType,
    required this.entityId,
    required this.operation, // 'create', 'update', 'delete'
    required this.data,
    required this.createdAt,
    this.syncedAt,
    this.syncStatus = 'pending', // 'pending', 'syncing', 'synced', 'failed'
    this.errorMessage,
    this.retryCount = 0,
  });

  final String id;
  final String shopId;
  final String entityType; // e.g., 'product', 'sale', 'customer'
  final String entityId;
  final String operation;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  DateTime? syncedAt;
  String syncStatus;
  String? errorMessage;
  int retryCount;

  Map<String, dynamic> toJson() => {
    'id': id,
    'shop_id': shopId,
    'entity_type': entityType,
    'entity_id': entityId,
    'operation': operation,
    'data': data,
    'created_at': createdAt.toIso8601String(),
    'synced_at': syncedAt?.toIso8601String(),
    'sync_status': syncStatus,
    'error_message': errorMessage,
    'retry_count': retryCount,
  };

  factory SyncQueueItem.fromJson(Map<String, dynamic> json) => SyncQueueItem(
    id: json['id'] as String,
    shopId: json['shop_id'] as String,
    entityType: json['entity_type'] as String,
    entityId: json['entity_id'] as String,
    operation: json['operation'] as String,
    data: (json['data'] as Map?)?.cast<String, dynamic>() ?? {},
    createdAt: DateTime.parse(json['created_at'] as String),
    syncedAt: json['synced_at'] != null ? DateTime.parse(json['synced_at'] as String) : null,
    syncStatus: json['sync_status'] as String? ?? 'pending',
    errorMessage: json['error_message'] as String?,
    retryCount: json['retry_count'] as int? ?? 0,
  );
}

/// Represents a cloud synchronization conflict
class SyncConflict {
  SyncConflict({
    required this.id,
    required this.shopId,
    required this.entityType,
    required this.entityId,
    required this.localData,
    required this.remoteData,
    required this.localUpdatedAt,
    required this.remoteUpdatedAt,
    required this.detectedAt,
    this.resolution,
  });

  final String id;
  final String shopId;
  final String entityType;
  final String entityId;
  final Map<String, dynamic> localData;
  final Map<String, dynamic> remoteData;
  final DateTime localUpdatedAt;
  final DateTime remoteUpdatedAt;
  final DateTime detectedAt;
  ConflictResolutionStrategy? resolution;

  bool get isLocalNewer => localUpdatedAt.isAfter(remoteUpdatedAt);

  Map<String, dynamic> toJson() => {
    'id': id,
    'shop_id': shopId,
    'entity_type': entityType,
    'entity_id': entityId,
    'local_data': localData,
    'remote_data': remoteData,
    'local_updated_at': localUpdatedAt.toIso8601String(),
    'remote_updated_at': remoteUpdatedAt.toIso8601String(),
    'detected_at': detectedAt.toIso8601String(),
    'resolution': resolution?.toString().split('.').last,
  };
}

/// Represents the result of a sync operation
class SyncResult {
  SyncResult({
    required this.success,
    required this.message,
    this.itemsSynced = 0,
    this.itemsFailed = 0,
    this.conflicts = const [],
    this.errorDetails,
  });

  final bool success;
  final String message;
  final int itemsSynced;
  final int itemsFailed;
  final List<SyncConflict> conflicts;
  final String? errorDetails;

  Map<String, dynamic> toJson() => {
    'success': success,
    'message': message,
    'items_synced': itemsSynced,
    'items_failed': itemsFailed,
    'conflicts': conflicts.map((c) => c.toJson()).toList(),
    'error_details': errorDetails,
  };
}

/// User session data from cloud authentication
class CloudAuthSession {
  CloudAuthSession({
    required this.userId,
    required this.username,
    required this.shopId,
    required this.role,
    required this.authToken,
    required this.expiresAt,
    required this.createdAt,
  });

  final String userId;
  final String username;
  final String shopId;
  final String role; // 'admin', 'employee', 'super_admin'
  final String authToken;
  final DateTime expiresAt;
  final DateTime createdAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'username': username,
    'shop_id': shopId,
    'role': role,
    'auth_token': authToken,
    'expires_at': expiresAt.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
  };

  factory CloudAuthSession.fromJson(Map<String, dynamic> json) => CloudAuthSession(
    userId: json['user_id'] as String,
    username: json['username'] as String,
    shopId: json['shop_id'] as String,
    role: json['role'] as String,
    authToken: json['auth_token'] as String,
    expiresAt: DateTime.parse(json['expires_at'] as String),
    createdAt: DateTime.parse(json['created_at'] as String),
  );
}

/// Device registration for tracking sync across devices
class DeviceRegistration {
  DeviceRegistration({
    required this.deviceId,
    required this.shopId,
    required this.userId,
    required this.deviceName,
    required this.deviceType, // 'windows', 'mobile', 'web'
    required this.registeredAt,
    this.lastSyncAt,
  });

  final String deviceId;
  final String shopId;
  final String userId;
  final String deviceName;
  final String deviceType;
  final DateTime registeredAt;
  DateTime? lastSyncAt;

  Map<String, dynamic> toJson() => {
    'device_id': deviceId,
    'shop_id': shopId,
    'user_id': userId,
    'device_name': deviceName,
    'device_type': deviceType,
    'registered_at': registeredAt.toIso8601String(),
    'last_sync_at': lastSyncAt?.toIso8601String(),
  };
}

/// Tracks sync state for conflict detection
class SyncCheckpoint {
  SyncCheckpoint({
    required this.shopId,
    required this.lastSyncAt,
    required this.lastSyncedItemId,
  });

  final String shopId;
  final DateTime lastSyncAt;
  final String lastSyncedItemId;

  Map<String, dynamic> toJson() => {
    'shop_id': shopId,
    'last_sync_at': lastSyncAt.toIso8601String(),
    'last_synced_item_id': lastSyncedItemId,
  };

  factory SyncCheckpoint.fromJson(Map<String, dynamic> json) => SyncCheckpoint(
    shopId: json['shop_id'] as String,
    lastSyncAt: DateTime.parse(json['last_sync_at'] as String),
    lastSyncedItemId: json['last_synced_item_id'] as String,
  );
}
