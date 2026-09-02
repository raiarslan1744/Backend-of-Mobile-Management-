import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

import '../cloud/sync_queue_manager.dart';

class CategoryBreakdown {
  const CategoryBreakdown({
    required this.mobile,
    required this.accessories,
    required this.repair,
    required this.debtRecovery,
  });

  final double mobile;
  final double accessories;
  final double repair;
  final double debtRecovery;

  double get total => mobile + accessories + repair + debtRecovery;

  Map<String, double> asMap() => {
    'Mobile': mobile,
    'Accessories': accessories,
    'Repair': repair,
    'Debt Recovery': debtRecovery,
  };
}

class DashboardStats {
  const DashboardStats({
    required this.totalSales,
    required this.totalPurchases,
    required this.totalProfit,
    required this.lowStockItems,
    required this.totalCustomers,
    required this.totalProducts,
    required this.categoryBreakdown,
    required this.salesByCategory,
    required this.recentSales,
    required this.stockItems,
  });

  final double totalSales;
  final double totalPurchases;
  final double totalProfit;
  final int lowStockItems;
  final int totalCustomers;
  final int totalProducts;
  final CategoryBreakdown categoryBreakdown;
  final List<double> salesByCategory;
  final List<DashboardSale> recentSales;
  final List<DashboardStock> stockItems;
}

class DashboardSale {
  const DashboardSale({
    required this.productName,
    required this.amount,
    required this.soldAt,
    this.imei,
  });

  final String productName;
  final double amount;
  final DateTime soldAt;
  final String? imei;
}

class DashboardStock {
  const DashboardStock({required this.productName, required this.quantity});

  final String productName;
  final int quantity;
}

class DatabaseService {
  DatabaseService._(this._database);

  static DatabaseService? _instance;
  static String? storageDirectoryPath;
  final Database _database;

  static DatabaseService get instance {
    return _instance ??= DatabaseService._(sqlite3.openInMemory())
      .._createSchema();
  }

  void _ensureColumn(
    String tableName,
    String columnName,
    String columnDefinition,
  ) {
    final columnExists = _database
        .select("PRAGMA table_info($tableName)")
        .any((row) => (row['name'] as String?) == columnName);

    if (!columnExists) {
      _database.execute(
        'ALTER TABLE $tableName ADD COLUMN $columnName $columnDefinition',
      );
    }
  }

  double _asDouble(Object? value, {double fallback = 0}) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      return parsed ?? fallback;
    }
    return fallback;
  }

  int _asInt(Object? value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      return parsed ?? fallback;
    }
    return fallback;
  }

  DateTime? _safeDateTime(Object? value) {
    if (value == null || value is! String || value.trim().isEmpty) return null;
    try {
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }

  static Future<void> initialize(String directoryPath) async {
    storageDirectoryPath = directoryPath;
    final directory = Directory(directoryPath);
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    _instance?._database.dispose();
    _instance = DatabaseService._(
      sqlite3.open(
        '${directory.path}${Platform.pathSeparator}ak_mobile_shop_pos.sqlite',
      ),
    ).._createSchema();
  }

  Database get database => _database;

  void _createSchema() {
    _database.execute('''
      CREATE TABLE IF NOT EXISTS super_admin (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        username TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS shops (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        owner_name TEXT NOT NULL,
        contact TEXT NOT NULL,
        address TEXT NOT NULL,
        shop_id TEXT NOT NULL UNIQUE,
        username TEXT NOT NULL,
        password_hash TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended')),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shop_id TEXT NOT NULL,
        name TEXT NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 0,
        reorder_level INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shop_id TEXT NOT NULL,
        name TEXT NOT NULL,
        contact TEXT,
        address TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    try {
      _database.execute('ALTER TABLE customers ADD COLUMN address TEXT');
    } catch (_) {}
    _database.execute('''
      CREATE TABLE IF NOT EXISTS purchases (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shop_id TEXT NOT NULL,
        product_id INTEGER,
        product_name TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        total_cost REAL NOT NULL,
        purchased_at TEXT NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shop_id TEXT NOT NULL,
        product_id INTEGER,
        product_name TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        selling_total REAL NOT NULL,
        purchase_total REAL NOT NULL,
        imei TEXT,
        sold_at TEXT NOT NULL,
        customer_name TEXT,
        customer_phone TEXT,
        customer_address TEXT,
        employee_id INTEGER,
        employee_name TEXT
      )
    ''');
    for (final column in ['employee_id INTEGER', 'employee_name TEXT']) {
      try {
        _database.execute('ALTER TABLE sales ADD COLUMN $column');
      } catch (_) {}
    }
    _database.execute('''
      CREATE TABLE IF NOT EXISTS employees (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shop_id TEXT NOT NULL,
        username TEXT NOT NULL,
        password_hash TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'disabled')),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(shop_id, username)
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS mobile_devices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shop_id TEXT NOT NULL,
        name TEXT NOT NULL,
        picture_path TEXT,
        color TEXT,
        imei1 TEXT NOT NULL UNIQUE,
        imei2 TEXT,
        ram TEXT,
        storage TEXT,
        condition TEXT NOT NULL CHECK (condition IN ('new', 'used')),
        source_customer_name TEXT,
        source_cnic TEXT,
        source_phone TEXT,
        source_address TEXT,
        source_cnic_picture TEXT,
        buy_price REAL NOT NULL DEFAULT 0,
        sell_price REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'available' CHECK (status IN ('available', 'sold')),
        deleted_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS accessories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shop_id TEXT NOT NULL,
        name TEXT NOT NULL,
        picture_path TEXT,
        buy_price REAL NOT NULL DEFAULT 0,
        sell_price REAL NOT NULL DEFAULT 0,
        quantity INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    _ensureColumn('mobile_devices', 'deleted_at', 'TEXT');
    _ensureColumn('accessories', 'deleted_at', 'TEXT');
    _ensureColumn('mobile_devices', 'color', 'TEXT');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS repairs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shop_id TEXT NOT NULL,
        name TEXT NOT NULL,
        cost REAL NOT NULL,
        charge REAL NOT NULL,
        profit REAL NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS debtors (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shop_id TEXT NOT NULL,
        customer_name TEXT NOT NULL,
        phone TEXT NOT NULL,
        address TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS debt_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        debtor_id INTEGER NOT NULL,
        item TEXT NOT NULL,
        amount REAL NOT NULL,
        type TEXT NOT NULL CHECK (type IN ('debt', 'payment')),
        created_at TEXT NOT NULL
      )
    ''');
    _ensureColumn(
      'debt_transactions',
      'type',
      "TEXT NOT NULL DEFAULT 'debt' CHECK (type IN ('debt', 'payment'))",
    );
    _ensureColumn(
      'debt_transactions',
      'created_at',
      'TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP',
    );
    _ensureColumn('debt_transactions', 'amount', 'REAL NOT NULL DEFAULT 0');
    _ensureColumn('debt_transactions', 'item', "TEXT NOT NULL DEFAULT ''");
    _database.execute(
      "UPDATE debt_transactions SET type = 'debt' WHERE type IS NULL OR type NOT IN ('debt', 'payment')",
    );
    _database.execute(
      "UPDATE debt_transactions SET created_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE created_at IS NULL OR trim(created_at) = ''",
    );
    _database.execute('''
      CREATE TABLE IF NOT EXISTS shop_settings (
        shop_id TEXT PRIMARY KEY,
        shop_name TEXT NOT NULL,
        address TEXT NOT NULL,
        phone TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS backup_settings (
        shop_id TEXT PRIMARY KEY,
        google_account TEXT,
        local_backup_path TEXT,
        auto_backup_enabled INTEGER NOT NULL DEFAULT 0,
        last_backup_at TEXT,
        updated_at TEXT NOT NULL
      )
    ''');
    _ensureColumn('backup_settings', 'local_backup_path', 'TEXT');

    // New tables for inventory workflow
    _database.execute('''
      CREATE TABLE IF NOT EXISTS mobile_models (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shop_id TEXT NOT NULL,
        name TEXT NOT NULL,
        image TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    _database.execute('''
      CREATE TABLE IF NOT EXISTS mobile_units (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shop_id TEXT NOT NULL,
        mobile_model_id INTEGER NOT NULL,
        imei_1 TEXT NOT NULL UNIQUE,
        imei_2 TEXT,
        buy_price REAL NOT NULL DEFAULT 0,
        ram TEXT,
        storage TEXT,
        supplier_id INTEGER,
        status TEXT NOT NULL DEFAULT 'available' CHECK (status IN ('available', 'sold', 'returned')),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (mobile_model_id) REFERENCES mobile_models(id),
        FOREIGN KEY (supplier_id) REFERENCES suppliers(id)
      )
    ''');

    _database.execute('''
      CREATE TABLE IF NOT EXISTS suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shop_id TEXT NOT NULL,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    _database.execute('''
      CREATE TABLE IF NOT EXISTS bill_number_sequence (
        shop_id TEXT PRIMARY KEY,
        next_number INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT NOT NULL
      )
    ''');

    _database.execute('''
      CREATE TABLE IF NOT EXISTS returns (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shop_id TEXT NOT NULL,
        sale_id INTEGER,
        sale_item_id INTEGER,
        mobile_unit_id INTEGER,
        bill_number TEXT,
        returned_at TEXT NOT NULL,
        return_reason TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // Add bill_number column to sales table if not exists
    _ensureColumn('sales', 'bill_number', 'TEXT');

    if (_database.select('SELECT id FROM super_admin WHERE id = 1').isEmpty) {
      final now = DateTime.now().toUtc().toIso8601String();
      _database.execute(
        'INSERT INTO super_admin (id, username, password_hash, created_at, updated_at) VALUES (1, ?, ?, ?, ?)',
        ['admin', hashPassword('admin123'), now, now],
      );
    }
  }

  static String hashPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  ({String whereClause, List<Object?> params}) _periodFilter(
    String column,
    String period,
  ) {
    final normalizedPeriod = _normalizeDashboardPeriod(period);
    if (normalizedPeriod == 'all') {
      return (whereClause: '', params: const <Object?>[]);
    }

    final range = _dashboardPeriodRange(normalizedPeriod);
    return (
      whereClause: ' AND $column >= ? AND $column <= ?',
      params: <Object?>[
        range.start.toUtc().toIso8601String(),
        range.end.toUtc().toIso8601String(),
      ],
    );
  }

  String _normalizeDashboardPeriod(String period) {
    switch (period.trim()) {
      case 'Daily':
      case 'Today':
        return 'Daily';
      case 'Weekly':
      case 'This Week':
        return 'Weekly';
      case 'Monthly':
      case 'This Month':
        return 'Monthly';
      case 'Yearly':
      case 'This Year':
        return 'Yearly';
      case 'all':
      case 'All':
        return 'all';
      default:
        return 'Daily';
    }
  }

  ({DateTime start, DateTime end}) _dashboardPeriodRange(String period) {
    final now = DateTime.now().toLocal();
    switch (period) {
      case 'Daily':
        return (
          start: DateTime(now.year, now.month, now.day),
          end: DateTime(now.year, now.month, now.day, 23, 59, 59, 999),
        );
      case 'Weekly':
        final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
        final start = DateTime(
          startOfWeek.year,
          startOfWeek.month,
          startOfWeek.day,
        );
        final end = start.add(
          const Duration(
            days: 6,
            hours: 23,
            minutes: 59,
            seconds: 59,
            milliseconds: 999,
          ),
        );
        return (start: start, end: end);
      case 'Monthly':
        final start = DateTime(now.year, now.month, 1);
        final endOfMonth = DateTime(
          now.year,
          now.month + 1,
          0,
          23,
          59,
          59,
          999,
        );
        return (start: start, end: endOfMonth);
      case 'Yearly':
        final start = DateTime(now.year, 1, 1);
        final end = DateTime(now.year, 12, 31, 23, 59, 59, 999);
        return (start: start, end: end);
      case 'all':
      default:
        return (
          start: DateTime.fromMillisecondsSinceEpoch(0),
          end: DateTime.now().toLocal().add(const Duration(days: 36500)),
        );
    }
  }

  Set<String> _returnedBillNumbers(String shopId) {
    final rows = _database.select(
      'SELECT DISTINCT bill_number FROM returns WHERE shop_id = ? AND bill_number IS NOT NULL',
      [shopId],
    );
    return rows.map((row) => row['bill_number']).whereType<String>().toSet();
  }

  DashboardStats dashboardStats(String shopId, {String period = 'all'}) {
    try {
      final normalizedPeriod = _normalizeDashboardPeriod(period);
      final salesFilter = _periodFilter('sold_at', normalizedPeriod);
      final repairFilter = _periodFilter('created_at', normalizedPeriod);
      final debtFilter = _periodFilter('t.created_at', normalizedPeriod);
      final purchaseFilter = _periodFilter('purchased_at', normalizedPeriod);
      final returnedBillNumbers = _returnedBillNumbers(shopId);

      final salesRows = _database.select(
        'SELECT selling_total, purchase_total, bill_number, imei, sold_at, product_name FROM sales WHERE shop_id = ?${salesFilter.whereClause} ORDER BY sold_at DESC',
        [shopId, ...salesFilter.params],
      );

      double totalSales = 0;
      double totalPurchases = 0;
      double totalProfit = 0;
      double mobileSales = 0;
      double accessorySales = 0;
      final filteredRecentSales = <Map<String, Object?>>[];

      for (final row in salesRows) {
        final billNumber = row['bill_number'] as String?;
        if (billNumber != null && returnedBillNumbers.contains(billNumber)) {
          continue;
        }

        final sellingTotal = _asDouble(row['selling_total']);
        final purchaseTotal = _asDouble(row['purchase_total']);
        totalSales += sellingTotal;
        totalPurchases += purchaseTotal;
        totalProfit += sellingTotal - purchaseTotal;

        final imei = row['imei'] as String?;
        if (imei != null && imei.isNotEmpty) {
          mobileSales += sellingTotal;
        } else {
          accessorySales += sellingTotal;
        }

        filteredRecentSales.add(row);
      }

      final repairRows = _database.select(
        'SELECT charge, cost, name, created_at FROM repairs WHERE shop_id = ?${repairFilter.whereClause}',
        [shopId, ...repairFilter.params],
      );
      double repairRevenue = 0;
      double repairCost = 0;
      for (final row in repairRows) {
        repairRevenue += _asDouble(row['charge']);
        repairCost += _asDouble(row['cost']);
        totalProfit += _asDouble(row['charge']) - _asDouble(row['cost']);
      }
      totalSales += repairRevenue;
      totalPurchases += repairCost;

      final purchasesQuery = _database.select(
        'SELECT COALESCE(SUM(total_cost), 0) AS total FROM purchases WHERE shop_id = ?${purchaseFilter.whereClause}',
        [shopId, ...purchaseFilter.params],
      );
      final purchases = purchasesQuery.isNotEmpty
          ? purchasesQuery.first as Map<String, Object?>
          : <String, Object?>{'total': 0};

      final lowStockQuery = _database.select(
        'SELECT COUNT(*) AS count FROM products WHERE shop_id = ? AND quantity <= reorder_level',
        [shopId],
      );
      final lowStock = lowStockQuery.isNotEmpty
          ? lowStockQuery.first as Map<String, Object?>
          : <String, Object?>{'count': 0};

      final accessoryLowStockQuery = _database.select(
        'SELECT COUNT(*) AS count FROM accessories WHERE shop_id = ? AND deleted_at IS NULL AND quantity <= 0',
        [shopId],
      );
      final accessoryLowStock = accessoryLowStockQuery.isNotEmpty
          ? accessoryLowStockQuery.first as Map<String, Object?>
          : <String, Object?>{'count': 0};

      final customersQuery = _database.select(
        'SELECT COUNT(*) AS count FROM customers WHERE shop_id = ?',
        [shopId],
      );
      final customers = customersQuery.isNotEmpty
          ? customersQuery.first as Map<String, Object?>
          : <String, Object?>{'count': 0};

      final productsQuery = _database.select(
        'SELECT COUNT(*) AS count FROM products WHERE shop_id = ?',
        [shopId],
      );
      final products = productsQuery.isNotEmpty
          ? productsQuery.first as Map<String, Object?>
          : <String, Object?>{'count': 0};

      final mobileProductsQuery = _database.select(
        "SELECT COUNT(*) AS count FROM mobile_devices WHERE shop_id = ? AND status = 'available'",
        [shopId],
      );
      final mobileProducts = mobileProductsQuery.isNotEmpty
          ? mobileProductsQuery.first as Map<String, Object?>
          : <String, Object?>{'count': 0};

      final accessoryProductsQuery = _database.select(
        'SELECT COUNT(*) AS count FROM accessories WHERE shop_id = ? AND quantity > 0',
        [shopId],
      );
      final accessoryProducts = accessoryProductsQuery.isNotEmpty
          ? accessoryProductsQuery.first as Map<String, Object?>
          : <String, Object?>{'count': 0};

      final recentRows = _database.select(
        "SELECT bill_number, product_name, selling_total, sold_at, imei FROM sales WHERE shop_id = ?${salesFilter.whereClause} UNION ALL SELECT NULL AS bill_number, name AS product_name, charge AS selling_total, created_at AS sold_at, NULL AS imei FROM repairs WHERE shop_id = ?${repairFilter.whereClause} ORDER BY sold_at DESC LIMIT 3",
        [shopId, ...salesFilter.params, shopId, ...repairFilter.params],
      );
      final stockRows = _database.select(
        'SELECT name, quantity FROM products WHERE shop_id = ? AND quantity <= reorder_level ORDER BY quantity ASC LIMIT 3',
        [shopId],
      );

      final repairCategoryQuery = _database.select(
        'SELECT COALESCE(SUM(charge), 0) AS total FROM repairs WHERE shop_id = ?${repairFilter.whereClause}',
        [shopId, ...repairFilter.params],
      );
      final repairCategory = repairCategoryQuery.isNotEmpty
          ? repairCategoryQuery.first as Map<String, Object?>
          : <String, Object?>{'total': 0};

      final debtCategoryQuery = _database.select(
        "SELECT COALESCE(SUM(t.amount), 0) AS total FROM debt_transactions t JOIN debtors d ON d.id = t.debtor_id WHERE d.shop_id = ? AND t.type = 'payment'${debtFilter.whereClause}",
        [shopId, ...debtFilter.params],
      );
      final debtCategory = debtCategoryQuery.isNotEmpty
          ? debtCategoryQuery.first as Map<String, Object?>
          : <String, Object?>{'total': 0};

      final weeklySales = List<double>.filled(7, 0);
      final today = DateTime.now().toLocal();
      final weeklyRows = _database.select(
        'SELECT selling_total, sold_at, bill_number FROM sales WHERE shop_id = ? AND sold_at >= ? AND sold_at <= ?',
        [
          shopId,
          today.subtract(const Duration(days: 6)).toUtc().toIso8601String(),
          DateTime.now().toUtc().toIso8601String(),
        ],
      );
      for (final row in weeklyRows) {
        final billNumber = row['bill_number'] as String?;
        if (billNumber != null && returnedBillNumbers.contains(billNumber)) {
          continue;
        }
        final soldAt = _safeDateTime(row['sold_at']);
        if (soldAt == null) continue;
        final age = today.difference(soldAt.toLocal()).inDays;
        if (age >= 0 && age < 7) {
          weeklySales[6 - age] += _asDouble(row['selling_total']);
        }
      }

      final recentSales = recentRows
          .map((row) {
            final soldAt = _safeDateTime(row['sold_at']);
            final billNumber = row['bill_number'] as String?;
            if (billNumber != null &&
                returnedBillNumbers.contains(billNumber)) {
              return null;
            }
            return DashboardSale(
              productName: (row['product_name'] as String?) ?? 'Unknown item',
              amount: _asDouble(row['selling_total']),
              soldAt: soldAt ?? DateTime.now(),
              imei: row['imei'] as String?,
            );
          })
          .whereType<DashboardSale>()
          .take(3)
          .toList(growable: false);

      final stockItems = stockRows
          .map(
            (row) => DashboardStock(
              productName: (row['name'] as String?) ?? 'Unknown item',
              quantity: _asInt(row['quantity']),
            ),
          )
          .toList(growable: false);

      return DashboardStats(
        totalSales: totalSales + repairRevenue,
        totalPurchases: _asDouble(purchases['total']) + repairCost,
        totalProfit: totalProfit,
        lowStockItems:
            _asInt(lowStock['count']) + _asInt(accessoryLowStock['count']),
        totalCustomers: _asInt(customers['count']),
        totalProducts:
            _asInt(products['count']) +
            _asInt(mobileProducts['count']) +
            _asInt(accessoryProducts['count']),
        categoryBreakdown: CategoryBreakdown(
          mobile: mobileSales,
          accessories: accessorySales,
          repair: repairRevenue,
          debtRecovery: _asDouble(debtCategory['total']),
        ),
        salesByCategory: weeklySales,
        recentSales: recentSales,
        stockItems: stockItems,
      );
    } catch (error, stackTrace) {
      debugPrint('DashboardStats error: $error');
      debugPrintStack(stackTrace: stackTrace);
      return const DashboardStats(
        totalSales: 0,
        totalPurchases: 0,
        totalProfit: 0,
        lowStockItems: 0,
        totalCustomers: 0,
        totalProducts: 0,
        categoryBreakdown: CategoryBreakdown(
          mobile: 0,
          accessories: 0,
          repair: 0,
          debtRecovery: 0,
        ),
        salesByCategory: [0, 0, 0, 0, 0, 0, 0],
        recentSales: [],
        stockItems: [],
      );
    }
  }

  void resetForTesting() {
    SyncQueueManager.instance.refreshDatabase();
    _database.execute('DELETE FROM shops');
    _database.execute('DELETE FROM products');
    _database.execute('DELETE FROM customers');
    _database.execute('DELETE FROM purchases');
    _database.execute('DELETE FROM sales');
    _database.execute('DELETE FROM employees');
    _database.execute('DELETE FROM mobile_devices');
    _database.execute('DELETE FROM accessories');
    _database.execute('DELETE FROM repairs');
    _database.execute('DELETE FROM debtors');
    _database.execute('DELETE FROM debt_transactions');
    _database.execute('DELETE FROM shop_settings');
    _database.execute('DELETE FROM backup_settings');
    _database.execute('DELETE FROM super_admin');
    _database.execute('DELETE FROM mobile_models');
    _database.execute('DELETE FROM mobile_units');
    _database.execute('DELETE FROM suppliers');
    _database.execute('DELETE FROM bill_number_sequence');
    _database.execute('DELETE FROM returns');
    SyncQueueManager.instance.resetForTesting();
    _createSchema();
  }

  // Bill Number Methods
  String generateBillNumber(String shopId) {
    try {
      // Initialize sequence if not exists
      final existing = _database.select(
        'SELECT next_number FROM bill_number_sequence WHERE shop_id = ?',
        [shopId],
      );

      late int nextNumber;
      if (existing.isEmpty) {
        nextNumber = 1;
        final now = DateTime.now().toUtc().toIso8601String();
        _database.execute(
          'INSERT INTO bill_number_sequence (shop_id, next_number, updated_at) VALUES (?, ?, ?)',
          [shopId, 2, now],
        );
      } else {
        nextNumber = _asInt(existing.first['next_number']);
        final now = DateTime.now().toUtc().toIso8601String();
        _database.execute(
          'UPDATE bill_number_sequence SET next_number = ?, updated_at = ? WHERE shop_id = ?',
          [nextNumber + 1, now, shopId],
        );
      }

      return 'BILL-${nextNumber.toString().padLeft(6, '0')}';
    } catch (e) {
      debugPrint('Error generating bill number: $e');
      return 'BILL-ERROR';
    }
  }

  // Mobile Models Methods
  int createMobileModel(String shopId, String name, String? image) {
    final now = DateTime.now().toUtc().toIso8601String();
    _database.execute(
      'INSERT INTO mobile_models (shop_id, name, image, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
      [shopId, name, image, now, now],
    );
    final result = _database.select('SELECT last_insert_rowid() as id');
    return _asInt(result.first['id']);
  }

  List<Map<String, Object?>> getMobileModels(String shopId) {
    return _database.select(
      'SELECT * FROM mobile_models WHERE shop_id = ? ORDER BY created_at DESC',
      [shopId],
    );
  }

  Map<String, Object?>? getMobileModel(int modelId) {
    final result = _database.select(
      'SELECT * FROM mobile_models WHERE id = ?',
      [modelId],
    );
    return result.isNotEmpty ? result.first : null;
  }

  Map<String, Object?>? getMobileModelForShop(int modelId, String shopId) {
    final result = _database.select(
      'SELECT * FROM mobile_models WHERE id = ? AND shop_id = ?',
      [modelId, shopId],
    );
    return result.isNotEmpty ? result.first : null;
  }

  void deleteMobileModel(int modelId, {required String shopId}) {
    _database.execute(
      'DELETE FROM mobile_units WHERE mobile_model_id = ? AND shop_id = ?',
      [modelId, shopId],
    );
    _database.execute(
      'DELETE FROM mobile_models WHERE id = ? AND shop_id = ?',
      [modelId, shopId],
    );
  }

  // Mobile Units Methods
  int createMobileUnit(
    String shopId,
    int mobileModelId,
    String imei1,
    String? imei2,
    double buyPrice,
    String? ram,
    String? storage,
    int? supplierId,
  ) {
    final now = DateTime.now().toUtc().toIso8601String();
    _database.execute(
      '''INSERT INTO mobile_units 
         (shop_id, mobile_model_id, imei_1, imei_2, buy_price, ram, storage, supplier_id, status, created_at, updated_at) 
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
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
    final result = _database.select('SELECT last_insert_rowid() as id');
    return _asInt(result.first['id']);
  }

  List<Map<String, Object?>> getMobileUnitsByModel(int mobileModelId, [String? shopId]) {
    final filter = shopId == null ? 'mobile_model_id = ?' : 'mobile_model_id = ? AND shop_id = ?';
    return _database.select(
      'SELECT * FROM mobile_units WHERE $filter AND status = ? ORDER BY created_at DESC',
      [mobileModelId, if (shopId != null) shopId, 'available'],
    );
  }

  int getAvailableStockCount(int mobileModelId, String shopId) {
    final result = _database.select(
      'SELECT COUNT(*) as count FROM mobile_units WHERE mobile_model_id = ? AND shop_id = ? AND status = ?',
      [mobileModelId, shopId, 'available'],
    );
    return result.isNotEmpty ? _asInt(result.first['count']) : 0;
  }

  Map<String, Object?>? getMobileUnitByImei(String imei1, String shopId) {
    final result = _database.select(
      'SELECT * FROM mobile_units WHERE imei_1 = ? AND shop_id = ?',
      [imei1, shopId],
    );
    return result.isNotEmpty ? result.first : null;
  }

  void updateMobileUnitStatus(int unitId, String status, {String? shopId}) {
    final now = DateTime.now().toUtc().toIso8601String();
    _database.execute(
      'UPDATE mobile_units SET status = ?, updated_at = ? WHERE id = ?${shopId == null ? '' : ' AND shop_id = ?'}',
      [status, now, unitId, if (shopId != null) shopId],
    );
  }

  void deleteMobileUnit(int unitId, {required String shopId}) {
    _database.execute('DELETE FROM mobile_units WHERE id = ? AND shop_id = ?', [
      unitId,
      shopId,
    ]);
  }

  // Suppliers Methods
  int createSupplier(
    String shopId,
    String name,
    String? phone,
    String? address,
    String? notes,
  ) {
    final now = DateTime.now().toUtc().toIso8601String();
    _database.execute(
      'INSERT INTO suppliers (shop_id, name, phone, address, notes, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [shopId, name, phone, address, notes, now, now],
    );
    final result = _database.select('SELECT last_insert_rowid() as id');
    return _asInt(result.first['id']);
  }

  List<Map<String, Object?>> getSuppliers(String shopId) {
    return _database.select(
      'SELECT * FROM suppliers WHERE shop_id = ? ORDER BY created_at DESC',
      [shopId],
    );
  }

  Map<String, Object?>? getSupplier(int supplierId) {
    final result = _database.select('SELECT * FROM suppliers WHERE id = ?', [
      supplierId,
    ]);
    return result.isNotEmpty ? result.first : null;
  }

  void deleteSupplier(int supplierId) {
    _database.execute('DELETE FROM suppliers WHERE id = ?', [supplierId]);
  }

  // Returns Methods
  int createReturn(
    String shopId,
    int? saleId,
    int? saleItemId,
    int? mobileUnitId,
    String? billNumber,
    String returnReason,
  ) {
    final now = DateTime.now().toUtc().toIso8601String();
    _database.execute(
      '''INSERT INTO returns 
         (shop_id, sale_id, sale_item_id, mobile_unit_id, bill_number, returned_at, return_reason, created_at, updated_at) 
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        shopId,
        saleId,
        saleItemId,
        mobileUnitId,
        billNumber,
        now,
        returnReason,
        now,
        now,
      ],
    );
    final result = _database.select('SELECT last_insert_rowid() as id');
    return _asInt(result.first['id']);
  }

  List<Map<String, Object?>> getReturnsByBillNumber(
    String billNumber,
    String shopId,
  ) {
    return _database.select(
      'SELECT * FROM returns WHERE bill_number = ? AND shop_id = ? ORDER BY returned_at DESC',
      [billNumber, shopId],
    );
  }

  List<Map<String, Object?>> getReturnsBySaleId(int saleId) {
    return _database.select(
      'SELECT * FROM returns WHERE sale_id = ? ORDER BY returned_at DESC',
      [saleId],
    );
  }
}
