import 'package:flutter/material.dart';
import 'dart:io';
import 'package:pdf/pdf.dart';
import '../../../core/auth/app_session.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

import 'inventory_service.dart';
import '../management/admin_management_service.dart';

class MobileInventoryPage extends StatelessWidget {
  const MobileInventoryPage({super.key, required this.shopId, this.isEmployee = false});

  final String shopId;
  final bool isEmployee;

  @override
  Widget build(BuildContext context) => InventoryPage(shopId: shopId, accessoriesMode: false, isEmployee: isEmployee);
}

class AccessoriesInventoryPage extends StatelessWidget {
  const AccessoriesInventoryPage({super.key, required this.shopId, this.isEmployee = false});

  final String shopId;
  final bool isEmployee;

  @override
  Widget build(BuildContext context) => InventoryPage(shopId: shopId, accessoriesMode: true, isEmployee: isEmployee);
}

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key, required this.shopId, required this.accessoriesMode, this.isEmployee = false});

  final String shopId;
  final bool accessoriesMode;
  final bool isEmployee;

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final _service = InventoryService();
  final _cart = SharedCart.instance;
  final _searchController = TextEditingController();
  final _scannerController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cart.addListener(_refresh);
  }

  @override
  void dispose() {
    _cart.removeListener(_refresh);
    _searchController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final mobileItems = widget.accessoriesMode ? const <MobileDevice>[] : _service.mobileDevices(widget.shopId, search: _searchController.text);
    final accessoryItems = widget.accessoriesMode ? _service.accessories(widget.shopId, search: _searchController.text) : const <AccessoryItem>[];
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text(widget.accessoriesMode ? 'Accessories Inventory' : 'Mobile Inventory', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Color(0xFF1D2941)))),
              if (!widget.isEmployee)
                ElevatedButton.icon(onPressed: () => _showAddDialog(), icon: const Icon(Icons.add), label: Text(widget.accessoriesMode ? 'Add New Item' : 'Add New Device'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4E2BCB), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15))),
            ]),
            const SizedBox(height: 8),
            const Text('Dashboard  •  Inventory', style: TextStyle(color: Color(0xFF6A7283))),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF4E2BCB),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.accessoriesMode
                          ? 'Total Accessories Stock Value: PKR ${_service.totalAccessoriesStockValue(widget.shopId).toStringAsFixed(0)}'
                          : 'Total Mobile Stock Value: PKR ${_service.totalMobileStockValue(widget.shopId).toStringAsFixed(0)}',
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: LayoutBuilder(builder: (context, constraints) {
                final cart = const CartPanel();
                final inventory = Column(children: [
                  Row(children: [
                    Expanded(child: TextField(controller: _searchController, onChanged: (_) => _refresh(), decoration: InputDecoration(hintText: widget.accessoriesMode ? 'Search in accessories...' : 'Search by model, brand, IMEI or barcode...', prefixIcon: const Icon(Icons.search), suffixIcon: widget.accessoriesMode ? null : IconButton(onPressed: _scanImei, icon: const Icon(Icons.qr_code_scanner)), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)))),
                    if (!widget.accessoriesMode) ...[const SizedBox(width: 12), OutlinedButton.icon(onPressed: _scanImei, icon: const Icon(Icons.qr_code_scanner), label: const Text('Scan IMEI'), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17)))],
                  ]),
                  const SizedBox(height: 18),
                  Expanded(child: widget.accessoriesMode ? _buildAccessories(accessoryItems) : _buildMobiles(mobileItems)),
                ]);
                return constraints.maxWidth > 900 ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: inventory), const SizedBox(width: 18), SizedBox(width: 350, child: cart)]) : Column(children: [Expanded(child: inventory), const SizedBox(height: 18), SizedBox(height: 330, child: cart)]);
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobiles(List<MobileDevice> items) => _inventoryCard(
    header: 'All Phones',
    count: items.length,
    child: items.isEmpty ? const _EmptyState(message: 'No mobile devices in inventory') : ListView.separated(itemCount: items.length, separatorBuilder: (_, index) => const Divider(height: 1), itemBuilder: (_, index) {
      final item = items[index];
      return _productTile(title: item.name, subtitle: '${item.color}  •  ${item.ram ?? ''} ${item.storage ?? ''}\nIMEI 1: ${item.imei1}', price: item.buyPrice, label: 'Buy Price', stock: item.condition.toUpperCase(), icon: Icons.phone_iphone, imagePath: item.picturePath, onTap: () { SharedCart.instance.addMobile(widget.shopId, item); _refresh(); });
    }),
  );

  Widget _buildAccessories(List<AccessoryItem> items) => _inventoryCard(
    header: 'All Accessories',
    count: items.length,
    child: items.isEmpty ? const _EmptyState(message: 'No accessories in inventory') : ListView.separated(itemCount: items.length, separatorBuilder: (_, index) => const Divider(height: 1), itemBuilder: (_, index) {
      final item = items[index];
      return _productTile(title: item.name, subtitle: 'Available quantity: ${item.quantity}', price: item.buyPrice, label: 'Buy Price', stock: 'STOCK ${item.quantity}', icon: Icons.inventory_2_outlined, imagePath: item.picturePath, onTap: () { SharedCart.instance.addAccessory(widget.shopId, item); _refresh(); });
    }),
  );

  Widget _inventoryCard({required String header, required int count, required Widget child}) => Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E7EF))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Padding(padding: const EdgeInsets.fromLTRB(20, 18, 20, 14), child: Row(children: [Text(header, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1D2941))), const SizedBox(width: 8), Text('$count items', style: const TextStyle(color: Color(0xFF6A7283)))])), const Divider(height: 1), Expanded(child: child)]));

  Widget _productTile({required String title, required String subtitle, required double price, required String label, required String stock, required IconData icon, required String? imagePath, required VoidCallback onTap}) => InkWell(onTap: onTap, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13), child: Row(children: [Container(width: 58, height: 58, decoration: BoxDecoration(color: const Color(0xFFEEF0F7), borderRadius: BorderRadius.circular(8)), child: imagePath != null && File(imagePath).existsSync() ? Image.file(File(imagePath), fit: BoxFit.cover, errorBuilder: (_, error, stack) => Icon(icon, color: const Color(0xFF4E2BCB), size: 30)) : Icon(icon, color: const Color(0xFF4E2BCB), size: 30)), const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1D2941))), const SizedBox(height: 5), Text(subtitle, style: const TextStyle(fontSize: 12, height: 1.35, color: Color(0xFF6A7283)))])), Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF6A7283))), const SizedBox(height: 4), Text('PKR ${price.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF1D2941))), const SizedBox(height: 6), Text(stock, style: const TextStyle(fontSize: 11, color: Color(0xFF2E9D62)))])])));

  void _scanImei() {
    showDialog<void>(context: context, builder: (context) => AlertDialog(title: const Text('Scan IMEI'), content: TextField(controller: _scannerController, autofocus: true, onSubmitted: (_) { Navigator.of(context).pop(); _handleScan(); }, decoration: const InputDecoration(hintText: 'Scan or enter IMEI', prefixIcon: Icon(Icons.qr_code_scanner))), actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')), ElevatedButton(onPressed: () { Navigator.of(context).pop(); _handleScan(); }, child: const Text('Find Device'))]));
  }

  void _handleScan() {
    final imei = _scannerController.text.trim();
    _scannerController.clear();
    if (imei.isEmpty) return;
    final device = _service.findMobileByImei(widget.shopId, imei);
    if (device != null) {
      SharedCart.instance.addMobile(widget.shopId, device);
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Device added to cart')));
    } else {
      final unit = _service.findMobileUnitByImei(widget.shopId, imei);
      if (unit != null) {
        SharedCart.instance.addMobileUnit(widget.shopId, unit);
        _refresh();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Device added to cart')));
      } else if (widget.isEmployee) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Employees cannot add new mobile inventory records.')));
      } else {
        _showAddDialog(scannedImei: imei);
      }
    }
  }

  void _showAddDialog({String? scannedImei}) {
    showDialog<void>(context: context, builder: (context) => AddInventoryDialog(shopId: widget.shopId, accessoriesMode: widget.accessoriesMode, initialImei: scannedImei, onSaved: _refresh));
  }
}

class CartPanel extends StatefulWidget {
  const CartPanel({super.key});

  @override
  State<CartPanel> createState() => _CartPanelState();
}

class _CartPanelState extends State<CartPanel> {
  final _service = InventoryService();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();

  @override
  void dispose() { _name.dispose(); _phone.dispose(); _address.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final cart = SharedCart.instance;
    return AnimatedBuilder(
      animation: cart,
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E7EF)),
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.shopping_cart_outlined, color: Color(0xFF4E2BCB)),
                const SizedBox(width: 10),
                const Expanded(child: Text('Cart', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF1D2941)))),
                Text('${cart.lines.length}', style: const TextStyle(color: Color(0xFF6A7283))),
              ]),
              const Divider(height: 26),
              Expanded(child: cart.lines.isEmpty ? const _EmptyState(message: 'Your cart is empty') : ListView.separated(
                itemCount: cart.lines.length,
                separatorBuilder: (_, index) => const Divider(height: 18),
                itemBuilder: (_, index) {
                  final line = cart.lines[index];
                  final key = line.isMobile ? 'mobile-${line.device!.id}' : 'accessory-${line.accessory!.id}';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(line.name, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1D2941))),
                            const SizedBox(height: 4),
                            Text(line.detail, style: const TextStyle(fontSize: 11, color: Color(0xFF6A7283))),
                            if (line.isMobile) Text('Buy Price: PKR ${line.buyPrice.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11, color: Color(0xFF6A7283))),
                          ])),
                          Text('PKR ${line.total.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          IconButton(onPressed: () => cart.removeAt(index), icon: const Icon(Icons.close, size: 18)),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                            child: TextFormField(
                              key: ValueKey('sale-price-$key'),
                              initialValue: line.salePrice.toStringAsFixed(0),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Sell Price',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              onChanged: (value) {
                                final parsed = double.tryParse(value.trim());
                                if (parsed != null) {
                                  line.salePrice = parsed;
                                  setState(() {});
                                }
                              },
                            ),
                          ),
                          if (!line.isMobile) ...[
                            const SizedBox(width: 8),
                            Row(children: [
                              IconButton(onPressed: () { if (line.quantity > 1) { line.quantity--; setState(() {}); } }, icon: const Icon(Icons.remove_circle_outline)),
                              Text('${line.quantity}', style: const TextStyle(fontWeight: FontWeight.w700)),
                              IconButton(onPressed: () { line.quantity++; setState(() {}); }, icon: const Icon(Icons.add_circle_outline)),
                            ]),
                          ],
                        ]),
                      ],
                    ),
                  );
                },
              )),
              const Divider(height: 24),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Total', style: TextStyle(fontWeight: FontWeight.w700)),
                Text('PKR ${cart.total.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: Color(0xFF4E2BCB))),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: ElevatedButton(onPressed: () => _checkout(context, false), child: const Text('Make Sale'))),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton(onPressed: () => _checkout(context, true), child: const Text('Print Bill'))),
              ]),
            ],
          ),
        );
      },
    );
  }

  void _checkout(BuildContext context, bool print) {
    final cart = SharedCart.instance;
    if (cart.lines.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cart is empty.'))); return; }
    for (final line in cart.lines) {
      if (!line.hasValidSalePrice) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Every cart item must have a valid selling price greater than or equal to 0.')));
        return;
      }
    }
    if (cart.hasMobile) {
      showDialog<void>(context: context, builder: (context) => AlertDialog(title: const Text('Customer Details'), content: Column(mainAxisSize: MainAxisSize.min, children: [_input(_name, 'Customer name'), _input(_phone, 'Phone number'), _input(_address, 'Address')]), actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')), ElevatedButton(onPressed: () { Navigator.of(context).pop(); _saveSale(print); }, child: Text(print ? 'Print Bill' : 'Make Sale'))]));
    } else {
      _saveSale(print);
    }
  }

  Widget _input(TextEditingController controller, String hint) => Padding(padding: const EdgeInsets.only(bottom: 10), child: TextField(controller: controller, decoration: InputDecoration(labelText: hint, border: const OutlineInputBorder())));

  Future<void> _saveSale(bool print) async {
    final cart = SharedCart.instance;
    for (final line in cart.lines) {
      if (!line.hasValidSalePrice) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Every cart item must have a valid selling price greater than or equal to 0.')));
        return;
      }
    }
    final completedLines = List<CartLine>.from(cart.lines);
    final shopId = cart.shopId ?? '';
    final employeeId = AppSession.instance.userId;
    final employeeName = AppSession.instance.username;
    final result = _service.completeSale(
      shopId: shopId,
      cart: completedLines,
      customerName: _name.text,
      customerPhone: _phone.text,
      customerAddress: _address.text,
      employeeId: employeeId,
      employeeName: employeeName,
    );
    if (result != null) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result))); return; }
    final total = SharedCart.instance.total;
    SharedCart.instance.clear();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(print ? 'Bill ready to print.' : 'Sale completed successfully.')));
    if (print) {
      await Printing.layoutPdf(
        onLayout: (_) => _buildBillPdf(shopId, total, completedLines),
      );
    }
  }

  Future<Uint8List> _buildBillPdf(String shopId, double total, List<CartLine> lines) async {
    final details = AdminManagementService().shopDetails(shopId);
    final now = DateTime.now();
    final document = pw.Document();
    document.addPage(pw.Page(
      pageFormat: PdfPageFormat(80 * PdfPageFormat.mm, 220 * PdfPageFormat.mm, marginAll: 3 * PdfPageFormat.mm),
      build: (context) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Center(child: pw.Text(details.name.toUpperCase(), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold))),
        pw.Center(child: pw.Text(details.address)),
        pw.Center(child: pw.Text('Phone: ${details.phone}')),
        pw.Divider(),
        pw.Center(child: pw.Text('SALE INVOICE', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
        pw.SizedBox(height: 5),
        pw.Text('Bill: ${SharedCart.instance.lastBillNumber ?? 'BILL-N/A'}'),
        pw.Text('Date: ${now.toLocal().year}-${now.toLocal().month.toString().padLeft(2, '0')}-${now.toLocal().day.toString().padLeft(2, '0')}'),
        pw.Text('Time: ${now.toLocal().hour.toString().padLeft(2, '0')}:${now.toLocal().minute.toString().padLeft(2, '0')}'),
        if (_name.text.trim().isNotEmpty) pw.Text('Customer: ${_name.text.trim()}'),
        if (_phone.text.trim().isNotEmpty) pw.Text('Phone: ${_phone.text.trim()}'),
        if (_address.text.trim().isNotEmpty) pw.Text('Address: ${_address.text.trim()}'),
        pw.Divider(),
        pw.Table(columnWidths: {0: const pw.FixedColumnWidth(18), 1: const pw.FlexColumnWidth(3), 2: const pw.FixedColumnWidth(28), 3: const pw.FixedColumnWidth(42)}, children: [
          pw.TableRow(children: [pw.Text('#'), pw.Text('Item'), pw.Text('Qty'), pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Amount'))]),
          ...lines.asMap().entries.map((entry) {
            final line = entry.value;
            return pw.TableRow(children: [pw.Text('${entry.key + 1}'), pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text(line.name), if (line.isMobile) pw.Text(line.detail, style: const pw.TextStyle(fontSize: 8))]), pw.Text('${line.quantity}'), pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('PKR ${line.total.toStringAsFixed(0)}'))]);
          }),
        ]),
        pw.Divider(),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Subtotal'), pw.Text('PKR ${total.toStringAsFixed(0)}')]),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Final Total'), pw.Text('PKR ${total.toStringAsFixed(0)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))]),
        pw.SizedBox(height: 16),
        pw.Center(child: pw.Text('Developed By Arslan Kharal')),
      ]),
    ));
    return document.save();
  }

}

class AddInventoryDialog extends StatefulWidget {
  const AddInventoryDialog({super.key, required this.shopId, required this.accessoriesMode, this.initialImei, required this.onSaved});

  final String shopId;
  final bool accessoriesMode;
  final String? initialImei;
  final VoidCallback onSaved;

  @override
  State<AddInventoryDialog> createState() => _AddInventoryDialogState();
}

class _AddInventoryDialogState extends State<AddInventoryDialog> {
  final _service = InventoryService();
  final _name = TextEditingController();
  String? _selectedImagePath;
  String? _selectedCnicImagePath;
  final _color = TextEditingController();
  final _imei1 = TextEditingController();
  final _imei2 = TextEditingController();
  final _ram = TextEditingController();
  final _storage = TextEditingController();
  final _buy = TextEditingController(text: '0');
  final _quantity = TextEditingController(text: '1');
  final _sourceName = TextEditingController();
  final _sourceCnic = TextEditingController();
  final _sourcePhone = TextEditingController();
  final _sourceAddress = TextEditingController();
  String _condition = 'new';

  @override
  void initState() { super.initState(); _imei1.text = widget.initialImei ?? ''; }
  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = result?.files.single.path;
    if (path != null && mounted) setState(() => _selectedImagePath = path);
  }

  Widget _imagePickerField() => Padding(padding: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [if (_selectedImagePath != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Image.file(File(_selectedImagePath!), height: 90, width: 120, fit: BoxFit.cover, errorBuilder: (_, error, stack) => const SizedBox(height: 90, width: 120, child: Icon(Icons.broken_image_outlined)))), OutlinedButton.icon(onPressed: _pickImage, icon: const Icon(Icons.upload_file), label: Text(_selectedImagePath == null ? 'Upload Image' : 'Change Image'))]));

  Widget _cnicImagePickerField() => Padding(padding: const EdgeInsets.only(bottom: 12), child: OutlinedButton.icon(onPressed: () async { final result = await FilePicker.platform.pickFiles(type: FileType.image); final path = result?.files.single.path; if (path != null && mounted) setState(() => _selectedCnicImagePath = path); }, icon: const Icon(Icons.upload_file), label: Text(_selectedCnicImagePath == null ? 'Upload CNIC Picture (optional)' : 'Change CNIC Picture')));

  @override
  void dispose() { for (final controller in [_name, _color, _imei1, _imei2, _ram, _storage, _buy, _quantity, _sourceName, _sourceCnic, _sourcePhone, _sourceAddress]) { controller.dispose(); } super.dispose(); }

  @override
  Widget build(BuildContext context) => AlertDialog(title: Text(widget.initialImei != null ? 'Add Mobile' : widget.accessoriesMode ? 'Add New Item' : 'Add New Device'), content: SizedBox(width: 550, child: SingleChildScrollView(child: Column(children: widget.accessoriesMode ? [_field(_name, 'Item name'), _imagePickerField(), _field(_buy, 'Buy price', numeric: true), _field(_quantity, 'Quantity', numeric: true)] : [_field(_name, 'Mobile Model *'), _imagePickerField(), _field(_color, 'Colour'), _field(_imei1, 'IMEI 1 *'), _field(_imei2, 'IMEI 2 (optional)'), _field(_ram, 'RAM (optional)'), _field(_storage, 'Storage (optional)'), _field(_buy, 'Buy price *', numeric: true), DropdownButtonFormField<String>(initialValue: _condition, decoration: const InputDecoration(labelText: 'Condition', border: OutlineInputBorder()), items: const [DropdownMenuItem(value: 'new', child: Text('New')), DropdownMenuItem(value: 'used', child: Text('Used'))], onChanged: (value) => setState(() => _condition = value ?? 'new')), if (_condition == 'used') ...[_field(_sourceName, 'Customer name'), _field(_sourceCnic, 'CNIC number'), _field(_sourcePhone, 'Phone number'), _field(_sourceAddress, 'Address'), _cnicImagePickerField()]]))), actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')), if (widget.initialImei != null && !widget.accessoriesMode) ...[OutlinedButton(onPressed: () => _saveScanned(addToCart: false), child: const Text('Add to Inventory')), ElevatedButton(onPressed: () => _saveScanned(addToCart: true), child: const Text('Add to Cart'))] else ElevatedButton(onPressed: _save, child: const Text('Save'))]);

  Widget _field(TextEditingController controller, String label, {bool numeric = false}) => Padding(padding: const EdgeInsets.only(bottom: 12), child: TextField(controller: controller, keyboardType: numeric ? TextInputType.number : TextInputType.text, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder())));

  Future<void> _save() async {
    final storedImagePath = _selectedImagePath == null ? null : await _service.storeImage(widget.shopId, _selectedImagePath!, accessory: widget.accessoriesMode);
    final storedCnicImagePath = _selectedCnicImagePath == null ? null : await _service.storeImage(widget.shopId, _selectedCnicImagePath!, accessory: false);
    if (!mounted) return;
    if ((_selectedImagePath != null && storedImagePath == null) || (_selectedCnicImagePath != null && storedCnicImagePath == null)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('The selected image could not be saved. Please choose it again.')));
      return;
    }
    final error = widget.accessoriesMode ? _service.addAccessory(shopId: widget.shopId, name: _name.text, picturePath: storedImagePath, buyPrice: double.tryParse(_buy.text) ?? 0, quantity: int.tryParse(_quantity.text) ?? 0) : _service.addMobile(shopId: widget.shopId, name: _name.text, picturePath: storedImagePath, color: _color.text, imei1: _imei1.text, imei2: _imei2.text, ram: _ram.text, storage: _storage.text, condition: _condition, sourceCustomerName: _sourceName.text, sourceCnic: _sourceCnic.text, sourcePhone: _sourcePhone.text, sourceAddress: _sourceAddress.text, sourceCnicPicture: storedCnicImagePath, buyPrice: double.tryParse(_buy.text) ?? 0);
    if (error != null) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error))); return; }
    if (widget.initialImei != null && _imei1.text.trim().isNotEmpty) {
      final device = _service.findMobileByImei(widget.shopId, _imei1.text.trim());
      if (device != null) SharedCart.instance.addMobile(widget.shopId, device);
    }
    Navigator.of(context).pop();
    widget.onSaved();
  }

  Future<void> _saveScanned({required bool addToCart}) async {
    final unit = _service.addScannedMobileUnit(
      shopId: widget.shopId,
      modelName: _name.text,
      imei1: _imei1.text,
      buyPrice: double.tryParse(_buy.text) ?? 0,
      ram: _ram.text,
      storage: _storage.text,
    );
    if (unit == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mobile model, buy price, and a unique IMEI are required.')));
      return;
    }
    if (addToCart) SharedCart.instance.addMobileUnit(widget.shopId, unit);
    if (mounted) {
      Navigator.of(context).pop();
      widget.onSaved();
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Center(child: Text(message, style: const TextStyle(color: Color(0xFF6A7283))));
}
