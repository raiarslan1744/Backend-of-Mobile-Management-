import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../bin/server.dart';
import '../lib/sync_engine.dart';

Future<String> _loginSuperAdminToken() async {
  final response = await http.post(
    Uri.parse('http://127.0.0.1:8080/api/auth/login'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'username': Platform.environment['SUPER_ADMIN_USERNAME'] ?? 'admin',
      'password': Platform.environment['SUPER_ADMIN_PASSWORD'] ?? 'admin123',
      'shopId': 'SUPER_ADMIN',
      'deviceId': 'integration-super-admin',
    }),
  );
  if (response.statusCode != 200) {
    throw StateError('Super Admin test login failed: ${response.statusCode}');
  }
  return (jsonDecode(response.body) as Map<String, dynamic>)['authToken']
      as String;
}

Future<http.Response> _createShop({
  required String authToken,
  required String shopId,
  required String username,
  bool includeDeviceLimit = true,
  Object? deviceLimit = 3,
}) => http.post(
  Uri.parse('http://127.0.0.1:8080/api/shops'),
  headers: {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $authToken',
  },
  body: jsonEncode({
    'shopId': shopId,
    'licenseAssigned': true,
    'isLifetime': true,
    'ownerName': 'Integration Owner',
    'contact': '12345',
    'address': 'Integration Street',
    'username': username,
    'password': 'admin-password-123',
    if (includeDeviceLimit) 'deviceLimit': deviceLimit,
  }),
);

Future<http.Response> _loginShop({
  required String shopId,
  required String username,
  String password = 'admin-password-123',
  String? deviceId,
}) => http.post(
  Uri.parse('http://127.0.0.1:8080/api/auth/login'),
  headers: {'Content-Type': 'application/json'},
  body: jsonEncode({
    'username': username,
    'password': password,
    'shopId': shopId,
    if (deviceId != null) 'deviceId': deviceId,
  }),
);

void main() {
  // Integration fixtures must never connect to a production database.
  final uri = Uri.tryParse(Platform.environment['DATABASE_URL'] ?? '');
  final isolated =
      uri?.host == '127.0.0.1' &&
      uri?.port == 55439 &&
      uri?.path == '/ak_unification_test';
  if (!isolated) {
    test(
      'isolated PostgreSQL integration fixture',
      () {},
      skip: 'Dedicated localhost PostgreSQL fixture is not configured.',
    );
    return;
  }

  const port = 8080;
  late ServerApp server;
  late String superAdminToken;

  setUp(() async {
    await ServerApp.stopAll();
    server = await ServerApp.start(port: port);
    await server.listen(port: port);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    superAdminToken = await _loginSuperAdminToken();
  });

  tearDown(() async {
    await server.close();
    await ServerApp.stopAll();
  });

  group('cloud backend', () {
    test('device limits, legacy IDs, revocation, authorization, and races', () async {
      final stamp = DateTime.now().microsecondsSinceEpoch;

      final missingLimit = await _createShop(
        authToken: superAdminToken,
        shopId: 'LIMIT-MISSING-$stamp',
        username: 'limit-missing-$stamp',
        includeDeviceLimit: false,
      );
      expect(missingLimit.statusCode, 400);
      for (final invalidLimit in [null, 0, -1, 1.5, 1001]) {
        final invalid = await _createShop(
          authToken: superAdminToken,
          shopId: 'LIMIT-INVALID-$stamp-${invalidLimit ?? 'null'}',
          username: 'limit-invalid-$stamp-${invalidLimit ?? 'null'}',
          deviceLimit: invalidLimit,
        );
        expect(invalid.statusCode, 400, reason: invalid.body);
      }
      final unauthenticatedCreate = await http.post(
        Uri.parse('http://127.0.0.1:8080/api/shops'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'shopId': 'UNAUTH-$stamp'}),
      );
      expect(unauthenticatedCreate.statusCode, 401);

      final limitOneShop = 'LIMIT-ONE-$stamp';
      final createdLimitOneShop = await _createShop(
        authToken: superAdminToken,
        shopId: limitOneShop,
        username: 'limit-one-$stamp',
        deviceLimit: 1,
      );
      expect(createdLimitOneShop.statusCode, 200);
      expect(
        (jsonDecode(createdLimitOneShop.body)
            as Map<String, dynamic>)['registeredDeviceCount'],
        0,
      );
      final firstLogin = await _loginShop(
        shopId: limitOneShop,
        username: 'limit-one-$stamp',
        deviceId: 'limit-one-device-a',
      );
      expect(firstLogin.statusCode, 200, reason: firstLogin.body);
      final firstToken =
          (jsonDecode(firstLogin.body) as Map<String, dynamic>)['authToken']
              as String;
      final deviceRows = await server.db.select(
        'SELECT device_id, device_name, device_type, created_at, last_seen_at FROM devices WHERE shop_id = ? AND device_id = ?',
        [limitOneShop, 'limit-one-device-a'],
      );
      expect(deviceRows, hasLength(1));
      expect(deviceRows.single['device_name'], isNotEmpty);
      expect(deviceRows.single['device_type'], isNotEmpty);
      expect(deviceRows.single['created_at'], isNotEmpty);
      expect(deviceRows.single['last_seen_at'], isNotEmpty);
      expect(
        await DeviceStateStore(server.db).activeDeviceCount(limitOneShop),
        1,
      );
      final firstDeviceList = await http.get(
        Uri.parse(
          'http://127.0.0.1:8080/api/super-admin/shops/$limitOneShop/devices',
        ),
        headers: {'Authorization': 'Bearer $superAdminToken'},
      );
      expect(firstDeviceList.statusCode, 200);
      final firstDeviceListBody =
          jsonDecode(firstDeviceList.body) as Map<String, dynamic>;
      expect(firstDeviceListBody['registeredDeviceCount'], 1);
      final firstListedDevice =
          (firstDeviceListBody['devices'] as List).single
              as Map<String, dynamic>;
      expect(firstListedDevice['deviceId'], 'limit-one-device-a');
      expect(firstListedDevice['deviceName'], isNotEmpty);
      expect(firstListedDevice['platform'], isNotEmpty);
      expect(firstListedDevice['firstRegistered'], isNotEmpty);
      expect(firstListedDevice['lastSeen'], isNotEmpty);
      expect(firstListedDevice['status'], 'active');
      final logout = await http.post(
        Uri.parse('http://127.0.0.1:8080/api/auth/logout'),
        headers: {'Authorization': 'Bearer $firstToken'},
      );
      expect(logout.statusCode, 200);
      final internalSyncDownload = await http.post(
        Uri.parse('http://127.0.0.1:8080/api/sync/download'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $firstToken',
        },
        body: jsonEncode({'batchSize': 500}),
      );
      expect(internalSyncDownload.statusCode, 200);
      expect(
        (jsonDecode(internalSyncDownload.body)
            as Map<String, dynamic>)['changes'],
        isEmpty,
        reason: 'Device-limit state must not enter normal shop sync.',
      );
      final repeatedLogin = await _loginShop(
        shopId: limitOneShop,
        username: 'limit-one-$stamp',
        deviceId: 'limit-one-device-a',
      );
      expect(repeatedLogin.statusCode, 200, reason: repeatedLogin.body);
      final repeatedToken =
          (jsonDecode(repeatedLogin.body) as Map<String, dynamic>)['authToken']
              as String;
      expect(
        await server.db.select(
          'SELECT device_id FROM devices WHERE shop_id = ? AND device_id = ?',
          [limitOneShop, 'limit-one-device-a'],
        ),
        hasLength(1),
      );
      final secondDevice = await _loginShop(
        shopId: limitOneShop,
        username: 'limit-one-$stamp',
        deviceId: 'limit-one-device-b',
      );
      expect(secondDevice.statusCode, 403);
      expect(
        (jsonDecode(secondDevice.body) as Map<String, dynamic>)['code'],
        'DEVICE_LIMIT_REACHED',
      );

      final deviceListUrl =
          'http://127.0.0.1:8080/api/super-admin/shops/$limitOneShop/devices';
      expect((await http.get(Uri.parse(deviceListUrl))).statusCode, 401);
      final adminList = await http.get(
        Uri.parse(deviceListUrl),
        headers: {'Authorization': 'Bearer $firstToken'},
      );
      expect(adminList.statusCode, 403);

      final listedDevices = await http.get(
        Uri.parse(deviceListUrl),
        headers: {'Authorization': 'Bearer $superAdminToken'},
      );
      expect(listedDevices.statusCode, 200, reason: listedDevices.body);
      expect(
        (jsonDecode(listedDevices.body)
            as Map<String, dynamic>)['registeredDeviceCount'],
        1,
      );
      final revokeUrl =
          'http://127.0.0.1:8080/api/super-admin/shops/$limitOneShop/devices/limit-one-device-a';
      expect((await http.delete(Uri.parse(revokeUrl))).statusCode, 401);
      expect(
        (await http.delete(
          Uri.parse(revokeUrl),
          headers: {'Authorization': 'Bearer $firstToken'},
        )).statusCode,
        403,
      );
      final revoked = await http.delete(
        Uri.parse(revokeUrl),
        headers: {'Authorization': 'Bearer $superAdminToken'},
      );
      expect(revoked.statusCode, 200, reason: revoked.body);
      final invalidatedSession = await http.get(
        Uri.parse('http://127.0.0.1:8080/api/sync/protocol'),
        headers: {'Authorization': 'Bearer $repeatedToken'},
      );
      expect(invalidatedSession.statusCode, 401);
      final revokedLogin = await _loginShop(
        shopId: limitOneShop,
        username: 'limit-one-$stamp',
        deviceId: 'limit-one-device-a',
      );
      expect(revokedLogin.statusCode, 403);
      expect(
        (jsonDecode(revokedLogin.body) as Map<String, dynamic>)['code'],
        'DEVICE_REVOKED',
      );
      expect(
        (await _loginShop(
          shopId: limitOneShop,
          username: 'limit-one-$stamp',
          deviceId: 'limit-one-device-b',
        )).statusCode,
        200,
        reason: 'Revocation must free the only slot.',
      );

      final limitTwoShop = 'LIMIT-TWO-$stamp';
      expect(
        (await _createShop(
          authToken: superAdminToken,
          shopId: limitTwoShop,
          username: 'limit-two-$stamp',
          deviceLimit: 2,
        )).statusCode,
        200,
      );
      expect(
        (await _loginShop(
          shopId: limitTwoShop,
          username: 'limit-two-$stamp',
          deviceId: 'limit-two-a',
        )).statusCode,
        200,
      );
      final deviceBLogin = await _loginShop(
        shopId: limitTwoShop,
        username: 'limit-two-$stamp',
        deviceId: 'limit-two-b',
      );
      expect(deviceBLogin.statusCode, 200);
      final deviceBToken =
          (jsonDecode(deviceBLogin.body) as Map<String, dynamic>)['authToken']
              as String;
      expect(
        (await _loginShop(
          shopId: limitTwoShop,
          username: 'limit-two-$stamp',
          deviceId: 'limit-two-b',
        )).statusCode,
        200,
      );
      final thirdDevice = await _loginShop(
        shopId: limitTwoShop,
        username: 'limit-two-$stamp',
        deviceId: 'limit-two-c',
      );
      expect(thirdDevice.statusCode, 403);
      expect(
        (jsonDecode(thirdDevice.body) as Map<String, dynamic>)['code'],
        'DEVICE_LIMIT_REACHED',
      );
      final decreaseLimit = await http.put(
        Uri.parse('http://127.0.0.1:8080/api/super-admin/shops/$limitTwoShop'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $superAdminToken',
        },
        body: jsonEncode({
          'ownerName': 'Integration Owner',
          'contact': '12345',
          'address': 'Integration Street',
          'username': 'limit-two-$stamp',
          'deviceLimit': 1,
        }),
      );
      expect(decreaseLimit.statusCode, 200, reason: decreaseLimit.body);
      final updateBody = jsonDecode(decreaseLimit.body) as Map<String, dynamic>;
      expect(updateBody['deviceLimit'], 1);
      expect(updateBody['registeredDeviceCount'], 0);
      expect(
        await server.db.select(
          'SELECT token FROM sessions WHERE token = ? AND device_id = ?',
          [deviceBToken, 'limit-two-b'],
        ),
        hasLength(1),
        reason: 'Changing a generation must not invalidate existing sessions.',
      );
      final overLimit = await http.get(
        Uri.parse(
          'http://127.0.0.1:8080/api/super-admin/shops/$limitTwoShop/devices',
        ),
        headers: {'Authorization': 'Bearer $superAdminToken'},
      );
      final overLimitBody = jsonDecode(overLimit.body) as Map<String, dynamic>;
      expect(overLimitBody['registeredDeviceCount'], 0);
      expect(overLimitBody['overDeviceLimit'], isFalse);
      expect(
        (overLimitBody['devices'] as List).where(
          (device) => (device as Map)['status'] == 'active',
        ),
        hasLength(2),
      );
      expect(
        (await _loginShop(
          shopId: limitTwoShop,
          username: 'limit-two-$stamp',
          deviceId: 'limit-two-a',
        )).statusCode,
        200,
      );
      final refreshedDeviceList = await http.get(
        Uri.parse('http://127.0.0.1:8080/api/super-admin/shops'),
        headers: {'Authorization': '******'},
      );
      expect(refreshedDeviceList.statusCode, 200);
      final refreshedShops = (jsonDecode(
        refreshedDeviceList.body,
      ) as List<dynamic>).cast<Map<String, dynamic>>();
      final refreshedShop = refreshedShops.singleWhere(
        (shop) => shop['shopId'] == limitTwoShop,
      );
      expect(refreshedShop['deviceLimit'], 1);
      expect(refreshedShop['registeredDeviceCount'], 1);
      final refreshedDevices = await http.get(
        Uri.parse(
          'http://127.0.0.1:8080/api/super-admin/shops/$limitTwoShop/devices',
        ),
        headers: {'Authorization': '******'},
      );
      expect(refreshedDevices.statusCode, 200);
      final refreshedDeviceBody =
          jsonDecode(refreshedDevices.body) as Map<String, dynamic>;
      expect(refreshedDeviceBody['registeredDeviceCount'], 1);
      expect(
        (refreshedDeviceBody['devices'] as List).where(
          (device) =>
              (device as Map)['deviceId'] == 'limit-two-a' &&
              device['status'] == 'active',
        ),
        hasLength(1),
      );
      final blockedDuringOverage = await _loginShop(
        shopId: limitTwoShop,
        username: 'limit-two-$stamp',
        deviceId: 'limit-two-c',
      );
      expect(blockedDuringOverage.statusCode, 403);
      expect(
        (jsonDecode(blockedDuringOverage.body) as Map<String, dynamic>)['code'],
        'DEVICE_LIMIT_REACHED',
      );
      final revokeLimitTwoA = await http.delete(
        Uri.parse(
          'http://127.0.0.1:8080/api/super-admin/shops/$limitTwoShop/devices/limit-two-a',
        ),
        headers: {'Authorization': 'Bearer $superAdminToken'},
      );
      expect(revokeLimitTwoA.statusCode, 200, reason: revokeLimitTwoA.body);
      expect(
        await server.db.select(
          'SELECT token FROM sessions WHERE token = ? AND device_id = ?',
          [deviceBToken, 'limit-two-b'],
        ),
        hasLength(1),
        reason: 'Revoking one device must not invalidate another device.',
      );
      expect(
        (await http.get(
          Uri.parse('http://127.0.0.1:8080/api/sync/protocol'),
          headers: {'Authorization': 'Bearer $deviceBToken'},
        )).statusCode,
        200,
        reason: 'Revoking one device must not invalidate another device.',
      );

      final nullLimitShop = 'LIMIT-NULL-$stamp';
      final legacyHash = hashPassword('legacy-password-123');
      final now = DateTime.now().toUtc().toIso8601String();
      await server.db.execute(
        'INSERT INTO shops (shop_id, owner_name, contact, address, username, password_hash, status, license_start_date, license_expiry_date, is_lifetime, license_assigned, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, TRUE, TRUE, ?, ?)',
        [
          nullLimitShop,
          'Legacy owner',
          '12345',
          'Legacy street',
          'null-limit-$stamp',
          legacyHash,
          'active',
          now,
          now,
          now,
        ],
      );
      await server.db.execute(
        'INSERT INTO users (id, username, password_hash, shop_id, role, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          'user-$nullLimitShop',
          'null-limit-$stamp',
          legacyHash,
          nullLimitShop,
          'admin',
          now,
          now,
        ],
      );
      for (final deviceId in ['null-limit-a', 'null-limit-b']) {
        final nullLimitLogin = await _loginShop(
          shopId: nullLimitShop,
          username: 'null-limit-$stamp',
          password: 'legacy-password-123',
          deviceId: deviceId,
        );
        expect(nullLimitLogin.statusCode, 200);
        expect(
          (jsonDecode(nullLimitLogin.body)
              as Map<String, dynamic>)['deviceLimit'],
          isNull,
        );
      }

      final legacyShop = 'LEGACY-ID-$stamp';
      expect(
        (await _createShop(
          authToken: superAdminToken,
          shopId: legacyShop,
          username: 'legacy-id-$stamp',
          deviceLimit: 2,
        )).statusCode,
        200,
      );
      final oldClient = await _loginShop(
        shopId: legacyShop,
        username: 'legacy-id-$stamp',
      );
      expect(oldClient.statusCode, 200, reason: oldClient.body);
      final oldToken =
          (jsonDecode(oldClient.body) as Map<String, dynamic>)['authToken']
              as String;
      final modernClient = await _loginShop(
        shopId: legacyShop,
        username: 'legacy-id-$stamp',
        deviceId: 'persistent-device-$stamp',
      );
      expect(modernClient.statusCode, 200, reason: modernClient.body);
      final oldSessionStillValid = await http.get(
        Uri.parse('http://127.0.0.1:8080/api/sync/protocol'),
        headers: {'Authorization': 'Bearer $oldToken'},
      );
      expect(oldSessionStillValid.statusCode, 200);
      final legacyList = await http.get(
        Uri.parse(
          'http://127.0.0.1:8080/api/super-admin/shops/$legacyShop/devices',
        ),
        headers: {'Authorization': 'Bearer $superAdminToken'},
      );
      final legacyDevices =
          (jsonDecode(legacyList.body) as Map<String, dynamic>)['devices']
              as List<dynamic>;
      expect(legacyDevices, hasLength(2));
      expect(
        legacyDevices.where((device) => (device as Map)['isLegacy'] == true),
        hasLength(1),
      );
      final revokeLegacy = await http.delete(
        Uri.parse(
          'http://127.0.0.1:8080/api/super-admin/shops/$legacyShop/devices/flutter-client',
        ),
        headers: {'Authorization': 'Bearer $superAdminToken'},
      );
      expect(revokeLegacy.statusCode, 200, reason: revokeLegacy.body);
      final revokedLegacySession = await http.get(
        Uri.parse('http://127.0.0.1:8080/api/sync/protocol'),
        headers: {'Authorization': 'Bearer $oldToken'},
      );
      expect(revokedLegacySession.statusCode, 401);

      final raceShop = 'LIMIT-RACE-$stamp';
      expect(
        (await _createShop(
          authToken: superAdminToken,
          shopId: raceShop,
          username: 'limit-race-$stamp',
          deviceLimit: 1,
        )).statusCode,
        200,
      );
      final raceResults = await Future.wait([
        _loginShop(
          shopId: raceShop,
          username: 'limit-race-$stamp',
          deviceId: 'race-device-a',
        ),
        _loginShop(
          shopId: raceShop,
          username: 'limit-race-$stamp',
          deviceId: 'race-device-b',
        ),
      ]);
      expect(
        raceResults.where((response) => response.statusCode == 200),
        hasLength(1),
      );
      final raceRejected = raceResults.singleWhere(
        (response) => response.statusCode == 403,
      );
      expect(
        (jsonDecode(raceRejected.body) as Map<String, dynamic>)['code'],
        'DEVICE_LIMIT_REACHED',
      );
    });

    test(
      'profile sync, shop username updates, and management authorization',
      () async {
        final stamp = DateTime.now().microsecondsSinceEpoch;
        final shopId = 'PROFILE-$stamp';
        expect(
          (await _createShop(
            authToken: superAdminToken,
            shopId: shopId,
            username: 'profile-admin-$stamp',
            deviceLimit: 3,
          )).statusCode,
          200,
        );
        final adminLogin = await _loginShop(
          shopId: shopId,
          username: 'profile-admin-$stamp',
          deviceId: 'profile-device-a',
        );
        final adminBody = jsonDecode(adminLogin.body) as Map<String, dynamic>;
        final adminToken = adminBody['authToken'] as String;
        final otherShopId = 'PROFILE-OTHER-$stamp';
        expect(
          (await _createShop(
            authToken: superAdminToken,
            shopId: otherShopId,
            username: 'profile-other-$stamp',
          )).statusCode,
          200,
        );
        final adminShopCreate = await http.post(
          Uri.parse('http://127.0.0.1:8080/api/shops'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $adminToken',
          },
          body: jsonEncode({
            'shopId': 'ADMIN-CREATE-$stamp',
            'licenseAssigned': true,
            'isLifetime': true,
            'ownerName': 'Not permitted',
            'contact': '12345',
            'address': 'Not permitted',
            'username': 'admin-not-permitted-$stamp',
            'password': 'admin-password-123',
            'deviceLimit': 1,
          }),
        );
        expect(adminShopCreate.statusCode, 403);

        final updateProfile = await http.put(
          Uri.parse('http://127.0.0.1:8080/api/shop/profile'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $adminToken',
          },
          body: jsonEncode({
            'shopId': otherShopId,
            'name': 'Cloud Current Name',
            'address': 'Cloud Current Address',
            'phone': '555-0101',
          }),
        );
        expect(updateProfile.statusCode, 200, reason: updateProfile.body);
        expect(
          (jsonDecode(updateProfile.body) as Map<String, dynamic>)['shopId'],
          shopId,
        );
        final otherProfile = await http.get(
          Uri.parse('http://127.0.0.1:8080/api/super-admin/shops'),
          headers: {'Authorization': 'Bearer $superAdminToken'},
        );
        final untouchedShop = (jsonDecode(otherProfile.body) as List)
            .cast<Map>()
            .singleWhere((shop) => shop['shopId'] == otherShopId);
        expect(untouchedShop['ownerName'], 'Integration Owner');
        final secondDevice = await _loginShop(
          shopId: shopId,
          username: 'profile-admin-$stamp',
          deviceId: 'profile-device-b',
        );
        final secondSession =
            jsonDecode(secondDevice.body) as Map<String, dynamic>;
        expect(secondSession['shopProfile']['name'], 'Cloud Current Name');
        expect(
          secondSession['shopProfile']['address'],
          'Cloud Current Address',
        );
        expect(secondSession['shopProfile']['phone'], '555-0101');

        final employeeCreate = await http.post(
          Uri.parse('http://127.0.0.1:8080/api/employees'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $adminToken',
          },
          body: jsonEncode({
            'shopId': shopId,
            'username': 'profile-employee-$stamp',
            'password': 'employee-password',
            'status': 'active',
          }),
        );
        expect(employeeCreate.statusCode, 200, reason: employeeCreate.body);
        final employeeCreateShop = await http.post(
          Uri.parse('http://127.0.0.1:8080/api/shops'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $adminToken',
          },
          body: jsonEncode({
            'shopId': 'EMPLOYEE-CREATE-$stamp',
            'licenseAssigned': true,
            'isLifetime': true,
            'ownerName': 'Not permitted',
            'contact': '12345',
            'address': 'Not permitted',
            'username': 'not-permitted-$stamp',
            'password': 'admin-password-123',
            'deviceLimit': 1,
          }),
        );
        expect(employeeCreateShop.statusCode, 403);
        final employeeLogin = await _loginShop(
          shopId: shopId,
          username: 'profile-employee-$stamp',
          password: 'employee-password',
          deviceId: 'profile-employee-device',
        );
        expect(employeeLogin.statusCode, 200, reason: employeeLogin.body);
        final employeeToken =
            (jsonDecode(employeeLogin.body)
                    as Map<String, dynamic>)['authToken']
                as String;
        expect(
          (await http.get(
            Uri.parse('http://127.0.0.1:8080/api/shop/profile'),
            headers: {'Authorization': 'Bearer $employeeToken'},
          )).statusCode,
          403,
        );
        expect(
          (await http.put(
            Uri.parse('http://127.0.0.1:8080/api/shop/profile'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $employeeToken',
            },
            body: jsonEncode({
              'name': 'forbidden',
              'address': 'forbidden',
              'phone': 'forbidden',
            }),
          )).statusCode,
          403,
        );
        expect(
          (await http.get(
            Uri.parse('http://127.0.0.1:8080/api/shop/profile'),
            headers: {'Authorization': 'Bearer $superAdminToken'},
          )).statusCode,
          403,
        );
        expect(
          (await http.put(
            Uri.parse('http://127.0.0.1:8080/api/shop/profile'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $superAdminToken',
            },
            body: jsonEncode({
              'name': 'forbidden',
              'address': 'forbidden',
              'phone': 'forbidden',
            }),
          )).statusCode,
          403,
        );

        final collision = await http.post(
          Uri.parse('http://127.0.0.1:8080/api/employees'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $adminToken',
          },
          body: jsonEncode({
            'shopId': shopId,
            'username': 'duplicate-$stamp',
            'password': 'employee-password',
            'status': 'active',
          }),
        );
        expect(collision.statusCode, 200, reason: collision.body);
        final duplicateUpdate = await http.put(
          Uri.parse('http://127.0.0.1:8080/api/super-admin/shops/$shopId'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $superAdminToken',
          },
          body: jsonEncode({
            'ownerName': 'New owner',
            'contact': '555-0102',
            'address': 'New address',
            'username': 'duplicate-$stamp',
          }),
        );
        expect(duplicateUpdate.statusCode, 409);

        final usernameUpdate = await http.put(
          Uri.parse('http://127.0.0.1:8080/api/super-admin/shops/$shopId'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $superAdminToken',
          },
          body: jsonEncode({
            'ownerName': 'New owner',
            'contact': '555-0103',
            'address': 'New address',
            'username': 'renamed-admin-$stamp',
          }),
        );
        expect(usernameUpdate.statusCode, 200, reason: usernameUpdate.body);
        expect(
          (await _loginShop(
            shopId: shopId,
            username: 'profile-admin-$stamp',
          )).statusCode,
          401,
        );
        expect(
          (await _loginShop(
            shopId: shopId,
            username: 'renamed-admin-$stamp',
          )).statusCode,
          200,
        );
        final shops = await http.get(
          Uri.parse('http://127.0.0.1:8080/api/super-admin/shops'),
          headers: {'Authorization': 'Bearer $superAdminToken'},
        );
        final updatedShop = (jsonDecode(shops.body) as List)
            .cast<Map>()
            .singleWhere((shop) => shop['shopId'] == shopId);
        expect(updatedShop['username'], 'renamed-admin-$stamp');
        expect(updatedShop['contact'], '555-0103');
      },
    );

    test('shop admin can log in and sync data to a second device', () async {
      final shopId = 'SHOP-${DateTime.now().microsecondsSinceEpoch}';
      const username = 'ali';
      const password = 'admin123';

      final createShopResponse = await http.post(
        Uri.parse('http://127.0.0.1:8080/api/shops'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $superAdminToken',
        },
        body: jsonEncode({
          'shopId': shopId,
          'licenseAssigned': true,
          'isLifetime': true,
          'ownerName': 'Ali',
          'contact': '12345',
          'address': 'Main Street',
          'username': username,
          'password': password,
          'deviceLimit': 3,
        }),
      );
      expect(createShopResponse.statusCode, 200);

      final loginA = await http.post(
        Uri.parse('http://127.0.0.1:8080/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
          'shopId': shopId,
          'deviceId': 'device-A',
        }),
      );
      expect(loginA.statusCode, 200, reason: loginA.body);

      final sessionA = jsonDecode(loginA.body) as Map<String, dynamic>;
      final tokenA = sessionA['authToken'] as String;

      final initialSyncA = await http.get(
        Uri.parse('http://127.0.0.1:8080/api/sync/initial?shopId=$shopId'),
        headers: {'Authorization': 'Bearer $tokenA'},
      );
      expect(initialSyncA.statusCode, 200);

      final productsA = [
        {
          'id': '$shopId-prod-1',
          'name': 'Samsung A15',
          'quantity': 5,
          'price': 23000,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        },
        {
          'id': '$shopId-prod-2',
          'name': 'PowerBank',
          'quantity': 12,
          'price': 1500,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        },
      ];

      final uploadA = await http.post(
        Uri.parse('http://127.0.0.1:8080/api/sync/upload'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $tokenA',
        },
        body: jsonEncode({
          'items': productsA
              .map(
                (product) => {
                  'id': 'sync-${product['id']}',
                  'shopId': shopId,
                  'entityType': 'product',
                  'entityId': product['id'],
                  'operation': 'create',
                  'data': product,
                  'createdAt': DateTime.now().toUtc().toIso8601String(),
                },
              )
              .toList(),
        }),
      );
      expect(uploadA.statusCode, 200, reason: uploadA.body);
      expect(
        (jsonDecode(uploadA.body) as Map)['itemsSynced'],
        2,
        reason: uploadA.body,
      );

      final loginB = await http.post(
        Uri.parse('http://127.0.0.1:8080/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
          'shopId': shopId,
          'deviceId': 'device-B',
        }),
      );
      expect(loginB.statusCode, 200, reason: loginB.body);

      final sessionB = jsonDecode(loginB.body) as Map<String, dynamic>;
      final tokenB = sessionB['authToken'] as String;

      final downloadB = await http.post(
        Uri.parse('http://127.0.0.1:8080/api/sync/download'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $tokenB',
        },
        body: jsonEncode({
          'lastSyncTime': '1970-01-01T00:00:00.000Z',
          'entityTypes': ['product'],
          'batchSize': 50,
        }),
      );

      expect(downloadB.statusCode, 200, reason: downloadB.body);
      final payload = jsonDecode(downloadB.body) as Map<String, dynamic>;
      final changes = payload['changes'] as List<dynamic>;
      expect(changes, hasLength(2));
      expect(
        changes.every((change) => (change as Map)['_type'] == 'product'),
        isTrue,
      );
      expect(
        changes.map((change) => (change as Map)['id']).toSet(),
        equals({'$shopId-prod-1', '$shopId-prod-2'}),
      );
    });

    test(
      'employee can log in to correct shop and shop isolation is enforced',
      () async {
        final shopId = 'SHOP-${DateTime.now().microsecondsSinceEpoch}';
        final otherShopId = 'SHOP-${DateTime.now().microsecondsSinceEpoch + 1}';
        const adminUser = 'ali';
        const adminPassword = 'admin123';

        final shopA = await http.post(
          Uri.parse('http://127.0.0.1:8080/api/shops'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $superAdminToken',
          },
          body: jsonEncode({
            'shopId': shopId,
            'licenseAssigned': true,
            'isLifetime': true,
            'ownerName': 'Ali',
            'contact': '12345',
            'address': 'Addr 1',
            'username': adminUser,
            'password': adminPassword,
            'deviceLimit': 3,
          }),
        );
        expect(shopA.statusCode, 200);

        final shopB = await http.post(
          Uri.parse('http://127.0.0.1:8080/api/shops'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $superAdminToken',
          },
          body: jsonEncode({
            'shopId': otherShopId,
            'licenseAssigned': true,
            'isLifetime': true,
            'ownerName': 'Other',
            'contact': '67890',
            'address': 'Addr 2',
            'username': 'otheradmin',
            'password': 'otherpass',
            'deviceLimit': 3,
          }),
        );
        expect(shopB.statusCode, 200);

        final adminLogin = await http.post(
          Uri.parse('http://127.0.0.1:8080/api/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'username': adminUser,
            'password': adminPassword,
            'shopId': shopId,
            'deviceId': 'device-admin',
          }),
        );
        final adminToken =
            (jsonDecode(adminLogin.body) as Map<String, dynamic>)['authToken']
                as String;

        final createEmployee = await http.post(
          Uri.parse('http://127.0.0.1:8080/api/employees'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $adminToken',
          },
          body: jsonEncode({
            'shopId': shopId,
            'username': 'employee01',
            'password': 'emp123',
            'status': 'active',
          }),
        );
        expect(createEmployee.statusCode, 200, reason: createEmployee.body);

        final employeeLogin = await http.post(
          Uri.parse('http://127.0.0.1:8080/api/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'username': 'employee01',
            'password': 'emp123',
            'shopId': shopId,
            'deviceId': 'device-employee',
          }),
        );
        expect(employeeLogin.statusCode, 200, reason: employeeLogin.body);

        final employeeToken =
            (jsonDecode(employeeLogin.body)
                    as Map<String, dynamic>)['authToken']
                as String;

        final baselineAccess = await http.get(
          Uri.parse('http://127.0.0.1:8080/api/sync/initial?shopId=$shopId'),
          headers: {'Authorization': 'Bearer $employeeToken'},
        );
        expect(baselineAccess.statusCode, 200);

        final crossShopAccess = await http.get(
          Uri.parse(
            'http://127.0.0.1:8080/api/sync/initial?shopId=$otherShopId',
          ),
          headers: {'Authorization': 'Bearer $employeeToken'},
        );
        expect(crossShopAccess.statusCode, 403);
      },
    );

    test('super admin can permanently delete a shop and a reused shop ID starts clean', () async {
      final originalShopId = 'SHOP-${DateTime.now().microsecondsSinceEpoch}';
      final superUsername =
          Platform.environment['SUPER_ADMIN_USERNAME'] ?? 'admin';
      final superPassword =
          Platform.environment['SUPER_ADMIN_PASSWORD'] ?? 'admin123';

      final createShopResponse = await http.post(
        Uri.parse('http://127.0.0.1:8080/api/shops'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $superAdminToken',
        },
        body: jsonEncode({
          'shopId': originalShopId,
          'licenseAssigned': true,
          'isLifetime': true,
          'ownerName': 'Delete Test',
          'contact': '12345',
          'address': 'Deleted Street',
          'username': 'delete-admin',
          'password': 'delete-pass',
          'deviceLimit': 3,
        }),
      );
      expect(
        createShopResponse.statusCode,
        200,
        reason: createShopResponse.body,
      );

      final superLogin = await http.post(
        Uri.parse('http://127.0.0.1:8080/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': superUsername,
          'password': superPassword,
          'shopId': 'SUPER_ADMIN',
          'deviceId': 'super-admin-delete-test',
        }),
      );
      expect(superLogin.statusCode, 200, reason: superLogin.body);

      final superSession = jsonDecode(superLogin.body) as Map<String, dynamic>;
      final superToken = superSession['authToken'] as String;

      final deleteResponse = await http.delete(
        Uri.parse(
          'http://127.0.0.1:8080/api/super-admin/shops/$originalShopId',
        ),
        headers: {'Authorization': 'Bearer $superToken'},
      );
      expect(deleteResponse.statusCode, 200, reason: deleteResponse.body);

      final listResponse = await http.get(
        Uri.parse('http://127.0.0.1:8080/api/super-admin/shops'),
        headers: {'Authorization': 'Bearer $superToken'},
      );
      expect(listResponse.statusCode, 200, reason: listResponse.body);
      final shops = jsonDecode(listResponse.body) as List<dynamic>;
      expect(
        shops.any(
          (shop) => (shop as Map<String, dynamic>)['shopId'] == originalShopId,
        ),
        isFalse,
      );

      final recreateShopResponse = await http.post(
        Uri.parse('http://127.0.0.1:8080/api/shops'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $superAdminToken',
        },
        body: jsonEncode({
          'shopId': originalShopId,
          'licenseAssigned': true,
          'isLifetime': true,
          'ownerName': 'Fresh Shop Owner',
          'contact': '99999',
          'address': 'New Street',
          'username': 'fresh-admin',
          'password': 'fresh-pass',
          'deviceLimit': 3,
        }),
      );
      expect(
        recreateShopResponse.statusCode,
        200,
        reason: recreateShopResponse.body,
      );

      final loginAfterReuse = await http.post(
        Uri.parse('http://127.0.0.1:8080/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': 'fresh-admin',
          'password': 'fresh-pass',
          'shopId': originalShopId,
          'deviceId': 'reuse-device',
        }),
      );
      expect(loginAfterReuse.statusCode, 200, reason: loginAfterReuse.body);

      final reusedSession =
          jsonDecode(loginAfterReuse.body) as Map<String, dynamic>;
      final reusedInitialSync = await http.get(
        Uri.parse(
          'http://127.0.0.1:8080/api/sync/initial?shopId=$originalShopId',
        ),
        headers: {'Authorization': 'Bearer ${reusedSession['authToken']}'},
      );
      expect(reusedInitialSync.statusCode, 200, reason: reusedInitialSync.body);
      final reusedData =
          jsonDecode(reusedInitialSync.body) as Map<String, dynamic>;
      expect(reusedData['products'], isEmpty);
      expect(reusedData['sales'], isEmpty);
      expect(reusedData['mobile_devices'], isEmpty);
      expect(reusedData['purchases'], isEmpty);

      final repeatedDelete = await http.delete(
        Uri.parse(
          'http://127.0.0.1:8080/api/super-admin/shops/$originalShopId',
        ),
        headers: {'Authorization': 'Bearer $superToken'},
      );
      // The recreated shop exists, so deleting it succeeds. A further repeat
      // must report missing; the old fixture skipped this second deletion.
      expect(repeatedDelete.statusCode, 200);
      final missingDelete = await http.delete(
        Uri.parse(
          'http://127.0.0.1:8080/api/super-admin/shops/$originalShopId',
        ),
        headers: {'Authorization': 'Bearer $superToken'},
      );
      expect(missingDelete.statusCode, 404);
    });

    test('login returns controlled responses for invalid requests', () async {
      final shopId = 'SHOP-${DateTime.now().microsecondsSinceEpoch}';
      final createShopResponse = await http.post(
        Uri.parse('http://127.0.0.1:8080/api/shops'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $superAdminToken',
        },
        body: jsonEncode({
          'shopId': shopId,
          'licenseAssigned': true,
          'isLifetime': true,
          'ownerName': 'Auth Test Owner',
          'contact': '12345',
          'address': 'Auth Test Street',
          'username': 'auth-test-user',
          'password': 'auth-test-password',
          'deviceLimit': 3,
        }),
      );
      expect(createShopResponse.statusCode, 200);

      Future<http.Response> login({
        String? username,
        String? password,
        String? requestedShopId,
        Object? body,
      }) => http.post(
        Uri.parse('http://127.0.0.1:8080/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: body == null
            ? jsonEncode({
                if (username != null) 'username': username,
                if (password != null) 'password': password,
                if (requestedShopId != null) 'shopId': requestedShopId,
                'deviceId': 'auth-validation-test',
              })
            : body,
      );

      final valid = await login(
        username: 'auth-test-user',
        password: 'auth-test-password',
        requestedShopId: shopId,
      );
      expect(valid.statusCode, 200, reason: valid.body);
      final session = jsonDecode(valid.body) as Map<String, dynamic>;
      expect(session['authToken'], isA<String>());
      expect(session['shopId'], shopId);
      expect(session['role'], 'admin');

      expect(
        (await login(
          username: 'auth-test-user',
          password: 'wrong-password',
          requestedShopId: shopId,
        )).statusCode,
        401,
      );
      expect(
        (await login(
          username: 'does-not-exist',
          password: 'auth-test-password',
          requestedShopId: shopId,
        )).statusCode,
        401,
      );
      expect(
        (await login(
          username: 'auth-test-user',
          password: 'auth-test-password',
          requestedShopId: 'SHOP-DOES-NOT-EXIST',
        )).statusCode,
        401,
      );
      expect(
        (await login(
          password: 'auth-test-password',
          requestedShopId: shopId,
        )).statusCode,
        400,
      );
      expect(
        (await login(
          username: 'auth-test-user',
          requestedShopId: shopId,
        )).statusCode,
        400,
      );
      expect(
        (await login(
          username: 'auth-test-user',
          password: 'auth-test-password',
        )).statusCode,
        400,
      );
      expect((await login(body: '{not-json')).statusCode, 400);

      final protocolWithoutAuth = await http.get(
        Uri.parse('http://127.0.0.1:8080/api/sync/protocol'),
      );
      expect(protocolWithoutAuth.statusCode, 401);
      final accessWithoutAuth = await http.get(
        Uri.parse(
          'http://127.0.0.1:8080/api/auth/validate-shop-access?shopId=$shopId',
        ),
      );
      expect(accessWithoutAuth.statusCode, 401);

      final token = session['authToken'] as String;
      final protocol = await http.get(
        Uri.parse('http://127.0.0.1:8080/api/sync/protocol'),
        headers: {'Authorization': 'Bearer $token'},
      );
      expect(protocol.statusCode, 200, reason: protocol.body);
      expect(jsonDecode(protocol.body), {'version': 2});
      final shopAccess = await http.get(
        Uri.parse(
          'http://127.0.0.1:8080/api/auth/validate-shop-access?shopId=$shopId',
        ),
        headers: {'Authorization': 'Bearer $token'},
      );
      expect(shopAccess.statusCode, 200, reason: shopAccess.body);
      expect((jsonDecode(shopAccess.body) as Map)['hasAccess'], isTrue);
      final otherShopAccess = await http.get(
        Uri.parse(
          'http://127.0.0.1:8080/api/auth/validate-shop-access?shopId=0',
        ),
        headers: {'Authorization': 'Bearer $token'},
      );
      expect(otherShopAccess.statusCode, 403, reason: otherShopAccess.body);

      final concurrentResponses = await Future.wait([
        http.get(
          Uri.parse('http://127.0.0.1:8080/api/sync/protocol'),
          headers: {'Authorization': 'Bearer $token'},
        ),
        http.get(
          Uri.parse(
            'http://127.0.0.1:8080/api/auth/validate-shop-access?shopId=0',
          ),
          headers: {'Authorization': 'Bearer $token'},
        ),
      ]);
      expect(concurrentResponses[0].statusCode, 200);
      expect(concurrentResponses[1].statusCode, 403);
    });

    test('health endpoints remain available independently of login', () async {
      for (final path in ['/health', '/api/health']) {
        final response = await http.get(
          Uri.parse('http://127.0.0.1:8080$path'),
        );
        expect(response.statusCode, 200, reason: response.body);
        expect((jsonDecode(response.body) as Map)['status'], 'healthy');
      }
    });
  });
}
