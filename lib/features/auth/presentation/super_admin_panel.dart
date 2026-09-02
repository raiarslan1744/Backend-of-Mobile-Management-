import 'package:flutter/material.dart';

import '../logic/super_admin_service.dart';

class SuperAdminPanel extends StatefulWidget {
  const SuperAdminPanel({super.key, this.onLogout});

  final VoidCallback? onLogout;

  @override
  State<SuperAdminPanel> createState() => _SuperAdminPanelState();
}

class _SuperAdminPanelState extends State<SuperAdminPanel> {
  final _service = SuperAdminService();
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      ShopsManagementPage(service: _service),
      SettingsPage(service: _service),
    ];

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth > 900;
          return Row(
            children: [
              Container(
                width: wide ? 240 : 70,
                color: const Color(0xFF0D2340),
                padding: const EdgeInsets.symmetric(
                  vertical: 24,
                  horizontal: 12,
                ),
                child: wide
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'AK POS',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                          const SizedBox(height: 30),
                          _navButton(
                            label: 'Shops Management',
                            selected: _selectedIndex == 0,
                            onPressed: () => setState(() => _selectedIndex = 0),
                          ),
                          const SizedBox(height: 12),
                          _navButton(
                            label: 'Settings',
                            selected: _selectedIndex == 1,
                            onPressed: () => setState(() => _selectedIndex = 1),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: widget.onLogout ?? () {},
                            icon: const Icon(
                              Icons.logout,
                              color: Colors.white70,
                            ),
                            label: const Text(
                              'Logout',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          IconButton(
                            onPressed: () => setState(() => _selectedIndex = 0),
                            icon: const Icon(
                              Icons.storefront,
                              color: Colors.white70,
                            ),
                          ),
                          IconButton(
                            onPressed: () => setState(() => _selectedIndex = 1),
                            icon: const Icon(
                              Icons.settings,
                              color: Colors.white70,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: widget.onLogout ?? () {},
                            icon: const Icon(
                              Icons.logout,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
              ),
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFFDCCBEA),
                        Color(0xFFD5E0EE),
                        Color(0xFFBFEFF3),
                      ],
                    ),
                  ),
                  child: pages[_selectedIndex],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _navButton({
    required String label,
    required bool selected,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: selected
              ? Colors.white.withValues(alpha: 0.16)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          alignment: Alignment.centerLeft,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white70,
              fontSize: 16,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class ShopsManagementPage extends StatefulWidget {
  const ShopsManagementPage({super.key, required this.service});

  final SuperAdminService service;

  @override
  State<ShopsManagementPage> createState() => _ShopsManagementPageState();
}

enum _ShopAction { edit, toggleStatus, delete }

class _ShopsManagementPageState extends State<ShopsManagementPage> {
  final _ownerNameController = TextEditingController();
  final _contactController = TextEditingController();
  final _addressController = TextEditingController();
  final _shopIdController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _deletingShopIds = <String>{};

  @override
  void initState() {
    super.initState();
    _loadCloudShops();
  }

  Future<void> _loadCloudShops() async {
    try {
      final migrated = await widget.service.migrateLocalShopsToCloud();
      final count = await widget.service.refreshShopsFromCloud();
      if (mounted) {
        setState(() {});
        debugPrint(
          'Cloud shop migration uploaded $migrated shops; list returned $count shops',
        );
      }
    } catch (error) {
      debugPrint('Cloud shop list unavailable: $error');
    }
  }

  @override
  void dispose() {
    _ownerNameController.dispose();
    _contactController.dispose();
    _addressController.dispose();
    _shopIdController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showCreateShopDialog() {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFFEAF4FF),
          title: const Text('Create New Shop'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _field(label: 'Owner Name', controller: _ownerNameController),
                  _field(label: 'Contact', controller: _contactController),
                  _field(label: 'Address', controller: _addressController),
                  _field(label: 'Shop ID', controller: _shopIdController),
                  _field(label: 'Username', controller: _usernameController),
                  _field(
                    label: 'Password',
                    controller: _passwordController,
                    obscureText: true,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final result = await widget.service.createShopInCloud(
                  ownerName: _ownerNameController.text,
                  contact: _contactController.text,
                  address: _addressController.text,
                  shopId: _shopIdController.text,
                  username: _usernameController.text,
                  password: _passwordController.text,
                );

                if (!mounted || !context.mounted) {
                  return;
                }

                Navigator.of(context).pop();
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(result.message)));

                if (result.success) {
                  setState(() {
                    _ownerNameController.clear();
                    _contactController.clear();
                    _addressController.clear();
                    _shopIdController.clear();
                    _usernameController.clear();
                    _passwordController.clear();
                  });
                }
              },
              child: const Text('Create Shop'),
            ),
          ],
        );
      },
    );
  }

  void _showEditShopDialog(ShopModel shop) {
    final ownerNameController = TextEditingController(text: shop.ownerName);
    final contactController = TextEditingController(text: shop.contact);
    final addressController = TextEditingController(text: shop.address);
    final usernameController = TextEditingController(text: shop.username);
    final passwordController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFEAF4FF),
        title: const Text('Edit Shop'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field(label: 'Owner Name', controller: ownerNameController),
                _field(label: 'Contact', controller: contactController),
                _field(label: 'Address', controller: addressController),
                _field(label: 'Username', controller: usernameController),
                _field(
                  label: 'New Password (optional)',
                  controller: passwordController,
                  obscureText: true,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final result = widget.service.updateShop(
                shopId: shop.shopId,
                ownerName: ownerNameController.text,
                contact: contactController.text,
                address: addressController.text,
                username: usernameController.text,
                password: passwordController.text,
              );
              Navigator.of(context).pop();
              ScaffoldMessenger.of(this.context)
                  .showSnackBar(SnackBar(content: Text(result.message)));
              if (result.success && mounted) setState(() {});
            },
            child: const Text('Save Changes'),
          ),
        ],
      ),
    ).whenComplete(() {
      ownerNameController.dispose();
      contactController.dispose();
      addressController.dispose();
      usernameController.dispose();
      passwordController.dispose();
    });
  }

  Future<void> _deleteShop(ShopModel shop) async {
    debugPrint('DELETE BUTTON CLICKED shopId=${shop.shopId}');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Shop'),
        content: const Text(
          'Are you sure you want to delete this shop?\nThis action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    debugPrint(
      'CONFIRMATION ACCEPTED shopId=${shop.shopId} confirmed=${confirmed == true}',
    );
    if (!mounted || confirmed != true || _deletingShopIds.contains(shop.shopId)) {
      return;
    }

    setState(() => _deletingShopIds.add(shop.shopId));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Deleting...')),
      );
    }
    try {
      debugPrint('CLOUD DELETE STARTED shopId=${shop.shopId}');
      final result = await widget.service.deleteShop(shopId: shop.shopId);
      if (!mounted) return;
      debugPrint(
        'DELETE FINAL RESULT shopId=${shop.shopId} success=${result.success} message=${result.message}',
      );
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.message)));
      if (result.success) {
        setState(() {});
      }
    } catch (error, stackTrace) {
      debugPrint(
        'DELETE FINAL RESULT shopId=${shop.shopId} success=false error=$error stackTrace=$stackTrace',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not connect to cloud server. Shop was not deleted.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _deletingShopIds.remove(shop.shopId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Shops Management',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w300,
                    color: Color(0xFF102D5E),
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _showCreateShopDialog,
                icon: const Icon(Icons.add),
                label: const Text('+ Create New Shop'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0C2E59),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: 1000,
                  child: DataTable(
                    headingTextStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF102D5E),
                    ),
                    dataTextStyle: const TextStyle(color: Color(0xFF102D5E)),
                    columns: const [
                      DataColumn(label: Text('Owner Name')),
                      DataColumn(label: Text('Contact')),
                      DataColumn(label: Text('Address')),
                      DataColumn(label: Text('Shop ID')),
                      DataColumn(label: Text('Username')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Action')),
                    ],
                    rows: widget.service.shops.map((shop) {
                      return DataRow(
                        cells: [
                          DataCell(Text(shop.ownerName)),
                          DataCell(Text(shop.contact)),
                          DataCell(Text(shop.address)),
                          DataCell(Text(shop.shopId)),
                          DataCell(Text(shop.username)),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: shop.status == ShopStatus.active
                                    ? Colors.green.withValues(alpha: 0.18)
                                    : Colors.orange.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  shop.status.toString(),
                                  style: TextStyle(
                                    color: shop.status == ShopStatus.active
                                        ? Colors.green.shade800
                                        : Colors.orange.shade800,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            _deletingShopIds.contains(shop.shopId)
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : PopupMenuButton<_ShopAction>(
                                    tooltip: 'Shop actions',
                                    padding: EdgeInsets.zero,
                                    iconSize: 20,
                                    constraints: const BoxConstraints(
                                      minWidth: 32,
                                      minHeight: 32,
                                    ),
                                    onSelected: (action) {
                                      switch (action) {
                                        case _ShopAction.edit:
                                          _showEditShopDialog(shop);
                                        case _ShopAction.toggleStatus:
                                          final result = widget.service
                                              .toggleShopStatus(
                                                shopId: shop.shopId,
                                              );
                                          if (mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(result.message),
                                              ),
                                            );
                                            setState(() {});
                                          }
                                        case _ShopAction.delete:
                                          _deleteShop(shop);
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                        value: _ShopAction.edit,
                                        child: ListTile(
                                          dense: true,
                                          leading: Icon(Icons.edit_outlined),
                                          title: Text('Edit'),
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: _ShopAction.toggleStatus,
                                        child: ListTile(
                                          dense: true,
                                          leading: Icon(
                                            Icons.toggle_on_outlined,
                                          ),
                                          title: Text('Change status'),
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: _ShopAction.delete,
                                        child: ListTile(
                                          dense: true,
                                          leading: Icon(Icons.delete_outline),
                                          title: Text('Delete'),
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    bool obscureText = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            obscureText: obscureText,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({required this.service, super.key});

  final SuperAdminService service;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _currentUsernameController = TextEditingController();
  final _newUsernameController = TextEditingController();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void dispose() {
    _currentUsernameController.dispose();
    _newUsernameController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(16),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Super Admin Settings',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w300,
                      color: Color(0xFF102D5E),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _settingsField(
                    label: 'Current Username',
                    controller: _currentUsernameController,
                  ),
                  _settingsField(
                    label: 'New Username',
                    controller: _newUsernameController,
                  ),
                  _settingsField(
                    label: 'Current Password',
                    controller: _currentPasswordController,
                    obscureText: true,
                  ),
                  _settingsField(
                    label: 'New Password',
                    controller: _newPasswordController,
                    obscureText: true,
                  ),
                  _settingsField(
                    label: 'Confirm New Password',
                    controller: _confirmPasswordController,
                    obscureText: true,
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        final result = widget.service
                            .updateSuperAdminCredentials(
                              currentUsername: _currentUsernameController.text,
                              currentPassword: _currentPasswordController.text,
                              newUsername: _newUsernameController.text,
                              newPassword: _newPasswordController.text,
                              confirmNewPassword:
                                  _confirmPasswordController.text,
                            );

                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(result.message)));

                        if (result.success) {
                          setState(() {
                            _currentUsernameController.clear();
                            _newUsernameController.clear();
                            _currentPasswordController.clear();
                            _newPasswordController.clear();
                            _confirmPasswordController.clear();
                          });
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0C2E59),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Save Changes'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _settingsField({
    required String label,
    required TextEditingController controller,
    bool obscureText = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFF102D5E),
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            obscureText: obscureText,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }
}
