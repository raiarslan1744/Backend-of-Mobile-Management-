import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

void main() {
  final databaseUrl = Platform.environment['DATABASE_URL'] ?? '';
  final uri = Uri.tryParse(databaseUrl);
  final isolated =
      uri?.host == '127.0.0.1' &&
      uri?.port == 55439 &&
      uri?.path == '/ak_unification_test';

  test(
    'bootstrap refuses missing or unexpected arguments before connecting',
    () async {
      for (final args in [
        <String>[],
        ['--unknown'],
        ['--initialize-database', '--extra'],
      ]) {
        final result = await Process.run(
          Platform.resolvedExecutable,
          ['run', 'bin/bootstrap.dart', ...args],
          environment: {
            'DATABASE_URL': 'postgresql://127.0.0.1:1/not-a-database',
          },
        );
        expect(result.exitCode, 64);
        expect(result.stderr, contains('No database changes performed'));
      }
    },
  );

  group(
    'isolated PostgreSQL production startup',
    () {
      late Connection database;
      Process? server;
      final output = StringBuffer();

      Future<void> stopServer() async {
        final running = server;
        server = null;
        if (running != null) {
          running.kill();
          await running.exitCode.timeout(const Duration(seconds: 10));
        }
      }

      Future<void> startServer(String url, int port) async {
        output.clear();
        server = await Process.start(
          Platform.resolvedExecutable,
          ['run', 'bin/server.dart'],
          environment: {
            'DATABASE_URL': url,
            'PORT': '$port',
            // These must never replace the existing database credentials.
            'SUPER_ADMIN_USERNAME': 'must-not-replace-existing-admin',
            'SUPER_ADMIN_PASSWORD': 'must-not-replace-existing-password',
          },
        );
        server!.stdout.transform(utf8.decoder).listen(output.write);
        server!.stderr.transform(utf8.decoder).listen(output.write);
        int? exitCode;
        unawaited(server!.exitCode.then((value) => exitCode = value));
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        while (DateTime.now().isBefore(deadline)) {
          if (exitCode != null) fail('Server exited ($exitCode): $output');
          try {
            final response = await http
                .get(Uri.parse('http://127.0.0.1:$port/health'))
                .timeout(const Duration(milliseconds: 500));
            if (response.statusCode == 200) return;
          } catch (_) {
            // The child is still compiling/starting.
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        fail('Server did not start: $output');
      }

      Future<Map<String, Object?>> snapshot() async {
        final result = <String, Object?>{};
        final schema = await database.execute('''
        SELECT 'column' AS kind, table_name AS name,
          column_name || ':' || data_type || ':' || is_nullable || ':' || COALESCE(column_default, '') AS definition
        FROM information_schema.columns WHERE table_schema = 'public'
        UNION ALL
        SELECT 'index', indexname, indexdef FROM pg_indexes WHERE schemaname = 'public'
        UNION ALL
        SELECT 'constraint', c.conname, pg_get_constraintdef(c.oid)
        FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace
        WHERE n.nspname = 'public'
        ORDER BY 1, 2, 3
      ''');
        result['schema'] = schema.map((row) => row.toList()).toList();
        final tables = await database.execute(
          "SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename",
        );
        for (final row in tables) {
          final table = row[0] as String;
          final quoted = table.replaceAll('"', '""');
          final rows = await database.execute(
            'SELECT to_jsonb(t)::text FROM "$quoted" t ORDER BY 1',
          );
          result[table] = rows.map((entry) => entry[0]).toList();
        }
        return result;
      }

      setUp(() async {
        if (!isolated) fail('Only the dedicated local fixture is permitted.');
        database = await Connection.openFromUrl(databaseUrl);
      });

      tearDown(() async {
        await stopServer();
        await database.close();
      });

      test('default entry point starts with read-only transactions and preserves all rows/schema', () async {
        final role =
            'startup_readonly_${DateTime.now().microsecondsSinceEpoch}';
        await database.execute('CREATE ROLE $role LOGIN');
        await database.execute(
          'ALTER ROLE $role SET default_transaction_read_only = on',
        );
        await database.execute(
          'GRANT CONNECT ON DATABASE ak_unification_test TO $role',
        );
        await database.execute('GRANT USAGE ON SCHEMA public TO $role');
        await database.execute(
          'GRANT SELECT ON ALL TABLES IN SCHEMA public TO $role',
        );
        final readOnlyUrl = uri!.replace(userInfo: role).toString();
        final readOnly = await Connection.openFromUrl(readOnlyUrl);
        try {
          expect(
            (await readOnly.execute('SHOW transaction_read_only')).single[0],
            'on',
          );
        } finally {
          await readOnly.close();
        }
        final before = await snapshot();
        await startServer(readOnlyUrl, 19082);
        for (final route in ['/health', '/api/health']) {
          final health = await http.get(
            Uri.parse('http://127.0.0.1:19082$route'),
          );
          expect(health.statusCode, 200);
        }
        await stopServer();
        expect(
          await snapshot(),
          equals(before),
          reason: 'Default startup must not alter schema or data.',
        );
      });

      test('writable default startup preserves persisted super-admin credentials and login', () async {
        final username = Platform.environment['SUPER_ADMIN_USERNAME']!;
        final password = Platform.environment['SUPER_ADMIN_PASSWORD']!;
        final before = await snapshot();
        await startServer(databaseUrl, 19083);
        expect(
          await snapshot(),
          equals(before),
          reason: 'Even with write privileges, startup must perform no writes.',
        );
        Future<http.Response> login(String user, String secret) => http.post(
          Uri.parse('http://127.0.0.1:19083/api/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'shopId': 'SUPER_ADMIN',
            'username': user,
            'password': secret,
            'deviceId': 'isolated-startup-test',
          }),
        );
        expect((await login(username, password)).statusCode, 200);
        expect(
          (await login(
            'must-not-replace-existing-admin',
            'must-not-replace-existing-password',
          )).statusCode,
          401,
        );
        final afterLogin = await snapshot();
        expect(afterLogin['super_admin'], equals(before['super_admin']));
        expect(afterLogin['users'], equals(before['users']));
      });
    },
    skip: isolated
        ? false
        : 'Dedicated localhost PostgreSQL fixture is not configured.',
  );
}
