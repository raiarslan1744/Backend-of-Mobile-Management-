import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../bin/server.dart';

void main() {
  final hasDatabase = (Platform.environment['TEST_DATABASE_URL'] ?? Platform.environment['DATABASE_URL']) != null &&
      (Platform.environment['TEST_DATABASE_URL'] ?? Platform.environment['DATABASE_URL'] ?? '').trim().isNotEmpty;

  if (!hasDatabase) {
    test('PostgreSQL integration tests are skipped when TEST_DATABASE_URL is not configured.', () {
      expect(true, isTrue);
    });
    return;
  }

  const port = 8080;
  late ServerApp server;

  setUp(() async {
    await ServerApp.stopAll();
    server = await ServerApp.start(port: port);
    await server.listen(port: port);
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });

  tearDown(() async {
    await server.close();
    await ServerApp.stopAll();
  });

  group('cloud backend', () {
    test('shop admin can log in and sync data to a second device', () async {
      final shopId = 'SHOP-${DateTime.now().microsecondsSinceEpoch}';
      const username = 'ali';
      const password = 'admin123';

      final createShopResponse = await http.post(
        Uri.parse('http://127.0.0.1:8080/api/shops'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'shopId': shopId,
          'ownerName': 'Ali',
          'contact': '12345',
          'address': 'Main Street',
          'username': username,
          'password': password,
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
        {'id': 'prod-1', 'name': 'Samsung A15', 'quantity': 5, 'price': 23000, 'updatedAt': DateTime.now().toUtc().toIso8601String()},
        {'id': 'prod-2', 'name': 'PowerBank', 'quantity': 12, 'price': 1500, 'updatedAt': DateTime.now().toUtc().toIso8601String()},
      ];

      final uploadA = await http.post(
        Uri.parse('http://127.0.0.1:8080/api/sync/upload'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $tokenA',
        },
        body: jsonEncode({
          'items': productsA.map((product) => {
            'id': 'sync-${product['id']}',
            'shopId': shopId,
            'entityType': 'product',
            'entityId': product['id'],
            'operation': 'create',
            'data': product,
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          }).toList(),
        }),
      );
      expect(uploadA.statusCode, 200, reason: uploadA.body);

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
      expect(changes.any((change) => (change as Map<String, dynamic>)['entityType'] == 'product'), isTrue);
    });

    test('employee can log in to correct shop and shop isolation is enforced', () async {
      final shopId = 'SHOP-${DateTime.now().microsecondsSinceEpoch}';
      final otherShopId = 'SHOP-${DateTime.now().microsecondsSinceEpoch + 1}';
      const adminUser = 'ali';
      const adminPassword = 'admin123';

      final shopA = await http.post(
        Uri.parse('http://127.0.0.1:8080/api/shops'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'shopId': shopId,
          'ownerName': 'Ali',
          'contact': '12345',
          'address': 'Addr 1',
          'username': adminUser,
          'password': adminPassword,
        }),
      );
      expect(shopA.statusCode, 200);

      final shopB = await http.post(
        Uri.parse('http://127.0.0.1:8080/api/shops'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'shopId': otherShopId,
          'ownerName': 'Other',
          'contact': '67890',
          'address': 'Addr 2',
          'username': 'otheradmin',
          'password': 'otherpass',
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
      final adminToken = (jsonDecode(adminLogin.body) as Map<String, dynamic>)['authToken'] as String;

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

      final employeeToken = (jsonDecode(employeeLogin.body) as Map<String, dynamic>)['authToken'] as String;

      final baselineAccess = await http.get(
        Uri.parse('http://127.0.0.1:8080/api/sync/initial?shopId=$shopId'),
        headers: {'Authorization': 'Bearer $employeeToken'},
      );
      expect(baselineAccess.statusCode, 200);

      final crossShopAccess = await http.get(
        Uri.parse('http://127.0.0.1:8080/api/sync/initial?shopId=$otherShopId'),
        headers: {'Authorization': 'Bearer $employeeToken'},
      );
      expect(crossShopAccess.statusCode, 403);
    });
  });
}
