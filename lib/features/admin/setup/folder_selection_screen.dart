import 'package:flutter/material.dart';

import '../../../app/routes.dart';

class FolderSelectionScreen extends StatefulWidget {
  const FolderSelectionScreen({super.key, required this.shopId});

  final String shopId;

  @override
  State<FolderSelectionScreen> createState() => _FolderSelectionScreenState();
}

class _FolderSelectionScreenState extends State<FolderSelectionScreen> {
  String _selectedFolderPath = '';

  Future<void> _pickFolder() async {
    const folder = 'C:/AKMobileShop';
    setState(() {
      _selectedFolderPath = folder;
    });
  }

  void _continue() {
    if (_selectedFolderPath.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a valid folder before continuing.')),
      );
      return;
    }

    Navigator.of(context).pushReplacementNamed(
      AppRoutes.adminDashboard,
      arguments: widget.shopId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
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
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select Data Storage Folder',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w300,
                      color: Color(0xFF102D5E),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Select a folder where all your shop data will be stored.\nThis folder can later be copied and used as a backup when moving to another Windows computer or device.',
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.5,
                      color: Color(0xFF102D5E),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white70),
                          ),
                          child: Text(
                            _selectedFolderPath.isEmpty
                                ? 'No folder selected'
                                : _selectedFolderPath,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF102D5E),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _pickFolder,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0C2E59),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        ),
                        child: const Text('Select Folder'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      onPressed: _continue,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0C2E59),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
                      ),
                      child: const Text('Continue'),
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
}
