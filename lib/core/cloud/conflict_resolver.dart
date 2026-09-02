library;

/// Handles conflict detection and resolution between local and remote data
import 'cloud_sync_models.dart';

class ConflictResolver {
  /// Detect if there's a conflict between local and remote data
  SyncConflict? detectConflict({
    required String shopId,
    required String entityType,
    required String entityId,
    required Map<String, dynamic> localData,
    required Map<String, dynamic> remoteData,
  }) {
    final localUpdatedAt = _getUpdatedTime(localData);
    final remoteUpdatedAt = _getUpdatedTime(remoteData);

    // No conflict if one side was never modified
    if (localUpdatedAt == null || remoteUpdatedAt == null) {
      return null;
    }

    // Conflict exists when the records differ, even if timestamps match.
    final dataIsDifferent = _dataIsDifferent(localData, remoteData);

    if (dataIsDifferent) {
      return SyncConflict(
        id: '${shopId}_${entityType}_${entityId}_${DateTime.now().millisecondsSinceEpoch}',
        shopId: shopId,
        entityType: entityType,
        entityId: entityId,
        localData: localData,
        remoteData: remoteData,
        localUpdatedAt: localUpdatedAt,
        remoteUpdatedAt: remoteUpdatedAt,
        detectedAt: DateTime.now(),
      );
    }

    return null;
  }

  /// Resolve a conflict using a strategy
  Map<String, dynamic>? resolveConflict(SyncConflict conflict) {
    // Determine resolution strategy based on conflict type
    final strategy = _determineStrategy(conflict);
    conflict.resolution = strategy;

    switch (strategy) {
      case ConflictResolutionStrategy.serverWins:
        return conflict.remoteData;
      case ConflictResolutionStrategy.clientWins:
        return conflict.localData;
      case ConflictResolutionStrategy.merge:
        return _attemptMerge(conflict);
      case ConflictResolutionStrategy.manual:
        // Return null to indicate manual review needed
        return null;
    }
  }

  /// Determine resolution strategy
  ConflictResolutionStrategy _determineStrategy(SyncConflict conflict) {
    // Strategy 1: Server data is always newer
    if (conflict.remoteUpdatedAt.isAfter(conflict.localUpdatedAt)) {
      return ConflictResolutionStrategy.serverWins;
    }

    // Strategy 2: Local data is newer
    if (conflict.localUpdatedAt.isAfter(conflict.remoteUpdatedAt)) {
      return ConflictResolutionStrategy.clientWins;
    }

    // Strategy 3: Try to merge if possible
    if (_canMerge(conflict)) {
      return ConflictResolutionStrategy.merge;
    }

    // Strategy 4: Manual review required
    return ConflictResolutionStrategy.manual;
  }

  /// Attempt to merge conflicting data
  Map<String, dynamic> _attemptMerge(SyncConflict conflict) {
    final merged = <String, dynamic>{};

    // Start with remote data as base.
    merged.addAll(conflict.remoteData);

    for (final entry in conflict.localData.entries) {
      final remoteVal = conflict.remoteData[entry.key];
      if (!conflict.remoteData.containsKey(entry.key)) {
        merged[entry.key] = entry.value;
        continue;
      }

      if (_isNumericField(entry.key) && entry.value is num && remoteVal is num) {
        merged[entry.key] = _max(entry.value as num, remoteVal);
        continue;
      }

      merged[entry.key] = entry.value;
    }

    return merged;
  }

  /// Check if data can be merged
  bool _canMerge(SyncConflict conflict) {
    final localKeys = conflict.localData.keys.toSet();
    final remoteKeys = conflict.remoteData.keys.toSet();

    if (localKeys.isEmpty || remoteKeys.isEmpty) {
      return true;
    }

    final sharedKeys = localKeys.intersection(remoteKeys);
    final onlyLocal = localKeys.difference(remoteKeys);
    final onlyRemote = remoteKeys.difference(localKeys);

    if (onlyLocal.isNotEmpty || onlyRemote.isNotEmpty) {
      return true;
    }

    return sharedKeys.any(_isNumericField) || sharedKeys.length < localKeys.length;
  }

  /// Check if data differs (ignoring timestamps and metadata)
  bool _dataIsDifferent(Map<String, dynamic> local, Map<String, dynamic> remote) {
    final localKeys = local.keys
        .where((k) => !_isMetadataField(k))
        .toSet();
    final remoteKeys = remote.keys
        .where((k) => !_isMetadataField(k))
        .toSet();

    if (localKeys.length != remoteKeys.length) {
      return true;
    }

    for (final key in localKeys) {
      if (!remoteKeys.contains(key)) {
        return true;
      }
      if (local[key] != remote[key]) {
        return true;
      }
    }

    return false;
  }

  /// Get the updated timestamp from a record
  DateTime? _getUpdatedTime(Map<String, dynamic> data) {
    final updatedAt = data['updated_at'] ?? data['_updated_at'];

    if (updatedAt is String) {
      try {
        return DateTime.parse(updatedAt);
      } catch (_) {
        return null;
      }
    }

    if (updatedAt is DateTime) {
      return updatedAt;
    }

    return null;
  }

  /// Check if a field is metadata
  bool _isMetadataField(String fieldName) {
    return fieldName.startsWith('_') ||
        fieldName == 'created_at' ||
        fieldName == 'updated_at' ||
        fieldName == 'synced_at' ||
        fieldName == 'id';
  }

  /// Check if a field typically contains numeric values
  bool _isNumericField(String fieldName) {
    return fieldName.contains('quantity') ||
        fieldName.contains('price') ||
        fieldName.contains('cost') ||
        fieldName.contains('amount') ||
        fieldName.contains('total') ||
        fieldName.contains('stock') ||
        fieldName.contains('count');
  }

  num _max(num a, num b) => a > b ? a : b;
}
