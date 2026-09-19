import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

import '../lib/sync_engine.dart';

String hashPassword(String password) {
  return sha256.convert(utf8.encode(password)).toString();
}

String utcNow() => DateTime.now().toUtc().toIso8601String();

class SuperAdminCredentials {
  const SuperAdminCredentials({required this.username, required this.password});

  final String username;
  final String password;
}

SuperAdminCredentials resolveSuperAdminCredentials(
  Map<String, String> environment,
) {
  final username = environment['SUPER_ADMIN_USERNAME']?.trim() ?? '';
  final password = environment['SUPER_ADMIN_PASSWORD']?.trim() ?? '';
  if (username.isEmpty || password.isEmpty) {
    throw StateError(
      'SUPER_ADMIN_USERNAME and SUPER_ADMIN_PASSWORD must be configured in the environment.',
    );
  }
  return SuperAdminCredentials(username: username, password: password);
}

class SuperAdminUserAction {
  const SuperAdminUserAction({required this.shouldInsert, this.existingUserId});

  final bool shouldInsert;
  final String? existingUserId;
}

SuperAdminUserAction resolveSuperAdminUserAction(
  List<Map<String, Object?>> users,
) {
  final existing = users.cast<Map<String, Object?>>().where(
    (user) => user['role'] == 'super_admin' && user['shop_id'] == 'SUPER_ADMIN',
  );
  if (existing.isEmpty) {
    return const SuperAdminUserAction(shouldInsert: true);
  }
  return SuperAdminUserAction(
    shouldInsert: false,
    existingUserId: existing.first['id']?.toString(),
  );
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
  'mobile_units',
  'mobile_models',
  'mobile_devices',
  'suppliers',
  'purchases',
  'returns',
  'bill_number_sequence',
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

class DatabaseAdapter implements SyncDatabase {
  DatabaseAdapter._(this.postgresConnection);

  final Connection postgresConnection;
  static final _transactionKey = Object();
  Session get _session =>
      Zone.current[_transactionKey] as Session? ?? postgresConnection;
  final _columnCache = <String, Map<String, String>>{};

  @override
  Future<T> syncTransaction<T>(Future<T> Function() action) =>
      postgresConnection.runTx(
        (transaction) => runZoned(() async {
          await transaction.execute('SELECT pg_advisory_xact_lock(825017431)');
          return action();
        }, zoneValues: {_transactionKey: transaction}),
      );

  @override
  Future<Map<String, String>> columns(String table) async {
    if (_columnCache.containsKey(table)) return _columnCache[table]!;
    final rows = await select(
      'SELECT column_name,data_type FROM information_schema.columns WHERE table_schema=? AND table_name=?',
      ['public', table],
    );
    return _columnCache[table] = {
      for (final row in rows)
        row['column_name'] as String: row['data_type'] as String,
    };
  }

  static Future<DatabaseAdapter> open() async {
    final databaseUrl = Platform.environment['DATABASE_URL'];
    if (databaseUrl == null || databaseUrl.trim().isEmpty) {
      throw StateError('DATABASE_URL is required for the production backend');
    }
    final connection = await Connection.openFromUrl(databaseUrl);
    return DatabaseAdapter._(connection);
  }

  Future<List<Map<String, Object?>>> select(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    final normalized = _normalizeSql(sql, parameters);
    final result = await _session.execute(
      normalized.sql,
      parameters: normalized.values,
    );
    return result
        .map((row) => Map<String, Object?>.from(row.toColumnMap()))
        .toList(growable: false);
  }

  Future<void> execute(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    final normalized = _normalizeSql(sql, parameters);
    await _session.execute(normalized.sql, parameters: normalized.values);
  }

  Future<void> dispose() async {
    await postgresConnection.close();
  }

  ({String sql, List<Object?> values}) _normalizeSql(
    String sql,
    List<Object?> parameters,
  ) {
    var normalized = _postgresify(sql);
    final values = <Object?>[];
    if (parameters.isNotEmpty) {
      var index = 0;
      normalized = normalized.replaceAllMapped(RegExp(r'\?'), (match) {
        index++;
        values.add(parameters[index - 1]);
        return '\$$index';
      });
    }
    return (sql: normalized, values: values);
  }

  String _postgresify(String sql) {
    var normalized = sql.trim();
    normalized = normalized.replaceAll(
      RegExp(r'\bAUTOINCREMENT\b', caseSensitive: false),
      '',
    );
    normalized = normalized.replaceAll(
      RegExp(r'\bINTEGER PRIMARY KEY\b', caseSensitive: false),
      'BIGSERIAL PRIMARY KEY',
    );
    normalized = normalized.replaceAll(
      RegExp(r'\bCURRENT_TIMESTAMP\b', caseSensitive: false),
      'NOW()',
    );
    normalized = _rewriteInsertOrReplace(normalized);
    normalized = _rewriteInsertOrIgnore(normalized);
    return normalized;
  }

  String _rewriteInsertOrReplace(String sql) {
    final match = RegExp(
      r'INSERT\s+OR\s+REPLACE\s+INTO\s+(\w+)\s*\(([^)]+)\)\s*VALUES\s*\((.*)\)',
      caseSensitive: false,
    ).firstMatch(sql);
    if (match == null) {
      return sql;
    }

    final table = match.group(1)!;
    final columns = match
        .group(2)!
        .split(',')
        .map((column) => column.trim())
        .where((column) => column.isNotEmpty)
        .toList();
    final values = match.group(3)!;
    final assignments = columns
        .where((column) => column.toLowerCase() != 'id')
        .map((column) => '"$column" = EXCLUDED."$column"')
        .join(', ');
    return 'INSERT INTO "$table" (${columns.map((column) => '"$column"').join(', ')}) VALUES ($values) ON CONFLICT ("id") DO UPDATE SET $assignments';
  }

  String _rewriteInsertOrIgnore(String sql) {
    final match = RegExp(
      r'INSERT\s+OR\s+IGNORE\s+INTO\s+(\w+)\s*\(([^)]+)\)\s*VALUES\s*\((.*)\)',
      caseSensitive: false,
    ).firstMatch(sql);
    if (match == null) {
      return sql;
    }

    final table = match.group(1)!;
    final columns = match
        .group(2)!
        .split(',')
        .map((column) => column.trim())
        .where((column) => column.isNotEmpty)
        .toList();
    final values = match.group(3)!;
    return 'INSERT INTO "$table" (${columns.map((column) => '"$column"').join(', ')}) VALUES ($values) ON CONFLICT DO NOTHING';
  }
}

class ServerApp {
  ServerApp._(this.dbPath, this.db);

  static ServerApp? _activeInstance;

  final String dbPath;
  final DatabaseAdapter db;
  final Router router = Router();
  HttpServer? _httpServer;
  int? _port;

  static Future<ServerApp> start({String? dbPath, int? port}) async {
    final resolvedPort =
        port ?? int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;

    if (_activeInstance != null) {
      if (_activeInstance!._httpServer == null &&
          _activeInstance!._port == resolvedPort) {
        await _activeInstance!.listen(port: resolvedPort);
      }
      return _activeInstance!;
    }

    final database = await DatabaseAdapter.open();
    final app = ServerApp._(dbPath ?? 'postgresql', database);
    // Normal API startup only connects to an existing database.
    // Schema and super-admin setup require the separate explicit bootstrap.
    app._registerRoutes();
    _activeInstance = app;
    await app.listen(host: InternetAddress.anyIPv4, port: resolvedPort);
    return app;
  }

  /// Mutates the configured database; only call for explicitly authorized setup.
  /// Normal API startup never invokes this method.
  static Future<void> initializeDatabaseForSetup() async {
    final database = await DatabaseAdapter.open();
    try {
      await ServerApp._('postgresql', database)._initializeSchema();
    } finally {
      await database.dispose();
    }
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
        status TEXT NOT NULL DEFAULT 'active',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        license_start_date TEXT,
        license_expiry_date TEXT,
        is_lifetime BOOLEAN NOT NULL DEFAULT FALSE
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

    await _seedSuperAdmin();

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
    try {
      await db.execute(
        'ALTER TABLE debt_transactions ADD COLUMN shop_id TEXT NOT NULL DEFAULT ""',
      );
    } catch (_) {}

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

    // New tables for inventory workflow
    await db.execute('''
      CREATE TABLE IF NOT EXISTS mobile_models (
        id BIGSERIAL PRIMARY KEY,
        shop_id TEXT NOT NULL,
        name TEXT NOT NULL,
        image TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS mobile_units (
        id BIGSERIAL PRIMARY KEY,
        shop_id TEXT NOT NULL,
        mobile_model_id BIGINT NOT NULL,
        imei_1 TEXT NOT NULL,
        imei_2 TEXT,
        buy_price REAL NOT NULL DEFAULT 0,
        ram TEXT,
        storage TEXT,
        supplier_id BIGINT,
        status TEXT NOT NULL DEFAULT 'available' CHECK (status IN ('available', 'sold', 'returned')),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await _ensureColumn(
      'mobile_units',
      'is_deleted',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute(
      'ALTER TABLE mobile_units DROP CONSTRAINT IF EXISTS mobile_units_imei_1_key',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS mobile_units_active_imei1 ON mobile_units(shop_id, imei_1) WHERE is_deleted = 0',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS mobile_units_active_imei2 ON mobile_units(shop_id, imei_2) WHERE is_deleted = 0 AND imei_2 IS NOT NULL',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS mobile_devices_active_imei1 ON mobile_devices(shop_id, imei1) WHERE is_deleted = 0 AND imei1 IS NOT NULL',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS mobile_devices_active_imei2 ON mobile_devices(shop_id, imei2) WHERE is_deleted = 0 AND imei2 IS NOT NULL',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS suppliers (
        id BIGSERIAL PRIMARY KEY,
        shop_id TEXT NOT NULL,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS bill_number_sequence (
        shop_id TEXT PRIMARY KEY,
        next_number BIGINT NOT NULL DEFAULT 1,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS returns (
        id BIGSERIAL PRIMARY KEY,
        shop_id TEXT NOT NULL,
        sale_id TEXT,
        sale_item_id BIGINT,
        mobile_unit_id BIGINT,
        bill_number TEXT,
        returned_at TEXT NOT NULL,
        return_reason TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await _ensureColumn('sales', 'bill_number', 'TEXT');
    await _ensureColumn('sales', 'product_id', 'TEXT');
    await _ensureColumn('sales', 'sold_at', 'TEXT');
    await _ensureColumn('purchases', 'product_id', 'TEXT');
    await _ensureColumn('purchases', 'purchased_at', 'TEXT');
    await _ensureColumn('returns', 'sale_amount', 'REAL NOT NULL DEFAULT 0');
    await _ensureColumn(
      'returns',
      'purchase_amount',
      'REAL NOT NULL DEFAULT 0',
    );
    await _ensureColumn(
      'mobile_models',
      'is_deleted',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureColumn('mobile_models', 'deleted_at', 'TEXT');
    await _ensureTableColumns();
  }

  Future<void> _ensureTableColumns() async {
    await _ensureColumn(
      'debt_transactions',
      'shop_id',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumn('shops', 'status', "TEXT NOT NULL DEFAULT 'active'");
    await _ensureColumn('shops', 'license_start_date', 'TEXT');
    await _ensureColumn('shops', 'license_expiry_date', 'TEXT');
    await _ensureColumn('shops', 'license_assigned', 'BOOLEAN');
    await _ensureColumn(
      'shops',
      'is_lifetime',
      'BOOLEAN NOT NULL DEFAULT FALSE',
    );
  }

  Future<bool> _tableExists(String tableName) async {
    final rows = await db.select(
      'SELECT table_name FROM information_schema.tables WHERE table_schema = ? AND table_name = ?',
      ['public', tableName],
    );
    return rows.isNotEmpty;
  }

  Future<void> _ensureColumn(
    String tableName,
    String columnName,
    String columnDefinition,
  ) async {
    if (!await _tableExists(tableName)) return;
    final columns = await db.select(
      'SELECT column_name FROM information_schema.columns WHERE table_schema = ? AND table_name = ? AND column_name = ?',
      ['public', tableName, columnName],
    );
    final exists = columns.isNotEmpty;
    if (!exists) {
      await db.execute(
        'ALTER TABLE $tableName ADD COLUMN $columnName $columnDefinition',
      );
    }
  }

  void _registerRoutes() {
    router.get('/health', _health);
    router.get('/api/health', _health);
    router.get('/api/super-admin/shops', _listShops);
    router.post('/api/super-admin/shops', _createShop);
    router.post('/api/super-admin/shops/<shopId>/license', _renewShopLicense);
    router.delete('/api/super-admin/shops/<shopId>', _deleteShop);
    router.post('/api/shops', _createShop);
    router.post('/api/auth/login', _login);
    router.post('/api/auth/logout', _logout);
    router.get('/api/auth/validate-shop-access', _validateShopAccess);
    router.post('/api/auth/register-device', _registerDevice);
    router.post('/api/sync/upload', _uploadSync);
    router.get('/api/sync/protocol', (shelf.Request request) async {
      if (await _requireAuth(request) == null) return shelf.Response(401);
      return shelf.Response.ok(jsonEncode({'version': 2}));
    });
    router.post('/api/sync/download', _downloadSync);
    router.get('/api/sync/initial', _initialSync);
    router.post('/api/sync/conflict-report', _reportConflict);
    router.post('/api/employees', _createEmployee);

    // New inventory workflow endpoints
    router.post('/api/mobile-models', _createMobileModel);
    router.get('/api/mobile-models', _getMobileModels);
    router.post('/api/mobile-units', _createMobileUnit);
    router.get('/api/mobile-units', _getMobileUnits);
    router.post('/api/suppliers', _createSupplier);
    router.get('/api/suppliers', _getSuppliers);
    router.post('/api/returns', _createReturn);
    router.get('/api/returns', _getReturns);
    router.get('/api/bill-number', _generateBillNumber);
  }

  Future<void> _seedSuperAdmin() async {
    final config = resolveSuperAdminCredentials(Platform.environment);
    final now = utcNow();
    final passwordHash = hashPassword(config.password);
    await db.execute(
      'INSERT INTO super_admin (id, username, password_hash, created_at, updated_at) VALUES (?, ?, ?, ?, ?) ON CONFLICT (id) DO UPDATE SET username = EXCLUDED.username, password_hash = EXCLUDED.password_hash, updated_at = EXCLUDED.updated_at',
      [1, config.username, passwordHash, now, now],
    );
    final existingUsers = await db.select(
      'SELECT id, role, shop_id FROM users WHERE shop_id = ? AND role = ?',
      ['SUPER_ADMIN', 'super_admin'],
    );
    final action = resolveSuperAdminUserAction(existingUsers);
    if (action.existingUserId != null) {
      await db.execute(
        'UPDATE users SET username = ?, password_hash = ?, updated_at = ? WHERE id = ?',
        [config.username, passwordHash, now, action.existingUserId],
      );
    } else {
      await db.execute(
        'INSERT INTO users (id, username, password_hash, shop_id, role, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          const Uuid().v4(),
          config.username,
          passwordHash,
          'SUPER_ADMIN',
          'super_admin',
          now,
          now,
        ],
      );
    }
  }

  Future<shelf.Response> _health(shelf.Request request) async {
    return shelf.Response.ok(
      jsonEncode({
        'status': 'healthy',
        'timestamp': utcNow(),
        'database': 'connected',
      }),
    );
  }

  Future<shelf.Response> _deleteShop(shelf.Request request) async {
    final deleteStartedAt = DateTime.now();
    print('DELETE REQUEST RECEIVED elapsedMs=0');
    final shopId = request.params['shopId']?.trim() ?? '';
    print(
      'DELETE START shopId=$shopId elapsedMs=${DateTime.now().difference(deleteStartedAt).inMilliseconds}',
    );

    final auth = await _requireAuth(request);
    if (auth == null) {
      print(
        'DELETE AUTH FAILED shopId=$shopId elapsedMs=${DateTime.now().difference(deleteStartedAt).inMilliseconds}',
      );
      return shelf.Response(401, body: jsonEncode({'error': 'Unauthorized'}));
    }
    print(
      'DELETE AUTH VERIFIED shopId=$shopId elapsedMs=${DateTime.now().difference(deleteStartedAt).inMilliseconds}',
    );
    if (auth['user']['role'] != 'super_admin') {
      print('DELETE FAILURE shopId=$shopId status=403 category=forbidden');
      return shelf.Response(
        403,
        body: jsonEncode({'error': 'Super admin authorization required'}),
      );
    }
    if (shopId.isEmpty || shopId == 'SUPER_ADMIN') {
      print(
        'DELETE FAILURE shopId=$shopId status=400 category=invalid_shop_id',
      );
      return shelf.Response(
        400,
        body: jsonEncode({'error': 'A valid shopId is required'}),
      );
    }

    try {
      final shopRows = await db.select(
        'SELECT shop_id FROM shops WHERE shop_id = ?',
        [shopId],
      );
      print(
        'DELETE SHOP LOOKUP COMPLETE shopId=$shopId rows=${shopRows.length} elapsedMs=${DateTime.now().difference(deleteStartedAt).inMilliseconds}',
      );
      if (shopRows.isEmpty) {
        print('DELETE FAILURE shopId=$shopId status=404 category=not_found');
        return shelf.Response(
          404,
          body: jsonEncode({'error': 'Shop not found', 'shopId': shopId}),
        );
      }

      print(
        'DELETE STARTING TRANSACTION shopId=$shopId elapsedMs=${DateTime.now().difference(deleteStartedAt).inMilliseconds}',
      );
      await db.execute('BEGIN');
      try {
        await db.execute("SET LOCAL lock_timeout = '5s'");
        await db.execute("SET LOCAL statement_timeout = '12s'");

        final escapedShopId = shopId.replaceAll("'", "''");
        print(
          'DELETE BATCH STARTED shopId=$shopId elapsedMs=${DateTime.now().difference(deleteStartedAt).inMilliseconds}',
        );
        await db.execute('''
          DO \$delete_shop\$
          DECLARE
            target_shop_id TEXT := '$escapedShopId';
            batch_started_at TIMESTAMPTZ := clock_timestamp();
            section_started_at TIMESTAMPTZ;
            deleted_count BIGINT;
          BEGIN
            RAISE NOTICE 'SHOP DELETE START shopId=%', target_shop_id;

            section_started_at := clock_timestamp();
            DELETE FROM sync_records WHERE shop_id = target_shop_id;
            GET DIAGNOSTICS deleted_count = ROW_COUNT;
            RAISE NOTICE 'SHOP DELETE section=sync_records rows=% elapsed_ms=%', deleted_count, EXTRACT(EPOCH FROM (clock_timestamp() - section_started_at)) * 1000;

            section_started_at := clock_timestamp();
            DELETE FROM mobile_units WHERE shop_id = target_shop_id;
            GET DIAGNOSTICS deleted_count = ROW_COUNT;
            RAISE NOTICE 'SHOP DELETE section=mobile_units rows=% elapsed_ms=%', deleted_count, EXTRACT(EPOCH FROM (clock_timestamp() - section_started_at)) * 1000;

            section_started_at := clock_timestamp();
            DELETE FROM mobile_devices WHERE shop_id = target_shop_id;
            GET DIAGNOSTICS deleted_count = ROW_COUNT;
            RAISE NOTICE 'SHOP DELETE section=mobile_devices rows=% elapsed_ms=%', deleted_count, EXTRACT(EPOCH FROM (clock_timestamp() - section_started_at)) * 1000;

            section_started_at := clock_timestamp();
            DELETE FROM sales WHERE shop_id = target_shop_id;
            GET DIAGNOSTICS deleted_count = ROW_COUNT;
            RAISE NOTICE 'SHOP DELETE section=sales rows=% elapsed_ms=%', deleted_count, EXTRACT(EPOCH FROM (clock_timestamp() - section_started_at)) * 1000;

            section_started_at := clock_timestamp();
            DELETE FROM returns WHERE shop_id = target_shop_id;
            GET DIAGNOSTICS deleted_count = ROW_COUNT;
            RAISE NOTICE 'SHOP DELETE section=returns rows=% elapsed_ms=%', deleted_count, EXTRACT(EPOCH FROM (clock_timestamp() - section_started_at)) * 1000;

            section_started_at := clock_timestamp();
            DELETE FROM purchases WHERE shop_id = target_shop_id;
            GET DIAGNOSTICS deleted_count = ROW_COUNT;
            RAISE NOTICE 'SHOP DELETE section=purchases rows=% elapsed_ms=%', deleted_count, EXTRACT(EPOCH FROM (clock_timestamp() - section_started_at)) * 1000;

            section_started_at := clock_timestamp();
            DELETE FROM accessories WHERE shop_id = target_shop_id;
            GET DIAGNOSTICS deleted_count = ROW_COUNT;
            RAISE NOTICE 'SHOP DELETE section=accessories rows=% elapsed_ms=%', deleted_count, EXTRACT(EPOCH FROM (clock_timestamp() - section_started_at)) * 1000;

            section_started_at := clock_timestamp();
            DELETE FROM products WHERE shop_id = target_shop_id;
            GET DIAGNOSTICS deleted_count = ROW_COUNT;
            RAISE NOTICE 'SHOP DELETE section=products rows=% elapsed_ms=%', deleted_count, EXTRACT(EPOCH FROM (clock_timestamp() - section_started_at)) * 1000;

            section_started_at := clock_timestamp();
            DELETE FROM customers WHERE shop_id = target_shop_id;
            GET DIAGNOSTICS deleted_count = ROW_COUNT;
            RAISE NOTICE 'SHOP DELETE section=customers rows=% elapsed_ms=%', deleted_count, EXTRACT(EPOCH FROM (clock_timestamp() - section_started_at)) * 1000;

            section_started_at := clock_timestamp();
            DELETE FROM repairs WHERE shop_id = target_shop_id;
            GET DIAGNOSTICS deleted_count = ROW_COUNT;
            RAISE NOTICE 'SHOP DELETE section=repairs rows=% elapsed_ms=%', deleted_count, EXTRACT(EPOCH FROM (clock_timestamp() - section_started_at)) * 1000;

            section_started_at := clock_timestamp();
            DELETE FROM debt_transactions WHERE shop_id = target_shop_id;
            GET DIAGNOSTICS deleted_count = ROW_COUNT;
            RAISE NOTICE 'SHOP DELETE section=debt_transactions rows=% elapsed_ms=%', deleted_count, EXTRACT(EPOCH FROM (clock_timestamp() - section_started_at)) * 1000;

            section_started_at := clock_timestamp();
            DELETE FROM debtors WHERE shop_id = target_shop_id;
            GET DIAGNOSTICS deleted_count = ROW_COUNT;
            RAISE NOTICE 'SHOP DELETE section=debtors rows=% elapsed_ms=%', deleted_count, EXTRACT(EPOCH FROM (clock_timestamp() - section_started_at)) * 1000;

            section_started_at := clock_timestamp();
            DELETE FROM employees WHERE shop_id = target_shop_id;
            GET DIAGNOSTICS deleted_count = ROW_COUNT;
            RAISE NOTICE 'SHOP DELETE section=employees rows=% elapsed_ms=%', deleted_count, EXTRACT(EPOCH FROM (clock_timestamp() - section_started_at)) * 1000;

            section_started_at := clock_timestamp();
            DELETE FROM devices WHERE shop_id = target_shop_id;
            GET DIAGNOSTICS deleted_count = ROW_COUNT;
            RAISE NOTICE 'SHOP DELETE section=devices rows=% elapsed_ms=%', deleted_count, EXTRACT(EPOCH FROM (clock_timestamp() - section_started_at)) * 1000;

            section_started_at := clock_timestamp();
            DELETE FROM sessions
              WHERE user_id IN (
                SELECT id FROM users WHERE shop_id = target_shop_id
              );
            GET DIAGNOSTICS deleted_count = ROW_COUNT;
            RAISE NOTICE 'SHOP DELETE section=sessions/users rows=% elapsed_ms=%', deleted_count, EXTRACT(EPOCH FROM (clock_timestamp() - section_started_at)) * 1000;

            section_started_at := clock_timestamp();
            DELETE FROM users WHERE shop_id = target_shop_id;
            GET DIAGNOSTICS deleted_count = ROW_COUNT;
            RAISE NOTICE 'SHOP DELETE section=users rows=% elapsed_ms=%', deleted_count, EXTRACT(EPOCH FROM (clock_timestamp() - section_started_at)) * 1000;

            section_started_at := clock_timestamp();
            DELETE FROM shops WHERE shop_id = target_shop_id;
            GET DIAGNOSTICS deleted_count = ROW_COUNT;
            RAISE NOTICE 'SHOP DELETE section=shops rows=% elapsed_ms=%', deleted_count, EXTRACT(EPOCH FROM (clock_timestamp() - section_started_at)) * 1000;

            RAISE NOTICE 'SHOP DELETE END shopId=% total_elapsed_ms=%', target_shop_id, EXTRACT(EPOCH FROM (clock_timestamp() - batch_started_at)) * 1000;
          END
          \$delete_shop\$;
        ''');
        print(
          'DELETE BATCH COMPLETE shopId=$shopId elapsedMs=${DateTime.now().difference(deleteStartedAt).inMilliseconds}',
        );
        await db.execute('COMMIT');
        print(
          'COMMIT COMPLETE shopId=$shopId elapsedMs=${DateTime.now().difference(deleteStartedAt).inMilliseconds}',
        );
      } catch (error, stackTrace) {
        await db.execute('ROLLBACK');
        print(
          'DATABASE CLEANUP FAILED shopId=$shopId type=${error.runtimeType} message=$error stackTrace=$stackTrace',
        );
        rethrow;
      }

      final elapsedMs = DateTime.now()
          .difference(deleteStartedAt)
          .inMilliseconds;
      print(
        'DELETE RESPONSE SENT shopId=$shopId status=200 elapsedMs=$elapsedMs',
      );
      return shelf.Response.ok(
        jsonEncode({
          'success': true,
          'shopId': shopId,
          'message': 'Shop deleted successfully',
        }),
      );
    } catch (error, stackTrace) {
      final elapsedMs = DateTime.now()
          .difference(deleteStartedAt)
          .inMilliseconds;
      print(
        'DELETE FAILURE shopId=$shopId status=500 category=server_error elapsedMs=$elapsedMs type=${error.runtimeType} message=$error stackTrace=$stackTrace',
      );
      return shelf.Response(
        500,
        body: jsonEncode({'error': 'Failed to delete shop'}),
      );
    }
  }

  Future<shelf.Response> _createShop(shelf.Request request) async {
    final auth = await _requireAuth(request);
    final isAuthorityRequest = request.url.pathSegments.contains('super-admin');
    if (isAuthorityRequest && auth == null) {
      return shelf.Response(401, body: jsonEncode({'error': 'Unauthorized'}));
    }
    if (isAuthorityRequest &&
        auth != null &&
        auth['user']['role'] != 'super_admin') {
      return shelf.Response(
        403,
        body: jsonEncode({'error': 'Super admin authorization required'}),
      );
    }

    final body = await _body(request);
    final shopId = (body['shopId'] ?? body['shop_id'])?.toString() ?? '';
    final username = (body['username'] ?? 'admin').toString();
    final password = (body['password'] ?? 'admin123').toString();
    final passwordHash = body['passwordHash']?.toString();
    print('CREATE SHOP CLICKED shopId=$shopId username=$username');
    if (shopId.isEmpty) {
      return shelf.Response(
        400,
        body: jsonEncode({'error': 'shopId is required'}),
      );
    }

    final existingShop = await db.select(
      'SELECT shop_id FROM shops WHERE shop_id = ?',
      [shopId],
    );
    if (existingShop.isNotEmpty) {
      return shelf.Response(
        409,
        body: jsonEncode({'error': 'Shop already exists'}),
      );
    }

    final now = utcNow();
    final resolvedHash = passwordHash ?? hashPassword(password);
    final licenseStartDate = body['licenseStartDate']?.toString() ?? now;
    final isLifetime = body['isLifetime'] == true;
    final licenseExpiryDate = isLifetime
        ? null
        : body['licenseExpiryDate']?.toString();
    if (body['licenseAssigned'] != true ||
        (!isLifetime &&
            (licenseExpiryDate == null ||
                DateTime.tryParse(licenseExpiryDate) == null))) {
      return shelf.Response(
        400,
        body: jsonEncode({'error': 'A valid assigned license is required'}),
      );
    }
    try {
      await db.execute(
        'INSERT INTO shops (shop_id, owner_name, contact, address, username, password_hash, status, license_start_date, license_expiry_date, is_lifetime, license_assigned, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          shopId,
          (body['ownerName'] ?? 'Shop Owner').toString(),
          (body['contact'] ?? '').toString(),
          (body['address'] ?? '').toString(),
          username,
          resolvedHash,
          body['status']?.toString() == 'suspended' ? 'suspended' : 'active',
          licenseStartDate,
          licenseExpiryDate,
          isLifetime,
          body['licenseAssigned'] == true ? true : null,
          now,
          now,
        ],
      );

      final userId = const Uuid().v4();
      await db.execute(
        'INSERT OR IGNORE INTO users (id, username, password_hash, shop_id, role, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [userId, username, resolvedHash, shopId, 'admin', now, now],
      );

      print('CREATE SHOP FINAL RESULT shopId=$shopId success=true');
      return shelf.Response.ok(
        jsonEncode({
          'success': true,
          'shopId': shopId,
          'username': username,
          'status': 'active',
          'licenseStartDate': licenseStartDate,
          'licenseExpiryDate': licenseExpiryDate,
          'isLifetime': isLifetime,
          'licenseAssigned': true,
        }),
      );
    } catch (error, stackTrace) {
      print(
        'CREATE SHOP FINAL RESULT shopId=$shopId success=false type=${error.runtimeType} message=$error stackTrace=$stackTrace',
      );
      return shelf.Response(
        500,
        body: jsonEncode({'error': 'Failed to create shop'}),
      );
    }
  }

  Future<shelf.Response> _listShops(shelf.Request request) async {
    final auth = await _requireAuth(request);
    if (auth == null) {
      return shelf.Response(401, body: jsonEncode({'error': 'Unauthorized'}));
    }
    if (auth['user']['role'] != 'super_admin') {
      return shelf.Response(
        403,
        body: jsonEncode({'error': 'Super admin authorization required'}),
      );
    }
    final rows = await db.select(
      'SELECT * FROM shops ORDER BY created_at DESC',
    );
    for (final row in rows) {
      final lifetime = row['is_lifetime'] == true || row['is_lifetime'] == 1;
      final expiry = DateTime.tryParse(
        row['license_expiry_date']?.toString() ?? '',
      );
      if (!lifetime &&
          expiry != null &&
          DateTime.now().toUtc().isAfter(expiry)) {
        row['status'] = 'suspended';
        await db.execute(
          'UPDATE shops SET status = ?, updated_at = ? WHERE shop_id = ?',
          ['suspended', utcNow(), row['shop_id']],
        );
      }
    }
    return shelf.Response.ok(
      jsonEncode(
        rows
            .map(
              (row) => {
                'shopId': row['shop_id'],
                'ownerName': row['owner_name'],
                'contact': row['contact'],
                'address': row['address'],
                'username': row['username'],
                'createdAt': row['created_at'],
                'updatedAt': row['updated_at'],
                'status': row['status'],
                'licenseStartDate': row['license_start_date'],
                'licenseExpiryDate': row['license_expiry_date'],
                'isLifetime':
                    row['is_lifetime'] == true || row['is_lifetime'] == 1,
                'licenseAssigned':
                    row['license_assigned'] == true ||
                    row['license_assigned'] == 1,
              },
            )
            .toList(),
      ),
    );
  }

  Future<shelf.Response> _renewShopLicense(shelf.Request request) async {
    final auth = await _requireAuth(request);
    if (auth == null || auth['user']['role'] != 'super_admin') {
      return shelf.Response(
        403,
        body: jsonEncode({'error': 'Super admin authorization required'}),
      );
    }
    final shopId = request.params['shopId']?.trim() ?? '';
    final body = await _body(request);
    final isLifetime = body['isLifetime'] == true;
    final expiry = isLifetime ? null : body['licenseExpiryDate']?.toString();
    if (!isLifetime && (expiry == null || DateTime.tryParse(expiry) == null)) {
      return shelf.Response(
        400,
        body: jsonEncode({'error': 'A valid license expiry date is required'}),
      );
    }
    final rows = await db.select(
      'SELECT shop_id FROM shops WHERE shop_id = ?',
      [shopId],
    );
    if (rows.isEmpty) {
      return shelf.Response(404, body: jsonEncode({'error': 'Shop not found'}));
    }
    await db.execute(
      'UPDATE shops SET status = ?, license_start_date = ?, license_expiry_date = ?, is_lifetime = ?, updated_at = ? WHERE shop_id = ?',
      [
        'active',
        body['licenseStartDate']?.toString() ?? utcNow(),
        expiry,
        isLifetime,
        utcNow(),
        shopId,
      ],
    );
    return shelf.Response.ok(jsonEncode({'success': true, 'shopId': shopId}));
  }

  Future<shelf.Response> _login(shelf.Request request) async {
    try {
      return await _loginInternal(request);
    } on FormatException catch (error, stackTrace) {
      print('AUTH_LOGIN_INVALID_REQUEST message=${error.message}');
      print('AUTH_LOGIN_INVALID_REQUEST_STACK $stackTrace');
      return shelf.Response(
        400,
        body: jsonEncode({
          'error': 'Request body must be a valid JSON object',
          'code': 'INVALID_REQUEST',
        }),
      );
    } catch (error, stackTrace) {
      final diagnosticMessage = error
          .toString()
          .replaceAll(
            RegExp(
              r'(?i)(password|token|secret|authorization)\s*[=:]\s*[^\s,}]+',
            ),
            r'$1=[redacted]',
          )
          .replaceAll(
            RegExp(r'Bearer\s+\S+', caseSensitive: false),
            'Bearer [redacted]',
          );
      print(
        'AUTH_LOGIN_EXCEPTION type=${error.runtimeType} message=$diagnosticMessage',
      );
      print('AUTH_LOGIN_STACK $stackTrace');
      return shelf.Response(
        500,
        body: jsonEncode({'error': 'Authentication server error'}),
      );
    }
  }

  Future<shelf.Response> _loginInternal(shelf.Request request) async {
    final body = await _body(request, rejectMalformed: true);
    final username = body['username']?.toString().trim() ?? '';
    final suppliedShopId = body['shopId']?.toString().trim() ?? '';
    final password = body['password']?.toString() ?? '';
    final deviceId = body['deviceId']?.toString() ?? 'unknown-device';
    if (username.isEmpty || password.isEmpty) {
      return shelf.Response(
        400,
        body: jsonEncode({
          'error': 'username and password are required',
          'code': 'MISSING_CREDENTIALS',
        }),
      );
    }
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
      "SELECT * FROM employees WHERE username = ? AND shop_id = ? AND password_hash = ? AND status = 'active' AND is_deleted = 0",
      [username, suppliedShopId, hashPassword(password)],
    );
    if (superAdminRows.isEmpty &&
        shopAdminRows.isEmpty &&
        shopCredentialRows.isEmpty &&
        employeeRows.isEmpty) {
      if (suppliedShopId.isEmpty) {
        return shelf.Response(
          400,
          body: jsonEncode({
            'error': 'shopId is required for shop users',
            'code': 'MISSING_SHOP_ID',
          }),
        );
      }
      return shelf.Response(
        401,
        body: jsonEncode({
          'error': 'Invalid credentials',
          'code': 'INVALID_CREDENTIALS',
        }),
      );
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
                        'password_hash':
                            shopCredentialRows.first['password_hash'],
                      }
                    : {
                        'id': employeeRows.first['id'],
                        'username': employeeRows.first['username'],
                        'shop_id': employeeRows.first['shop_id'],
                        'role': 'employee',
                        'password_hash': employeeRows.first['password_hash'],
                      }));
    final shopId =
        user['shop_id']?.toString() ??
        (superAdminRows.isNotEmpty ? 'SUPER_ADMIN' : suppliedShopId);
    final role = user['role']?.toString() ?? 'employee';
    if (role != 'super_admin') {
      final shopRows = await db.select(
        'SELECT status, license_assigned, license_expiry_date, is_lifetime FROM shops WHERE shop_id = ?',
        [shopId],
      );
      if (shopRows.isNotEmpty) {
        final shop = shopRows.first;
        final isLifetime =
            shop['is_lifetime'] == true || shop['is_lifetime'] == 1;
        final expiry = DateTime.tryParse(
          shop['license_expiry_date']?.toString() ?? '',
        );
        final expired =
            shop['license_assigned'] == true &&
            !isLifetime &&
            expiry != null &&
            DateTime.now().toUtc().isAfter(expiry);
        if (expired && shop['status'] != 'suspended') {
          await db.execute(
            'UPDATE shops SET status = ?, updated_at = ? WHERE shop_id = ?',
            ['suspended', utcNow(), shopId],
          );
        }
        if (shop['status'] == 'suspended' || expired) {
          return shelf.Response(
            403,
            body: jsonEncode({
              'error': 'Your shop license has expired. Please contact the administrator to renew your license.',
              'code': 'SHOP_LICENSE_EXPIRED',
            }),
          );
        }
      }
    }
    if (role != 'super_admin' &&
        suppliedShopId.isNotEmpty &&
        suppliedShopId != shopId) {
      return shelf.Response(
        403,
        body: jsonEncode({
          'error': 'Shop ID does not match the authenticated user',
          'code': 'SHOP_MISMATCH',
        }),
      );
    }

    final token = const Uuid().v4();
    final now = utcNow();
    final expiresAt = DateTime.now()
        .toUtc()
        .add(const Duration(hours: 24))
        .toIso8601String();
    await db.execute(
      'INSERT INTO sessions (id, user_id, token, device_id, expires_at, created_at) VALUES (?, ?, ?, ?, ?, ?)',
      [
        const Uuid().v4(),
        user['id'] as String,
        token,
        deviceId,
        expiresAt,
        now,
      ],
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
    if (role != 'super_admin') {
      final licenseRows = await db.select(
        'SELECT license_start_date, license_expiry_date, is_lifetime, license_assigned FROM shops WHERE shop_id = ?',
        [shopId],
      );
      if (licenseRows.isNotEmpty) {
        sessionPayload['licenseStartDate'] =
            licenseRows.first['license_start_date'];
        sessionPayload['licenseExpiryDate'] =
            licenseRows.first['license_expiry_date'];
        sessionPayload['isLifetime'] =
            licenseRows.first['is_lifetime'] == true ||
            licenseRows.first['is_lifetime'] == 1;
        sessionPayload['licenseAssigned'] =
            licenseRows.first['license_assigned'] == true ||
            licenseRows.first['license_assigned'] == 1;
        sessionPayload['licenseAssigned'] =
            licenseRows.first['license_start_date'] != null ||
            licenseRows.first['license_expiry_date'] != null ||
            sessionPayload['isLifetime'] == true;
      }
    }

    try {
      await db.execute(
        'INSERT INTO devices (id, user_id, shop_id, device_id, imei, device_name, device_type, created_at, last_seen_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT (shop_id, device_id) DO UPDATE SET user_id = EXCLUDED.user_id, imei = EXCLUDED.imei, device_name = EXCLUDED.device_name, device_type = EXCLUDED.device_type, last_seen_at = EXCLUDED.last_seen_at',
        [
          const Uuid().v4(),
          user['id'].toString(),
          shopId,
          deviceId,
          deviceId,
          'Flutter Client',
          'windows',
          now,
          now,
        ],
      );
    } catch (error) {
      print('Auth login device-write exception type=${error.runtimeType}');
      rethrow;
    }

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
    final hasAccess =
        user['shop_id'] == shopId || user['role'] == 'super_admin';
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
      'INSERT OR REPLACE INTO devices (id, user_id, shop_id, device_id, imei, device_name, device_type, created_at, last_seen_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        const Uuid().v4(),
        userId,
        shopId,
        deviceId,
        body['imei']?.toString() ?? deviceId,
        body['deviceName']?.toString() ?? 'Flutter Client',
        body['deviceType']?.toString() ?? 'windows',
        now,
        now,
      ],
    );
    return shelf.Response.ok(
      jsonEncode({'registered': true, 'deviceId': deviceId}),
    );
  }

  Future<shelf.Response> _uploadSync(shelf.Request request) async {
    final auth = await _requireAuth(request);
    if (auth == null)
      return shelf.Response(401, body: jsonEncode({'error': 'Unauthorized'}));
    final body = await _body(request);
    final items = body['items'];
    if (items is! List || items.length > 500)
      return shelf.Response(400, body: jsonEncode({'error': 'Invalid batch'}));
    final engine = SyncEngine(db);
    final conflicts = <Map<String, dynamic>>[];
    final accepted = <Map<String, dynamic>>[];
    for (final item in items) {
      try {
        final outcome = await engine.upload(
          auth['user']['shop_id'] as String,
          auth['user']['role'] as String,
          Map<String, dynamic>.from(item as Map),
        );
        if (outcome['accepted'] == true) {
          accepted.add(outcome);
        } else {
          conflicts.add(outcome);
        }
      } catch (_) {
        // No acknowledgements or change-log entry survive a failed transaction.
        conflicts.add({'code': 'SAVE_FAILED'});
      }
    }
    return shelf.Response.ok(
      jsonEncode({
        'itemsSynced': accepted.length,
        'itemsFailed': conflicts.length,
        'results': accepted,
        'conflicts': conflicts,
      }),
    );
  }

  Future<shelf.Response> _downloadSync(shelf.Request request) async {
    final auth = await _requireAuth(request);
    if (auth == null)
      return shelf.Response(401, body: jsonEncode({'error': 'Unauthorized'}));
    final body = await _body(request);
    try {
      final result = await SyncEngine(db).download(
        auth['user']['shop_id'] as String,
        cursor: body['cursor']?.toString(),
        limit: body['batchSize'] is int ? body['batchSize'] as int : 200,
      );
      return shelf.Response.ok(jsonEncode(result));
    } on FormatException {
      return shelf.Response(
        400,
        body: jsonEncode({'error': 'Invalid sync cursor'}),
      );
    }
  }

  Future<shelf.Response> _initialSync(shelf.Request request) async {
    final auth = await _requireAuth(request);
    if (auth == null) {
      return shelf.Response(401, body: jsonEncode({'error': 'Unauthorized'}));
    }

    final shopId =
        request.url.queryParameters['shopId'] ??
        auth['user']['shop_id'] as String;
    if (auth['user']['shop_id'] != shopId &&
        auth['user']['role'] != 'super_admin') {
      return shelf.Response(
        403,
        body: jsonEncode({'error': 'Shop access denied'}),
      );
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
      'mobile_models': await _fetchTableRows('mobile_models', shopId),
      'mobile_units': await _fetchTableRows('mobile_units', shopId),
      'suppliers': await _fetchTableRows('suppliers', shopId),
      'returns': await _fetchTableRows('returns', shopId),
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
      'INSERT OR REPLACE INTO sync_records (id, shop_id, entity_type, entity_id, operation, data, created_at, updated_at, is_deleted) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        const Uuid().v4(),
        shopId,
        'conflict',
        '$entityType:$entityId',
        'conflict',
        jsonEncode(conflict),
        now,
        now,
        0,
      ],
    );
    return shelf.Response.ok(
      jsonEncode({
        'resolved': true,
        'entityType': entityType,
        'entityId': entityId,
      }),
    );
  }

  Future<shelf.Response> _createEmployee(shelf.Request request) async {
    final auth = await _requireAuth(request);
    if (auth == null) {
      return shelf.Response(401, body: jsonEncode({'error': 'Unauthorized'}));
    }
    final user = auth['user'];
    if (user['role'] != 'admin') {
      return shelf.Response(
        403,
        body: jsonEncode({'error': 'Only admins can create employees'}),
      );
    }
    final body = await _body(request);
    final username = body['username']?.toString() ?? '';
    final password = body['password']?.toString() ?? '';
    final shopId = (body['shopId'] ?? user['shop_id']).toString();
    if (username.isEmpty || password.isEmpty) {
      return shelf.Response(
        400,
        body: jsonEncode({'error': 'username and password required'}),
      );
    }

    final employeeId = const Uuid().v4();
    final now = utcNow();
    final passwordHash = hashPassword(password);
    await db.execute(
      'INSERT OR REPLACE INTO employees (id, shop_id, username, password_hash, status, created_at, updated_at, is_deleted) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        employeeId,
        shopId,
        username,
        passwordHash,
        body['status']?.toString() ?? 'active',
        now,
        now,
        0,
      ],
    );
    await db.execute(
      'INSERT OR REPLACE INTO users (id, username, password_hash, shop_id, role, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [employeeId, username, passwordHash, shopId, 'employee', now, now],
    );

    return shelf.Response.ok(
      jsonEncode({
        'success': true,
        'employeeId': employeeId,
        'shopId': shopId,
        'username': username,
      }),
    );
  }

  Future<Map<String, dynamic>?> _requireAuth(shelf.Request request) async {
    final token = authTokenFromRequest(request);
    if (token == null) return null;
    final rows = await db.select(
      'SELECT s.*, u.username, u.shop_id, u.role, u.password_hash FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token = ?',
      [token],
    );
    if (rows.isEmpty) return null;
    final session = rows.first;
    final expiresAt = session['expires_at'] as String;
    if (DateTime.parse(expiresAt).isBefore(DateTime.now().toUtc())) {
      await db.execute('DELETE FROM sessions WHERE token = ?', [token]);
      return null;
    }
    if (session['role'] == 'employee') {
      final employee = await db.select(
        "SELECT id FROM employees WHERE shop_id=? AND username=? AND status='active' AND is_deleted=0",
        [session['shop_id'], session['username']],
      );
      if (employee.isEmpty) return null;
    }
    if (session['role'] != 'super_admin') {
      final shopRows = await db.select(
        'SELECT status, license_expiry_date, is_lifetime FROM shops WHERE shop_id = ?',
        [session['shop_id']],
      );
      if (shopRows.isNotEmpty) {
        final shop = shopRows.first;
        final lifetime =
            shop['is_lifetime'] == true || shop['is_lifetime'] == 1;
        final expiry = DateTime.tryParse(
          shop['license_expiry_date']?.toString() ?? '',
        );
        if (shop['status'] == 'suspended' ||
            (!lifetime &&
                expiry != null &&
                DateTime.now().toUtc().isAfter(expiry))) {
          return null;
        }
      }
    }
    return {'token': token, 'user': session};
  }

  Future<Map<String, dynamic>> _body(
    shelf.Request request, {
    bool rejectMalformed = false,
  }) async {
    final body = await request.readAsString();
    if (body.trim().isEmpty) {
      return <String, dynamic>{};
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      if (rejectMalformed) {
        throw const FormatException('Request body is not valid JSON');
      }
    }
    if (rejectMalformed) {
      throw const FormatException('Request body must be a JSON object');
    }
    return <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> _fetchTableRows(
    String tableName,
    String shopId,
  ) => SyncEngine(db).snapshot(shopId, tableName);

  // Mobile Model Endpoints
  Future<shelf.Response> _createMobileModel(shelf.Request request) async {
    final auth = await _requireAuth(request);
    if (auth == null) {
      return shelf.Response(401, body: jsonEncode({'error': 'Unauthorized'}));
    }
    final shopId = auth['user']['shop_id'] as String;
    final body = await _body(request);
    final name = body['name']?.toString() ?? '';
    final image = body['image']?.toString();

    if (name.isEmpty) {
      return shelf.Response(
        400,
        body: jsonEncode({'error': 'Model name is required'}),
      );
    }

    final now = utcNow();
    await db.execute(
      'INSERT INTO mobile_models (shop_id, name, image, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
      [shopId, name, image, now, now],
    );
    return shelf.Response.ok(jsonEncode({'success': true, 'shopId': shopId}));
  }

  Future<shelf.Response> _getMobileModels(shelf.Request request) async {
    final auth = await _requireAuth(request);
    if (auth == null) {
      return shelf.Response(401, body: jsonEncode({'error': 'Unauthorized'}));
    }
    final shopId = auth['user']['shop_id'] as String;
    final rows = await db.select(
      'SELECT * FROM mobile_models WHERE shop_id = ? ORDER BY created_at DESC',
      [shopId],
    );
    return shelf.Response.ok(jsonEncode(rows));
  }

  // Mobile Unit Endpoints
  Future<shelf.Response> _createMobileUnit(shelf.Request request) async {
    final auth = await _requireAuth(request);
    if (auth == null) {
      return shelf.Response(401, body: jsonEncode({'error': 'Unauthorized'}));
    }
    final shopId = auth['user']['shop_id'] as String;
    final body = await _body(request);
    final mobileModelId = body['mobileModelId'];
    final imei1 = body['imei1']?.toString() ?? '';
    final imei2 = body['imei2']?.toString();
    final buyPrice = (body['buyPrice'] as num?)?.toDouble() ?? 0;
    final ram = body['ram']?.toString();
    final storage = body['storage']?.toString();
    final supplierId = body['supplierId'];

    if (imei1.isEmpty || buyPrice <= 0) {
      return shelf.Response(
        400,
        body: jsonEncode({'error': 'IMEI and buyPrice are required'}),
      );
    }

    try {
      final now = utcNow();
      await db.execute(
        'INSERT INTO mobile_units (shop_id, mobile_model_id, imei_1, imei_2, buy_price, ram, storage, supplier_id, status, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          shopId,
          mobileModelId,
          imei1,
          imei2,
          buyPrice,
          ram,
          storage,
          supplierId,
          'available',
          now,
          now,
        ],
      );
      return shelf.Response.ok(jsonEncode({'success': true}));
    } catch (e) {
      return shelf.Response(
        400,
        body: jsonEncode({'error': 'IMEI already exists or invalid data'}),
      );
    }
  }

  Future<shelf.Response> _getMobileUnits(shelf.Request request) async {
    final auth = await _requireAuth(request);
    if (auth == null) {
      return shelf.Response(401, body: jsonEncode({'error': 'Unauthorized'}));
    }
    final shopId = auth['user']['shop_id'] as String;
    final modelId = request.url.queryParameters['modelId'];

    String sql =
        'SELECT * FROM mobile_units WHERE shop_id = ? AND is_deleted = 0';
    final params = <Object?>[shopId];

    if (modelId != null) {
      sql += ' AND mobile_model_id = ?';
      params.add(int.parse(modelId));
    }

    sql += ' ORDER BY created_at DESC';
    final rows = await db.select(sql, params);
    return shelf.Response.ok(jsonEncode(rows));
  }

  // Supplier Endpoints
  Future<shelf.Response> _createSupplier(shelf.Request request) async {
    final auth = await _requireAuth(request);
    if (auth == null) {
      return shelf.Response(401, body: jsonEncode({'error': 'Unauthorized'}));
    }
    final shopId = auth['user']['shop_id'] as String;
    final body = await _body(request);
    final name = body['name']?.toString() ?? '';
    final phone = body['phone']?.toString();
    final address = body['address']?.toString();
    final notes = body['notes']?.toString();

    if (name.isEmpty) {
      return shelf.Response(
        400,
        body: jsonEncode({'error': 'Supplier name is required'}),
      );
    }

    final now = utcNow();
    await db.execute(
      'INSERT INTO suppliers (shop_id, name, phone, address, notes, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [shopId, name, phone, address, notes, now, now],
    );
    return shelf.Response.ok(jsonEncode({'success': true}));
  }

  Future<shelf.Response> _getSuppliers(shelf.Request request) async {
    final auth = await _requireAuth(request);
    if (auth == null) {
      return shelf.Response(401, body: jsonEncode({'error': 'Unauthorized'}));
    }
    final shopId = auth['user']['shop_id'] as String;
    final rows = await db.select(
      'SELECT * FROM suppliers WHERE shop_id = ? ORDER BY created_at DESC',
      [shopId],
    );
    return shelf.Response.ok(jsonEncode(rows));
  }

  // Return Endpoints
  Future<shelf.Response> _createReturn(shelf.Request request) async {
    final auth = await _requireAuth(request);
    if (auth == null) {
      return shelf.Response(401, body: jsonEncode({'error': 'Unauthorized'}));
    }
    final shopId = auth['user']['shop_id'] as String;
    final body = await _body(request);
    final saleId = body['saleId'];
    final mobileUnitId = body['mobileUnitId'];
    final billNumber = body['billNumber']?.toString();
    final returnReason = body['returnReason']?.toString();

    final now = utcNow();
    await db.execute(
      'INSERT INTO returns (shop_id, sale_id, mobile_unit_id, bill_number, returned_at, return_reason, created_at, updated_at, is_deleted) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        shopId,
        saleId,
        mobileUnitId,
        billNumber,
        now,
        returnReason,
        now,
        now,
        0,
      ],
    );

    // Restore mobile unit status if applicable
    if (mobileUnitId != null) {
      await db.execute(
        'UPDATE mobile_units SET status = ?, updated_at = ? WHERE id = ?',
        ['available', now, mobileUnitId],
      );
    }

    return shelf.Response.ok(jsonEncode({'success': true}));
  }

  Future<shelf.Response> _getReturns(shelf.Request request) async {
    final auth = await _requireAuth(request);
    if (auth == null) {
      return shelf.Response(401, body: jsonEncode({'error': 'Unauthorized'}));
    }
    final shopId = auth['user']['shop_id'] as String;
    final billNumber = request.url.queryParameters['billNumber'];

    String sql = 'SELECT * FROM returns WHERE shop_id = ? AND is_deleted = 0';
    final params = <Object?>[shopId];

    if (billNumber != null) {
      sql += ' AND bill_number = ?';
      params.add(billNumber);
    }

    sql += ' ORDER BY returned_at DESC';
    final rows = await db.select(sql, params);
    return shelf.Response.ok(jsonEncode(rows));
  }

  // Bill Number Endpoint
  Future<shelf.Response> _generateBillNumber(shelf.Request request) async {
    final auth = await _requireAuth(request);
    if (auth == null) {
      return shelf.Response(401, body: jsonEncode({'error': 'Unauthorized'}));
    }
    final shopId = auth['user']['shop_id'] as String;

    try {
      final existing = await db.select(
        'SELECT next_number FROM bill_number_sequence WHERE shop_id = ?',
        [shopId],
      );

      late int nextNumber;
      if (existing.isEmpty) {
        nextNumber = 1;
        final now = utcNow();
        await db.execute(
          'INSERT INTO bill_number_sequence (shop_id, next_number, updated_at) VALUES (?, ?, ?)',
          [shopId, 2, now],
        );
      } else {
        nextNumber = (existing.first['next_number'] as num).toInt();
        final now = utcNow();
        await db.execute(
          'UPDATE bill_number_sequence SET next_number = ?, updated_at = ? WHERE shop_id = ?',
          [nextNumber + 1, now, shopId],
        );
      }

      final billNumber = 'BILL-${nextNumber.toString().padLeft(6, '0')}';
      return shelf.Response.ok(
        jsonEncode({'billNumber': billNumber, 'shopId': shopId}),
      );
    } catch (e) {
      return shelf.Response(
        500,
        body: jsonEncode({'error': 'Error generating bill number: $e'}),
      );
    }
  }
}

Future<void> main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final app = await ServerApp.start(port: port);
  await app.listen(host: InternetAddress.anyIPv4, port: port);
  final server = app._httpServer!;
  stderr.writeln(
    'AK Mobile Shop backend listening on ${server.address.host}:${server.port}',
  );
}
