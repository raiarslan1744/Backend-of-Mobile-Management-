import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

abstract interface class SyncDatabase {
  Future<List<Map<String, Object?>>> select(
    String sql, [
    List<Object?> parameters = const [],
  ]);
  Future<void> execute(String sql, [List<Object?> parameters = const []]);
  Future<T> syncTransaction<T>(Future<T> Function() action);
  Future<Map<String, String>> columns(String table);
}

const internalDeviceLimitEntityType = '_qodra_device_limit';
const internalDeviceRevocationEntityType = '_qodra_device_revocation';

class DeviceStateStore {
  DeviceStateStore(this.db);

  final SyncDatabase db;

  String _encodeKey(String value) =>
      base64Url.encode(utf8.encode(value)).replaceAll('=', '');

  String _limitRecordId(String shopId) =>
      'qodra-device-limit:${_encodeKey(shopId)}';

  String _revocationRecordId(String shopId, String deviceId) =>
      'qodra-device-revocation:${_encodeKey(shopId)}:${_encodeKey(deviceId)}';

  Future<int?> deviceLimit(String shopId) async {
    final rows = await db.select(
      'SELECT data FROM sync_records WHERE id = ? AND shop_id = ?',
      [_limitRecordId(shopId), shopId],
    );
    if (rows.isEmpty) return null;
    final data = jsonDecode(rows.single['data'] as String);
    if (data is! Map || data['limit'] is! int) {
      throw StateError(
        'Stored device-limit state is invalid for shop $shopId.',
      );
    }
    return data['limit'] as int;
  }

  Future<void> setDeviceLimit(String shopId, int? limit) async {
    if (limit != null && (limit < 1 || limit > 1000)) {
      throw ArgumentError.value(limit, 'limit', 'Must be between 1 and 1000.');
    }
    final recordId = _limitRecordId(shopId);
    if (limit == null) {
      await db.execute(
        'DELETE FROM sync_records WHERE id = ? AND shop_id = ?',
        [recordId, shopId],
      );
      return;
    }
    await _writeInternalRecord(
      id: recordId,
      shopId: shopId,
      entityType: internalDeviceLimitEntityType,
      entityId: 'device-limit',
      data: {'limit': limit},
    );
  }

  Future<bool> isDeviceRevoked(String shopId, String deviceId) async {
    final rows = await db.select(
      'SELECT id FROM sync_records WHERE id = ? AND shop_id = ?',
      [_revocationRecordId(shopId, deviceId), shopId],
    );
    return rows.isNotEmpty;
  }

  Future<Set<String>> revokedDeviceIds(
    String shopId,
    Iterable<String> deviceIds,
  ) async {
    final revoked = <String>{};
    for (final deviceId in deviceIds) {
      if (await isDeviceRevoked(shopId, deviceId)) revoked.add(deviceId);
    }
    return revoked;
  }

  Future<int> activeDeviceCount(String shopId) async {
    final rows = await db.select(
      'SELECT device_id FROM devices WHERE shop_id = ?',
      [shopId],
    );
    // The old client used one shared ID for every installation. Preserve its
    // registration, but do not let that unidentifiable row consume a modern
    // per-installation device slot.
    final deviceIds = rows
        .map((row) => row['device_id'].toString())
        .where((deviceId) => deviceId != 'flutter-client')
        .toList();
    final revoked = await revokedDeviceIds(shopId, deviceIds);
    return deviceIds.where((deviceId) => !revoked.contains(deviceId)).length;
  }

  Future<({bool allowed, String? code, String? message})> registerDevice({
    required String shopId,
    required String userId,
    required String deviceId,
    required String deviceName,
    required String deviceType,
  }) async {
    final shops = await db.select(
      'SELECT shop_id FROM shops WHERE shop_id = ?',
      [shopId],
    );
    if (shops.isEmpty) {
      return (
        allowed: false,
        code: 'SHOP_NOT_FOUND',
        message: 'Shop not found.',
      );
    }
    if (await isDeviceRevoked(shopId, deviceId)) {
      return (
        allowed: false,
        code: 'DEVICE_REVOKED',
        message: 'This device was revoked. Ask the Super Admin to authorize a replacement device.',
      );
    }

    final existing = await db.select(
      'SELECT id FROM devices WHERE shop_id = ? AND device_id = ?',
      [shopId, deviceId],
    );
    if (existing.isNotEmpty) {
      await db.execute(
        'UPDATE devices SET device_name = ?, device_type = ?, last_seen_at = ? WHERE shop_id = ? AND device_id = ?',
        [
          deviceName,
          deviceType,
          DateTime.now().toUtc().toIso8601String(),
          shopId,
          deviceId,
        ],
      );
      return (allowed: true, code: null, message: null);
    }

    final limit = await deviceLimit(shopId);
    if (limit != null && await activeDeviceCount(shopId) >= limit) {
      return (
        allowed: false,
        code: 'DEVICE_LIMIT_REACHED',
        message: 'Device limit reached for this shop. Ask the Super Admin to remove a registered device or increase the device limit.',
      );
    }

    final now = DateTime.now().toUtc().toIso8601String();
    await db.execute(
      'INSERT INTO devices (id, user_id, shop_id, device_id, imei, device_name, device_type, created_at, last_seen_at) VALUES (?, ?, ?, ?, NULL, ?, ?, ?, ?)',
      [
        const Uuid().v4(),
        userId,
        shopId,
        deviceId,
        deviceName,
        deviceType,
        now,
        now,
      ],
    );
    return (allowed: true, code: null, message: null);
  }

  Future<bool> revokeDevice(String shopId, String deviceId) async {
    final rows = await db.select(
      'SELECT id FROM devices WHERE shop_id = ? AND device_id = ?',
      [shopId, deviceId],
    );
    if (rows.isEmpty) return false;
    await _writeInternalRecord(
      id: _revocationRecordId(shopId, deviceId),
      shopId: shopId,
      entityType: internalDeviceRevocationEntityType,
      entityId: deviceId,
      data: {
        'deviceId': deviceId,
        'revokedAt': DateTime.now().toUtc().toIso8601String(),
      },
    );
    return true;
  }

  Future<void> _writeInternalRecord({
    required String id,
    required String shopId,
    required String entityType,
    required String entityId,
    required Map<String, Object?> data,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.execute(
      'INSERT INTO sync_records (id, shop_id, entity_type, entity_id, operation, data, created_at, updated_at, is_deleted) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0) ON CONFLICT (id) DO UPDATE SET operation = EXCLUDED.operation, data = EXCLUDED.data, updated_at = EXCLUDED.updated_at, is_deleted = 0',
      [id, shopId, entityType, entityId, 'update', jsonEncode(data), now, now],
    );
  }
}

const syncTables = <String, String>{
  'product': 'products',
  'customer': 'customers',
  'employee': 'employees',
  'supplier': 'suppliers',
  'mobile_model': 'mobile_models',
  'mobile_unit': 'mobile_units',
  'mobile_device': 'mobile_devices',
  'accessory': 'accessories',
  'debtor': 'debtors',
  'debt_transaction': 'debt_transactions',
  'purchase': 'purchases',
  'sale': 'sales',
  'repair': 'repairs',
  'return': 'returns',
};
String? canonicalEntity(String input) {
  if (syncTables.containsKey(input)) return input;
  for (final e in syncTables.entries) {
    if (e.value == input) return e.key;
  }
  return null;
}

String canonicalJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((e) => e.toString()).toList()..sort();
    return '{${keys.map((k) => '${jsonEncode(k)}:${canonicalJson(value[k])}').join(',')}}';
  }
  if (value is List) return '[${value.map(canonicalJson).join(',')}]';
  return jsonEncode(value);
}

DateTime recordTime(Map<String, dynamic> data) =>
    DateTime.tryParse(
      '${data['updated_at'] ?? data['updatedAt'] ?? data['created_at'] ?? data['createdAt'] ?? data['sold_at'] ?? data['purchased_at'] ?? ''}',
    )?.toUtc() ??
    DateTime.utc(1970);
bool isTombstone(Map<String, dynamic> data) =>
    data['is_deleted'] == 1 ||
    data['is_deleted'] == true ||
    data['deleted_at'] != null ||
    data['operation'] == 'delete';
Map<String, dynamic> publicRecord(Map<String, dynamic> row) => {...row}
  ..remove('password_hash')
  ..remove('password')
  ..remove('_quantity_totals')
  ..remove('_quantity_versions');

class SyncEngine {
  SyncEngine(this.db);
  final SyncDatabase db;

  Future<Map<String, dynamic>> upload(
    String shop,
    String role,
    Map<String, dynamic> item,
  ) async {
    if (item['shopId']?.toString() != shop) return {'code': 'SHOP_MISMATCH'};
    final entity = canonicalEntity('${item['entityType']}');
    final id = item['entityId']?.toString();
    final operation = item['operation']?.toString();
    if (entity == null ||
        id == null ||
        id.isEmpty ||
        !{'create', 'update', 'delete'}.contains(operation) ||
        item['data'] is! Map) {
      return {'code': 'INVALID_CHANGE'};
    }
    if (entity == 'employee' && role != 'admin')
      return {'code': 'PERMISSION_DENIED'};
    final data = Map<String, dynamic>.from(item['data'] as Map);
    if ((data['shop_id'] ?? data['shopId'] ?? shop).toString() != shop)
      return {'code': 'SHOP_MISMATCH'};
    data['id'] = id;
    data['shop_id'] = shop;
    data['is_deleted'] = operation == 'delete' ? 1 : 0;
    data['created_at'] ??=
        data['createdAt'] ??
        data['sold_at'] ??
        data['purchased_at'] ??
        item['createdAt'];
    data['updated_at'] ??= data['updatedAt'] ?? item['createdAt'];
    if (DateTime.tryParse('${data['created_at']}') == null ||
        DateTime.tryParse('${data['updated_at']}') == null)
      return {'code': 'INVALID_TIMESTAMP'};
    final eventId = sha256
        .convert(
          utf8.encode(
            canonicalJson([
              shop,
              entity,
              id,
              item['createdAt'],
              operation,
              data,
            ]),
          ),
        )
        .toString();
    return db.syncTransaction(() async {
      final duplicate = await db.select(
        'SELECT id FROM sync_records WHERE id=? AND shop_id=?',
        [eventId, shop],
      );
      final table = syncTables[entity]!;
      final columns = await db.columns(table);
      final pk = _typed(id, columns['id']!);
      final rows = await db.select('SELECT * FROM $table WHERE id=?', [pk]);
      if (rows.isNotEmpty && rows.single['shop_id'] != shop)
        return {'code': 'ID_COLLISION'};
      final history = await db.select(
        'SELECT * FROM sync_records WHERE shop_id=? AND entity_type IN (?,?) AND entity_id=? AND operation IN (?,?,?) ORDER BY updated_at DESC,id DESC LIMIT 1',
        [shop, entity, table, id, 'create', 'update', 'delete'],
      );
      Map<String, dynamic>? current = rows.isEmpty
          ? null
          : Map<String, dynamic>.from(rows.single);
      if (history.isNotEmpty)
        current = {
          ...?current,
          ...Map<String, dynamic>.from(
            jsonDecode(history.single['data'] as String) as Map,
          ),
        };
      if (duplicate.isNotEmpty)
        return {
          'accepted': true,
          'current': current == null ? null : publicRecord(current),
        };
      if (operation == 'create' &&
          current != null &&
          DateTime.tryParse('${current['created_at']}') !=
              DateTime.tryParse('${data['created_at']}'))
        return {'code': 'ID_COLLISION', 'current': publicRecord(current)};
      // Validate referenced tenants before storing any business data.
      for (final relation in {
        'mobile_model_id': 'mobile_models',
        'supplier_id': 'suppliers',
        'debtor_id': 'debtors',
        'mobile_unit_id': 'mobile_units',
        'sale_id': 'sales',
        'employee_id': 'employees',
      }.entries) {
        if (data[relation.key] == null) continue;
        final types = await db.columns(relation.value);
        final parent = await db.select(
          'SELECT shop_id FROM ${relation.value} WHERE id=?',
          [_typed(data[relation.key], types['id']!)],
        );
        if (parent.isEmpty || parent.single['shop_id'] != shop)
          return {'code': 'MISSING_PARENT'};
      }
      final incomingDeleted = isTombstone(data);
      final currentWins =
          current != null &&
          (isTombstone(current) ||
              (!incomingDeleted &&
                  (recordTime(current).isAfter(recordTime(data)) ||
                      (recordTime(current) == recordTime(data) &&
                          canonicalJson(current)
                                  .compareTo(canonicalJson(data)) >
                              0))));
      final hasQuantity =
          entity == 'accessory' &&
          data['_quantity_source'] is String &&
          data['_quantity_total'] is int &&
          !incomingDeleted &&
          (current == null || !isTombstone(current));
      if (currentWins && !hasQuantity) {
        await _archive(shop, entity, id, data, current, eventId);
        return {
          'code': 'REMOTE_VERSION_WINS',
          'current': publicRecord(current),
        };
      }
      var merged = <String, dynamic>{...?current, ...data};
      if (currentWins) merged = {...data, ...current};
      if (hasQuantity) {
        final source = data['_quantity_source'] as String;
        final total = data['_quantity_total'] as int;
        final totals = Map<String, dynamic>.from(
          current?['_quantity_totals'] as Map? ?? {},
        );
        final versions = Map<String, dynamic>.from(
          current?['_quantity_versions'] as Map? ?? {},
        );
        final revision = DateTime.parse('${item['createdAt']}').toUtc();
        final previous = DateTime.tryParse('${versions[source]}');
        if (previous == null || revision.isAfter(previous)) {
          merged['quantity'] = current == null
              ? data['quantity']
              : (current['quantity'] as num).toInt() +
                    total -
                    ((totals[source] as num?)?.toInt() ?? 0);
          totals[source] = total;
          versions[source] = revision.toIso8601String();
        } else {
          merged['quantity'] = current!['quantity'];
        }
        merged['_quantity_totals'] = totals;
        merged['_quantity_versions'] = versions;
      }
      merged.remove('_quantity_source');
      merged.remove('_quantity_total');
      if (current != null && canonicalJson(current) != canonicalJson(merged))
        await _archive(shop, entity, id, current, data, eventId);
      final writable = <String, dynamic>{};
      for (final entry in merged.entries) {
        if (columns.containsKey(entry.key))
          writable[entry.key] = _typed(entry.value, columns[entry.key]!);
      }
      if (operation == 'delete') {
        // Tables without a delete flag retain their row; sync_records holds the tombstone.
        if (columns.containsKey('is_deleted'))
          await db.execute(
            'UPDATE $table SET is_deleted=1,updated_at=? WHERE id=? AND shop_id=?',
            [data['updated_at'], pk, shop],
          );
      } else {
        final names = writable.keys.toList();
        await db.execute(
          'INSERT INTO $table (${names.join(',')}) VALUES (${List.filled(names.length, '?').join(',')}) ON CONFLICT(id) DO UPDATE SET ${names.where((n) => n != 'id' && n != 'shop_id').map((n) => '$n=excluded.$n').join(',')} WHERE $table.shop_id=excluded.shop_id',
          names.map((n) => writable[n]).toList(),
        );
      }
      if (entity == 'employee') await _employeeUser(shop, merged, operation!);
      final ts = await _arrival();
      await db.execute(
        'INSERT INTO sync_records(id,shop_id,entity_type,entity_id,operation,data,created_at,updated_at,is_deleted) VALUES(?,?,?,?,?,?,?,?,?)',
        [
          eventId,
          shop,
          entity,
          id,
          operation,
          jsonEncode(merged),
          item['createdAt'],
          ts,
          incomingDeleted ? 1 : 0,
        ],
      );
      return {'accepted': true, 'current': publicRecord(merged)};
    });
  }

  Object? _typed(Object? value, String type) {
    if (value == null) return null;
    if (type.contains('int') || type == 'bigserial')
      return value is int ? value : int.parse(value.toString());
    if (type == 'text' || type.contains('character')) return value.toString();
    if (type == 'real' || type.contains('double') || type == 'numeric')
      return value is num ? value.toDouble() : double.parse(value.toString());
    return value;
  }

  Future<String> _arrival() async {
    // Uploads hold a transaction advisory lock, so this order is also commit order.
    final row = await db.select(
      'SELECT MAX(updated_at) AS value FROM sync_records',
    );
    final last = DateTime.tryParse('${row.single['value']}');
    var now = DateTime.now().toUtc();
    if (last != null && !now.isAfter(last))
      now = last.add(const Duration(microseconds: 1));
    return '${now.toIso8601String().split('.').first}.${(now.millisecond * 1000 + now.microsecond).toString().padLeft(6, '0')}Z';
  }

  Future<void> _archive(
    String shop,
    String entity,
    String id,
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
    String event,
  ) async {
    final ts = await _arrival();
    await db.execute(
      'INSERT INTO sync_records(id,shop_id,entity_type,entity_id,operation,data,created_at,updated_at,is_deleted) VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO NOTHING',
      [
        'conflict:$event',
        shop,
        'conflict',
        '$entity:$id',
        'conflict',
        jsonEncode({'retained': local, 'other': remote}),
        ts,
        ts,
        0,
      ],
    );
  }

  Future<void> _employeeUser(
    String shop,
    Map<String, dynamic> row,
    String operation,
  ) async {
    final users = await db.select(
      'SELECT id,role,password_hash FROM users WHERE shop_id=? AND username=?',
      [shop, row['username']],
    );
    if (users.isNotEmpty && users.single['role'] != 'employee')
      throw StateError('Employee username is reserved');
    if (users.isEmpty) {
      await db.execute(
        'INSERT INTO users(id,shop_id,username,password_hash,role,created_at,updated_at) VALUES(?,?,?,?,?,?,?)',
        [
          row['id'].toString(),
          shop,
          row['username'],
          row['password_hash'],
          'employee',
          row['created_at'],
          row['updated_at'],
        ],
      );
    } else {
      if (operation == 'delete' ||
          row['status'] != 'active' ||
          users.single['password_hash'] != row['password_hash']) {
        await db.execute('DELETE FROM sessions WHERE user_id=?', [
          users.single['id'],
        ]);
      }
      await db.execute(
        'UPDATE users SET password_hash=?,updated_at=? WHERE id=? AND shop_id=?',
        [row['password_hash'], row['updated_at'], users.single['id'], shop],
      );
    }
  }

  Future<Map<String, dynamic>> download(
    String shop, {
    String? cursor,
    int limit = 200,
  }) async {
    String time = '1970-01-01T00:00:00.000000Z', id = '';
    if (cursor != null && cursor.isNotEmpty) {
      final decoded = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(cursor))),
      ) as List;
      if (decoded.length != 2 || DateTime.tryParse('${decoded[0]}') == null)
        throw FormatException('Invalid cursor');
      time = decoded[0].toString();
      id = decoded[1].toString();
    }
    limit = limit.clamp(1, 500);
    final rows = await db.select(
      'SELECT * FROM sync_records WHERE shop_id=? AND entity_type NOT IN (?,?,?) AND (updated_at>? OR (updated_at=? AND id>?)) ORDER BY updated_at,id LIMIT ?',
      [
        shop,
        'conflict',
        internalDeviceLimitEntityType,
        internalDeviceRevocationEntityType,
        time,
        time,
        id,
        limit + 1,
      ],
    );
    final page = rows.take(limit).toList();
    final changes = page
        .map(
          (r) => publicRecord({
            ...Map<String, dynamic>.from(
              jsonDecode(r['data'] as String) as Map,
            ),
            '_type': r['entity_type'],
            'id': r['entity_id'],
            'shop_id': shop,
            'operation': r['operation'],
          }),
        )
        .toList();
    final next = page.isEmpty
        ? cursor
        : base64Url.encode(
            utf8.encode(jsonEncode([page.last['updated_at'], page.last['id']])),
          );
    return {
      'changes': changes,
      'nextCursor': next,
      'hasMore': rows.length > limit,
      'totalCount': changes.length,
    };
  }

  Future<List<Map<String, dynamic>>> snapshot(String shop, String table) async {
    final entity = canonicalEntity(table);
    if (entity == null) throw ArgumentError('Unsupported entity');
    final rows = await db.select('SELECT * FROM $table WHERE shop_id=?', [
      shop,
    ]);
    final records = {
      for (final row in rows) '${row['id']}': Map<String, dynamic>.from(row),
    };
    final history = await db.select(
      'SELECT * FROM sync_records WHERE shop_id=? AND entity_type IN (?,?) AND operation IN (?,?,?) ORDER BY updated_at,id',
      [shop, entity, table, 'create', 'update', 'delete'],
    );
    for (final row in history) {
      final id = '${row['entity_id']}';
      records[id] = {
        ...?records[id],
        ...Map<String, dynamic>.from(jsonDecode(row['data'] as String) as Map),
        'id': id,
        'shop_id': shop,
        'is_deleted': row['is_deleted'],
      };
    }
    return records.values.map(publicRecord).toList();
  }
}
