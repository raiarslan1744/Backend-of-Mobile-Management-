import '../../../core/auth/app_session.dart';
import '../../../core/database/database_service.dart';
import '../../../core/cloud/cloud_sync_service.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';

class MobileDevice {
  const MobileDevice({
    required this.id,
    required this.name,
    required this.picturePath,
    required this.color,
    required this.imei1,
    required this.imei2,
    required this.ram,
    required this.storage,
    required this.condition,
    required this.buyPrice,
    required this.sellPrice,
  });

  final int id;
  final String name;
  final String? picturePath;
  final String? color;
  final String imei1;
  final String? imei2;
  final String? ram;
  final String? storage;
  final String condition;
  final double buyPrice;
  final double sellPrice;
}

class AccessoryItem {
  const AccessoryItem({
    required this.id,
    required this.name,
    required this.picturePath,
    required this.buyPrice,
    required this.sellPrice,
    required this.quantity,
  });

  final int id;
  final String name;
  final String? picturePath;
  final double buyPrice;
  final double sellPrice;
  final int quantity;
}

class MobileModel {
  const MobileModel({
    required this.id,
    required this.shopId,
    required this.name,
    required this.image,
    required this.stockCount,
    required this.createdAt,
  });

  final int id;
  final String shopId;
  final String name;
  final String? image;
  final int stockCount;
  final DateTime createdAt;

  bool get isLowStock => stockCount <= 2;
}

class MobileUnit {
  const MobileUnit({
    required this.id,
    required this.shopId,
    required this.mobileModelId,
    required this.imei1,
    required this.imei2,
    required this.buyPrice,
    required this.ram,
    required this.storage,
    required this.supplierId,
    required this.status,
    required this.createdAt,
  });

  final int id;
  final String shopId;
  final int mobileModelId;
  final String imei1;
  final String? imei2;
  final double buyPrice;
  final String? ram;
  final String? storage;
  final int? supplierId;
  final String status;
  final DateTime createdAt;

  bool get isAvailable => status == 'available';
  bool get isSold => status == 'sold';
}

class Supplier {
  const Supplier({
    required this.id,
    required this.shopId,
    required this.name,
    required this.phone,
    required this.address,
    required this.notes,
    required this.createdAt,
  });

  final int id;
  final String shopId;
  final String name;
  final String? phone;
  final String? address;
  final String? notes;
  final DateTime createdAt;
}

class SaleReturn {
  const SaleReturn({
    required this.id,
    required this.shopId,
    required this.saleId,
    required this.mobileUnitId,
    required this.billNumber,
    required this.returnedAt,
    required this.returnReason,
  });

  final int id;
  final String shopId;
  final int? saleId;
  final int? mobileUnitId;
  final String? billNumber;
  final DateTime returnedAt;
  final String? returnReason;
}

class CartLine {
  CartLine.mobile(this.device, {double? salePrice, this.mobileUnit})
      : accessory = null,
        quantity = 1,
        salePrice = salePrice ?? device?.sellPrice ?? 0;
  CartLine.accessory(this.accessory, {this.quantity = 1, double? salePrice})
      : device = null,
        mobileUnit = null,
        salePrice = salePrice ?? accessory?.sellPrice ?? 0;

  final MobileDevice? device;
  final MobileUnit? mobileUnit;
  final AccessoryItem? accessory;
  int quantity;
  double salePrice;

  bool get isMobile => device != null || mobileUnit != null;
  String get name => device?.name ?? accessory?.name ?? 'Mobile Device';
  String get detail => device != null
      ? 'IMEI: ${device!.imei1}'
      : mobileUnit != null
      ? 'IMEI: ${mobileUnit!.imei1}'
      : 'Accessory';
  double get unitPrice => salePrice;
  double get buyPrice => device?.buyPrice ?? mobileUnit?.buyPrice ?? accessory!.buyPrice;
  double get total => unitPrice * quantity;
  bool get hasValidSalePrice => !salePrice.isNaN && salePrice >= 0;
}

class InventoryService {
  InventoryService() : _database = DatabaseService.instance;

  final DatabaseService _database;

  void _queue(String shopId, String entityType, int entityId, Map<String, dynamic> data) {
    CloudSyncService.instance.queueChange(
      shopId: shopId,
      entityType: entityType,
      entityId: entityId.toString(),
      operation: 'create',
      data: data,
    );
  }

  Future<String?> storeImage(String shopId, String sourcePath, {required bool accessory}) async {
    final root = DatabaseService.storageDirectoryPath;
    if (root == null || sourcePath.trim().isEmpty) return null;
    final source = File(sourcePath);
    if (!await source.exists()) return null;
    final category = accessory ? 'Accessories' : 'Mobiles';
    final folder = Directory('$root${Platform.pathSeparator}shop_$shopId${Platform.pathSeparator}Images${Platform.pathSeparator}$category');
    await folder.create(recursive: true);
    final extension = source.path.contains('.') ? source.path.substring(source.path.lastIndexOf('.')) : '.image';
    final target = File('${folder.path}${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}$extension');
    await source.copy(target.path);
    return target.path;
  }

  String? _requireAdmin() {
    return AppSession.instance.role == 'admin' ? null : 'Only shop admins can modify inventory.';
  }

  List<MobileDevice> mobileDevices(String shopId, {String search = '', bool includeDeleted = false}) {
    final query = search.trim();
    final where = includeDeleted ? 'shop_id = ?' : "shop_id = ? AND deleted_at IS NULL AND status = 'available'";
    final rows = query.isEmpty
        ? _database.database.select('SELECT * FROM mobile_devices WHERE $where ORDER BY id DESC', [shopId])
        : _database.database.select('SELECT * FROM mobile_devices WHERE $where AND (name LIKE ? OR imei1 LIKE ? OR imei2 LIKE ?) ORDER BY id DESC', [shopId, '%$query%', '%$query%', '%$query%']);
    return rows.map(_mobileFromRow).toList(growable: false);
  }

  MobileDevice? findMobileByImei(String shopId, String imei) {
    final rows = _database.database.select(
      "SELECT * FROM mobile_devices WHERE shop_id = ? AND deleted_at IS NULL AND status = 'available' AND (imei1 = ? OR imei2 = ?)",
      [shopId, imei.trim(), imei.trim()],
    );
    return rows.isEmpty ? null : _mobileFromRow(rows.first);
  }

  List<AccessoryItem> accessories(String shopId, {String search = '', bool includeDeleted = false}) {
    final query = search.trim();
    final base = includeDeleted ? 'SELECT * FROM accessories WHERE shop_id = ?' : 'SELECT * FROM accessories WHERE shop_id = ? AND deleted_at IS NULL AND quantity > 0';
    final rows = query.isEmpty
        ? _database.database.select('$base ORDER BY id DESC', [shopId])
        : _database.database.select('$base AND name LIKE ? ORDER BY id DESC', [shopId, '%$query%']);
    return rows.map(_accessoryFromRow).toList(growable: false);
  }

  double totalMobileStockValue(String shopId) {
    final rows = _database.database.select(
      "SELECT COALESCE(SUM(buy_price), 0) AS total FROM mobile_devices WHERE shop_id = ? AND status = 'available'",
      [shopId],
    );
    return rows.isEmpty ? 0 : ((rows.first['total'] as num?) ?? 0).toDouble();
  }

  double totalAccessoriesStockValue(String shopId) {
    final rows = _database.database.select(
      'SELECT COALESCE(SUM(buy_price * quantity), 0) AS total FROM accessories WHERE shop_id = ? AND quantity > 0',
      [shopId],
    );
    return rows.isEmpty ? 0 : ((rows.first['total'] as num?) ?? 0).toDouble();
  }

  String? addMobile({
    required String shopId,
    required String name,
    String? color,
    required String imei1,
    String? imei2,
    String? ram,
    String? storage,
    required String condition,
    String? picturePath,
    String? sourceCustomerName,
    String? sourceCnic,
    String? sourcePhone,
    String? sourceAddress,
    String? sourceCnicPicture,
    double buyPrice = 0,
    double sellPrice = 0,
  }) {
    if (name.trim().isEmpty || imei1.trim().isEmpty) return 'Device name and IMEI 1 are required.';
    if (buyPrice <= 0) return 'Buy price is required and must be greater than zero.';
    if (condition == 'used' && [sourceCustomerName, sourceCnic, sourcePhone, sourceAddress].any((value) => value == null || value.trim().isEmpty)) return 'Customer name, CNIC, phone number, and address are required for used devices.';
    final now = DateTime.now().toUtc().toIso8601String();
    final normalizedColor = (color ?? '').trim();
    try {
      _database.database.execute('''INSERT INTO mobile_devices
        (shop_id, name, picture_path, color, imei1, imei2, ram, storage, condition, source_customer_name, source_cnic, source_phone, source_address, source_cnic_picture, buy_price, sell_price, created_at, updated_at, deleted_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''', [shopId, name.trim(), picturePath, normalizedColor, imei1.trim(), imei2?.trim(), ram?.trim(), storage?.trim(), condition, sourceCustomerName?.trim(), sourceCnic?.trim(), sourcePhone?.trim(), sourceAddress?.trim(), sourceCnicPicture, buyPrice, sellPrice, now, now, null]);
      final deviceId = _database.database.select('SELECT last_insert_rowid() AS id').first['id'] as int;
      _queue(shopId, 'mobile_device', deviceId, {'id': deviceId, 'shop_id': shopId, 'name': name.trim(), 'picture_path': picturePath, 'color': normalizedColor, 'imei1': imei1.trim(), 'imei2': imei2?.trim(), 'ram': ram?.trim(), 'storage': storage?.trim(), 'condition': condition, 'buy_price': buyPrice, 'sell_price': sellPrice, 'status': 'available', 'created_at': now, 'updated_at': now});
      _database.database.execute('INSERT INTO purchases (shop_id, product_id, product_name, quantity, total_cost, purchased_at) VALUES (?, ?, ?, 1, ?, ?)', [shopId, deviceId, name.trim(), buyPrice, now]);
      return null;
    } catch (_) {
      return 'IMEI 1 or IMEI 2 already exists.';
    }
  }

  String? addAccessory({required String shopId, required String name, String? picturePath, required double buyPrice, double sellPrice = 0, required int quantity}) {
    if (name.trim().isEmpty || quantity < 1) return 'Item name and a quantity greater than zero are required.';
    if (buyPrice <= 0) return 'Buy price is required and must be greater than zero.';
    final now = DateTime.now().toUtc().toIso8601String();
    _database.database.execute('INSERT INTO accessories (shop_id, name, picture_path, buy_price, sell_price, quantity, created_at, updated_at, deleted_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)', [shopId, name.trim(), picturePath, buyPrice, sellPrice, quantity, now, now, null]);
    _database.database.execute('INSERT INTO purchases (shop_id, product_id, product_name, quantity, total_cost, purchased_at) VALUES (?, last_insert_rowid(), ?, ?, ?, ?)', [shopId, name.trim(), quantity, buyPrice * quantity, now]);
    return null;
  }

  String? deleteMobile({required String shopId, required int mobileId}) {
    final adminError = _requireAdmin();
    if (adminError != null) return adminError;
    final now = DateTime.now().toUtc().toIso8601String();
    _database.database.execute('UPDATE mobile_devices SET deleted_at = ?, updated_at = ?, status = CASE WHEN status = \'sold\' THEN \'sold\' ELSE \'deleted\' END WHERE id = ? AND shop_id = ?', [now, now, mobileId, shopId]);
    return null;
  }

  String? deleteAccessory({required String shopId, required int accessoryId}) {
    final adminError = _requireAdmin();
    if (adminError != null) return adminError;
    final now = DateTime.now().toUtc().toIso8601String();
    _database.database.execute('UPDATE accessories SET deleted_at = ?, updated_at = ? WHERE id = ? AND shop_id = ?', [now, now, accessoryId, shopId]);
    return null;
  }

  String? updateAccessory({
    required String shopId,
    required int accessoryId,
    required String name,
    String? picturePath,
    required double buyPrice,
    required int quantity,
  }) {
    final adminError = _requireAdmin();
    if (adminError != null) return adminError;
    if (name.trim().isEmpty || quantity < 0) return 'Item name and valid quantity are required.';
    if (buyPrice <= 0) return 'Buy price is required and must be greater than zero.';
    final now = DateTime.now().toUtc().toIso8601String();
    _database.database.execute(
      'UPDATE accessories SET name = ?, picture_path = ?, buy_price = ?, quantity = ?, updated_at = ?, deleted_at = CASE WHEN deleted_at IS NOT NULL THEN NULL ELSE deleted_at END WHERE id = ? AND shop_id = ?',
      [name.trim(), picturePath, buyPrice, quantity, now, accessoryId, shopId],
    );
    return null;
  }

  String? updateMobile({
    required String shopId,
    required int mobileId,
    required String name,
    String? color,
    required String imei1,
    String? imei2,
    String? ram,
    String? storage,
    required String condition,
    String? picturePath,
    String? sourceCustomerName,
    String? sourceCnic,
    String? sourcePhone,
    String? sourceAddress,
    String? sourceCnicPicture,
    required double buyPrice,
  }) {
    final adminError = _requireAdmin();
    if (adminError != null) return adminError;
    if (name.trim().isEmpty || imei1.trim().isEmpty) return 'Device name and IMEI 1 are required.';
    if (buyPrice <= 0) return 'Buy price is required and must be greater than zero.';
    if (condition == 'used' && [sourceCustomerName, sourceCnic, sourcePhone, sourceAddress].any((value) => value == null || value.trim().isEmpty)) return 'Customer name, CNIC, phone number, and address are required for used devices.';
    final now = DateTime.now().toUtc().toIso8601String();
    final normalizedColor = (color ?? '').trim();
    try {
      _database.database.execute(
        '''UPDATE mobile_devices SET name = ?, picture_path = ?, color = ?, imei1 = ?, imei2 = ?, ram = ?, storage = ?, condition = ?, source_customer_name = ?, source_cnic = ?, source_phone = ?, source_address = ?, source_cnic_picture = ?, buy_price = ?, updated_at = ?, deleted_at = CASE WHEN deleted_at IS NOT NULL THEN NULL ELSE deleted_at END WHERE id = ? AND shop_id = ?''',
        [name.trim(), picturePath, normalizedColor, imei1.trim(), imei2?.trim(), ram?.trim(), storage?.trim(), condition, sourceCustomerName?.trim(), sourceCnic?.trim(), sourcePhone?.trim(), sourceAddress?.trim(), sourceCnicPicture, buyPrice, now, mobileId, shopId],
      );
      return null;
    } catch (_) {
      return 'IMEI 1 or IMEI 2 already exists.';
    }
  }

  String? completeSale({
    required String shopId,
    required List<CartLine> cart,
    String? customerName,
    String? customerPhone,
    String? customerAddress,
    int? employeeId,
    String? employeeName,
  }) {
    if (cart.isEmpty) return 'Cart is empty.';
    if (cart.any((line) => !line.hasValidSalePrice)) return 'Every cart item must have a valid selling price greater than or equal to 0.';
    if (cart.any((line) => line.isMobile) && (customerName == null || customerName.trim().isEmpty || customerPhone == null || customerPhone.trim().isEmpty || customerAddress == null || customerAddress.trim().isEmpty)) return 'Customer name, phone number, and address are required for mobile sales.';
    
    final now = DateTime.now().toUtc().toIso8601String();
    final billNumber = _database.generateBillNumber(shopId);
    SharedCart.instance.lastBillNumber = billNumber;
    if (cart.any((line) => line.isMobile)) {
      _database.database.execute('INSERT INTO customers (shop_id, name, contact, address, created_at) VALUES (?, ?, ?, ?, ?)', [shopId, customerName!.trim(), customerPhone!.trim(), customerAddress!.trim(), now]);
    }
    for (final line in cart) {
      if (line.isMobile) {
        if (line.device != null) {
          // Old mobile_devices table support
          final device = line.device!;
          _database.database.execute("UPDATE mobile_devices SET status = 'sold', updated_at = ? WHERE id = ? AND status = 'available'", [now, device.id]);
          _database.database.execute(
            'INSERT INTO sales (shop_id, product_id, product_name, quantity, selling_total, purchase_total, imei, customer_name, customer_phone, customer_address, sold_at, employee_id, employee_name, bill_number) VALUES (?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [shopId, device.id, device.name, line.salePrice, device.buyPrice, device.imei1, customerName?.trim(), customerPhone?.trim(), customerAddress?.trim(), now, employeeId, employeeName, billNumber],
          );
        } else if (line.mobileUnit != null) {
          // New mobile_units table support
          final unit = line.mobileUnit!;
          _database.updateMobileUnitStatus(unit.id, 'sold', shopId: shopId);
          
          // Get model name from mobile_models
          final model = _database.getMobileModel(unit.mobileModelId);
          final modelName = model?['name'] as String? ?? 'Mobile Device';
          
          _database.database.execute(
            'INSERT INTO sales (shop_id, product_id, product_name, quantity, selling_total, purchase_total, imei, customer_name, customer_phone, customer_address, sold_at, employee_id, employee_name, bill_number) VALUES (?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [shopId, unit.mobileModelId, modelName, line.salePrice, unit.buyPrice, unit.imei1, customerName?.trim(), customerPhone?.trim(), customerAddress?.trim(), now, employeeId, employeeName, billNumber],
          );
        }
      } else {
        final item = line.accessory!;
        final rows = _database.database.select('SELECT quantity FROM accessories WHERE id = ? AND shop_id = ?', [item.id, shopId]);
        if (rows.isEmpty || (rows.first['quantity'] as int) < line.quantity) return 'Insufficient accessory stock for ${item.name}.';
        _database.database.execute('UPDATE accessories SET quantity = quantity - ?, updated_at = ? WHERE id = ?', [line.quantity, now, item.id]);
        _database.database.execute(
          'INSERT INTO sales (shop_id, product_id, product_name, quantity, selling_total, purchase_total, customer_name, customer_phone, customer_address, sold_at, employee_id, employee_name, bill_number) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [shopId, item.id, item.name, line.quantity, line.total, line.buyPrice * line.quantity, customerName?.trim(), customerPhone?.trim(), customerAddress?.trim(), now, employeeId, employeeName, billNumber],
        );
      }
    }
    return null;
  }

  MobileDevice _mobileFromRow(Map<String, Object?> row) {
    final colorValue = (row['color'] as String?) ?? '';
    return MobileDevice(
      id: row['id'] as int,
      name: row['name'] as String,
      picturePath: row['picture_path'] as String?,
      color: colorValue.trim().isEmpty ? null : colorValue,
      imei1: row['imei1'] as String,
      imei2: row['imei2'] as String?,
      ram: row['ram'] as String?,
      storage: row['storage'] as String?,
      condition: row['condition'] as String,
      buyPrice: (row['buy_price'] as num).toDouble(),
      sellPrice: (row['sell_price'] as num).toDouble(),
    );
  }

  AccessoryItem _accessoryFromRow(Map<String, Object?> row) => AccessoryItem(id: row['id'] as int, name: row['name'] as String, picturePath: row['picture_path'] as String?, buyPrice: (row['buy_price'] as num).toDouble(), sellPrice: (row['sell_price'] as num).toDouble(), quantity: row['quantity'] as int);

  // Mobile Model Methods
  String? createMobileModel({
    required String shopId,
    required String name,
    String? image,
  }) {
    if (name.trim().isEmpty) return 'Model name is required.';
    final existing = _database.database.select(
      'SELECT id FROM mobile_models WHERE shop_id = ? AND lower(name) = lower(?) LIMIT 1',
      [shopId, name.trim()],
    );
    if (existing.isNotEmpty) return null;
    try {
      final modelId = _database.createMobileModel(shopId, name.trim(), image);
      final now = DateTime.now().toUtc().toIso8601String();
      _queue(shopId, 'mobile_model', modelId, {'id': modelId, 'shop_id': shopId, 'name': name.trim(), 'image': image, 'created_at': now, 'updated_at': now});
      return null;
    } catch (e) {
      return 'Error creating mobile model: $e';
    }
  }

  List<MobileModel> getMobileModels(String shopId) {
    final rows = _database.getMobileModels(shopId);
    return rows.map((row) {
      final modelId = row['id'] as int;
      final stockCount = _database.getAvailableStockCount(modelId, shopId);
      return MobileModel(
        id: modelId,
        shopId: row['shop_id'] as String,
        name: row['name'] as String,
        image: row['image'] as String?,
        stockCount: stockCount,
        createdAt: DateTime.parse(row['created_at'] as String),
      );
    }).toList();
  }

  int availableMobileUnitCount(String shopId) {
    final rows = _database.database.select(
      "SELECT COUNT(*) AS count FROM mobile_units WHERE shop_id = ? AND status = 'available'",
      [shopId],
    );
    return rows.isEmpty ? 0 : (rows.first['count'] as num).toInt();
  }

  double totalMobileUnitStockValue(String shopId) {
    final rows = _database.database.select(
      "SELECT COALESCE(SUM(buy_price), 0) AS total FROM mobile_units WHERE shop_id = ? AND status = 'available'",
      [shopId],
    );
    return rows.isEmpty ? 0 : (rows.first['total'] as num).toDouble();
  }

  MobileModel? getMobileModel(int modelId, String shopId) {
    final row = _database.getMobileModelForShop(modelId, shopId);
    if (row == null) return null;
    final stockCount = _database.getAvailableStockCount(modelId, shopId);
    return MobileModel(
      id: modelId,
      shopId: row['shop_id'] as String,
      name: row['name'] as String,
      image: row['image'] as String?,
      stockCount: stockCount,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  // Mobile Unit Methods
  String? addMobileUnit({
    required String shopId,
    required int mobileModelId,
    required String imei1,
    String? imei2,
    required double buyPrice,
    String? ram,
    String? storage,
    int? supplierId,
  }) {
    if (imei1.trim().isEmpty) return 'IMEI 1 is required.';
    if (buyPrice <= 0) return 'Buy price must be greater than zero.';
    
    try {
      final unitId = _database.createMobileUnit(
        shopId,
        mobileModelId,
        imei1.trim(),
        imei2?.trim(),
        buyPrice,
        ram?.trim(),
        storage?.trim(),
        supplierId,
      );
      final now = DateTime.now().toUtc().toIso8601String();
      _queue(shopId, 'mobile_unit', unitId, {'id': unitId, 'shop_id': shopId, 'mobile_model_id': mobileModelId, 'imei_1': imei1.trim(), 'imei_2': imei2?.trim(), 'buy_price': buyPrice, 'ram': ram?.trim(), 'storage': storage?.trim(), 'supplier_id': supplierId, 'status': 'available', 'created_at': now, 'updated_at': now});
      
      // Record purchase
      final model = _database.getMobileModel(mobileModelId);
      final modelName = model?['name'] as String? ?? 'Mobile Unit';
      _database.database.execute(
        'INSERT INTO purchases (shop_id, product_id, product_name, quantity, total_cost, purchased_at) VALUES (?, ?, ?, 1, ?, ?)',
        [shopId, mobileModelId, modelName, buyPrice, now],
      );
      
      return null;
    } catch (e) {
      return 'Error: IMEI may already exist or invalid data.';
    }
  }

  MobileUnit? addScannedMobileUnit({
    required String shopId,
    required String modelName,
    required String imei1,
    required double buyPrice,
    String? ram,
    String? storage,
  }) {
    final normalizedImei = imei1.trim();
    final normalizedModel = modelName.trim();
    if (normalizedModel.isEmpty || normalizedImei.isEmpty || buyPrice <= 0) {
      return null;
    }
    if (_database.database.select(
      'SELECT 1 FROM mobile_devices WHERE shop_id = ? AND (imei1 = ? OR imei2 = ?) UNION ALL SELECT 1 FROM mobile_units WHERE shop_id = ? AND (imei_1 = ? OR imei_2 = ?) LIMIT 1',
      [shopId, normalizedImei, normalizedImei, shopId, normalizedImei, normalizedImei],
    ).isNotEmpty) {
      return null;
    }

    final existingModel = _database.database.select(
      'SELECT id FROM mobile_models WHERE shop_id = ? AND lower(name) = lower(?) LIMIT 1',
      [shopId, normalizedModel],
    );
    final modelId = existingModel.isNotEmpty
        ? existingModel.first['id'] as int
        : _database.createMobileModel(shopId, normalizedModel, null);
    if (existingModel.isEmpty) {
      final now = DateTime.now().toUtc().toIso8601String();
      _queue(shopId, 'mobile_model', modelId, {'id': modelId, 'shop_id': shopId, 'name': normalizedModel, 'image': null, 'created_at': now, 'updated_at': now});
    }

    final error = addMobileUnit(
      shopId: shopId,
      mobileModelId: modelId,
      imei1: normalizedImei,
      buyPrice: buyPrice,
      ram: ram,
      storage: storage,
    );
    if (error != null) return null;
    final row = _database.database.select(
      'SELECT * FROM mobile_units WHERE shop_id = ? AND imei_1 = ? LIMIT 1',
      [shopId, normalizedImei],
    );
    if (row.isEmpty) return null;
    final unit = row.first;
    return MobileUnit(
      id: unit['id'] as int,
      shopId: shopId,
      mobileModelId: unit['mobile_model_id'] as int,
      imei1: unit['imei_1'] as String,
      imei2: unit['imei_2'] as String?,
      buyPrice: (unit['buy_price'] as num).toDouble(),
      ram: unit['ram'] as String?,
      storage: unit['storage'] as String?,
      supplierId: unit['supplier_id'] as int?,
      status: unit['status'] as String,
      createdAt: DateTime.parse(unit['created_at'] as String),
    );
  }

  List<MobileUnit> getMobileUnitsByModel(int mobileModelId, [String? shopId]) {
    final rows = _database.getMobileUnitsByModel(mobileModelId, shopId);
    return rows.map((row) {
      return MobileUnit(
        id: row['id'] as int,
        shopId: row['shop_id'] as String,
        mobileModelId: row['mobile_model_id'] as int,
        imei1: row['imei_1'] as String,
        imei2: row['imei_2'] as String?,
        buyPrice: (row['buy_price'] as num).toDouble(),
        ram: row['ram'] as String?,
        storage: row['storage'] as String?,
        supplierId: row['supplier_id'] as int?,
        status: row['status'] as String,
        createdAt: DateTime.parse(row['created_at'] as String),
      );
    }).toList();
  }

  MobileUnit? findMobileUnitByImei(String shopId, String imei) {
    final row = _database.getMobileUnitByImei(imei.trim(), shopId);
    if (row == null) return null;
    return MobileUnit(
      id: row['id'] as int,
      shopId: row['shop_id'] as String,
      mobileModelId: row['mobile_model_id'] as int,
      imei1: row['imei_1'] as String,
      imei2: row['imei_2'] as String?,
      buyPrice: (row['buy_price'] as num).toDouble(),
      ram: row['ram'] as String?,
      storage: row['storage'] as String?,
      supplierId: row['supplier_id'] as int?,
      status: row['status'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  String? deleteMobileUnit(int unitId, String shopId) {
    final adminError = _requireAdmin();
    if (adminError != null) return adminError;
    try {
      _database.deleteMobileUnit(unitId, shopId: shopId);
      return null;
    } catch (e) {
      return 'Error deleting mobile unit: $e';
    }
  }

  String? deleteMobileModel({required String shopId, required int modelId}) {
    final adminError = _requireAdmin();
    if (adminError != null) return adminError;
    try {
      _database.deleteMobileModel(modelId, shopId: shopId);
      return null;
    } catch (e) {
      return 'Error deleting mobile model: $e';
    }
  }

  // Supplier Methods
  String? createSupplier({
    required String shopId,
    required String name,
    String? phone,
    String? address,
    String? notes,
  }) {
    if (name.trim().isEmpty) return 'Supplier name is required.';
    try {
      _database.createSupplier(shopId, name.trim(), phone?.trim(), address?.trim(), notes?.trim());
      return null;
    } catch (e) {
      return 'Error creating supplier: $e';
    }
  }

  List<Supplier> getSuppliers(String shopId) {
    final rows = _database.getSuppliers(shopId);
    return rows.map((row) {
      return Supplier(
        id: row['id'] as int,
        shopId: row['shop_id'] as String,
        name: row['name'] as String,
        phone: row['phone'] as String?,
        address: row['address'] as String?,
        notes: row['notes'] as String?,
        createdAt: DateTime.parse(row['created_at'] as String),
      );
    }).toList();
  }

  String? deleteSupplier(int supplierId, String shopId) {
    final adminError = _requireAdmin();
    if (adminError != null) return adminError;
    try {
      _database.deleteSupplier(supplierId);
      return null;
    } catch (e) {
      return 'Error deleting supplier: $e';
    }
  }

  // Return Methods
  String? processSaleReturn({
    required String shopId,
    required int saleId,
    required int? mobileUnitId,
    required String? billNumber,
    String? returnReason,
  }) {
    if (billNumber == null || billNumber.trim().isEmpty) return 'Bill number is required.';

    try {
      _database.createReturn(shopId, saleId, null, mobileUnitId, billNumber, returnReason ?? '');
      if (mobileUnitId != null) {
        _database.updateMobileUnitStatus(mobileUnitId, 'available', shopId: shopId);
      }
      return null;
    } catch (e) {
      return 'Error processing return: $e';
    }
  }

  String? returnSaleByBillNumber({
    required String shopId,
    required String billNumber,
    String? returnReason,
  }) {
    final normalizedBillNumber = billNumber.trim();
    if (normalizedBillNumber.isEmpty) return 'Bill number is required.';

    final saleRows = _database.database.select(
      'SELECT * FROM sales WHERE shop_id = ? AND bill_number = ? ORDER BY sold_at DESC LIMIT 1',
      [shopId, normalizedBillNumber],
    );
    if (saleRows.isEmpty) return 'No sale found for this bill number.';

    final sale = saleRows.first;
    final saleId = (sale['id'] as int?) ?? -1;
    final saleImei = sale['imei'] as String?;
    final mobileUnitId = saleImei != null && saleImei.trim().isNotEmpty
        ? (_database.getMobileUnitByImei(saleImei.trim(), shopId)?['id'] as int?)
        : null;

    return processSaleReturn(
      shopId: shopId,
      saleId: saleId,
      mobileUnitId: mobileUnitId,
      billNumber: normalizedBillNumber,
      returnReason: returnReason,
    );
  }

  List<SaleReturn> getReturnsByBillNumber(String billNumber, String shopId) {
    final rows = _database.getReturnsByBillNumber(billNumber, shopId);
    return rows.map((row) {
      return SaleReturn(
        id: row['id'] as int,
        shopId: row['shop_id'] as String,
        saleId: row['sale_id'] as int?,
        mobileUnitId: row['mobile_unit_id'] as int?,
        billNumber: row['bill_number'] as String?,
        returnedAt: DateTime.parse(row['returned_at'] as String),
        returnReason: row['return_reason'] as String?,
      );
    }).toList();
  }
}

class SharedCart extends ChangeNotifier {
  static final SharedCart instance = SharedCart._();
  SharedCart._();

  final List<CartLine> lines = [];
  String? shopId;

  void addMobile(String activeShopId, MobileDevice device) {
    shopId ??= activeShopId;
    if (shopId == activeShopId && !lines.any((line) => line.device?.id == device.id)) {
      lines.add(CartLine.mobile(device, salePrice: device.sellPrice));
      notifyListeners();
    }
  }

  void addAccessory(String activeShopId, AccessoryItem item) {
    shopId ??= activeShopId;
    if (shopId != activeShopId) return;
    final index = lines.indexWhere((line) => line.accessory?.id == item.id);
    if (index == -1) {
      lines.add(CartLine.accessory(item, salePrice: item.sellPrice));
    } else if (lines[index].quantity < item.quantity) {
      lines[index] = CartLine.accessory(item, quantity: lines[index].quantity + 1, salePrice: lines[index].salePrice);
    }
    notifyListeners();
  }

  void addMobileUnit(String activeShopId, MobileUnit unit) {
    shopId ??= activeShopId;
    if (shopId != activeShopId || unit.status != 'available') return;
    if (lines.any((line) => line.mobileUnit?.id == unit.id)) return;
    lines.add(CartLine.mobile(null, mobileUnit: unit));
    notifyListeners();
  }

  void removeAt(int index) { lines.removeAt(index); if (lines.isEmpty) shopId = null; notifyListeners(); }
  void clear() { lines.clear(); shopId = null; lastBillNumber = null; notifyListeners(); }
  String? lastBillNumber;
  double get total => lines.fold(0, (sum, line) => sum + line.total);
  bool get hasMobile => lines.any((line) => line.isMobile);
}
