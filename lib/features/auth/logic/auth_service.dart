import 'dart:async';

import '../../../core/auth/app_session.dart';
import '../../../core/cloud/cloud_api_service.dart';
import '../../../core/cloud/cloud_sync_service.dart';

import 'package:flutter/foundation.dart';

import '../../admin/employees/employees_service.dart';
import 'super_admin_service.dart';

enum LoginRole { superAdmin, admin, employee }

class LoginResult {
  const LoginResult({
    required this.success,
    required this.role,
    required this.message,
    this.shopId,
    this.userId,
    this.username,
    this.cloudSyncRequired = false,
  });

  final bool success;
  final LoginRole? role;
  final String message;
  final String? shopId;
  final int? userId;
  final String? username;
  final bool cloudSyncRequired;
}

class AuthService {
  CloudSyncService get _cloudSync => CloudSyncService.instance;

  Future<LoginResult> loginAsync({
    required String username,
    required String password,
    String? shopId,
  }) async {
    final normalizedUsername = username.trim();
    final normalizedPassword = password.trim();
    final normalizedShopId = (shopId ?? '').trim();

    bool isOnline;
    try {
      isOnline = await _cloudSync.apiService.isNetworkAvailable();
    } catch (error) {
      AppSession.instance.clear();
      final message = error is CloudAuthException &&
              error.kind == CloudAuthFailureKind.timeout
          ? 'Server connection timed out. Please check your internet connection and try again.'
          : 'The cloud backend returned a server error. Please try again later.';
      return LoginResult(success: false, role: null, message: message);
    }
    if (isOnline) {
      if (kDebugMode) {
        debugPrint(
          'Authentication path=cloud_attempt username=$normalizedUsername shopId=$normalizedShopId backendReachable=true',
        );
      }
      try {
        final cloudAuthenticated = await _cloudSync.authenticate(
          username: normalizedUsername,
          password: normalizedPassword,
          shopId: normalizedShopId,
        );

        if (!cloudAuthenticated || _cloudSync.currentSession == null) {
          if (kDebugMode) {
            debugPrint(
              'Authentication source=cloud username=$normalizedUsername shopId=$normalizedShopId success=false backendReachable=true reason=invalid_credentials',
            );
          }
          await _invalidateLocalCredentials(
            username: normalizedUsername,
            shopId: normalizedShopId,
          );
          AppSession.instance.clear();
          return const LoginResult(
            success: false,
            role: null,
            message: 'Invalid username, password, or Shop ID.',
          );
        }

        final session = _cloudSync.currentSession!;
        final role = session.role == 'super_admin'
            ? LoginRole.superAdmin
            : session.role == 'employee'
            ? LoginRole.employee
            : LoginRole.admin;

        await _refreshLocalOfflineCredentials(
          username: normalizedUsername,
          password: normalizedPassword,
          shopId: normalizedShopId,
          role: role,
        );

        if (kDebugMode) {
          debugPrint(
            'Authentication source=cloud role=${role.name} username=$normalizedUsername shopId=$normalizedShopId success=true',
          );
        }
        AppSession.instance.update(
          role: role.name,
          shopId: role == LoginRole.superAdmin ? null : session.shopId,
          username: session.username,
        );
        return LoginResult(
          success: true,
          role: role,
          message: '${role.name} login successful',
          shopId: role == LoginRole.superAdmin ? null : session.shopId,
          username: session.username,
          cloudSyncRequired: role != LoginRole.superAdmin,
        );
      } catch (error) {
        if (kDebugMode) {
          debugPrint(
            'Authentication source=cloud username=$normalizedUsername shopId=$normalizedShopId success=false backendReachable=true reason=server_error details=${error.toString()}',
          );
        }
        if (error is CloudAuthException &&
            error.kind == CloudAuthFailureKind.network) {
          final localAttempt = login(
            username: normalizedUsername,
            password: normalizedPassword,
            shopId: normalizedShopId,
          );
          if (localAttempt.success) {
            if (kDebugMode) {
              debugPrint(
                'Authentication source=local-fallback username=$normalizedUsername shopId=$normalizedShopId backendReachable=false reason=cloud_connection_lost',
              );
            }
            return localAttempt;
          }
        }
        AppSession.instance.clear();
        final message =
            error is CloudAuthException &&
                error.kind == CloudAuthFailureKind.timeout
            ? 'Server connection timed out. Please check your internet connection and try again.'
            : error is CloudAuthException &&
                  error.kind == CloudAuthFailureKind.network
            ? 'Unable to reach the cloud backend. Please check your internet connection.'
            : 'The cloud backend returned a server error. Please try again later.';
        return LoginResult(success: false, role: null, message: message);
      }
    }

    if (kDebugMode) {
      debugPrint(
        'Authentication source=local-fallback username=$normalizedUsername shopId=$normalizedShopId backendReachable=false',
      );
    }

    final localAttempt = login(
      username: normalizedUsername,
      password: normalizedPassword,
      shopId: normalizedShopId,
    );
    if (!localAttempt.success) {
      AppSession.instance.clear();
      return const LoginResult(
        success: false,
        role: null,
        message: 'Invalid username, password, or Shop ID.',
      );
    }

    return localAttempt;
  }

  Future<void> _refreshLocalOfflineCredentials({
    required String username,
    required String password,
    required String shopId,
    required LoginRole role,
  }) async {
    if (role == LoginRole.superAdmin) {
      return;
    }

    if (shopId.isNotEmpty) {
      final shopExists = SuperAdminService.instance.shopExists(shopId);
      if (shopExists) {
        SuperAdminService.instance.upsertShopCredential(
          shopId: shopId,
          username: username,
          password: password,
        );
      } else {
        SuperAdminService.instance.createShop(
          ownerName: 'Cloud User',
          contact: 'Cloud',
          address: 'Synced',
          shopId: shopId,
          username: username,
          password: password,
        );
      }
    }

    if (role == LoginRole.employee) {
      EmployeeManagementService.instance.upsertEmployeeCredential(
        shopId: shopId,
        username: username,
        password: password,
      );
    }
  }

  Future<void> _invalidateLocalCredentials({
    required String username,
    required String shopId,
  }) async {
    if (shopId.isNotEmpty) {
      SuperAdminService.instance.invalidateShopCredential(shopId);
      EmployeeManagementService.instance.invalidateEmployeeCredential(
        shopId: shopId,
        username: username,
      );
    }
  }

  LoginResult login({
    required String username,
    required String password,
    String? shopId,
  }) {
    final normalizedUsername = username.trim();
    final normalizedPassword = password.trim();
    final normalizedShopId = (shopId ?? '').trim();

    if (SuperAdminService.instance.isSuperAdminCredentials(
      normalizedUsername,
      normalizedPassword,
    )) {
      final result = const LoginResult(
        success: true,
        role: LoginRole.superAdmin,
        message: 'Super admin login successful',
      );
      AppSession.instance.update(
        role: LoginRole.superAdmin.name,
        shopId: null,
        username: normalizedUsername,
      );
      return result;
    }

    final backendSession = _loginWithCloudBackend(
      username: normalizedUsername,
      password: normalizedPassword,
      shopId: normalizedShopId,
    );
    if (backendSession != null) {
      return backendSession;
    }

    final shop = SuperAdminService.instance.findShopByCredentials(
      username: normalizedUsername,
      password: normalizedPassword,
      shopId: normalizedShopId,
    );

    if (shop != null) {
      if (SuperAdminService.instance.isShopSuspended(shop.shopId)) {
        final result = const LoginResult(
          success: false,
          role: LoginRole.admin,
          message:
              'This shop has been suspended. Please contact the Super Admin.',
        );
        AppSession.instance.clear();
        return result;
      }

      final result = LoginResult(
        success: true,
        role: LoginRole.admin,
        message: 'Admin login successful',
        shopId: shop.shopId,
        username: normalizedUsername,
        cloudSyncRequired: true,
      );
      AppSession.instance.update(
        role: LoginRole.admin.name,
        shopId: shop.shopId,
        username: normalizedUsername,
      );
      return result;
    }

    final employee = EmployeeManagementService.instance
        .findEmployeeByCredentials(
          username: normalizedUsername,
          password: normalizedPassword,
          shopId: normalizedShopId,
        );

    if (employee != null) {
      if (employee.status == 'disabled') {
        final result = const LoginResult(
          success: false,
          role: LoginRole.employee,
          message: 'This employee account is disabled.',
        );
        AppSession.instance.clear();
        return result;
      }

      final result = LoginResult(
        success: true,
        role: LoginRole.employee,
        message: 'Employee login successful',
        shopId: employee.shopId,
        userId: employee.id,
        username: employee.username,
        cloudSyncRequired: true,
      );
      AppSession.instance.update(
        role: LoginRole.employee.name,
        shopId: employee.shopId,
        username: employee.username,
        userId: employee.id,
      );
      return result;
    }

    AppSession.instance.clear();
    return const LoginResult(
      success: false,
      role: null,
      message: 'Invalid username, password, or Shop ID.',
    );
  }

  LoginResult? _loginWithCloudBackend({
    required String username,
    required String password,
    required String shopId,
  }) {
    return null;
  }

  /// Authenticate with cloud backend
  /// Call this after successful local authentication
  Future<bool> authenticateWithCloud({
    required String username,
    required String password,
    required String shopId,
  }) async {
    try {
      return await _cloudSync.authenticate(
        username: username,
        password: password,
        shopId: shopId,
      );
    } catch (e) {
      return false;
    }
  }
}
