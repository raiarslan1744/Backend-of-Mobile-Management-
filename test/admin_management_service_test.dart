import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:develop/core/database/database_service.dart';
import 'package:develop/features/admin/management/admin_management_service.dart';

void main() {
  test('persists repair profit, debt balance, and shop settings', () {
    DatabaseService.instance.resetForTesting();
    final service = AdminManagementService();
    const shopId = 'MANAGEMENT-SHOP';

    final repair = service.addRepair(shopId: shopId, name: 'Battery Change', cost: 1300, charge: 3000);
    expect(repair?.profit, 1700);
    expect(service.repairs(shopId), hasLength(1));

    final debtor = service.addDebtor(shopId: shopId, name: 'Ali', phone: '0300', address: 'Lahore')!;
    expect(service.addDebt(debtorId: debtor.id, item: 'Cable', amount: 100), isNull);
    expect(service.addDebt(debtorId: debtor.id, item: 'Charger', amount: 500), isNull);
    expect(service.addPayment(debtorId: debtor.id, amount: 200), isNull);
    expect(service.debtHistory(debtor.id), hasLength(3));
    expect(service.debtors(shopId).single.balance, 400);
  });

  test('persists the local backup folder and writes backups there', () async {
    final tempRoot = await Directory.systemTemp.createTemp('local_backup_test_');
    addTearDown(() async {
      DatabaseService.instance.database.dispose();
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    await DatabaseService.initialize('${tempRoot.path}${Platform.pathSeparator}app_data');
    DatabaseService.instance.resetForTesting();
    final service = AdminManagementService();
    const shopId = 'BACKUP-SHOP';

    final selectedDir = Directory('${tempRoot.path}${Platform.pathSeparator}shop_backups');
    await selectedDir.create(recursive: true);

    await service.setLocalBackupFolderPath(selectedDir.path, shopId: shopId);
    expect(await service.getLocalBackupFolderPath(shopId: shopId), selectedDir.path);

    final backupPath = await service.createLocalBackup(shopId);
    expect(backupPath, isNotNull);
    expect(backupPath!.contains(selectedDir.path), isTrue);
    expect(File(backupPath).existsSync(), isTrue);
  });
}
