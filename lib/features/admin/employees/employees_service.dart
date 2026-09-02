import '../../../core/database/database_service.dart';

class EmployeeAccount {
  const EmployeeAccount({
    required this.id,
    required this.shopId,
    required this.username,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String shopId;
  final String username;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class EmployeeManagementService {
  EmployeeManagementService() : _database = DatabaseService.instance;

  static final EmployeeManagementService instance = EmployeeManagementService();

  final DatabaseService _database;

  List<EmployeeAccount> employeesForShop(String shopId) {
    final rows = _database.database.select(
      'SELECT * FROM employees WHERE shop_id = ? ORDER BY created_at DESC',
      [shopId],
    );
    return rows.map(_employeeFromRow).toList(growable: false);
  }

  EmployeeAccount? findEmployeeByCredentials({
    required String username,
    required String password,
    required String shopId,
  }) {
    final rows = _database.database.select(
      'SELECT * FROM employees WHERE username = ? AND shop_id = ? AND password_hash = ? AND status = ?',
      [username.trim(), shopId.trim(), DatabaseService.hashPassword(password), 'active'],
    );
    if (rows.isEmpty) {
      return null;
    }
    return _employeeFromRow(rows.first);
  }

  void invalidateEmployeeCredential({
    required String shopId,
    required String username,
  }) {
    final trimmedShopId = shopId.trim();
    final trimmedUsername = username.trim();
    if (trimmedShopId.isEmpty || trimmedUsername.isEmpty) return;
    _database.database.execute(
      'UPDATE employees SET status = ?, password_hash = ?, updated_at = ? WHERE shop_id = ? AND username = ?',
      ['disabled', DatabaseService.hashPassword('INVALIDATED_OFFLINE_AUTH'), DateTime.now().toUtc().toIso8601String(), trimmedShopId, trimmedUsername],
    );
  }

  void upsertEmployeeCredential({
    required String shopId,
    required String username,
    required String password,
  }) {
    final trimmedShopId = shopId.trim();
    final trimmedUsername = username.trim();
    if (trimmedShopId.isEmpty || trimmedUsername.isEmpty) return;

    final existing = _database.database.select(
      'SELECT id FROM employees WHERE shop_id = ? AND username = ?',
      [trimmedShopId, trimmedUsername],
    );
    final now = DateTime.now().toUtc().toIso8601String();
    if (existing.isEmpty) {
      _database.database.execute(
        '''INSERT INTO employees (shop_id, username, password_hash, status, created_at, updated_at)
           VALUES (?, ?, ?, 'active', ?, ?)''',
        [trimmedShopId, trimmedUsername, DatabaseService.hashPassword(password.trim()), now, now],
      );
      return;
    }

    _database.database.execute(
      'UPDATE employees SET password_hash = ?, status = ?, updated_at = ? WHERE shop_id = ? AND username = ?',
      [DatabaseService.hashPassword(password.trim()), 'active', now, trimmedShopId, trimmedUsername],
    );
  }

  String? createEmployee({
    required String shopId,
    required String username,
    required String password,
  }) {
    final trimmedShopId = shopId.trim();
    final trimmedUsername = username.trim();
    final trimmedPassword = password.trim();
    if (trimmedShopId.isEmpty || trimmedUsername.isEmpty || trimmedPassword.isEmpty) {
      return 'Username, password, and shop ID are required.';
    }

    final now = DateTime.now().toUtc().toIso8601String();
    try {
      _database.database.execute(
        '''INSERT INTO employees (shop_id, username, password_hash, status, created_at, updated_at)
           VALUES (?, ?, ?, 'active', ?, ?)''',
        [trimmedShopId, trimmedUsername, DatabaseService.hashPassword(trimmedPassword), now, now],
      );
      return null;
    } catch (_) {
      return 'Employee username already exists for this shop.';
    }
  }

  String? toggleEmployeeStatus({required int employeeId}) {
    final rows = _database.database.select('SELECT status FROM employees WHERE id = ?', [employeeId]);
    if (rows.isEmpty) return 'Employee not found.';
    final next = rows.first['status'] == 'active' ? 'disabled' : 'active';
    _database.database.execute(
      'UPDATE employees SET status = ?, updated_at = ? WHERE id = ?',
      [next, DateTime.now().toUtc().toIso8601String(), employeeId],
    );
    return null;
  }

  String? resetEmployeePassword({required int employeeId, required String newPassword}) {
    final trimmed = newPassword.trim();
    if (trimmed.isEmpty) return 'New password is required.';
    _database.database.execute(
      'UPDATE employees SET password_hash = ?, updated_at = ? WHERE id = ?',
      [DatabaseService.hashPassword(trimmed), DateTime.now().toUtc().toIso8601String(), employeeId],
    );
    return null;
  }

  EmployeeAccount _employeeFromRow(Map<String, Object?> row) {
    return EmployeeAccount(
      id: row['id'] as int,
      shopId: row['shop_id'] as String,
      username: row['username'] as String,
      status: row['status'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}
