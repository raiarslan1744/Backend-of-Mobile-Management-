import 'package:flutter/material.dart';

import '../../../app/routes.dart';
import '../logic/auth_service.dart';
import '../logic/super_admin_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _shopIdController = TextEditingController();
  final _authService = AuthService();

  bool _obscurePassword = true;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _shopIdController.dispose();
    super.dispose();
  }

  Future<void> _submitLogin() async {
    if (_isSubmitting) {
      return;
    }
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSubmitting = true);
    final result = await _authService.loginAsync(
      username: _usernameController.text,
      password: _passwordController.text,
      shopId: _shopIdController.text,
    );

    if (!mounted) {
      return;
    }

    setState(() => _isSubmitting = false);

    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFB3261E),
          margin: const EdgeInsets.all(24),
        ),
      );
      return;
    }

    if (result.role == LoginRole.superAdmin) {
      Navigator.of(context).pushReplacementNamed(AppRoutes.superAdminDashboard);
      return;
    }

    if (result.role == LoginRole.employee) {
      final shopId = result.shopId ?? _shopIdController.text.trim();
      Navigator.of(context)
          .pushReplacementNamed(AppRoutes.employeeDashboard, arguments: shopId);
      return;
    }

    final shopId = result.shopId ?? _shopIdController.text.trim();
    final matchingShops = SuperAdminService.instance.shops.where(
      (element) => element.shopId == shopId,
    );
    final isConfigured =
        matchingShops.isEmpty || matchingShops.first.username.isNotEmpty;

    if (isConfigured) {
      Navigator.of(context)
          .pushReplacementNamed(AppRoutes.adminDashboard, arguments: shopId);
    } else {
      Navigator.of(context)
          .pushReplacementNamed(AppRoutes.adminSetup, arguments: shopId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFDCCBEA), Color(0xFFD5E0EE), Color(0xFFBFEFF3)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.person_outline,
                        size: 42,
                        color: Color(0xFFF8F9FF),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'User Login',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w300,
                          letterSpacing: 0.4,
                          color: Color(0xFFF8F9FF),
                        ),
                      ),
                      const SizedBox(height: 28),
                      _buildTextField(
                        controller: _usernameController,
                        hintText: 'Username',
                        icon: Icons.person_outline,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Username is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 18),
                      _buildTextField(
                        controller: _passwordController,
                        hintText: 'Password',
                        icon: Icons.lock_outline,
                        obscureText: _obscurePassword,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Password is required';
                          }
                          return null;
                        },
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: Colors.white70,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 18),
                      _buildTextField(
                        controller: _shopIdController,
                        hintText: 'Shop ID',
                        icon: Icons.store_outlined,
                        validator: (value) {
                          final isSuperAdmin = SuperAdminService.instance
                              .isSuperAdminCredentials(
                                _usernameController.text.trim(),
                                _passwordController.text.trim(),
                              );
                          if (isSuperAdmin) {
                            return null;
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 30),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isSubmitting ? null : _submitLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0C2E59),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            elevation: 0,
                          ),
                          child: _isSubmitting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'LOGIN',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.5,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    required String? Function(String?) validator,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w300,
      ),
      validator: validator,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(
          color: Color(0xFFF3F8FF),
          fontWeight: FontWeight.w300,
        ),
        prefixIcon: Icon(icon, size: 18, color: Colors.white70),
        suffixIcon: suffixIcon,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
  }
}
