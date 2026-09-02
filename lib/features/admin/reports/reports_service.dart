import '../../../core/database/database_service.dart';
import '../management/admin_management_service.dart';

class ReportRecord {
  const ReportRecord({
    required this.id,
    required this.type,
    required this.dateTime,
    required this.person,
    required this.description,
    required this.amount,
    required this.detail,
    this.billNumber,
    this.saleId,
  });

  final String id;
  final String type;
  final DateTime dateTime;
  final String person;
  final String description;
  final double amount;
  final String detail;
  final String? billNumber;
  final int? saleId;
}

class ReportsService {
  ReportsService() : _database = DatabaseService.instance;
  final DatabaseService _database;

  List<ReportRecord> reports(
    String shopId, {
    String type = 'All',
    String search = '',
    DateTime? date,
  }) {
    final records = <ReportRecord>[];
    final returnedBillNumbers = _database.database.select(
      'SELECT DISTINCT bill_number FROM returns WHERE shop_id = ? AND bill_number IS NOT NULL',
      [shopId],
    ).map((row) => (row['bill_number'] as String?) ?? '').where((value) => value.isNotEmpty).toSet();

    final sales = _database.database.select(
      'SELECT id, product_name, quantity, selling_total, purchase_total, imei, customer_name, customer_phone, customer_address, sold_at, bill_number FROM sales WHERE shop_id = ? ORDER BY sold_at DESC',
      [shopId],
    );
    for (final row in sales) {
      final billNumber = (row['bill_number'] as String?) ?? '';
      if (billNumber.isNotEmpty && returnedBillNumbers.contains(billNumber)) {
        continue;
      }
      final isMobile = row['imei'] != null;
      final employeeName = (row['employee_name'] as String?)?.trim();
      records.add(ReportRecord(
        id: 'SALE-${row['id']}',
        type: isMobile ? 'Mobile Sale' : 'Accessories Sale',
        dateTime: DateTime.parse(row['sold_at'] as String),
        person: (row['customer_name'] as String?)?.trim().isNotEmpty == true ? row['customer_name'] as String : 'Walk-in customer',
        description: '${row['product_name']} x${row['quantity']}${employeeName != null && employeeName.isNotEmpty ? ' • by $employeeName' : ''}',
        amount: (row['selling_total'] as num).toDouble(),
        detail: '${row['product_name']}\n${isMobile ? 'IMEI: ${row['imei']}\n' : ''}Quantity: ${row['quantity']}\nRate: PKR ${((row['selling_total'] as num) / (row['quantity'] as num)).toStringAsFixed(0)}\n${(row['customer_phone'] as String?)?.isNotEmpty == true ? 'Phone: ${row['customer_phone']}\n' : ''}${(row['customer_address'] as String?)?.isNotEmpty == true ? 'Address: ${row['customer_address']}\n' : ''}${employeeName != null && employeeName.isNotEmpty ? 'Employee: $employeeName' : ''}',
        billNumber: billNumber.isNotEmpty ? billNumber : null,
        saleId: row['id'] as int,
      ));
    }
    final repairs = _database.database.select('SELECT * FROM repairs WHERE shop_id = ? ORDER BY created_at DESC', [shopId]);
    for (final row in repairs) {
      records.add(ReportRecord(
        id: 'REPAIR-${row['id']}',
        type: 'Repair',
        dateTime: DateTime.parse(row['created_at'] as String),
        person: 'Walk-in customer',
        description: row['name'] as String,
        amount: (row['charge'] as num).toDouble(),
        detail: 'Repair: ${row['name']}\nCost: PKR ${(row['cost'] as num).toStringAsFixed(0)}\nCharge: PKR ${(row['charge'] as num).toStringAsFixed(0)}\nProfit: PKR ${(row['profit'] as num).toStringAsFixed(0)}',
      ));
    }
    final debts = _database.database.select('''SELECT t.*, d.customer_name FROM debt_transactions t JOIN debtors d ON d.id = t.debtor_id WHERE d.shop_id = ? ORDER BY t.created_at DESC''', [shopId]);
    for (final row in debts) {
      final isPayment = row['type'] == 'payment';
      records.add(ReportRecord(
        id: 'DEBT-${row['id']}',
        type: 'Debt',
        dateTime: DateTime.parse(row['created_at'] as String),
        person: row['customer_name'] as String,
        description: row['item'] as String,
        amount: (row['amount'] as num).toDouble() * (isPayment ? -1 : 1),
        detail: '${isPayment ? 'Payment received' : 'Debt added'}\n${row['item']}\nAmount: PKR ${(row['amount'] as num).toStringAsFixed(0)}\nBalance: PKR ${_debtBalance(row['debtor_id'] as int, row['id'] as int).toStringAsFixed(0)}',
      ));
    }
    records.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    final query = search.trim().toLowerCase();
    return records.where((record) {
      final typeMatches = type == 'All' || record.type == type;
      final dateMatches = date == null || (record.dateTime.toLocal().year == date.year && record.dateTime.toLocal().month == date.month && record.dateTime.toLocal().day == date.day);
      final textMatches = query.isEmpty || [record.id, record.person, record.description, record.detail, record.billNumber ?? ''].join(' ').toLowerCase().contains(query);
      return typeMatches && dateMatches && textMatches;
    }).toList(growable: false);
  }

  ShopDetails shopDetails(String shopId) => AdminManagementService().shopDetails(shopId);

  double _debtBalance(int debtorId, int transactionId) {
    final row = _database.database.select("SELECT COALESCE(SUM(CASE WHEN type = 'debt' THEN amount ELSE -amount END), 0) AS balance FROM debt_transactions WHERE debtor_id = ? AND id <= ?", [debtorId, transactionId]).first;
    return (row['balance'] as num).toDouble();
  }
}
