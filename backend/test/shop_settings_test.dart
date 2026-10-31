import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../bin/server.dart';

final _databaseUri = Uri.tryParse(Platform.environment['DATABASE_URL'] ?? '');
final _isIsolatedDatabase =
    _databaseUri?.host == '127.0.0.1' &&
    _databaseUri?.port == 55439 &&
    _databaseUri?.path == '/ak_unification_test';

Future<http.Response> _request(
  http.Client client,
  String baseUrl,
  String method,
  String path, {
  Map<String, dynamic>? body,
  String? token,
}) async {
  final request = http.Request(method, Uri.parse('$baseUrl$path'));
  if (body != null) {
    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode(body);
  }
  if (token != null) request.headers['Authorization'] = 'Bearer $token';
  return http.Response.fromStream(await client.send(request));
}

void main() {
  test('shop phone validation accepts common forms and rejects invalid values', () {
    expect(canonicalShopPhone('  +1 (555) 123-4567  '), '+1 (555) 123-4567');
    expect(canonicalShopPhone('123'), isNull);
    expect(canonicalShopPhone('12345678<script>'), isNull);
  });

  if (!_isIsolatedDatabase) {
    test(
      'shop settings HTTP integration uses only the dedicated local database',
      () {},
      skip: 'Dedicated localhost PostgreSQL fixture is not configured.',
    );
    return;
  }

  test('shop settings enforce roles, persist phone, and refresh on another device', () async {
    const port = 19084;
    final server = await ServerApp.start(port: port);
    await server.listen(port: port);
    final client = http.Client();
    addTearDown(() async {
      client.close();
      await ServerApp.stopAll();
    });
    final baseUrl = 'http://127.0.0.1:$port';
    final suffix = DateTime.now().microsecondsSinceEpoch.toString();
    final now = utcNow();
    final superUsername = 'settings-super-$suffix';
    const superPassword = 'isolated-settings-password';
    await server.db.execute(
      'INSERT INTO users (id, username, password_hash, shop_id, role, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        const Uuid().v4(),
        superUsername,
        hashPassword(superPassword),
        'SUPER_ADMIN',
        'super_admin',
        now,
        now,
      ],
    );

    late String superToken;
    Future<void> createShop(String shopId) async {
      final response = await _request(
        client,
        baseUrl,
        'POST',
        '/api/shops',
        token: superToken,
        body: {
          'shopId': shopId,
          'username': 'admin-$shopId',
          'password': 'shop-password',
          'ownerName': 'Owner $shopId',
          'contact': '+1 555 123 4567',
          'address': 'Original Address',
          'licenseAssigned': true,
          'isLifetime': true,
        },
      );
      expect(response.statusCode, 200, reason: response.body);
    }

    Future<String> login(String username, String password, String shopId) async {
      final response = await _request(
        client,
        baseUrl,
        'POST',
        '/api/auth/login',
        body: {
          'username': username,
          'password': password,
          'shopId': shopId,
          'deviceId': 'settings-device',
        },
      );
      expect(response.statusCode, 200, reason: response.body);
      return (jsonDecode(response.body) as Map)['authToken'] as String;
    }

    superToken = await login(superUsername, superPassword, 'SUPER_ADMIN');
    final shopA = 'SETTINGS-A-$suffix';
    final shopB = 'SETTINGS-B-$suffix';
    await createShop(shopA);
    await createShop(shopB);
    final adminAToken = await login('admin-$shopA', 'shop-password', shopA);
    final adminBToken = await login('admin-$shopB', 'shop-password', shopB);

    final initial = await _request(
      client,
      baseUrl,
      'GET',
      '/api/shops/$shopA/settings',
      token: adminAToken,
    );
    expect(initial.statusCode, 200, reason: initial.body);
    final initialSettings = jsonDecode(initial.body) as Map<String, dynamic>;

    final deniedIdentity = await _request(
      client,
      baseUrl,
      'PUT',
      '/api/shops/$shopA/settings',
      token: adminAToken,
      body: {
        'ownerName': 'Unauthorized Name',
        'address': 'Unauthorized Address',
        'phone': initialSettings['phone'],
        'updatedAt': initialSettings['updatedAt'],
      },
    );
    expect(deniedIdentity.statusCode, 403);
    expect(
      (jsonDecode(deniedIdentity.body) as Map)['code'],
      'SHOP_IDENTITY_SUPER_ADMIN_ONLY',
    );

    final updatedPhone = await _request(
      client,
      baseUrl,
      'PUT',
      '/api/shops/$shopA/settings',
      token: adminAToken,
      body: {
        'phone': '+1 (555) 777-8888',
        'updatedAt': initialSettings['updatedAt'],
      },
    );
    expect(updatedPhone.statusCode, 200, reason: updatedPhone.body);
    expect(
      (jsonDecode(updatedPhone.body) as Map)['phone'],
      '+1 (555) 777-8888',
    );

    final staleWrite = await _request(
      client,
      baseUrl,
      'PUT',
      '/api/shops/$shopA/settings',
      token: adminAToken,
      body: {
        'phone': '+1 555 999 0000',
        'updatedAt': initialSettings['updatedAt'],
      },
    );
    expect(staleWrite.statusCode, 409);
    expect((jsonDecode(staleWrite.body) as Map)['code'], 'SHOP_SETTINGS_STALE');

    final crossShopRead = await _request(
      client,
      baseUrl,
      'GET',
      '/api/shops/$shopB/settings',
      token: adminAToken,
    );
    expect(crossShopRead.statusCode, 403);
    final crossShopWrite = await _request(
      client,
      baseUrl,
      'PUT',
      '/api/shops/$shopB/settings',
      token: adminAToken,
      body: {'phone': '+1 555 999 0000', 'updatedAt': 'unused'},
    );
    expect(crossShopWrite.statusCode, 403);

    final secondDeviceToken = await login(
      'admin-$shopA',
      'shop-password',
      shopA,
    );
    final refreshed = await _request(
      client,
      baseUrl,
      'GET',
      '/api/shops/$shopA/settings',
      token: secondDeviceToken,
    );
    expect((jsonDecode(refreshed.body) as Map)['phone'], '+1 (555) 777-8888');

    final superAdminEdit = await _request(
      client,
      baseUrl,
      'PUT',
      '/api/shops/$shopA/settings',
      token: superToken,
      body: {
        'ownerName': 'Super Admin Name',
        'address': 'Super Admin Address',
        'contact': '+1 555 333 4444',
        'username': 'admin-$shopA',
      },
    );
    expect(superAdminEdit.statusCode, 200, reason: superAdminEdit.body);
    final canonical = jsonDecode(superAdminEdit.body) as Map<String, dynamic>;
    expect(canonical['ownerName'], 'Super Admin Name');
    expect(canonical['address'], 'Super Admin Address');

    final foreignPhone = await _request(
      client,
      baseUrl,
      'PUT',
      '/api/shops/$shopB/settings',
      token: adminBToken,
      body: {'phone': 'invalid', 'updatedAt': 'unused'},
    );
    expect(foreignPhone.statusCode, 400);
  });
}
