import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../bin/server.dart';
import '../lib/sync_engine.dart';

void main() {
  final uri = Uri.tryParse(Platform.environment['DATABASE_URL'] ?? '');
  final isolated =
      uri?.host == '127.0.0.1' &&
      uri?.port == 55439 &&
      uri?.path == '/ak_unification_test';
  test(
    'isolated PostgreSQL HTTP sync, employee login, atomic failure and paginated replay',
    () async {
      if (!isolated)
        fail('Only the dedicated local test database is permitted.');
      final server = await ServerApp.start(port: 19081);
      addTearDown(() => ServerApp.stopAll());
      final base = 'http://127.0.0.1:19081';
      final shop = 'TEST-${DateTime.now().microsecondsSinceEpoch}';
      Future<http.Response> post(
        String path,
        Map<String, dynamic> body, [
        String? token,
      ]) => http.post(
        Uri.parse('$base$path'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );
      final created = await post('/api/shops', {
        'shopId': shop,
        'username': 'local-test-admin',
        'password': 'local-test-only',
        'ownerName': 'Isolated test',
        'licenseAssigned': true,
        'isLifetime': true,
      });
      expect(created.statusCode, 200, reason: created.body);
      final login = await post('/api/auth/login', {
        'shopId': shop,
        'username': 'local-test-admin',
        'password': 'local-test-only',
      });
      expect(login.statusCode, 200, reason: login.body);
      final loginData = jsonDecode(login.body) as Map;
      final session = (loginData['session'] ?? loginData) as Map;
      final token = session['authToken'] as String;
      final engine = SyncEngine(server.db);
      final now = DateTime.now().toUtc().toIso8601String();
      Map<String, dynamic> item(
        String type,
        String id,
        Map<String, dynamic> data,
      ) => {
        'shopId': shop,
        'entityType': type,
        'entityId': id,
        'operation': 'create',
        'createdAt': now,
        'data': {'created_at': now, 'updated_at': now, ...data},
      };
      final modelId = DateTime.now().microsecondsSinceEpoch.toString();
      final records = [
        item('mobile_model', modelId, {'name': 'Phone'}),
        item('supplier', modelId, {'name': 'Supplier'}),
        item('mobile_unit', modelId, {
          'mobile_model_id': modelId,
          'supplier_id': modelId,
          'imei_1': 'TEST-$modelId',
          'buy_price': 100,
        }),
        item('employee', 'e-$modelId', {
          'username': 'local-worker',
          'password_hash': hashPassword('test-worker'),
          'status': 'active',
        }),
        item('sale', 's-$modelId', {
          'product_name': 'Phone',
          'quantity': 1,
          'selling_total': 120,
          'purchase_total': 100,
          'sold_at': now,
          'employee_id': 'e-$modelId',
        }),
        item('debtor', 'd-$modelId', {
          'customer_name': 'Customer',
          'phone': '123',
          'address': 'Test',
        }),
        item('debt_transaction', 'dt-$modelId', {
          'debtor_id': 'd-$modelId',
          'item': 'Repair',
          'amount': 20,
          'type': 'debt',
        }),
      ];
      for (final record in records) {
        final response = await post('/api/sync/upload', {
          'items': [record],
        }, token);
        expect(response.statusCode, 200, reason: response.body);
        expect(
          (jsonDecode(response.body) as Map)['itemsSynced'],
          1,
          reason: '${record['entityType']}: ${response.body}',
        );
      }
      final initial = await http.get(
        Uri.parse('$base/api/sync/initial?shopId=$shop'),
        headers: {'Authorization': 'Bearer $token'},
      );
      expect(initial.statusCode, 200, reason: initial.body);
      final snapshot = jsonDecode(initial.body) as Map;
      expect(snapshot['mobile_models'], hasLength(1));
      expect(snapshot['suppliers'], hasLength(1));
      expect(snapshot['sales'], hasLength(1));
      expect(
        (snapshot['employees'] as List).single.containsKey('password_hash'),
        false,
      );
      final employeeLogin = await post('/api/auth/login', {
        'shopId': shop,
        'username': 'local-worker',
        'password': 'test-worker',
      });
      expect(employeeLogin.statusCode, 200, reason: employeeLogin.body);
      final employeeSession = jsonDecode(employeeLogin.body) as Map;
      final employeeToken =
          ((employeeSession['session'] ?? employeeSession) as Map)['authToken']
              as String;
      final employeeAccess = await http.get(
        Uri.parse('$base/api/sync/protocol'),
        headers: {'Authorization': 'Bearer $employeeToken'},
      );
      expect(employeeAccess.statusCode, 200);
      final before = (await engine.download(shop))['totalCount'];
      await expectLater(
        engine.upload(shop, 'admin', item('sale', 'invalid-$modelId', {})),
        throwsA(anything),
      );
      expect((await engine.download(shop))['totalCount'], before);
      final ids = <String>{};
      String? cursor;
      var pages = 0;
      while (true) {
        final result = await engine.download(shop, cursor: cursor, limit: 2);
        pages++;
        ids.addAll(
          (result['changes'] as List).map((r) => '${r['_type']}:${r['id']}'),
        );
        cursor = result['nextCursor'] as String?;
        if (result['hasMore'] != true) break;
      }
      expect(ids, hasLength(7));
      expect(pages, 4);
      final collision = await engine.upload('different-shop', 'admin', {
        ...records.first,
        'shopId': 'different-shop',
      });
      expect(collision['code'], 'ID_COLLISION');
    },
    skip: !isolated
        ? 'Dedicated localhost PostgreSQL test cluster is not configured.'
        : false,
  );
}
