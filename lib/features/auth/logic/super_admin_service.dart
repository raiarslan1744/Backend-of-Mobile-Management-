import 'package:flutter/foundation.dart';

import '../../../core/database/database_service.dart';
import '../../../core/cloud/cloud_sync_service.dart';

class ShopStatus {
  const ShopStatus._(this.value);

  final String value;
  static const ShopStatus active = ShopStatus._('Active');
  static const ShopStatus suspended = ShopStatus._('Suspended');

  @override
  String toString() => value;
}

class ShopModel {
  ShopModel({
    required this.id,
    required this.ownerName,
    required this.contact,
    required this.address,
    required this.shopId,
    required this.username,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String ownerName;
  final String contact;
  final String address;
  final String shopId;
  final String username;
  final ShopStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class ShopOperationResult {
  const ShopOperationResult({required this.success, required this.message});

  final bool success;
  final String message;
}

class SuperAdminService {
  SuperAdminService() : _database = DatabaseService.instance;

  static final SuperAdminService instance = SuperAdminService();
  final DatabaseService _database;

  Future<int> refreshShopsFromCloud() async {
    final session = CloudSyncService.instance.currentSession;
    if (session == null || session.role != 'super_admin') {
      return 0;
    }

    final remoteShops = await CloudSyncService.instance.apiService.listShops(
      session.authToken,
    );
    final remoteIds = remoteShops
        .map((shop) => shop['shopId']?.toString())
        .whereType<String>()
        .toSet();

    final localRows = _database.database.select('SELECT shop_id FROM shops');
    for (final row in localRows) {
      final localShopId = row['shop_id']?.toString() ?? '';
      if (localShopId.isEmpty || remoteIds.contains(localShopId)) {
        continue;
      }
      debugPrint(
        'Local shop cache removed because cloud is authoritative shopId=$localShopId',
      );
      _database.database.execute('DELETE FROM shops WHERE shop_id = ?', [
        localShopId,
      ]);
    }

    for (final remote in remoteShops) {
      final shopId = remote['shopId']?.toString() ?? '';
      if (shopId.isEmpty) continue;
      final existing = _database.database.select(
        'SELECT password_hash FROM shops WHERE shop_id = ?',
        [shopId],
      );
      final now = DateTime.now().toUtc().toIso8601String();
      if (existing.isEmpty) {
        _database.database.execute(
          '''INSERT INTO shops (owner_name, contact, address, shop_id, username, password_hash, status, created_at, updated_at)
             VALUES (?, ?, ?, ?, ?, ?, 'active', ?, ?)''',
          [
            remote['ownerName']?.toString() ?? '',
            remote['contact']?.toString() ?? '',
            remote['address']?.toString() ?? '',
            shopId,
            remote['username']?.toString() ?? '',
            '',
            remote['createdAt']?.toString() ?? now,
            remote['updatedAt']?.toString() ?? now,
          ],
        );
      } else {
        _database.database.execute(
          'UPDATE shops SET owner_name = ?, contact = ?, address = ?, username = ?, updated_at = ? WHERE shop_id = ?',
          [
            remote['ownerName']?.toString() ?? '',
            remote['contact']?.toString() ?? '',
            remote['address']?.toString() ?? '',
            remote['username']?.toString() ?? '',
            remote['updatedAt']?.toString() ?? now,
            shopId,
          ],
        );
      }
    }
    return remoteShops.length;
  }

  Future<int> migrateLocalShopsToCloud() async {
    final session = CloudSyncService.instance.currentSession;
    if (session == null || session.role != 'super_admin') return 0;

    debugPrint('Shop migration to cloud started');

    try {
      final remoteShops = await CloudSyncService.instance.apiService.listShops(
        session.authToken,
      );
      final remoteIds = remoteShops
          .map((shop) => shop['shopId']?.toString())
          .whereType<String>()
          .toSet();

      debugPrint('Cloud currently has ${remoteIds.length} shops');
      final localShops = _database.database.select('SELECT * FROM shops ORDER BY id');

      var migrated = 0;
      for (final row in localShops) {
        final shopId = row['shop_id']?.toString() ?? '';
        if (shopId.isEmpty) continue;

        if (remoteIds.isNotEmpty) {
          debugPrint(
            'Cloud is initialized; skipping local-to-cloud migration for shopId=$shopId to prevent stale deleted shops from returning',
          );
          continue;
        }

        if (remoteIds.contains(shopId)) {
          debugPrint('Shop already exists in cloud shopId=$shopId');
          continue;
        }

        debugPrint('Uploading local shop to cloud shopId=$shopId');
        try {
          final created = await CloudSyncService.instance.apiService.createShop(
            authToken: session.authToken,
            shop: {
              'ownerName': row['owner_name'],
              'contact': row['contact'],
              'address': row['address'],
              'shopId': shopId,
              'username': row['username'],
              'passwordHash': row['password_hash'],
            },
          );

          if (created) {
            migrated++;
            debugPrint('Successfully migrated shop to cloud shopId=$shopId');
          } else {
            debugPrint('Failed to migrate shop to cloud shopId=$shopId');
          }
        } catch (error, stackTrace) {
          debugPrint(
            'Migration error for shop shopId=$shopId error=$error stackTrace=$stackTrace',
          );
        }
      }

      debugPrint('Shop migration complete migrated=$migrated');
      return migrated;
    } catch (error, stackTrace) {
      debugPrint('Shop migration failed error=$error stackTrace=$stackTrace');
      return 0;
    }
  }

  Future<ShopOperationResult> createShopInCloud({
    required String ownerName,
    required String contact,
    required String address,
    required String shopId,
    required String username,
    required String password,
  }) async {
    debugPrint(
      'CREATE SHOP CLICKED ownerName=${ownerName.trim()} shopId=${shopId.trim()} username=${username.trim()}',
    );

    final trimmedOwner = ownerName.trim();
    final trimmedContact = contact.trim();
    final trimmedAddress = address.trim();
    final trimmedShopId = shopId.trim();
    final trimmedUsername = username.trim();
    final trimmedPassword = password.trim();

    if (trimmedOwner.isEmpty ||
        trimmedContact.isEmpty ||
        trimmedAddress.isEmpty ||
        trimmedShopId.isEmpty ||
        trimmedUsername.isEmpty ||
        trimmedPassword.isEmpty) {
      return const ShopOperationResult(
        success: false,
        message: 'All fields are required',
      );
    }

    final session = CloudSyncService.instance.currentSession;
    if (session == null || session.role != 'super_admin') {
      return const ShopOperationResult(
        success: false,
        message: 'You are not authorized to create a shop.',
      );
    }

    debugPrint(
      'CLOUD CREATE STARTED shopId=$trimmedShopId endpoint=/api/super-admin/shops method=POST',
    );
    final created = await CloudSyncService.instance.apiService.createShop(
      authToken: session.authToken,
      shop: {
        'ownerName': trimmedOwner,
        'contact': trimmedContact,
        'address': trimmedAddress,
        'shopId': trimmedShopId,
        'username': trimmedUsername,
        'password': trimmedPassword,
      },
    );

    debugPrint(
      'CLOUD CREATE RESPONSE shopId=$trimmedShopId success=$created',
    );
    if (!created) {
      return const ShopOperationResult(
        success: false,
        message: 'Unable to create shop in cloud',
      );
    }

    final result = createShop(
      ownerName: trimmedOwner,
      contact: trimmedContact,
      address: trimmedAddress,
      shopId: trimmedShopId,
      username: trimmedUsername,
      password: trimmedPassword,
    );
    debugPrint(
      'LOCAL SAVE STARTED shopId=$trimmedShopId success=${result.success}',
    );
    debugPrint(
      'LOCAL SAVE COMPLETED shopId=$trimmedShopId success=${result.success} message=${result.message}',
    );
    debugPrint(
      'CREATE SHOP FINAL RESULT shopId=$trimmedShopId success=${result.success} message=${result.message}',
    );
    return result;
  }

  List<ShopModel> get shops {
    final rows = _database.database.select('SELECT * FROM shops ORDER BY id');
    return rows.map(_shopFromRow).toList(growable: false);
  }

  String get superAdminUsername =>
      _database.database
              .select('SELECT username FROM super_admin WHERE id = 1')
              .first['username']
          as String;

  bool isSuperAdminCredentials(String username, String password) {
    final rows = _database.database.select(
      'SELECT id FROM super_admin WHERE id = 1 AND username = ? AND password_hash = ?',
      [username, DatabaseService.hashPassword(password)],
    );
    return rows.isNotEmpty;
  }

  bool shopExists(String shopId) {
    final rows = _database.database.select(
      'SELECT id FROM shops WHERE shop_id = ?',
      [shopId.trim()],
    );
    return rows.isNotEmpty;
  }

  void invalidateShopCredential(String shopId) {
    final trimmed = shopId.trim();
    if (trimmed.isEmpty) return;
    _database.database.execute(
      'UPDATE shops SET password_hash = ?, updated_at = ? WHERE shop_id = ?',
      [
        DatabaseService.hashPassword('INVALIDATED_OFFLINE_AUTH'),
        DateTime.now().toUtc().toIso8601String(),
        trimmed,
      ],
    );
  }

  void upsertShopCredential({
    required String shopId,
    required String username,
    required String password,
  }) {
    final trimmedShopId = shopId.trim();
    final trimmedUsername = username.trim();
    if (trimmedShopId.isEmpty || trimmedUsername.isEmpty) return;

    final existing = _database.database.select(
      'SELECT id FROM shops WHERE shop_id = ?',
      [trimmedShopId],
    );
    final now = DateTime.now().toUtc().toIso8601String();
    if (existing.isEmpty) {
      _database.database.execute(
        '''INSERT INTO shops (owner_name, contact, address, shop_id, username, password_hash, status, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, ?, 'active', ?, ?)''',
        [
          'Offline',
          'Offline',
          'Offline',
          trimmedShopId,
          trimmedUsername,
          DatabaseService.hashPassword(password.trim()),
          now,
          now,
        ],
      );
      return;
    }

    _database.database.execute(
      'UPDATE shops SET username = ?, password_hash = ?, updated_at = ? WHERE shop_id = ?',
      [
        trimmedUsername,
        DatabaseService.hashPassword(password.trim()),
        now,
        trimmedShopId,
      ],
    );
  }

  void resetForTesting() => _database.resetForTesting();

  ShopModel? findShopByCredentials({
    required String username,
    required String password,
    required String shopId,
  }) {
    final rows = _database.database.select(
      'SELECT * FROM shops WHERE username = ? AND shop_id = ? AND password_hash = ?',
      [username, shopId, DatabaseService.hashPassword(password)],
    );
    return rows.isEmpty ? null : _shopFromRow(rows.first);
  }

  ShopOperationResult createShop({
    required String ownerName,
    required String contact,
    required String address,
    required String shopId,
    required String username,
    required String password,
  }) {
    final values = [
      ownerName.trim(),
      contact.trim(),
      address.trim(),
      shopId.trim(),
      username.trim(),
      password.trim(),
    ];
    if (values.any((value) => value.isEmpty)) {
      return const ShopOperationResult(
        success: false,
        message: 'All fields are required',
      );
    }
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      _database.database.execute(
        '''INSERT INTO shops (owner_name, contact, address, shop_id, username, password_hash, status, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, ?, 'active', ?, ?)''',
        [
          values[0],
          values[1],
          values[2],
          values[3],
          values[4],
          DatabaseService.hashPassword(values[5]),
          now,
          now,
        ],
      );
      return const ShopOperationResult(
        success: true,
        message: 'Shop created successfully',
      );
    } catch (_) {
      return const ShopOperationResult(
        success: false,
        message: 'Shop ID already exists',
      );
    }
  }

  ShopOperationResult toggleShopStatus({required String shopId}) {
    final rows = _database.database.select(
      'SELECT status FROM shops WHERE shop_id = ?',
      [shopId],
    );
    if (rows.isEmpty) {
      return const ShopOperationResult(
        success: false,
        message: 'Shop not found',
      );
    }
    final newStatus = rows.first['status'] == 'active' ? 'suspended' : 'active';
    _database.database.execute(
      'UPDATE shops SET status = ?, updated_at = ? WHERE shop_id = ?',
      [newStatus, DateTime.now().toUtc().toIso8601String(), shopId],
    );
    return ShopOperationResult(
      success: true,
      message: newStatus == 'active'
          ? 'Shop activated successfully'
          : 'Shop suspended successfully',
    );
  }

  ShopOperationResult updateShop({
    required String shopId,
    required String ownerName,
    required String contact,
    required String address,
    required String username,
    String? password,
  }) {
    final values = [
      ownerName.trim(),
      contact.trim(),
      address.trim(),
      username.trim(),
    ];
    if (values.any((value) => value.isEmpty)) {
      return const ShopOperationResult(
        success: false,
        message: 'All fields are required',
      );
    }
    final existing = _database.database.select(
      'SELECT id FROM shops WHERE shop_id = ?',
      [shopId],
    );
    if (existing.isEmpty) {
      return const ShopOperationResult(
        success: false,
        message: 'Shop not found',
      );
    }
    final now = DateTime.now().toUtc().toIso8601String();
    if (password != null && password.trim().isNotEmpty) {
      _database.database.execute(
        'UPDATE shops SET owner_name = ?, contact = ?, address = ?, username = ?, password_hash = ?, updated_at = ? WHERE shop_id = ?',
        [
          values[0],
          values[1],
          values[2],
          values[3],
          DatabaseService.hashPassword(password.trim()),
          now,
          shopId,
        ],
      );
    } else {
      _database.database.execute(
        'UPDATE shops SET owner_name = ?, contact = ?, address = ?, username = ?, updated_at = ? WHERE shop_id = ?',
        [values[0], values[1], values[2], values[3], now, shopId],
      );
    }
    return const ShopOperationResult(
      success: true,
      message: 'Shop updated successfully',
    );
  }

  Future<ShopOperationResult> deleteShop({required String shopId}) async {
    final normalizedShopId = shopId.trim();
    final session = CloudSyncService.instance.currentSession;

    if (session == null || session.role != 'super_admin') {
      return const ShopOperationResult(
        success: false,
        message: 'You are not authorized to delete this shop.',
      );
    }

    if (normalizedShopId.isEmpty || normalizedShopId == 'SUPER_ADMIN') {
      return const ShopOperationResult(
        success: false,
        message: 'A valid shop ID is required.',
      );
    }

    debugPrint('DELETE START shopId=$normalizedShopId');

    try {
      final cloudDeleted = await CloudSyncService.instance.apiService.deleteShop(
        authToken: session.authToken,
        shopId: normalizedShopId,
      );
      if (!cloudDeleted) {
        debugPrint('DELETE FAILURE shopId=$normalizedShopId status=cloud_error');
        return const ShopOperationResult(
          success: false,
          message: 'Cloud shop deletion failed',
        );
      }

      debugPrint('DELETE RESPONSE shopId=$normalizedShopId status=200');

      final localTables = _database.database.select(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
      );

      _database.database.execute('BEGIN');
      try {
        final shopScopedTables = localTables
            .map((row) => (row['name'] as String? ?? '').trim())
            .where((tableName) => tableName.isNotEmpty)
            .where((tableName) {
              if (tableName == 'shops') {
                return false;
              }
              final columns = _database.database.select(
                'PRAGMA table_info($tableName)',
              );
              return columns.any((column) => column['name'] == 'shop_id');
            })
            .toList(growable: false);

        final debtorIds = _database.database
            .select('SELECT id FROM debtors WHERE shop_id = ?', [
              normalizedShopId,
            ])
            .map((row) => row['id'])
            .whereType<int>()
            .toList(growable: false);
        if (debtorIds.isNotEmpty) {
          final placeholders = List.filled(debtorIds.length, '?').join(', ');
          _database.database.execute(
            'DELETE FROM debt_transactions WHERE debtor_id IN ($placeholders)',
            debtorIds,
          );
        }

        for (final tableName in shopScopedTables) {
          _database.database.execute(
            'DELETE FROM $tableName WHERE shop_id = ?',
            [normalizedShopId],
          );
        }

        _database.database.execute('DELETE FROM shops WHERE shop_id = ?', [
          normalizedShopId,
        ]);
        _database.database.execute('COMMIT');
      } catch (error, stackTrace) {
        try {
          _database.database.execute('ROLLBACK');
        } catch (_) {}
        debugPrint(
          'LOCAL CLEANUP FAILED shopId=$normalizedShopId error=$error stackTrace=$stackTrace',
        );
        return const ShopOperationResult(
          success: false,
          message: 'Local shop deletion failed',
        );
      }

      await refreshShopsFromCloud();
      final verifiedRemoteShops = await CloudSyncService.instance.apiService
          .listShops(session.authToken);
      final stillExists = verifiedRemoteShops.any(
        (shop) => shop['shopId']?.toString() == normalizedShopId,
      );
      if (stillExists) {
        debugPrint(
          'DELETE FAILURE shopId=$normalizedShopId status=verification_failed',
        );
        return const ShopOperationResult(
          success: false,
          message: 'Shop deletion could not be verified in the cloud.',
        );
      }

      debugPrint('DELETE SUCCESS shopId=$normalizedShopId');
      return const ShopOperationResult(
        success: true,
        message: 'Shop deleted successfully',
      );
    } catch (error, stackTrace) {
      debugPrint(
        'DELETE FAILURE shopId=$normalizedShopId error=$error stackTrace=$stackTrace',
      );
      return const ShopOperationResult(
        success: false,
        message: 'Server error while deleting shop.',
      );
    }
  }

  ShopOperationResult updateSuperAdminCredentials({
    required String currentUsername,
    required String currentPassword,
    required String newUsername,
    required String newPassword,
    required String confirmNewPassword,
  }) {
    final row = _database.database
        .select('SELECT * FROM super_admin WHERE id = 1')
        .first;
    if (row['username'] != currentUsername.trim() ||
        row['password_hash'] !=
            DatabaseService.hashPassword(currentPassword.trim())) {
      return const ShopOperationResult(
        success: false,
        message: 'Current username or password is incorrect',
      );
    }
    if (newUsername.trim().isEmpty || newPassword.trim().isEmpty) {
      return const ShopOperationResult(
        success: false,
        message: 'New username and password are required',
      );
    }
    if (newPassword.trim() != confirmNewPassword.trim()) {
      return const ShopOperationResult(
        success: false,
        message: 'New password and confirm password must match',
      );
    }
    _database.database.execute(
      'UPDATE super_admin SET username = ?, password_hash = ?, updated_at = ? WHERE id = 1',
      [
        newUsername.trim(),
        DatabaseService.hashPassword(newPassword.trim()),
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
    return const ShopOperationResult(
      success: true,
      message: 'Super admin credentials updated successfully',
    );
  }

  bool isShopSuspended(String shopId) {
    final rows = _database.database.select(
      'SELECT status FROM shops WHERE shop_id = ?',
      [shopId],
    );
    return rows.isNotEmpty && rows.first['status'] == 'suspended';
  }

  ShopModel _shopFromRow(Map<String, Object?> row) {
    return ShopModel(
      id: row['id'] as int,
      ownerName: row['owner_name'] as String,
      contact: row['contact'] as String,
      address: row['address'] as String,
      shopId: row['shop_id'] as String,
      username: row['username'] as String,
      status: row['status'] == 'active'
          ? ShopStatus.active
          : ShopStatus.suspended,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}
