import 'package:flutter/material.dart';
import 'inventory_service.dart';

class SuppliersPage extends StatefulWidget {
  const SuppliersPage({super.key, required this.shopId});

  final String shopId;

  @override
  State<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends State<SuppliersPage> {
  final _service = InventoryService();
  late List<Supplier> _suppliers = [];
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refreshSuppliers();
  }

  void _refreshSuppliers() {
    setState(() {
      _suppliers = _service.getSuppliers(widget.shopId);
    });
  }

  void _showCreateDialog() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final addressController = TextEditingController();
    final notesController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Supplier'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Supplier Name *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone (Optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(
                  labelText: 'Address (Optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes (Optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final error = _service.createSupplier(
                shopId: widget.shopId,
                name: nameController.text,
                phone: phoneController.text.isEmpty ? null : phoneController.text,
                address: addressController.text.isEmpty ? null : addressController.text,
                notes: notesController.text.isEmpty ? null : notesController.text,
              );
              Navigator.pop(context);
              if (error != null) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
              } else {
                _refreshSuppliers();
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirm(Supplier supplier) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Supplier'),
        content: Text('Delete "${supplier.name}"? This will not affect existing inventory records.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final error = _service.deleteSupplier(supplier.id, widget.shopId);
              Navigator.pop(context);
              if (error != null) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
              } else {
                _refreshSuppliers();
              }
            },
            child: const Text('Delete'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Suppliers'),
        actions: [
          IconButton(onPressed: _refreshSuppliers, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search suppliers...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: _suppliers.isEmpty
                ? const Center(child: Text('No suppliers yet'))
                : ListView.builder(
                    itemCount: _suppliers.length,
                    itemBuilder: (context, index) {
                      final supplier = _suppliers[index];
                      final query = _searchController.text.toLowerCase();
                      if (!supplier.name.toLowerCase().contains(query)) {
                        return const SizedBox.shrink();
                      }
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: ListTile(
                          title: Text(supplier.name),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (supplier.phone != null) Text('Phone: ${supplier.phone}'),
                              if (supplier.address != null) Text('Address: ${supplier.address}'),
                            ],
                          ),
                          trailing: IconButton(
                            onPressed: () => _showDeleteConfirm(supplier),
                            icon: const Icon(Icons.delete, color: Colors.red),
                          ),
                        ),
                      );
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
