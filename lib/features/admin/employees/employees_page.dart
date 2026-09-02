import 'package:flutter/material.dart';

import 'employees_service.dart';

class EmployeesPage extends StatefulWidget {
  const EmployeesPage({super.key, required this.shopId});

  final String shopId;

  @override
  State<EmployeesPage> createState() => _EmployeesPageState();
}

class _EmployeesPageState extends State<EmployeesPage> {
  final _service = EmployeeManagementService.instance;

  @override
  Widget build(BuildContext context) {
    final employees = _service.employeesForShop(widget.shopId);

    return Padding(
      padding: const EdgeInsets.all(26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Employees',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Color(0xFF1D2941)),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _addEmployee,
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text('Add Employee'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4E2BCB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('Manage employee accounts for this shop.', style: TextStyle(color: Color(0xFF6A7283))),
          const SizedBox(height: 24),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E7EF)),
              ),
              child: employees.isEmpty
                  ? const Center(
                      child: Text('No employees found for this shop.', style: TextStyle(color: Color(0xFF6A7283))),
                    )
                  : ListView.separated(
                      itemCount: employees.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final employee = employees[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFFE7E3FF),
                            child: Text(
                              employee.username.substring(0, 1).toUpperCase(),
                              style: const TextStyle(color: Color(0xFF4E2BCB), fontWeight: FontWeight.w700),
                            ),
                          ),
                          title: Text(employee.username),
                          subtitle: Text('Created: ${employee.createdAt.toLocal().toString()}'),
                          trailing: Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Chip(
                                label: Text(employee.status == 'active' ? 'Active' : 'Disabled'),
                                backgroundColor: employee.status == 'active' ? Colors.green.shade50 : Colors.red.shade50,
                                labelStyle: TextStyle(
                                  color: employee.status == 'active' ? Colors.green.shade800 : Colors.red.shade800,
                                ),
                              ),
                              IconButton(
                                onPressed: () => _toggleStatus(employee.id),
                                icon: Icon(employee.status == 'active' ? Icons.toggle_on : Icons.toggle_off),
                                tooltip: employee.status == 'active' ? 'Disable employee' : 'Enable employee',
                              ),
                              IconButton(
                                onPressed: () => _resetPassword(employee.id),
                                icon: const Icon(Icons.lock_reset),
                                tooltip: 'Reset password',
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addEmployee() async {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Employee'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: usernameController,
                decoration: const InputDecoration(labelText: 'Username'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Shop ID automatically assigned: ${widget.shopId}'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final error = _service.createEmployee(
                shopId: widget.shopId,
                username: usernameController.text,
                password: passwordController.text,
              );
              if (error != null) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
                return;
              }
              Navigator.of(context).pop(true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved == true && mounted) {
      setState(() {});
    }
  }

  Future<void> _toggleStatus(int employeeId) async {
    final error = _service.toggleEmployeeStatus(employeeId: employeeId);
    if (error != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    if (mounted) setState(() {});
  }

  Future<void> _resetPassword(int employeeId) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reset Password'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'New Password'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final error = _service.resetEmployeePassword(employeeId: employeeId, newPassword: controller.text);
              if (error != null) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
                return;
              }
              Navigator.of(context).pop(true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() {});
    }
  }
}
