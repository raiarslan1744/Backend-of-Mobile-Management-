import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';

import '../lib/sync_engine.dart';

void main() {
  group('DeviceStateStore', () {
    test(
      'keeps absent limits unlimited and persists explicit configuration',
      () async {
        final db = _MemoryDatabase();
        final store = DeviceStateStore(db);

        expect(await store.deviceLimit('shop-1'), isNull);
        await store.setDeviceLimit('shop-1', 2);

        expect(await DeviceStateStore(db).deviceLimit('shop-1'), 2);
        expect(
          db.syncRecords.values.single['entity_type'],
          internalDeviceLimitEntityType,
        );
        await DeviceStateStore(db).setDeviceLimit('shop-1', null);
        expect(await store.deviceLimit('shop-1'), isNull);
      },
    );

    test('serializes concurrent registrations at the final slot', () async {
      final db = _MemoryDatabase();
      final store = DeviceStateStore(db);
      await store.setDeviceLimit('shop-1', 1);

      final results = await Future.wait([
        db.syncTransaction(
          () => store.registerDevice(
            shopId: 'shop-1',
            userId: 'user-1',
            deviceId: 'device-a',
            deviceName: 'A',
            deviceType: 'android',
          ),
        ),
        db.syncTransaction(
          () => store.registerDevice(
            shopId: 'shop-1',
            userId: 'user-1',
            deviceId: 'device-b',
            deviceName: 'B',
            deviceType: 'windows',
          ),
        ),
      ]);

      expect(results.where((result) => result.allowed), hasLength(1));
      expect(
        results.where((result) => result.code == 'DEVICE_LIMIT_REACHED'),
        hasLength(1),
      );
      expect(await store.activeDeviceCount('shop-1'), 1);
    });

    test(
      'revocation persists, frees a slot, and blocks the revoked ID',
      () async {
        final db = _MemoryDatabase();
        final store = DeviceStateStore(db);
        await store.setDeviceLimit('shop-1', 1);
        final registered = await store.registerDevice(
          shopId: 'shop-1',
          userId: 'user-1',
          deviceId: 'device-a',
          deviceName: 'A',
          deviceType: 'android',
        );
        expect(registered.allowed, isTrue);

        expect(await store.revokeDevice('shop-1', 'device-a'), isTrue);
        expect(
          await DeviceStateStore(db).isDeviceRevoked('shop-1', 'device-a'),
          isTrue,
        );
        expect(await store.activeDeviceCount('shop-1'), 0);
        final reRegistration = await store.registerDevice(
          shopId: 'shop-1',
          userId: 'user-1',
          deviceId: 'device-a',
          deviceName: 'A',
          deviceType: 'android',
        );
        expect(reRegistration.allowed, isFalse);
        expect(reRegistration.code, 'DEVICE_REVOKED');

        final replacement = await store.registerDevice(
          shopId: 'shop-1',
          userId: 'user-1',
          deviceId: 'device-b',
          deviceName: 'B',
          deviceType: 'windows',
        );
        expect(replacement.allowed, isTrue);
        expect(
          db.syncRecords.values.where(
            (row) => row['entity_type'] == internalDeviceRevocationEntityType,
          ),
          hasLength(1),
        );
      },
    );

    test(
      'activates a fresh generation without counting preserved devices',
      () async {
        final db = _MemoryDatabase();
        final store = DeviceStateStore(db);
        for (final id in ['flutter-client', 'old-device']) {
          final oldRegistration = await store.registerDevice(
            shopId: 'shop-1',
            userId: 'legacy-user',
            deviceId: id,
            deviceName: 'Old device',
            deviceType: 'legacy',
          );
          expect(oldRegistration.allowed, isTrue);
        }
        final preservedDevices = Map<String, Map<String, Object?>>.fromEntries(
          db.devices.entries.map(
            (entry) =>
                MapEntry(entry.key, Map<String, Object?>.from(entry.value)),
          ),
        );
        expect(await store.activeDeviceCount('shop-1'), 2);

        await store.setDeviceLimit('shop-1', 1);

        expect(await store.deviceLimit('shop-1'), 1);
        expect(await store.activeDeviceCount('shop-1'), 0);
        expect(db.devices, preservedDevices);
        expect(db.devices, hasLength(2));

        final deviceA = await store.registerDevice(
          shopId: 'shop-1',
          userId: 'user-1',
          deviceId: 'device-a',
          deviceName: 'Pixel',
          deviceType: 'android',
        );
        expect(deviceA.allowed, isTrue);
        expect(await store.activeDeviceCount('shop-1'), 1);
        final savedDevice = db.devices['shop-1:device-a']!;
        expect(savedDevice['device_name'], 'Pixel');
        expect(savedDevice['device_type'], 'android');
        expect(savedDevice['created_at'], isNotEmpty);
        expect(savedDevice['last_seen_at'], isNotEmpty);

        final repeatedDeviceA = await store.registerDevice(
          shopId: 'shop-1',
          userId: 'user-1',
          deviceId: 'device-a',
          deviceName: 'Pixel updated',
          deviceType: 'android',
        );
        expect(repeatedDeviceA.allowed, isTrue);
        expect(await store.activeDeviceCount('shop-1'), 1);
        expect(db.devices, hasLength(3));
        expect(db.devices['shop-1:device-a']!['id'], savedDevice['id']);
        expect(
          db.devices['shop-1:device-a']!['created_at'],
          savedDevice['created_at'],
        );
        expect(db.devices['shop-1:device-a']!['device_name'], 'Pixel updated');

        final deviceBAtLimit = await store.registerDevice(
          shopId: 'shop-1',
          userId: 'user-1',
          deviceId: 'device-b',
          deviceName: 'B',
          deviceType: 'windows',
        );
        expect(deviceBAtLimit.allowed, isFalse);
        expect(deviceBAtLimit.code, 'DEVICE_LIMIT_REACHED');
        expect(db.devices.containsKey('shop-1:device-b'), isFalse);

        expect(await store.revokeDevice('shop-1', 'device-a'), isTrue);
        final revokedDeviceA = await store.registerDevice(
          shopId: 'shop-1',
          userId: 'user-1',
          deviceId: 'device-a',
          deviceName: 'A',
          deviceType: 'android',
        );
        expect(revokedDeviceA.allowed, isFalse);
        expect(revokedDeviceA.code, 'DEVICE_REVOKED');

        final deviceBAfterRevocation = await store.registerDevice(
          shopId: 'shop-1',
          userId: 'user-1',
          deviceId: 'device-b',
          deviceName: 'B',
          deviceType: 'windows',
        );
        expect(deviceBAfterRevocation.allowed, isTrue);
        expect(await store.activeDeviceCount('shop-1'), 1);
        expect(db.devices['shop-1:flutter-client']?['user_id'], 'legacy-user');
      },
    );

    test('changing a limit starts a new generation', () async {
      final db = _MemoryDatabase();
      final store = DeviceStateStore(db);
      await store.setDeviceLimit('shop-1', 1);
      final deviceA = await store.registerDevice(
        shopId: 'shop-1',
        userId: 'user-1',
        deviceId: 'device-a',
        deviceName: 'A',
        deviceType: 'android',
      );
      expect(deviceA.allowed, isTrue);
      expect(await store.activeDeviceCount('shop-1'), 1);

      final firstGeneration = (jsonDecode(
        db.syncRecords.values.singleWhere(
              (row) => row['entity_type'] == internalDeviceLimitEntityType,
            )['data']
            as String,
      ) as Map)['generation'];
      await store.setDeviceLimit('shop-1', 1);
      final unchangedGeneration = (jsonDecode(
        db.syncRecords.values.singleWhere(
              (row) => row['entity_type'] == internalDeviceLimitEntityType,
            )['data']
            as String,
      ) as Map)['generation'];
      expect(unchangedGeneration, firstGeneration);
      expect(await store.activeDeviceCount('shop-1'), 1);

      await store.setDeviceLimit('shop-1', 3);
      final changedGeneration = (jsonDecode(
        db.syncRecords.values.singleWhere(
              (row) => row['entity_type'] == internalDeviceLimitEntityType,
            )['data']
            as String,
      ) as Map)['generation'];
      expect(changedGeneration, isNot(firstGeneration));
      expect(await store.activeDeviceCount('shop-1'), 0);
    });

    test('upgrades a pre-generation limit on successful login', () async {
      final db = _MemoryDatabase();
      final store = DeviceStateStore(db);
      await store.registerDevice(
        shopId: 'shop-1',
        userId: 'old-user',
        deviceId: 'old-device',
        deviceName: 'Old',
        deviceType: 'legacy',
      );
      await store.setDeviceLimit('shop-1', 1);
      final limitRecord = db.syncRecords.values.singleWhere(
        (row) => row['entity_type'] == internalDeviceLimitEntityType,
      );
      limitRecord['data'] = jsonEncode({'limit': 1});

      expect(await store.activeDeviceCount('shop-1'), 0);
      final login = await store.registerDevice(
        shopId: 'shop-1',
        userId: 'old-user',
        deviceId: 'old-device',
        deviceName: 'Updated',
        deviceType: 'android',
      );

      expect(login.allowed, isTrue);
      expect(await store.activeDeviceCount('shop-1'), 1);
      expect(
        (jsonDecode(
          db.syncRecords.values.singleWhere(
                (row) => row['entity_type'] == internalDeviceLimitEntityType,
              )['data']
              as String,
        ) as Map)['generation'],
        isA<String>(),
      );
    });

    test(
      'does not replace the existing device identity on repeated login',
      () async {
        final db = _MemoryDatabase();
        final store = DeviceStateStore(db);
        await store.registerDevice(
          shopId: 'shop-1',
          userId: 'first-user',
          deviceId: 'flutter-client',
          deviceName: 'Legacy',
          deviceType: 'legacy',
        );
        final original = Map<String, Object?>.from(
          db.devices['shop-1:flutter-client']!,
        );

        final repeated = await store.registerDevice(
          shopId: 'shop-1',
          userId: 'other-user',
          deviceId: 'flutter-client',
          deviceName: 'Updated label',
          deviceType: 'android',
        );

        expect(repeated.allowed, isTrue);
        final updated = db.devices['shop-1:flutter-client']!;
        expect(updated['id'], original['id']);
        expect(updated['device_id'], 'flutter-client');
        expect(updated['user_id'], original['user_id']);
        expect(updated['created_at'], original['created_at']);
        expect(updated['device_name'], 'Updated label');
      },
    );
  });

  test('normal sync downloads exclude internal device-state records', () async {
    final db = _MemoryDatabase();
    db.syncRecords['business-record'] = _syncRecord(
      id: 'business-record',
      shopId: 'shop-1',
      entityType: 'product',
      entityId: 'product-1',
      data: {'name': 'Visible product'},
    );
    db.syncRecords['device-limit-record'] = _syncRecord(
      id: 'device-limit-record',
      shopId: 'shop-1',
      entityType: internalDeviceLimitEntityType,
      entityId: 'device-limit',
      data: {'limit': 1},
    );
    db.syncRecords['device-revocation-record'] = _syncRecord(
      id: 'device-revocation-record',
      shopId: 'shop-1',
      entityType: internalDeviceRevocationEntityType,
      entityId: 'device-a',
      data: {'deviceId': 'device-a'},
    );
    db.syncRecords['device-registration-record'] = _syncRecord(
      id: 'device-registration-record',
      shopId: 'shop-1',
      entityType: internalDeviceRegistrationEntityType,
      entityId: 'device-a',
      data: {'deviceId': 'device-a', 'generation': 'generation-1'},
    );

    final response = await SyncEngine(db).download('shop-1');

    expect(response['totalCount'], 1);
    expect(response['changes'], hasLength(1));
    expect((response['changes'] as List).single['name'], 'Visible product');
  });
}

Map<String, Object?> _syncRecord({
  required String id,
  required String shopId,
  required String entityType,
  required String entityId,
  required Map<String, Object?> data,
}) {
  final now = DateTime.now().toUtc().toIso8601String();
  return {
    'id': id,
    'shop_id': shopId,
    'entity_type': entityType,
    'entity_id': entityId,
    'operation': 'update',
    'data': jsonEncode(data),
    'created_at': now,
    'updated_at': now,
    'is_deleted': 0,
  };
}

class _MemoryDatabase implements SyncDatabase {
  final syncRecords = <String, Map<String, Object?>>{};
  final devices = <String, Map<String, Object?>>{};
  final shops = <String>{'shop-1'};
  Future<void> _transactionTail = Future<void>.value();

  @override
  Future<T> syncTransaction<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _transactionTail = _transactionTail.then((_) async {
      try {
        result.complete(await action());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  @override
  Future<Map<String, String>> columns(String table) async => const {};

  @override
  Future<List<Map<String, Object?>>> select(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    final normalized = sql.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.startsWith(
      'select data from sync_records where id = ? and shop_id = ?',
    )) {
      final row = syncRecords[parameters[0]];
      return row != null && row['shop_id'] == parameters[1]
          ? [
              {'data': row['data']},
            ]
          : [];
    }
    if (normalized.startsWith(
      'select id from sync_records where id = ? and shop_id = ?',
    )) {
      final row = syncRecords[parameters[0]];
      return row != null && row['shop_id'] == parameters[1]
          ? [
              {'id': row['id']},
            ]
          : [];
    }
    if (normalized.startsWith('select shop_id from shops where shop_id = ?')) {
      return shops.contains(parameters.single)
          ? [
              {'shop_id': parameters.single},
            ]
          : [];
    }
    if (normalized.startsWith(
      'select id from devices where shop_id = ? and device_id = ?',
    )) {
      final row = devices['${parameters[0]}:${parameters[1]}'];
      return row == null
          ? []
          : [
              {'id': row['id']},
            ];
    }
    if (normalized.startsWith(
      'select device_id from devices where shop_id = ?',
    )) {
      return devices.values
          .where((row) => row['shop_id'] == parameters.single)
          .map((row) => {'device_id': row['device_id']})
          .toList();
    }
    if (normalized.startsWith('select * from sync_records where shop_id=?')) {
      final entityTypes = parameters.skip(1).take(4).toSet();
      final rows =
          syncRecords.values
              .where(
                (row) =>
                    row['shop_id'] == parameters.first &&
                    !entityTypes.contains(row['entity_type']),
              )
              .toList()
            ..sort((a, b) {
              final time = (a['updated_at'] as String).compareTo(
                b['updated_at'] as String,
              );
              return time != 0
                  ? time
                  : (a['id'] as String).compareTo(b['id'] as String);
            });
      return rows.take(parameters.last as int).toList();
    }
    throw UnsupportedError('Unexpected test SQL: $sql');
  }

  @override
  Future<void> execute(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    final normalized = sql.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.startsWith(
      'delete from sync_records where id = ? and shop_id = ?',
    )) {
      final row = syncRecords[parameters[0]];
      if (row != null && row['shop_id'] == parameters[1]) {
        syncRecords.remove(parameters[0]);
      }
      return;
    }
    if (normalized.startsWith('insert into sync_records')) {
      syncRecords[parameters[0] as String] = {
        'id': parameters[0],
        'shop_id': parameters[1],
        'entity_type': parameters[2],
        'entity_id': parameters[3],
        'operation': parameters[4],
        'data': parameters[5],
        'created_at': parameters[6],
        'updated_at': parameters[7],
        'is_deleted': 0,
      };
      return;
    }
    if (normalized.startsWith('update devices set device_name')) {
      final row = devices['${parameters[3]}:${parameters[4]}'];
      if (row != null) {
        row['device_name'] = parameters[0];
        row['device_type'] = parameters[1];
        row['last_seen_at'] = parameters[2];
      }
      return;
    }
    if (normalized.startsWith('insert into devices')) {
      devices['${parameters[2]}:${parameters[3]}'] = {
        'id': parameters[0],
        'user_id': parameters[1],
        'shop_id': parameters[2],
        'device_id': parameters[3],
        'device_name': parameters[4],
        'device_type': parameters[5],
        'created_at': parameters[6],
        'last_seen_at': parameters[7],
      };
      return;
    }
    throw UnsupportedError('Unexpected test SQL: $sql');
  }
}
