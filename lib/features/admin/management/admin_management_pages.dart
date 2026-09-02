import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'admin_management_service.dart';

class RepairsPage extends StatefulWidget {
  const RepairsPage({super.key, required this.shopId});
  final String shopId;
  @override
  State<RepairsPage> createState() => _RepairsPageState();
}

class _RepairsPageState extends State<RepairsPage> {
  final _service = AdminManagementService();
  final _name = TextEditingController();
  final _cost = TextEditingController();
  final _charge = TextEditingController();
  @override
  void dispose() { _name.dispose(); _cost.dispose(); _charge.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth > 900;
      return _pageScaffold(
        'Repairs',
        wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _form()),
                  const SizedBox(width: 22),
                  Expanded(child: _history()),
                ],
              )
            : SingleChildScrollView(
                child: Column(
                  children: [
                    _form(),
                    const SizedBox(height: 18),
                    _history(),
                  ],
                ),
              ),
      );
    },
  );
  Widget _form() => _panel('Add Repair', Column(children: [_field(_name, 'Name of Repair'), _field(_cost, 'Cost', numeric: true), _field(_charge, 'Charge', numeric: true), SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _save, child: const Text('Make Sale')))]));
  Widget _history() => _panel('Repair History', SizedBox(height: 300, child: ListView(children: _service.repairs(widget.shopId).map((repair) => ListTile(title: Text(repair.name), subtitle: Text('Cost PKR ${repair.cost.toStringAsFixed(0)}  •  Charge PKR ${repair.charge.toStringAsFixed(0)}\n${repair.createdAt.toLocal()}'), trailing: Text('Profit\nPKR ${repair.profit.toStringAsFixed(0)}', textAlign: TextAlign.right))).toList())));
  void _save() { final repair = _service.addRepair(shopId: widget.shopId, name: _name.text, cost: double.tryParse(_cost.text) ?? -1, charge: double.tryParse(_charge.text) ?? -1); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(repair == null ? 'Enter valid repair details.' : 'Repair sale saved.'))); if (repair != null) { _name.clear(); _cost.clear(); _charge.clear(); setState(() {}); } }
}

class DebtPage extends StatefulWidget {
  const DebtPage({super.key, required this.shopId});
  final String shopId;
  @override
  State<DebtPage> createState() => _DebtPageState();
}
class _DebtPageState extends State<DebtPage> {
  final _service = AdminManagementService();
  List<DebtorRecord>? _debtors;
  Object? _loadError;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDebtors();
  }

  Future<void> _loadDebtors() async {
    if (mounted) setState(() { _loading = true; _loadError = null; });
    try {
      final debtors = await Future<List<DebtorRecord>>.value(_service.debtors(widget.shopId));
      if (!mounted) return;
      setState(() { _debtors = debtors; _loading = false; });
    } catch (error, stackTrace) {
      debugPrint('Unable to load debts for shop ${widget.shopId}: $error\n$stackTrace');
      if (!mounted) return;
      setState(() { _loadError = error; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) => _pageScaffold(
    'Debt',
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(alignment: Alignment.centerRight, child: ElevatedButton.icon(onPressed: _addDebtor, icon: const Icon(Icons.person_add_outlined), label: const Text('Add Debtor'))),
        const SizedBox(height: 16),
        _panel('Debtors', SizedBox(height: 360, child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Text('Unable to load debts'), const SizedBox(height: 8), ElevatedButton.icon(onPressed: _loadDebtors, icon: const Icon(Icons.refresh), label: const Text('Retry'))]))
                : (_debtors?.isEmpty ?? true)
                    ? const Center(child: Text('No debts found'))
                    : ListView(children: _debtors!.map((debtor) => ListTile(onTap: () => _details(debtor), title: Text(debtor.name), subtitle: Text('${debtor.phone}\n${debtor.address}'), trailing: Text('PKR ${debtor.balance.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w700)))).toList()))),
      ],
    ),
  );
  Future<void> _addDebtor() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final address = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Debtor'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [_field(name, 'Customer Name'), _field(phone, 'Phone Number'), _field(address, 'Address')],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              try {
                final debtor = _service.addDebtor(shopId: widget.shopId, name: name.text, phone: phone.text, address: address.text);
                if (debtor == null) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('Customer name, phone number, and address are required.')));
                  return;
                }
                Navigator.pop(dialogContext, true);
              } catch (error) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('Could not save debtor: $error')));
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    name.dispose();
    phone.dispose();
    address.dispose();
    if (saved == true && mounted) setState(() {});
  }
  void _details(DebtorRecord debtor) { showDialog<void>(context: context, builder: (context) => _DebtorDetails(service: _service, debtor: debtor, onChanged: () { Navigator.pop(context); setState(() {}); })); }
}
class _DebtorDetails extends StatefulWidget {
  const _DebtorDetails({required this.service, required this.debtor, required this.onChanged});
  final AdminManagementService service; final DebtorRecord debtor; final VoidCallback onChanged;
  @override State<_DebtorDetails> createState() => _DebtorDetailsState();
}
class _DebtorDetailsState extends State<_DebtorDetails> {
  final _item = TextEditingController(); final _amount = TextEditingController();
  @override void dispose() { _item.dispose(); _amount.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.debtor.name),
    content: SizedBox(
      width: 560,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${widget.debtor.phone}  •  ${widget.debtor.address}'),
          const SizedBox(height: 10),
          Text('Balance: PKR ${widget.debtor.balance.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView(
                shrinkWrap: true,
                children: widget.service.debtHistory(widget.debtor.id).map((entry) => ListTile(title: Text(entry.item), subtitle: Text(entry.createdAt.toLocal().toString()), trailing: Text('${entry.type == 'payment' ? '-' : '+'} PKR ${entry.amount.toStringAsFixed(0)}'))).toList(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [Expanded(child: ElevatedButton.icon(onPressed: _addDebt, icon: const Icon(Icons.add), label: const Text('Debt'))), const SizedBox(width: 8), Expanded(child: OutlinedButton.icon(onPressed: _addPayment, icon: const Icon(Icons.remove), label: const Text('Payment')))]),
        ],
      ),
    ),
  );
  void _addDebt() { _entry(false); }
  void _addPayment() { _entry(true); }
  void _entry(bool payment) { _item.text = payment ? 'Payment' : ''; showDialog<void>(context: context, builder: (context) => AlertDialog(title: Text(payment ? 'Add Payment' : 'Add Debt'), content: Column(mainAxisSize: MainAxisSize.min, children: [_field(_item, payment ? 'Payment' : 'Item'), _field(_amount, 'Amount', numeric: true)]), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton(onPressed: () { final amount = double.tryParse(_amount.text) ?? 0; final error = payment ? widget.service.addPayment(debtorId: widget.debtor.id, amount: amount) : widget.service.addDebt(debtorId: widget.debtor.id, item: _item.text, amount: amount); Navigator.pop(context); if (error != null) { ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(content: Text(error))); } else { _amount.clear(); widget.onChanged(); } }, child: const Text('Save'))])); }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.shopId});
  final String shopId;
  @override State<SettingsPage> createState() => _SettingsPageState();
}
class _SettingsPageState extends State<SettingsPage> {
  final _service = AdminManagementService(); final _name = TextEditingController(); final _address = TextEditingController(); final _phone = TextEditingController(); final _current = TextEditingController(); final _new = TextEditingController(); final _confirm = TextEditingController();
  @override void initState() { super.initState(); final details = _service.shopDetails(widget.shopId); _name.text = details.name; _address.text = details.address; _phone.text = details.phone; }
  @override void dispose() { for (final controller in [_name, _address, _phone, _current, _new, _confirm]) { controller.dispose(); } super.dispose(); }
  @override Widget build(BuildContext context) => _pageScaffold(
    'Settings',
    SingleChildScrollView(
      child: Column(
        children: [
          _panel('Shop Details', Column(children: [_field(_name, 'Shop Name'), _field(_address, 'Shop Address'), _field(_phone, 'Shop Phone Number'), _button('Save Shop Details', () { final error = _service.saveShopDetails(shopId: widget.shopId, name: _name.text, address: _address.text, phone: _phone.text); _message(error ?? 'Shop details saved.'); })])),
          const SizedBox(height: 20),
          _panel('Account Settings', Column(children: [_field(_current, 'Current Password', obscure: true), _field(_new, 'New Password', obscure: true), _field(_confirm, 'Confirm New Password', obscure: true), _button('Change Password', () { final error = _service.changePassword(shopId: widget.shopId, currentPassword: _current.text, newPassword: _new.text, confirmation: _confirm.text); _message(error ?? 'Password changed successfully.'); })])),
        ],
      ),
    ),
  );
  Widget _button(String text, VoidCallback action) => Align(alignment: Alignment.centerLeft, child: ElevatedButton(onPressed: action, child: Text(text)));
  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

class BackupPage extends StatefulWidget {
  const BackupPage({super.key, required this.shopId}); final String shopId;
  @override State<BackupPage> createState() => _BackupPageState();
}
class _BackupPageState extends State<BackupPage> {
  final _service = AdminManagementService();
  String _status = 'Google Drive authorization is not configured.';
  String? _backupFolderPath;

  @override
  void initState() {
    super.initState();
    _loadBackupFolder();
  }

  Future<void> _loadBackupFolder() async {
    final path = await _service.getLocalBackupFolderPath(shopId: widget.shopId);
    if (!mounted) return;
    setState(() => _backupFolderPath = path);
  }

  Future<void> _selectBackupFolder() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final selected = await FilePicker.platform.getDirectoryPath();
    if (selected == null || selected.trim().isEmpty) return;
    final error = await _service.setLocalBackupFolderPath(selected, shopId: widget.shopId);
    if (!mounted) return;
    if (error != null) {
      messenger?.showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() => _backupFolderPath = selected);
    messenger?.showSnackBar(SnackBar(content: Text('Backup folder saved: $selected')));
  }

  Future<void> _openBackupFolder() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await _service.openLocalBackupFolder(shopId: widget.shopId);
    } on StateError catch (error) {
      messenger?.showSnackBar(SnackBar(content: Text(error.message)));
      await _selectBackupFolder();
    }
  }

  Future<void> _restoreFromCustomFile() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['db', 'sqlite']);
    final path = result?.files.single.path;
    if (path == null || path.trim().isEmpty) return;

    if (!mounted) return;

    final isConfirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restore backup?'),
        content: Text('This will replace the current local SQLite data with the selected backup file:\n\n$path\n\nA safety backup will be created before restore.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Restore')),
        ],
      ),
    );

    if (isConfirmed != true) return;

    final error = await _service.restoreBackupFile(path, shopId: widget.shopId);
    if (!mounted) return;
    messenger?.showSnackBar(SnackBar(content: Text(error ?? 'Backup restored successfully.')));
  }

  @override
  Widget build(BuildContext context) => _pageScaffold(
    'Backup',
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panel(
          'Google Drive Backup',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Connect Google Drive using OAuth before enabling cloud backup.'),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => setState(() => _status = 'Google Drive OAuth setup is required for this application.'),
                icon: const Icon(Icons.cloud_outlined),
                label: const Text('Connect Google Drive'),
              ),
              const SizedBox(height: 8),
              Text(_status),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _panel(
          'Backup Location',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_backupFolderPath == null || _backupFolderPath!.trim().isEmpty)
                const Text('No backup location is configured. Please select a backup folder.')
              else
                SelectableText(_backupFolderPath!, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  ElevatedButton.icon(
                    onPressed: _selectBackupFolder,
                    icon: const Icon(Icons.folder_open),
                    label: Text(_backupFolderPath == null || _backupFolderPath!.trim().isEmpty ? 'Select Backup Folder' : 'Change Folder'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _openBackupFolder,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Open Backup Folder'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _panel(
          'Local Shop Data',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Create a portable copy containing this shop\'s SQLite data.'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                children: [
                  ElevatedButton.icon(
                    onPressed: () async {
                      final path = await _service.createLocalBackup(widget.shopId);
                      if (!mounted) return;
                      setState(() => _status = path == null ? 'Backup failed.' : 'Backup saved to $path');
                      _message(path == null ? 'Backup failed.' : 'Backup saved to $path');
                    },
                    icon: const Icon(Icons.save_alt),
                    label: const Text('Create Local Backup'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _service.openShopDataFolder(widget.shopId),
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Open Shop Data Folder'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _restoreFromCustomFile,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Restore from Backup File'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

Widget _pageScaffold(String title, Widget child) => LayoutBuilder(
  builder: (context, constraints) => Padding(
    padding: const EdgeInsets.all(26),
    child: SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Color(0xFF1D2941))),
            const SizedBox(height: 24),
            child,
          ],
        ),
      ),
    ),
  ),
);
Widget _panel(String title, Widget child) => Container(width: double.infinity, padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E7EF))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1D2941))), const SizedBox(height: 16), child]));
Widget _field(TextEditingController controller, String label, {bool numeric = false, bool obscure = false}) => Padding(padding: const EdgeInsets.only(bottom: 12), child: TextField(controller: controller, obscureText: obscure, keyboardType: numeric ? TextInputType.number : TextInputType.text, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder())));
