import 'dart:convert';
import 'dart:io';

import '../../../core/database/database_service.dart';

class RepairRecord {
  const RepairRecord({required this.id, required this.name, required this.cost, required this.charge, required this.profit, required this.createdAt});
  final int id;
  final String name;
  final double cost;
  final double charge;
  final double profit;
  final DateTime createdAt;
}

class DebtorRecord {
  const DebtorRecord({required this.id, required this.name, required this.phone, required this.address, required this.balance});
  final int id;
  final String name;
  final String phone;
  final String address;
  final double balance;
}

class DebtTransactionRecord {
  const DebtTransactionRecord({required this.item, required this.amount, required this.type, required this.createdAt});
  final String item;
  final double amount;
  final String type;
  final DateTime createdAt;
}

class ShopDetails {
  const ShopDetails({required this.name, required this.address, required this.phone});
  final String name;
  final String address;
  final String phone;
}

class AdminManagementService {
  AdminManagementService() : _database = DatabaseService.instance;
  final DatabaseService _database;

  RepairRecord? addRepair({required String shopId, required String name, required double cost, required double charge}) {
    if (name.trim().isEmpty || cost < 0 || charge < 0) return null;
    final now = DateTime.now().toUtc().toIso8601String();
    _database.database.execute('INSERT INTO repairs (shop_id, name, cost, charge, profit, created_at) VALUES (?, ?, ?, ?, ?, ?)', [shopId, name.trim(), cost, charge, charge - cost, now]);
    final row = _database.database.select('SELECT * FROM repairs WHERE rowid = last_insert_rowid()').first;
    return _repairFromRow(row);
  }

  List<RepairRecord> repairs(String shopId) => _database.database.select('SELECT * FROM repairs WHERE shop_id = ? ORDER BY created_at DESC', [shopId]).map(_repairFromRow).toList(growable: false);

  List<DebtorRecord> debtors(String shopId) => _database.database.select('''SELECT d.*, COALESCE(SUM(CASE WHEN t.type = 'debt' THEN t.amount ELSE -t.amount END), 0) AS balance FROM debtors d LEFT JOIN debt_transactions t ON t.debtor_id = d.id WHERE d.shop_id = ? GROUP BY d.id ORDER BY d.customer_name''', [shopId]).map(_debtorFromRow).toList(growable: false);

  DebtorRecord? addDebtor({required String shopId, required String name, required String phone, required String address}) {
    if ([name, phone, address].any((value) => value.trim().isEmpty)) return null;
    final now = DateTime.now().toUtc().toIso8601String();
    _database.database.execute('INSERT INTO debtors (shop_id, customer_name, phone, address, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)', [shopId, name.trim(), phone.trim(), address.trim(), now, now]);
    return debtors(shopId).firstWhere((debtor) => debtor.name == name.trim() && debtor.phone == phone.trim());
  }

  List<DebtTransactionRecord> debtHistory(int debtorId) => _database.database.select('SELECT * FROM debt_transactions WHERE debtor_id = ? ORDER BY created_at', [debtorId]).map((row) => DebtTransactionRecord(item: row['item'] as String, amount: (row['amount'] as num).toDouble(), type: row['type'] as String, createdAt: DateTime.parse(row['created_at'] as String))).toList(growable: false);

  String? addDebt({required int debtorId, required String item, required double amount}) => _addDebtTransaction(debtorId: debtorId, item: item, amount: amount, type: 'debt');
  String? addPayment({required int debtorId, required double amount}) => _addDebtTransaction(debtorId: debtorId, item: 'Payment', amount: amount, type: 'payment');

  String? _addDebtTransaction({required int debtorId, required String item, required double amount, required String type}) {
    if (item.trim().isEmpty || amount <= 0) return 'Enter a valid item and amount.';
    final current = _database.database.select("SELECT COALESCE(SUM(CASE WHEN type = 'debt' THEN amount ELSE -amount END), 0) AS balance FROM debt_transactions WHERE debtor_id = ?", [debtorId]).first['balance'] as num;
    if (type == 'payment' && amount > current) return 'Payment cannot exceed the outstanding balance.';
    _database.database.execute('INSERT INTO debt_transactions (debtor_id, item, amount, type, created_at) VALUES (?, ?, ?, ?, ?)', [debtorId, item.trim(), amount, type, DateTime.now().toUtc().toIso8601String()]);
    return null;
  }

  ShopDetails shopDetails(String shopId) {
    final saved = _database.database.select('SELECT shop_name, address, phone FROM shop_settings WHERE shop_id = ?', [shopId]);
    if (saved.isNotEmpty) {
      return ShopDetails(name: saved.first['shop_name'] as String, address: saved.first['address'] as String, phone: saved.first['phone'] as String);
    }
    final rows = _database.database.select('SELECT owner_name, address, contact FROM shops WHERE shop_id = ?', [shopId]);
    if (rows.isEmpty) return const ShopDetails(name: 'AK Mobile Shop', address: '', phone: '');
    return ShopDetails(name: rows.first['owner_name'] as String, address: rows.first['address'] as String, phone: rows.first['contact'] as String);
  }

  String? saveShopDetails({required String shopId, required String name, required String address, required String phone}) {
    if ([name, address, phone].any((value) => value.trim().isEmpty)) return 'All shop details are required.';
    final now = DateTime.now().toUtc().toIso8601String();
    _database.database.execute('UPDATE shops SET owner_name = ?, address = ?, contact = ?, updated_at = ? WHERE shop_id = ?', [name.trim(), address.trim(), phone.trim(), now, shopId]);
    _database.database.execute('INSERT INTO shop_settings (shop_id, shop_name, address, phone, updated_at) VALUES (?, ?, ?, ?, ?) ON CONFLICT(shop_id) DO UPDATE SET shop_name = excluded.shop_name, address = excluded.address, phone = excluded.phone, updated_at = excluded.updated_at', [shopId, name.trim(), address.trim(), phone.trim(), now]);
    return null;
  }

  String? changePassword({required String shopId, required String currentPassword, required String newPassword, required String confirmation}) {
    if (newPassword.isEmpty || newPassword != confirmation) return 'New passwords do not match.';
    final rows = _database.database.select('SELECT username FROM shops WHERE shop_id = ? AND password_hash = ?', [shopId, DatabaseService.hashPassword(currentPassword)]);
    if (rows.isEmpty) return 'Current password is incorrect.';
    _database.database.execute('UPDATE shops SET password_hash = ?, updated_at = ? WHERE shop_id = ?', [DatabaseService.hashPassword(newPassword), DateTime.now().toUtc().toIso8601String(), shopId]);
    return null;
  }

  static const String _defaultBackupScopeId = 'global';

  String _backupScopeId(String? shopId) => (shopId ?? _defaultBackupScopeId).trim().isEmpty ? _defaultBackupScopeId : (shopId ?? _defaultBackupScopeId).trim();

  Future<String?> getLocalBackupFolderPath({String? shopId}) async {
    final scopeId = _backupScopeId(shopId);
    final row = _database.database.select('SELECT local_backup_path FROM backup_settings WHERE shop_id = ?', [scopeId]).firstOrNull;
    final path = row?['local_backup_path'] as String?;
    if (path == null || path.trim().isEmpty) return null;
    final directory = Directory(path);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory.path;
  }

  Future<String?> setLocalBackupFolderPath(String path, {String? shopId}) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return 'Backup folder path cannot be empty.';
    final directory = Directory(trimmed);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final scopeId = _backupScopeId(shopId);
    final now = DateTime.now().toUtc().toIso8601String();
    _database.database.execute(
      'INSERT INTO backup_settings (shop_id, local_backup_path, updated_at) VALUES (?, ?, ?) ON CONFLICT(shop_id) DO UPDATE SET local_backup_path = excluded.local_backup_path, updated_at = excluded.updated_at',
      [scopeId, directory.path, now],
    );
    return null;
  }

  Future<bool> getAutoBackupEnabled({String? shopId}) async {
    final scopeId = _backupScopeId(shopId);
    final row = _database.database.select('SELECT auto_backup_enabled FROM backup_settings WHERE shop_id = ?', [scopeId]).firstOrNull;
    return (row?['auto_backup_enabled'] as int?) == 1;
  }

  Future<void> setAutoBackupEnabled(bool enabled, {String? shopId}) async {
    final scopeId = _backupScopeId(shopId);
    final now = DateTime.now().toUtc().toIso8601String();
    _database.database.execute(
      'INSERT INTO backup_settings (shop_id, auto_backup_enabled, updated_at) VALUES (?, ?, ?) ON CONFLICT(shop_id) DO UPDATE SET auto_backup_enabled = excluded.auto_backup_enabled, updated_at = excluded.updated_at',
      [scopeId, enabled ? 1 : 0, now],
    );
  }

  Future<String?> createLocalBackup(String shopId, {bool overwrite = false}) async {
    final folderPath = await getLocalBackupFolderPath(shopId: shopId);
    if (folderPath == null || folderPath.trim().isEmpty) {
      return 'No backup location is configured. Select a backup folder first.';
    }

    final sourcePath = DatabaseService.storageDirectoryPath;
    if (sourcePath == null) return 'Application data folder is not initialized.';

    final folder = Directory(folderPath);
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }

    final source = File('$sourcePath${Platform.pathSeparator}ak_mobile_shop_pos.sqlite');
    if (!await source.exists()) return 'Database file was not found.';

    final now = DateTime.now().toLocal();
    final shopName = shopDetails(shopId).name.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final safeShopId = shopId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    String fileName = 'AK_Backup_${safeShopId}_${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}.db';

    var candidate = File('${folder.path}${Platform.pathSeparator}$fileName');
    var copyIndex = 1;
    while (candidate.existsSync() && !overwrite) {
      final suffix = '_${copyIndex.toString().padLeft(2, '0')}';
      final base = fileName.substring(0, fileName.length - '.db'.length);
      fileName = '$base$suffix.db';
      candidate = File('${folder.path}${Platform.pathSeparator}$fileName');
      copyIndex += 1;
    }

    if (overwrite && candidate.existsSync()) {
      await candidate.delete();
    }

    await source.copy(candidate.path);

    final metadata = {
      'shop_id': shopId,
      'shop_name': shopName,
      'backup_date_time': now.toUtc().toIso8601String(),
      'file_name': fileName,
    };
    final metadataFile = File('${candidate.path}.json');
    await metadataFile.writeAsString(const JsonEncoder.withIndent('  ').convert(metadata));

    final images = Directory('$sourcePath${Platform.pathSeparator}shop_$shopId${Platform.pathSeparator}Images');
    if (await images.exists()) {
      final backupImages = Directory('${folder.path}${Platform.pathSeparator}images');
      await backupImages.create(recursive: true);
      await for (final entity in images.list(recursive: true)) {
        if (entity is File) {
          final relativePath = entity.path.substring(images.path.length + 1);
          final destination = File('${backupImages.path}${Platform.pathSeparator}$relativePath');
          await destination.parent.create(recursive: true);
          await entity.copy(destination.path);
        }
      }
    }

    return candidate.path;
  }

  Future<void> openShopDataFolder(String shopId) async {
    final sourcePath = DatabaseService.storageDirectoryPath;
    if (sourcePath == null) return;
    final folder = Directory('$sourcePath${Platform.pathSeparator}shop_$shopId');
    await folder.create(recursive: true);
    await Process.start('explorer.exe', [folder.path]);
  }

  Future<void> openLocalBackupFolder({String? shopId}) async {
    final folderPath = await getLocalBackupFolderPath(shopId: shopId);
    if (folderPath == null || folderPath.trim().isEmpty) {
      throw StateError('No backup location is configured.');
    }
    final folder = Directory(folderPath);
    if (!await folder.exists()) {
      throw StateError('The selected backup folder no longer exists. Please choose a new one.');
    }
    await Process.start('explorer.exe', [folder.path]);
  }

  Future<Map<String, String?>> inspectBackupFile(String backupPath) async {
    final file = File(backupPath);
    if (!await file.exists()) {
      return {'shop_id': null, 'shop_name': null, 'backup_date_time': null};
    }

    final metadataFile = File('${file.path}.json');
    if (await metadataFile.exists()) {
      final contents = await metadataFile.readAsString();
      try {
        final decoded = jsonDecode(contents); 
        if (decoded is Map<String, dynamic>) {
          return {
            'shop_id': decoded['shop_id']?.toString(),
            'shop_name': decoded['shop_name']?.toString(),
            'backup_date_time': decoded['backup_date_time']?.toString(),
          };
        }
      } catch (_) {}
    }

    return {
      'shop_id': null,
      'shop_name': null,
      'backup_date_time': null,
    };
  }

  Future<String?> restoreBackupFile(String backupPath, {String? shopId}) async {
    final file = File(backupPath);
    if (!await file.exists()) return 'Backup file was not found.';
    final metadata = await inspectBackupFile(backupPath);
    final resolvedShopId = shopId ?? metadata['shop_id'];
    if (resolvedShopId == null || resolvedShopId.isEmpty) {
      return 'This backup does not include a Shop ID and could not be validated.';
    }

    final sourcePath = DatabaseService.storageDirectoryPath;
    if (sourcePath == null) return 'Application data folder is not initialized.';
    final sourceFile = File('$sourcePath${Platform.pathSeparator}ak_mobile_shop_pos.sqlite');
    if (await sourceFile.exists()) {
      final safetyBackup = File('${sourceFile.path}.restore_safety_${DateTime.now().toLocal().millisecondsSinceEpoch}.bak');
      await sourceFile.copy(safetyBackup.path);
    }

    await file.copy(sourceFile.path);
    return null;
  }

  RepairRecord _repairFromRow(Map<String, Object?> row) => RepairRecord(id: row['id'] as int, name: row['name'] as String, cost: (row['cost'] as num).toDouble(), charge: (row['charge'] as num).toDouble(), profit: (row['profit'] as num).toDouble(), createdAt: DateTime.parse(row['created_at'] as String));
  DebtorRecord _debtorFromRow(Map<String, Object?> row) => DebtorRecord(id: row['id'] as int, name: row['customer_name'] as String, phone: row['phone'] as String, address: row['address'] as String, balance: (row['balance'] as num).toDouble());
}
