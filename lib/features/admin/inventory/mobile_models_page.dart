import 'package:flutter/material.dart';
import 'inventory_service.dart';
import 'inventory_pages.dart';

class MobileModelsPage extends StatefulWidget {
  const MobileModelsPage({super.key, required this.shopId});

  final String shopId;

  @override
  State<MobileModelsPage> createState() => _MobileModelsPageState();
}

class _MobileModelsPageState extends State<MobileModelsPage> {
  final _service = InventoryService();
  late List<MobileModel> _models = [];
  final _nameController = TextEditingController();
  final _searchController = TextEditingController();
  int? _selectedModelId;

  @override
  void initState() {
    super.initState();
    _refreshModels();
  }

  void _refreshModels() {
    setState(() {
      _models = _service.getMobileModels(widget.shopId);
    });
  }

  void _showCreateDialog() {
    _nameController.clear();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Mobile Model'),
        content: TextField(
          controller: _nameController,
          decoration: const InputDecoration(hintText: 'Model Name (e.g., iPhone 13)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final error = _service.createMobileModel(
                shopId: widget.shopId,
                name: _nameController.text,
              );
              Navigator.pop(context);
              if (error != null) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
              } else {
                _refreshModels();
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mobile Inventory'),
        actions: [
          IconButton(onPressed: _refreshModels, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search mobile model or IMEI...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Available Units: ${_service.availableMobileUnitCount(widget.shopId)}    Total Stock Value: Rs. ${_service.totalMobileUnitStockValue(widget.shopId).toStringAsFixed(0)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final modelsList = _models.isEmpty
                    ? const Center(child: Text('No mobile models yet'))
                    : ListView.builder(
                    itemCount: _models.length,
                    itemBuilder: (context, index) {
                      final model = _models[index];
                      final query = _searchController.text.toLowerCase();
                      final matchesImei = _service
                          .getMobileUnitsByModel(model.id, widget.shopId)
                          .any((unit) => unit.imei1.contains(query) || (unit.imei2?.contains(query) ?? false));
                      if (query.isNotEmpty && !model.name.toLowerCase().contains(query) && !matchesImei) {
                        return const SizedBox.shrink();
                      }
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: ListTile(
                          onTap: () => setState(() => _selectedModelId = model.id),
                          title: Text(model.name),
                          subtitle: Text('Stock: ${model.stockCount}${model.isLowStock ? ' (LOW)' : ''}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ElevatedButton(
                                onPressed: () => _addUnit(model.id),
                                child: const Text('Add Unit'),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: () => _showDetails(model),
                                child: const Text('Details'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                final units = _selectedModelId == null
                    ? const <MobileUnit>[]
                    : _service.getMobileUnitsByModel(_selectedModelId!, widget.shopId);
                final selectedModel = _selectedModelId == null
                    ? null
                    : _models.where((model) => model.id == _selectedModelId).firstOrNull;
                final unitsPanel = selectedModel == null
                  ? const Center(child: Text('Select a mobile model to view available units'))
                    : _unitsPanel(selectedModel, units);
                if (constraints.maxWidth <= 900) {
                  return Column(children: [Expanded(child: modelsList), const SizedBox(height: 12), SizedBox(height: 360, child: unitsPanel), const SizedBox(height: 12), SizedBox(height: 330, child: CartPanel())]);
                }
                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: Column(children: [Expanded(child: modelsList), const SizedBox(height: 12), SizedBox(height: 360, child: unitsPanel)])), const SizedBox(width: 16), SizedBox(width: 350, child: CartPanel())]);
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _addUnit(int modelId) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        final screenSize = MediaQuery.sizeOf(context);
        final dialogWidth = screenSize.width < 600 ? screenSize.width * 0.92 : 520.0;
        final dialogHeight = screenSize.height * 0.82;

        return Dialog(
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: SizedBox(
            width: dialogWidth,
            height: dialogHeight,
            child: MobileUnitsPage(shopId: widget.shopId, modelId: modelId),
          ),
        );
      },
    ).then((_) => _refreshModels());
  }

  Widget _unitsPanel(MobileModel model, List<MobileUnit> units) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFE2E7EF)), borderRadius: BorderRadius.circular(12)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text(model.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))), Text('${units.length} available')]),
      const Divider(),
      Expanded(child: units.isEmpty ? const Center(child: Text('No available units')) : ListView.separated(itemCount: units.length, separatorBuilder: (_, index) => const Divider(), itemBuilder: (_, index) { final unit = units[index]; return ListTile(title: Text('IMEI: ${unit.imei1}'), subtitle: Text('RAM: ${unit.ram ?? '-'}   Storage: ${unit.storage ?? '-'}\nBuy Price: Rs. ${unit.buyPrice.toStringAsFixed(0)}\nStatus: ${unit.status}'), trailing: ElevatedButton(onPressed: () => SharedCart.instance.addMobileUnit(widget.shopId, unit), child: const Text('Add to Cart'))); }))
    ]),
  );

  void _showDetails(MobileModel model) {
    final units = _service.getMobileUnitsByModel(model.id, widget.shopId);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${model.name} - Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Stock: ${model.stockCount}'),
              const SizedBox(height: 16),
              if (units.isEmpty)
                const Text('No units added yet')
              else
                ...units.map((unit) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('IMEI 1: ${unit.imei1}'),
                        if (unit.imei2 != null) Text('IMEI 2: ${unit.imei2}'),
                        if (unit.ram != null) Text('RAM: ${unit.ram}'),
                        if (unit.storage != null) Text('Storage: ${unit.storage}'),
                        Text('Buy Price: Rs. ${unit.buyPrice}'),
                        Text('Status: ${unit.status}'),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('ID: ${unit.id}'),
                            if (unit.status == 'available')
                              Row(children: [
                                TextButton(onPressed: () { SharedCart.instance.addMobileUnit(widget.shopId, unit); }, child: const Text('Add to Cart')),
                                TextButton(onPressed: () { _service.deleteMobileUnit(unit.id, widget.shopId); Navigator.pop(context); _refreshModels(); }, child: const Text('Delete', style: TextStyle(color: Colors.red))),
                              ]),
                          ],
                        ),
                      ],
                    ),
                  ),
                )),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              final result = _service.deleteMobileModel(shopId: widget.shopId, modelId: model.id);
              if (result != null) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
                return;
              }
              Navigator.pop(context);
              _refreshModels();
            },
            child: const Text('Delete Model', style: TextStyle(color: Colors.red)),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }
}

class MobileUnitsPage extends StatefulWidget {
  const MobileUnitsPage({super.key, required this.shopId, required this.modelId});

  final String shopId;
  final int modelId;

  @override
  State<MobileUnitsPage> createState() => _MobileUnitsPageState();
}

class _MobileUnitsPageState extends State<MobileUnitsPage> {
  final _service = InventoryService();
  late MobileModel? _model;
  final _imei1Controller = TextEditingController();
  final _imei2Controller = TextEditingController();
  final _buyPriceController = TextEditingController();
  final _ramController = TextEditingController();
  final _storageController = TextEditingController();
  late List<Supplier> _suppliers = [];
  int? _selectedSupplierId;

  @override
  void initState() {
    super.initState();
    _model = _service.getMobileModel(widget.modelId, widget.shopId);
    _suppliers = _service.getSuppliers(widget.shopId);
  }

  void _addUnit() {
    if (_imei1Controller.text.isEmpty || _buyPriceController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('IMEI 1 and Buy Price are required')),
      );
      return;
    }

    final error = _service.addMobileUnit(
      shopId: widget.shopId,
      mobileModelId: widget.modelId,
      imei1: _imei1Controller.text,
      imei2: _imei2Controller.text.isEmpty ? null : _imei2Controller.text,
      buyPrice: double.parse(_buyPriceController.text),
      ram: _ramController.text.isEmpty ? null : _ramController.text,
      storage: _storageController.text.isEmpty ? null : _storageController.text,
      supplierId: _selectedSupplierId,
    );

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    } else {
      _imei1Controller.clear();
      _imei2Controller.clear();
      _buyPriceController.clear();
      _ramController.clear();
      _storageController.clear();
      _selectedSupplierId = null;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unit added successfully')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_model == null) {
      return const Scaffold(
        body: Center(child: Text('Model not found')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1D2941),
        elevation: 0,
        title: Text('Add ${_model!.name}'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _imei1Controller,
              decoration: const InputDecoration(
                labelText: 'IMEI 1 *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _imei2Controller,
              decoration: const InputDecoration(
                labelText: 'IMEI 2 (Optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _ramController,
              decoration: const InputDecoration(
                labelText: 'RAM (Optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _storageController,
              decoration: const InputDecoration(
                labelText: 'Storage (Optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _buyPriceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Buy Price *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            if (_suppliers.isNotEmpty)
              DropdownButton<int?>(
                isExpanded: true,
                value: _selectedSupplierId,
                hint: const Text('Select Supplier (Optional)'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('No Supplier'),
                  ),
                  ..._suppliers.map((s) => DropdownMenuItem(
                    value: s.id,
                    child: Text(s.name),
                  )),
                ],
                onChanged: (value) => setState(() => _selectedSupplierId = value),
              ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _addUnit,
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
              child: const Text('Add Unit'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _imei1Controller.dispose();
    _imei2Controller.dispose();
    _buyPriceController.dispose();
    _ramController.dispose();
    _storageController.dispose();
    super.dispose();
  }
}
