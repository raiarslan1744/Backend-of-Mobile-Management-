import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

String hashPassword(String password) {
  return sha256.convert(utf8.encode(password)).toString();
}

String utcNow() => DateTime.now().toUtc().toIso8601String();

class SuperAdminCredentials {
  const SuperAdminCredentials({required this.username, required this.password});

  final String username;
  final String password;
}

class SuperAdminUserSeedResult {
  const SuperAdminUserSeedResult({required this.shouldInsert, required this.existingUserId});

  final bool shouldInsert;
  final String? existingUserId;
}

SuperAdminCredentials resolveSuperAdminCredentials(Map<String, String> environment) {
  final username = environment['SUPER_ADMIN_USERNAME']?.trim() ?? '';
  final password = environment['SUPER_ADMIN_PASSWORD']?.trim() ?? '';
  if (username.isEmpty || password.isEmpty) {
    throw StateError('SUPER_ADMIN_USERNAME and SUPER_ADMIN_PASSWORD must be configured in the environment.');
  }
  return SuperAdminCredentials(username: username, password: password);
}

SuperAdminUserSeedResult resolveSuperAdminUserAction(List<Map<String, Object?>> existingUsers) {
  for (final row in existingUsers) {
    final role = row['role']?.toString() ?? '';
    final shopId = row['shop_id']?.toString() ?? '';
    if (role == 'super_admin' || shopId == 'SUPER_ADMIN') {
      return SuperAdminUserSeedResult(shouldInsert: false, existingUserId: row['id']?.toString());
    }
  }
  return const SuperAdminUserSeedResult(shouldInsert: true, existingUserId: null);
}

List<String> getShopCleanupTableOrder() => const [
  'sync_records',
  'products',
  'sales',
  'customers',
  'employees',
  'repairs',
  'debtors',
  'debt_transactions',
  'accessories',
  'mobile_devices',
  'purchases',
  'devices',
  'sessions',
  'users',
  'shops',
];

String? authTokenFromRequest(shelf.Request request) {
  final authHeader = request.headers['authorization'];
  if (authHeader == null || !authHeader.startsWith('Bearer ')) {
    return null;
  }
  return authHeader.substring('Bearer '.length).trim();
}

class DatabaseAdapter {
  DatabaseAdapter._({required this.postgresConnection});

  final Connection? postgresConnection;

  static Future<DatabaseAdapter> open() async {
    final databaseUrl = Platform.environment['DATABASE_URL'];
    if (databaseUrl == null || databaseUrl.trim().isEmpty) {
      throw StateError('DATABASE_URL is required for the production backend.');
    }

    final connection = await Connection.openFromUrl(databaseUrl);
    return DatabaseAdapter._(postgresConnection: connection);
  }

  Future<List<Map<String, Object?>>> select(String sql, [List<Object?> parameters = const []]) async {
    final normalized = _normalizeSql(sql, parameters);
    final result = await postgresConnection!.execute(
      normalized.sql,
      parameters: normalized.values,
    );
    return result.map((row) => Map<String, Object?>.from(row.toColumnMap())).toList(growable: false);
  }

  Future<void> execute(String sql, [List<Object?> parameters = const []]) async {
    final normalized = _normalizeSql(sql, parameters);
    await postgresConnection!.execute(
      normalized.sql,
      parameters: normalized.values,
    );
  }

  Future<void> dispose() async {
    await postgresConnection?.close();
  }

  ({String sql, List<Object?> values}) _normalizeSql(String sql, List<Object?> parameters) {
    final trimmed = sql.trim();
    if (parameters.isEmpty) {
      return (sql: trimmed, values: const []);
    }

    if (RegExp(r'\$\d+').hasMatch(trimmed)) {
      return (sql: trimmed, values: parameters);
    }

    var normalized = trimmed;
    final values = <Object?>[];
    var index = 0;
    normalized = normalized.replaceAllMapped(RegExp(r'\?'), (match) {
      index++;
      values.add(parameters[index - 1]);
      return '\$${index}';
    });
    return (sql: normalized, values: values);
  }
}

class ServerApp {
  ServerApp._(this.db);

  static ServerApp? _activeInstance;

  final DatabaseAdapter db;
  final Router router = Router();
  HttpServer? _httpServer;
  int? _port;

  static Future<ServerApp> start({String? dbPath, int? port}) async {
    final resolvedPort = port ?? int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;

    if (_activeInstance != null) {
      if (_activeInstance!._httpServer == null && _activeInstance!._port == resolvedPort) {
        await _activeInstance!.listen(port: resolvedPort);
      }
      return _activeInstance!;
    }

    final database = await DatabaseAdapter.open();
    final app = ServerApp._(database);
    await app._initializeSchema();
    app._registerRoutes();
    _activeInstance = app;
    await app.listen(host: InternetAddress.anyIPv4, port: resolvedPort);
    return app;
  }

  static Future<void> stopAll() async {
    if (_activeInstance == null) return;
    await _activeInstance!.close();
    _activeInstance = null;
  }

  Future<void> listen({dynamic host, int port = 8080}) async {
    if (_httpServer != null) {
      return;
    }
    final bindHost = host ?? InternetAddress.anyIPv4;
    _port = port;
    _httpServer = await shelf_io.serve(router.call, bindHost, port);
  }

  Future<void> close() async {
    if (_httpServer != null) {
      await _httpServer!.close(force: true);
      _httpServer = null;
    }
    _port = null;
    db.dispose();
  }

  Future<void> _initializeSchema() async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS shops (
        shop_id TEXT PRIMARY KEY,
        owner_name TEXT NOT NULL,
        contact TEXT NOT NULL,
        address TEXT NOT NULL,
        username TEXT NOT NULL,
        password_hash TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS super_admin (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        username TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY,
        username TEXT NOT NULL,
        password_hash TEXT NOT NULL,
        shop_id TEXT NOT NULL,
        role TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(shop_id, username)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        token TEXT NOT NULL UNIQUE,
        device_id TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS devices (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        shop_id TEXT NOT NULL,
        device_id TEXT NOT NULL,
        imei TEXT,
        device_name TEXT,
        device_type TEXT,
        created_at TEXT NOT NULL,
        last_seen_at TEXT NOT NULL,
        UNIQUE(shop_id, device_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_records (
        id TEXT PRIMARY KEY,
        shop_id TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        data TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS products (
        id TEXT PRIMARY KEY,
        shop_id TEXT NOT NULL,
        name TEXT NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 0,
        price REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sales (
        id TEXT PRIMARY KEY,
        shop_id TEXT NOT NULL,
        product_name TEXT NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 0,
        selling_total REAL NOT NULL DEFAULT 0,
        purchase_total REAL NOT NULL DEFAULT 0,
        imei TEXT,
        customer_name TEXT,
        customer_phone TEXT,
        customer_address TEXT,
        employee_id TEXT,
        employee_name TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS customers (
        id TEXT PRIMARY KEY,
        shop_id TEXT NOT NULL,
        name TEXT NOT NULL,
        contact TEXT,
        address TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS employees (
        id TEXT PRIMARY KEY,
        shop_id TEXT NOT NULL,
        username TEXT NOT NULL,
        password_hash TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'active',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        UNIQUE(shop_id, username)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS repairs (
        id TEXT PRIMARY KEY,
        shop_id TEXT NOT NULL,
        name TEXT NOT NULL,
        cost REAL NOT NULL DEFAULT 0,
        charge REAL NOT NULL DEFAULT 0,
        profit REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS debtors (
        id TEXT PRIMARY KEY,
        shop_id TEXT NOT NULL,
        customer_name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS debt_transactions (
        id TEXT PRIMARY KEY,
        shop_id TEXT NOT NULL,
        debtor_id TEXT NOT NULL,
        item TEXT NOT NULL,
        amount REAL NOT NULL DEFAULT 0,
        type TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS accessories (
        id TEXT PRIMARY KEY,
        shop_id TEXT NOT NULL,
        name TEXT NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 0,
        buy_price REAL NOT NULL DEFAULT 0,
        sell_price REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS mobile_devices (
        id TEXT PRIMARY KEY,
        shop_id TEXT NOT NULL,
        name TEXT NOT NULL,
        imei1 TEXT,
        imei2 TEXT,
        color TEXT,
        status TEXT NOT NULL DEFAULT 'available',
        buy_price REAL NOT NULL DEFAULT 0,
        sell_price REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchases (
        id TEXT PRIMARY KEY,
        shop_id TEXT NOT NULL,
        product_name TEXT NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 0,
        total_cost REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('CREATE INDEX IF NOT EXISTS idx_sync_records_shop_updated ON sync_records(shop_id, updated_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_records_entity_type ON sync_records(entity_type, entity_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_users_shop ON users(shop_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sessions_token ON sessions(token)');

    await _ensureTableColumns();
    await _seedSuperAdmin();
  }

  Future<void> _ensureTableColumns() async {
    await _ensureColumn('debt_transactions', 'shop_id', 'TEXT NOT NULL DEFAULT \"\"');
  }

  Future<bool> _tableExists(String tableName) async {
    final rows = await db.select(
      'SELECT EXISTS ( SELECT 1 FROM information_schema.tables WHERE table_schema = \$1 AND table_name = \$2 ) AS table_exists',
      ['public', tableName],
    );
    return rows.isNotEmpty && (rows.first['table_exists'] == true);
  }

  Future<void> _ensureColumn(String tableName, String columnName, String columnDefinition) async {
    if (!await _tableExists(tableName)) return;

    final rows = await db.select(
      'SELECT EXISTS ( SELECT 1 FROM information_schema.columns WHERE table_schema = \$1 AND table_name = \$2 AND column_name = \$3 ) AS column_exists',
      ['public', tableName, columnName],
    );
    if (rows.isNotEmpty && (rows.first['column_exists'] == true)) {
      return;
    }

    final quotedTable = _quoteIdentifier(tableName);
    final quotedColumn = _quoteIdentifier(columnName);
    await db.execute('ALTER TABLE $quotedTable ADD COLUMN IF NOT EXISTS $quotedColumn $columnDefinition');
  }

  String _quoteIdentifier(String identifier) {
    return '"${identifier.replaceAll('"', '""')}"';
  }

  void _registerRoutes() {
    router.get('/health', _health);
    router.get('/api/health', _health);
    router.get('/api/super-admin/shops', _listShops);
    router.post('/api/super-admin/shops', _createShop);
    router.delete('/api/super-admin/shops', _deleteShop);
    router.delete('/api/super-admin/shops/:shopId', _deleteShop);
    router.post('/api/shops', _createShop);
    router.post('/api/auth/login', _login);
    router.post('/api/auth/logout', _logout);
    router.get('/api/auth/validate-shop-access', _validateShopAccess);
    router.post('/api/auth/register-device', _registerDevice);
    router.post('/api/sync/upload', _uploadSync);
    router.post('/api/sync/download', _downloadSync);
    router.get('/api/sync/initial', _initialSync);
    router.post('/api/sync/conflict-report', _reportConflict);
    router.post('/api/employees', _createEmployee);
  }

  Future<void> _seedSuperAdmin() async {
    final config = resolveSuperAdminCredentials(Platform.environment);
    final now = utcNow();
    final passwordHash = hashPassword(config.password);

    final existingSuperAdmin = await db.select('SELECT id, username, password_hash FROM super_admin WHERE id = 1 LIMIT 1');
    if (existingSuperAdmin.isEmpty) {
      await db.execute(
        'INSERT INTO super_admin (id, username, password_hash, created_at, updated_at) VALUES (?, ?, ?, ?, ?) ON CONFLICT (id) DO UPDATE SET username = EXCLUDED.username, password_hash = EXCLUDED.password_hash, updated_at = EXCLUDED.updated_at',
        [1, config.username, passwordHash, now, now],
      );
    } else {
      await db.execute(
        'UPDATE super_admin SET username = ?, password_hash = ?, updated_at = ? WHERE id = 1',
        [config.username, passwordHash, now],
      );
    }

    final existingSuperAdminUsers = await db.select(
      'SELECT id, role, shop_id FROM users WHERE role = ? OR shop_id = ? ORDER BY created_at DESC LIMIT 1',
      ['super_admin', 'SUPER_ADMIN'],
    );
    final userAction = resolveSuperAdminUserAction(existingSuperAdminUsers);
    final stableUserId = userAction.existingUserId ?? 'SUPER_ADMIN';

    if (userAction.shouldInsert) {
      await db.execute(
        'INSERT INTO users (id, username, password_hash, shop_id, role, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT (id) DO UPDATE SET username = EXCLUDED.username, password_hash = EXCLUDED.password_hash, shop_id = EXCLUDED.shop_id, role = EXCLUDED.role, updated_at = EXCLUDED.updated_at',
        [stableUserId, config.username, passwordHash, 'SUPER_ADMIN', 'super_admin', now, now],
      );
      return;
    }

    await db.execute(
      'UPDATE users SET username = ?, password_hash = ?, shop_id = ?, role = ?, updated_at = ? WHERE id = ?',
      [config.username, passwordHash, 'SUPER_ADMIN', 'super_admin', now, stableUserId],
    );
  }

  Future<shelf.Response> _deleteShop(shelf.Request request) async {
    final auth = await _requireAuth(request);
    if (auth == null) {
      return shelf.Response(401, body: jsonEncode({'error': 'Unauthorized'}));
    }
    if (auth['user']['role'] != 'super_admin') {
      return shelf.Response(403, body: jsonEncode({'error': 'Super admin authorization required'}));
    }

    final shopId = request.params['shopId'] ?? (await _body(request))['shopId']?.toString() ?? '';
    if (shopId.trim().isEmpty) {
      return shelf.Response(400, body: jsonEncode({'error': 'shopId is required'}));
    }

    try {
      final rows = await db.select('SELECT shop_id FROM shops WHERE shop_id = ?', [shopId]);
      if (rows.isEmpty) {
        return shelf.Response(404, body: jsonEncode({'error': 'Shop not found', 'shopId': shopId}));
      }

      final userRows = await db.select('SELECT id FROM users WHERE shop_id = ?', [shopId]);
      final userIds = userRows.map<String>((row) => row['id'] as String).toList(growable: false);

      await db.execute('BEGIN');
      try {
        if (userIds.isNotEmpty) {
          final placeholders = List.filled(userIds.length, '?').join(', ');
          await db.execute('DELETE FROM sessions WHERE user_id IN ($placeholders)', userIds);
        }

        for (final tableName in getShopCleanupTableOrder()) {
          if (tableName == 'shops') {
            await db.execute('DELETE FROM shops WHERE shop_id = ?', [shopId]);
            continue;
          }
          if (tableName == 'sessions') {
            continue;
          }
          if (tableName == 'users') {
            await db.execute('DELETE FROM users WHERE shop_id = ?', [shopId]);
            continue;
          }
          if (tableName == 'devices') {
            await db.execute('DELETE FROM devices WHERE shop_id = ?', [shopId]);
            continue;
          }
          await db.execute('DELETE FROM "$tableName" WHERE shop_id = ?', [shopId]);
        }

        await db.execute('DELETE FROM shops WHERE shop_id = ?', [shopId]);
        await db.execute('COMMIT');
      } catch (_) {
        await db.execute('ROLLBACK');
        rethrow;
      }

      return shelf.Response.ok(jsonEncode({'success': true, 'shopId': shopId, 'message': 'Shop deleted successfully'}));
    } catch (error) {
      return shelf.Response(500, body: jsonEncode({'error': 'Failed to delete shop', 'details': error.toString()}));
    }
  }

  Future<shelf.Response> _health(shelf.Request request) async {
    return shelf.Response.ok(jsonEncode({'status': 'healthy', 'timestamp': utcNow(), 'database': 'connected'}));
  }

  Future<shelf.Response> _createShop(shelf.Request request) async {
    final auth = await _requireAuth(request);
    final isAuthorityRequest = request.url.pathSegments.contains('super-admin');
    if (isAuthorityRequest && auth == null) {
      return shelf.Response(401, body: jsonEncode({'error': 'Unauthorized'}));
    }
    if (isAuthorityRequest && auth != null && auth['user']['role'] != 'super_admin') {
      return shelf.Response(403, body: jsonEncode({'error': 'Super admin authorization required'}));
    }

    final body = await _body(request);
    final shopId = (body['shopId'] ?? body['shop_id'])?.toString() ?? '';
    final username = (body['username'] ?? 'admin').toString();
    final password = (body['password'] ?? 'admin123').toString();
    if (shopId.isEmpty) {
      return shelf.Response(400, body: jsonEncode({'error': 'shopId is required'}));
    }

    final existingShop = await db.select('SELECT shop_id FROM shops WHERE shop_id = ?', [shopId]);
    if (existingShop.isNotEmpty) {
      return shelf.Response(409, body: jsonEncode({'error': 'Shop already exists'}));
    }

    final now = utcNow();
    await db.execute(
      'INSERT INTO shops (shop_id, owner_name, contact, address, username, password_hash, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [shopId, (body['ownerName'] ?? 'Shop Owner').toString(), (body['contact'] ?? '').toString(), (body['address'] ?? '').toString(), username, hashPassword(password), now, now],
    );

    final userId = const Uuid().v4();
    await db.execute(
      'INSERT INTO users (id, username, password_hash, shop_id, role, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT (shop_id, username) DO NOTHING',
      [userId, username, hashPassword(password), shopId, 'admin', now, now],
    );

    return shelf.Response.ok(jsonEncode({'success': true, 'shopId': shopId, 'username': username}));
  }

  Future<shelf.Response> _listShops(shelf.Request request) async {
    final auth = await _requireAuth(request);
    if (auth == null) {
      return shelf.Response(401, body: jsonEncode({'error': 'Unauthorized'}));
    }
    if (auth['user']['role'] != 'super_admin') {
      return shelf.Response(403, body: jsonEncode({'error': 'Super admin authorization required'}));
    }
    final rows = await db.select('SELECT * FROM shops ORDER BY created_at DESC');
    return shelf.Response.ok(jsonEncode(rows.map((row) => {
      'shopId': row['shop_id'],
      'ownerName': row['owner_name'],
      'contact': row['contact'],
      'address': row['address'],
      'username': row['username'],
      'createdAt': row['created_at'],
      'updatedAt': row['updated_at'],
    }).toList()));
  }

  Future<shelf.Response> _login(shelf.Request request) async {
    final body = await _body(request);
    final username = body['username']?.toString() ?? '';
    final suppliedShopId = body['shopId']?.toString() ?? '';
    final password = body['password']?.toString() ?? '';
    final deviceId = body['deviceId']?.toString() ?? 'unknown-device';

    final superAdminRows = await db.select(
      'SELECT * FROM users WHERE username = ? AND role = ? AND password_hash = ?',
      [username, 'super_admin', hashPassword(password)],
    );
    final shopAdminRows = await db.select(
      'SELECT * FROM users WHERE username = ? AND shop_id = ? AND password_hash = ? AND role = ?',
      [username, suppliedShopId, hashPassword(password), 'admin'],
    );
    final shopCredentialRows = shopAdminRows.isEmpty
        ? await db.select(
            'SELECT * FROM shops WHERE username = ? AND shop_id = ? AND password_hash = ?',
            [username, suppliedShopId, hashPassword(password)],
          )
        : const <Map<String, Object?>>[];
    final employeeRows = await db.select(
      'SELECT * FROM employees WHERE username = ? AND shop_id = ? AND password_hash = ?',
      [username, suppliedShopId, hashPassword(password)],
    );
    if (superAdminRows.isEmpty && shopAdminRows.isEmpty && shopCredentialRows.isEmpty && employeeRows.isEmpty) {
      return shelf.Response(401, body: jsonEncode({'error': 'Invalid credentials', 'code': 'INVALID_CREDENTIALS'}));
    }

    final user = superAdminRows.isNotEmpty
        ? superAdminRows.first
        : (shopAdminRows.isNotEmpty
            ? shopAdminRows.first
            : (shopCredentialRows.isNotEmpty
                ? {
                    'id': 'shop:${shopCredentialRows.first['shop_id']}',
                    'username': shopCredentialRows.first['username'],
                    'shop_id': shopCredentialRows.first['shop_id'],
                    'role': 'admin',
                    'password_hash': shopCredentialRows.first['password_hash'],
                  }
                : {
            'id': employeeRows.first['id'],
            'username': employeeRows.first['username'],
            'shop_id': employeeRows.first['shop_id'],
            'role': 'employee',
            'password_hash': employeeRows.first['password_hash'],
          }));
    final shopId = user['shop_id']?.toString() ?? (superAdminRows.isNotEmpty ? 'SUPER_ADMIN' : suppliedShopId);
    final role = user['role']?.toString() ?? 'employee';
    if (role != 'super_admin' && suppliedShopId.isNotEmpty && suppliedShopId != shopId) {
      return shelf.Response(403, body: jsonEncode({'error': 'Shop ID does not match the authenticated user', 'code': 'SHOP_MISMATCH'}));
    }

    final token = const Uuid().v4();
    final now = utcNow();
    final expiresAt = DateTime.now().toUtc().add(const Duration(hours: 24)).toIso8601String();
    await db.execute(
      'INSERT INTO sessions (id, user_id, token, device_id, expires_at, created_at) VALUES (?, ?, ?, ?, ?, ?)',
      [const Uuid().v4(), user['id'] as String, token, deviceId, expiresAt, now],
    );

    final sessionPayload = {
      'userId': user['id'],
      'username': user['username'],
      'shopId': shopId,
      'role': role,
      'authToken': token,
      'expiresAt': expiresAt,
      'createdAt': now,
    };

    await db.execute(
      'INSERT INTO devices (id, user_id, shop_id, device_id, imei, device_name, device_type, created_at, last_seen_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT (shop_id, device_id) DO UPDATE SET user_id = EXCLUDED.user_id, imei = EXCLUDED.imei, device_name = EXCLUDED.device_name, device_type = EXCLUDED.device_type, last_seen_at = EXCLUDED.last_seen_at',
      [const Uuid().v4(), user['id'] as String, shopId, deviceId, deviceId, 'Flutter Client', 'windows', now, now],
    );

    return shelf.Response.ok(jsonEncode(sessionPayload));
  }

  Future<shelf.Response> _logout(shelf.Request request) async {
    final token = authTokenFromRequest(request);
    if (token == null) {
      return shelf.Response(401, body: jsonEncode({'error': 'Unauthorized'}));
    }
    await db.execute('DELETE FROM sessions WHERE token = ?', [token]);
    return shelf.Response.ok(jsonEncode({'success': true}));
  }

  Future<shelf.Response> _validateShopAccess(shelf.Request request) async {
    final auth = await _requireAuth(request);
    if (auth == null) {
      return shelf.Response(401, body: jsonEncode({'error': 'Unauthorized'}));
    }
    final shopId = request.url.queryParameters['shopId'] ?? '';
    final user = auth['user'];
    final hasAccess = user['shop_id'] == shopId || user['role'] == 'admin';
    final payload = {'hasAccess': hasAccess, 'shopId': shopId};
    return hasAccess
        ? shelf.Response.ok(jsonEncode(payload))
        : shelf.Response(403, body: jsonEncode(payload));
  }

  Future<shelf.Response> _registerDevice(shelf.Request request) async {
    final auth = await _requireAuth(request);
    if (auth == null) {
      return shelf.Response(401, body: jsonEncode({'error': 'Unauthorized'}));
    }
    final body = await _body(request);
    final deviceId = body['deviceId']?.toString() ?? '';
    final shopId = auth['user']['shop_id'] as String;
    final userId = auth['user']['id'] as String;
    final now = utcNow();
    await db.execute(
      'INSERT INTO devices (id, user_id, shop_id, device_id, imei, device_name, device_type, created_at, last_seen_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT (shop_id, device_id) DO UPDATE SET user_id = EXCLUDED.user_id, imei = EXCLUDED.imei, device_name = EXCLUDED.device_name, device_type = EXCLUDED.device_type, last_seen_at = EXCLUDED.last_seen_at',
      [const Uuid().v4(), userId, shopId, deviceId, body['imei']?.toString() ?? deviceId, body['deviceName']?.toString() ?? 'Flutter Client', body['deviceType']?.toString() ?? 'windows', now, now],
    );
    return shelf.Response.ok(jsonEncode({'registered': true, 'deviceId': deviceId}));
  }

  Future<shelf.Response> _uploadSync(shelf.Request request) async {
    final auth = await _requireAuth(request);
    if (auth == null) {
      return shelf.Response(401, body: jsonEncode({'error': 'Unauthorized'}));
    }

    final body = await _body(request);
    final items = body['items'] as List<dynamic>? ?? const [];
    final user = auth['user'];
    final now = utcNow();
    var synced = 0;
    final conflicts = <Map<String, dynamic>>[];

    for (final item in items) {
      final map = Map<String, dynamic>.from(item as Map<String, dynamic>);
      final shopId = map['shopId']?.toString() ?? user['shop_id'] as String;
      if (shopId != user['shop_id']) {
        conflicts.add({'error': 'Shop ID mismatch', 'entityId': map['entityId']});
        continue;
      }

      final entityType = map['entityType']?.toString() ?? 'unknown';
      final entityId = (map['entityId'] ?? map['id'])?.toString() ?? const Uuid().v4();
      final operation = map['operation']?.toString() ?? 'update';
      final data = Map<String, dynamic>.from(map['data'] as Map<String, dynamic>? ?? {});
      data['id'] = entityId;
      data['shop_id'] = shopId;
      final recordId = map['id']?.toString() ?? const Uuid().v4();
      final recordTs = (map['createdAt'] ?? now).toString();

      await db.execute('INSERT INTO sync_records (id, shop_id, entity_type, entity_id, operation, data, created_at, updated_at, is_deleted) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT (id) DO UPDATE SET shop_id = EXCLUDED.shop_id, entity_type = EXCLUDED.entity_type, entity_id = EXCLUDED.entity_id, operation = EXCLUDED.operation, data = EXCLUDED.data, updated_at = EXCLUDED.updated_at, is_deleted = EXCLUDED.is_deleted', [
        recordId,
        shopId,
        entityType,
        entityId,
        operation,
        jsonEncode(data),
        recordTs,
        recordTs,
        operation == 'delete' ? 1 : 0,
      ]);

      final applied = await _applyEntityRecord(shopId, entityType, entityId, operation, data, now);
      if (applied) {
        synced++;
      }
    }

    return shelf.Response.ok(jsonEncode({'itemsSynced': synced, 'itemsFailed': conflicts.length, 'timestamp': now, 'conflicts': conflicts}));
  }

  Future<shelf.Response> _downloadSync(shelf.Request request) async {
    final auth = await _requireAuth(request);
    if (auth == null) {
      return shelf.Response(401, body: jsonEncode({'error': 'Unauthorized'}));
    }

    final body = await _body(request);
    final lastSyncTime = body['lastSyncTime']?.toString() ?? '1970-01-01T00:00:00.000Z';
    final entityTypes = (body['entityTypes'] as List<dynamic>? ?? const []).map((e) => e.toString()).toList();
    final shopId = auth['user']['shop_id'] as String;

    final changeRows = await db.select(
      'SELECT * FROM sync_records WHERE shop_id = ? AND updated_at > ? ${entityTypes.isNotEmpty ? "AND entity_type IN (${List.filled(entityTypes.length, '?').join(', ')})" : ''} ORDER BY updated_at ASC LIMIT ?',
      [
        shopId,
        lastSyncTime,
        ...entityTypes,
        body['batchSize'] is int ? body['batchSize'] as int : 200,
      ],
    );

    final changes = <Map<String, dynamic>>[];
    for (final row in changeRows) {
      final payload = jsonDecode(row['data'] as String) as Map<String, dynamic>;
      payload['_id'] = row['entity_id'];
      payload['_type'] = row['entity_type'];
      payload['entityType'] = row['entity_type'];
      payload['shopId'] = row['shop_id'];
      payload['operation'] = row['operation'];
      payload['timestamp'] = row['updated_at'];
      changes.add(payload);
    }

    return shelf.Response.ok(jsonEncode({
      'changes': changes,
      'lastSyncTime': utcNow(),
      'hasMore': false,
      'totalCount': changes.length,
    }));
  }

  Future<shelf.Response> _initialSync(shelf.Request request) async {
    final auth = await _requireAuth(request);
    if (auth == null) {
      return shelf.Response(401, body: jsonEncode({'error': 'Unauthorized'}));
    }

    final shopId = request.url.queryParameters['shopId'] ?? auth['user']['shop_id'] as String;
    if (auth['user']['shop_id'] != shopId && auth['user']['role'] != 'admin') {
      return shelf.Response(403, body: jsonEncode({'error': 'Shop access denied'}));
    }

    final payload = <String, List<Map<String, dynamic>>>{
      'products': await _fetchTableRows('products', shopId),
      'sales': await _fetchTableRows('sales', shopId),
      'customers': await _fetchTableRows('customers', shopId),
      'employees': await _fetchTableRows('employees', shopId),
      'repairs': await _fetchTableRows('repairs', shopId),
      'debtors': await _fetchTableRows('debtors', shopId),
      'debt_transactions': await _fetchTableRows('debt_transactions', shopId),
      'accessories': await _fetchTableRows('accessories', shopId),
      'mobile_devices': await _fetchTableRows('mobile_devices', shopId),
      'purchases': await _fetchTableRows('purchases', shopId),
    };

    return shelf.Response.ok(jsonEncode(payload));
  }

  Future<shelf.Response> _reportConflict(shelf.Request request) async {
    final auth = await _requireAuth(request);
    if (auth == null) {
      return shelf.Response(401, body: jsonEncode({'error': 'Unauthorized'}));
    }
    final body = await _body(request);
    final conflict = body['conflict'] ?? {};
    final entityType = conflict['entityType']?.toString() ?? 'unknown';
    final entityId = conflict['entityId']?.toString() ?? 'unknown';
    final shopId = auth['user']['shop_id'] as String;
    final now = utcNow();
    await db.execute(
      'INSERT INTO sync_records (id, shop_id, entity_type, entity_id, operation, data, created_at, updated_at, is_deleted) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT (id) DO UPDATE SET shop_id = EXCLUDED.shop_id, entity_type = EXCLUDED.entity_type, entity_id = EXCLUDED.entity_id, operation = EXCLUDED.operation, data = EXCLUDED.data, updated_at = EXCLUDED.updated_at, is_deleted = EXCLUDED.is_deleted',
      [const Uuid().v4(), shopId, 'conflict', '$entityType:$entityId', 'conflict', jsonEncode(conflict), now, now, 0],
    );
    return shelf.Response.ok(jsonEncode({'resolved': true, 'entityType': entityType, 'entityId': entityId}));
  }

  Future<shelf.Response> _createEmployee(shelf.Request request) async {
    final auth = await _requireAuth(request);
    if (auth == null) {
      return shelf.Response(401, body: jsonEncode({'error': 'Unauthorized'}));
    }
    final user = auth['user'];
    if (user['role'] != 'admin') {
      return shelf.Response(403, body: jsonEncode({'error': 'Only admins can create employees'}));
    }
    final body = await _body(request);
    final username = body['username']?.toString() ?? '';
    final password = body['password']?.toString() ?? '';
    final shopId = (body['shopId'] ?? user['shop_id']).toString();
    if (username.isEmpty || password.isEmpty) {
      return shelf.Response(400, body: jsonEncode({'error': 'username and password required'}));
    }

    final employeeId = const Uuid().v4();
    final now = utcNow();
    final passwordHash = hashPassword(password);
    await db.execute(
      'INSERT INTO employees (id, shop_id, username, password_hash, status, created_at, updated_at, is_deleted) VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT (id) DO UPDATE SET shop_id = EXCLUDED.shop_id, username = EXCLUDED.username, password_hash = EXCLUDED.password_hash, status = EXCLUDED.status, updated_at = EXCLUDED.updated_at, is_deleted = EXCLUDED.is_deleted',
      [employeeId, shopId, username, passwordHash, body['status']?.toString() ?? 'active', now, now, 0],
    );
    await db.execute(
      'INSERT INTO users (id, username, password_hash, shop_id, role, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT (shop_id, username) DO UPDATE SET password_hash = EXCLUDED.password_hash, updated_at = EXCLUDED.updated_at, role = EXCLUDED.role',
      [employeeId, username, passwordHash, shopId, 'employee', now, now],
    );

    return shelf.Response.ok(jsonEncode({'success': true, 'employeeId': employeeId, 'shopId': shopId, 'username': username}));
  }

  Future<Map<String, dynamic>?> _requireAuth(shelf.Request request) async {
    final token = authTokenFromRequest(request);
    if (token == null) return null;
    final rows = await db.select('SELECT s.*, u.username, u.shop_id, u.role, u.password_hash FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token = ?', [token]);
    if (rows.isEmpty) return null;
    final session = rows.first;
    final expiresAt = session['expires_at'] as String;
    if (DateTime.parse(expiresAt).isBefore(DateTime.now().toUtc())) {
      await db.execute('DELETE FROM sessions WHERE token = ?', [token]);
      return null;
    }
    return {'token': token, 'user': session};
  }

  Future<Map<String, dynamic>> _body(shelf.Request request) async {
    final body = await request.readAsString();
    if (body.trim().isEmpty) {
      return <String, dynamic>{};
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> _fetchTableRows(String tableName, String shopId) async {
    final rows = await db.select('SELECT * FROM $tableName WHERE shop_id = ? AND is_deleted = 0 ORDER BY updated_at DESC', [shopId]);
    return rows.map((row) {
      final map = <String, dynamic>{};
      for (final entry in row.entries) {
        if (entry.key == 'password_hash') continue;
        map[entry.key] = entry.value;
      }
      if (map.containsKey('updated_at')) {
        map['updatedAt'] = map['updated_at'];
      }
      if (map.containsKey('created_at')) {
        map['createdAt'] = map['created_at'];
      }
      return map;
    }).toList(growable: false);
  }

  Future<bool> _applyEntityRecord(String shopId, String entityType, String entityId, String operation, Map<String, dynamic> data, String now) async {
    final cleaned = <String, dynamic>{};
    cleaned['id'] = entityId;
    cleaned['shop_id'] = shopId;
    cleaned['updated_at'] = data['updatedAt'] ?? data['updated_at'] ?? now;
    cleaned['created_at'] = data['createdAt'] ?? data['created_at'] ?? now;
    cleaned['is_deleted'] = operation == 'delete' ? 1 : 0;

    data.forEach((key, value) {
      if (key == 'id' || key == 'shopId' || key == '_id' || key == 'entityId' || key == 'entity_id') {
        return;
      }
      if (key == 'shop_id' || key == 'shopId') {
        cleaned['shop_id'] = shopId;
        return;
      }
      if (key == 'updatedAt' || key == 'updated_at') {
        cleaned['updated_at'] = value;
        return;
      }
      if (key == 'createdAt' || key == 'created_at') {
        cleaned['created_at'] = value;
        return;
      }
      if (key == 'password') {
        cleaned['password_hash'] = hashPassword(value.toString());
        return;
      }
      cleaned[key] = value;
    });

    try {
      switch (entityType.toLowerCase()) {
        case 'product':
          await _upsertEntity('products', cleaned, operation);
          return true;
        case 'sale':
          await _upsertEntity('sales', cleaned, operation);
          return true;
        case 'customer':
          await _upsertEntity('customers', cleaned, operation);
          return true;
        case 'employee':
          await _upsertEntity('employees', cleaned, operation);
          return true;
        case 'repair':
          await _upsertEntity('repairs', cleaned, operation);
          return true;
        case 'debtor':
          await _upsertEntity('debtors', cleaned, operation);
          return true;
        case 'accessory':
          await _upsertEntity('accessories', cleaned, operation);
          return true;
        case 'mobile_device':
          await _upsertEntity('mobile_devices', cleaned, operation);
          return true;
        case 'purchase':
          await _upsertEntity('purchases', cleaned, operation);
          return true;
        default:
          return false;
      }
    } catch (_) {
      return false;
    }
  }

  Future<void> _upsertEntity(String tableName, Map<String, dynamic> row, String operation) async {
    final columns = row.keys.toList();
    final quotedColumns = columns.map((column) => '"$column"').join(', ');
    final createClause = 'INSERT INTO "$tableName" ($quotedColumns) VALUES (${List.filled(columns.length, '?').join(', ')}) ON CONFLICT (id) DO UPDATE SET ${columns.map((column) => '"$column" = EXCLUDED."$column"').join(', ')}';
    final values = columns.map((column) => row[column]).toList();

    if (operation == 'delete') {
      await db.execute(
        'UPDATE $tableName SET is_deleted = 1, updated_at = ? WHERE id = ? AND shop_id = ?',
        [row['updated_at'] ?? utcNow(), row['id'], row['shop_id']],
      );
      return;
    }

    await db.execute(createClause, values);
  }
}

Future<void> main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final app = await ServerApp.start(port: port);
  await app.listen(host: InternetAddress.anyIPv4, port: port);
  final server = app._httpServer!;
  stderr.writeln('AK Mobile Shop backend listening on ${server.address.host}:${server.port}');
}
