library;

/// Cloud API service for synchronizing data with backend
///
/// This service handles all communication with the cloud backend,
/// including authentication, data sync, and conflict resolution.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'cloud_sync_models.dart';

enum CloudAuthFailureKind { timeout, network, server }

class CloudAuthException implements Exception {
  const CloudAuthException(this.kind, this.message);

  final CloudAuthFailureKind kind;
  final String message;

  @override
  String toString() => message;
}

/// Base interface for cloud API implementations
abstract class CloudApiService {
  /// Authenticate user with cloud backend
  Future<CloudAuthSession?> authenticate({
    required String username,
    required String password,
    required String shopId,
  });

  /// Logout and invalidate session
  Future<void> logout(String authToken);

  /// Check if network is available
  Future<bool> isNetworkAvailable();

  /// Upload a single sync item to cloud
  Future<bool> uploadSyncItem(SyncQueueItem item, String authToken);

  /// Download changes for a shop since last sync
  Future<List<Map<String, dynamic>>> downloadChanges({
    required String shopId,
    required String authToken,
    required DateTime sinceTime,
  });

  /// Get initial sync data for new device
  Future<Map<String, List<Map<String, dynamic>>>> getInitialSync({
    required String shopId,
    required String authToken,
  });

  /// Validate that user has access to shop
  Future<bool> validateShopAccess({
    required String shopId,
    required String authToken,
  });

  Future<List<Map<String, dynamic>>> listShops(String authToken);

  Future<bool> createShop({
    required String authToken,
    required Map<String, dynamic> shop,
  });

  Future<bool> deleteShop({required String authToken, required String shopId});

  /// Register device for sync tracking
  Future<bool> registerDevice({
    required String shopId,
    required String userId,
    required String authToken,
    required DeviceRegistration device,
  });

  /// Report sync conflict to server
  Future<void> reportConflict(SyncConflict conflict, String authToken);
}

class RestCloudApiService implements CloudApiService {
  static const requestTimeout = Duration(seconds: 15);

  RestCloudApiService({String? baseUrl})
    : baseUrl = (baseUrl ?? AppConfig.normalizedApiBaseUrl).replaceAll(
        RegExp(r'/+$'),
        '',
      ),
      httpClient = http.Client() {
    if (kDebugMode) {
      debugPrint('Cloud API base URL: ${this.baseUrl}');
    }
  }

  final String baseUrl;
  final http.Client httpClient;

  Map<String, String> _headers(String authToken, {bool json = true}) {
    final headers = <String, String>{};
    if (json) {
      headers['Content-Type'] = 'application/json';
    }
    if (authToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $authToken';
    }
    return headers;
  }

  @override
  Future<CloudAuthSession?> authenticate({
    required String username,
    required String password,
    required String shopId,
  }) async {
    if (kDebugMode) {
      debugPrint(
        'Cloud auth attempt: endpoint=/api/auth/login username=$username shopId=$shopId backendReachable=unknown',
      );
    }
    final stopwatch = Stopwatch()..start();
    try {
      final response = await httpClient
          .post(
            Uri.parse('$baseUrl/api/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': username,
              'password': password,
              'shopId': shopId,
              'deviceId': 'flutter-client',
            }),
          )
          .timeout(requestTimeout);

      if (kDebugMode) {
        debugPrint(
          'Cloud API POST /api/auth/login status=${response.statusCode} responseTimeMs=${stopwatch.elapsedMilliseconds} backendReachable=true authErrorCategory=${response.statusCode == 200
              ? 'none'
              : response.statusCode == 401 || response.statusCode == 403
              ? 'invalid_credentials'
              : 'server_error'}',
        );
      }

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final session = body as Map<String, dynamic>;
        return CloudAuthSession(
          userId: session['userId']?.toString() ?? '',
          username: session['username']?.toString() ?? username,
          shopId: session['shopId']?.toString() ?? shopId,
          role: session['role']?.toString() ?? 'admin',
          authToken: session['authToken']?.toString() ?? '',
          expiresAt:
              DateTime.tryParse(session['expiresAt']?.toString() ?? '') ??
              DateTime.now().add(const Duration(hours: 24)),
          createdAt:
              DateTime.tryParse(session['createdAt']?.toString() ?? '') ??
              DateTime.now(),
        );
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        return null;
      }

      throw CloudAuthException(
        CloudAuthFailureKind.server,
        'Cloud auth failed with HTTP ${response.statusCode}: ${response.reasonPhrase}',
      );
    } catch (error) {
      final kind = error is TimeoutException
          ? CloudAuthFailureKind.timeout
          : error is SocketException || error is http.ClientException
          ? CloudAuthFailureKind.network
          : error is CloudAuthException
          ? error.kind
          : CloudAuthFailureKind.server;
      if (kDebugMode) {
        debugPrint(
          'Cloud auth failure: backendReachable=true errorCategory=${kind.name} responseTimeMs=${stopwatch.elapsedMilliseconds}',
        );
      }
      if (error is CloudAuthException) rethrow;
      throw CloudAuthException(kind, error.toString());
    }
  }

  @override
  Future<void> logout(String authToken) async {
    await httpClient.post(
      Uri.parse('$baseUrl/api/auth/logout'),
      headers: _headers(authToken),
    );
  }

  @override
  Future<bool> isNetworkAvailable() async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await httpClient
          .get(Uri.parse('$baseUrl/api/health'))
          .timeout(requestTimeout);
      if (kDebugMode) {
        debugPrint(
          'Cloud API GET /api/health status=${response.statusCode} responseTimeMs=${stopwatch.elapsedMilliseconds} backendReachable=${response.statusCode == 200}',
        );
      }
      if (response.statusCode == 200) {
        return true;
      }
      throw const CloudAuthException(
        CloudAuthFailureKind.server,
        'Cloud health check returned a server error.',
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          'Cloud API GET /api/health status=unavailable responseTimeMs=${stopwatch.elapsedMilliseconds} errorCategory=${error is TimeoutException
              ? 'timeout'
              : error is CloudAuthException
              ? error.kind.name
              : 'network_error'} backendReachable=${error is CloudAuthException && error.kind == CloudAuthFailureKind.server}',
        );
      }
      if (error is TimeoutException) {
        throw const CloudAuthException(
          CloudAuthFailureKind.timeout,
          'Cloud health check timed out.',
        );
      }
      if (error is CloudAuthException &&
          error.kind == CloudAuthFailureKind.server) {
        rethrow;
      }
      return false;
    }
  }

  @override
  Future<bool> uploadSyncItem(SyncQueueItem item, String authToken) async {
    final response = await httpClient.post(
      Uri.parse('$baseUrl/api/sync/upload'),
      headers: _headers(authToken),
      body: jsonEncode({
        'items': [
          {
            'id': item.id,
            'shopId': item.shopId,
            'entityType': item.entityType,
            'entityId': item.entityId,
            'operation': item.operation,
            'data': item.data,
            'createdAt': item.createdAt.toIso8601String(),
          },
        ],
      }),
    );

    if (response.statusCode >= 400) {
      throw Exception('Upload failed: ${response.body}');
    }

    final payload = jsonDecode(response.body);
    final success = payload is Map<String, dynamic>
        ? payload['itemsSynced'] != null
        : false;
    return success;
  }

  @override
  Future<List<Map<String, dynamic>>> downloadChanges({
    required String shopId,
    required String authToken,
    required DateTime sinceTime,
  }) async {
    final response = await httpClient.post(
      Uri.parse('$baseUrl/api/sync/download'),
      headers: _headers(authToken),
      body: jsonEncode({
        'shopId': shopId,
        'lastSyncTime': sinceTime.toUtc().toIso8601String(),
        'entityTypes': [
          'product',
          'sale',
          'customer',
          'employee',
          'repair',
          'debtor',
          'accessory',
          'mobile_device',
          'mobile_model',
          'mobile_unit',
          'supplier',
          'return',
          'purchase',
        ],
        'batchSize': 200,
      }),
    );

    if (response.statusCode >= 400) {
      throw Exception('Download failed: ${response.body}');
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final changes = (payload['changes'] as List<dynamic>? ?? <dynamic>[])
        .map((e) => Map<String, dynamic>.from(e as Map<String, dynamic>))
        .toList(growable: false);
    return changes;
  }

  @override
  Future<Map<String, List<Map<String, dynamic>>>> getInitialSync({
    required String shopId,
    required String authToken,
  }) async {
    final response = await httpClient.get(
      Uri.parse('$baseUrl/api/sync/initial?shopId=$shopId'),
      headers: _headers(authToken),
    );

    if (response.statusCode >= 400) {
      throw Exception('Initial sync failed: ${response.body}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final result = <String, List<Map<String, dynamic>>>{};
    body.forEach((key, value) {
      result[key] = (value as List<dynamic>)
          .map(
            (item) => Map<String, dynamic>.from(item as Map<String, dynamic>),
          )
          .toList(growable: false);
    });
    return result;
  }

  @override
  Future<bool> validateShopAccess({
    required String shopId,
    required String authToken,
  }) async {
    final response = await httpClient.get(
      Uri.parse('$baseUrl/api/auth/validate-shop-access?shopId=$shopId'),
      headers: _headers(authToken),
    );
    if (response.statusCode == 403) return false;
    if (response.statusCode >= 400) return false;
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['hasAccess'] == true;
  }

  @override
  Future<List<Map<String, dynamic>>> listShops(String authToken) async {
    final stopwatch = Stopwatch()..start();
    final response = await httpClient
        .get(
          Uri.parse('$baseUrl/api/super-admin/shops'),
          headers: _headers(authToken),
        )
        .timeout(RestCloudApiService.requestTimeout);
    if (kDebugMode) {
      debugPrint(
        'Cloud API GET /api/super-admin/shops status=${response.statusCode} elapsedMs=${stopwatch.elapsedMilliseconds}',
      );
    }
    if (response.statusCode >= 400) {
      throw Exception('Shop list failed: ${response.body}');
    }
    final payload = jsonDecode(response.body) as List<dynamic>;
    return payload
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
  }

  @override
  Future<bool> createShop({
    required String authToken,
    required Map<String, dynamic> shop,
  }) async {
    final endpoint = '$baseUrl/api/super-admin/shops';
    final requestBody = Map<String, dynamic>.from(shop);
    final shopId = requestBody['shopId']?.toString() ?? 'unknown';
    final stopwatch = Stopwatch()..start();
    debugPrint(
      'CLOUD CREATE STARTED shopId=$shopId method=POST endpoint=$endpoint',
    );
    try {
      final response = await httpClient
          .post(
            Uri.parse(endpoint),
            headers: _headers(authToken),
            body: jsonEncode(requestBody),
          )
          .timeout(requestTimeout);
      debugPrint(
        'RESPONSE STATUS shopId=$shopId status=${response.statusCode} elapsedMs=${stopwatch.elapsedMilliseconds}',
      );
      if (response.statusCode == 200) {
        final payload = jsonDecode(response.body);
        final success = payload is Map && payload['success'] == true;
        debugPrint(
          'BACKEND RESULT shopId=$shopId success=$success body=${response.body}',
        );
        return success;
      }
      debugPrint(
        'BACKEND RESULT shopId=$shopId success=false body=${response.body}',
      );
      return false;
    } catch (error, stackTrace) {
      debugPrint(
        'CLOUD CREATE FAILED shopId=$shopId elapsedMs=${stopwatch.elapsedMilliseconds} error=$error stackTrace=$stackTrace',
      );
      rethrow;
    }
  }

  @override
  Future<bool> deleteShop({
    required String authToken,
    required String shopId,
  }) async {
    final encodedShopId = Uri.encodeComponent(shopId.trim());
    final uri = Uri.parse('$baseUrl/api/super-admin/shops/$encodedShopId');
    final stopwatch = Stopwatch()..start();
    debugPrint(
      'CLOUD DELETE STARTED shopId=${shopId.trim()} method=DELETE endpoint=${uri.toString()}',
    );
    try {
      final response = await httpClient
          .delete(uri, headers: _headers(authToken))
          .timeout(RestCloudApiService.requestTimeout);
      debugPrint(
        'RESPONSE STATUS shopId=${shopId.trim()} status=${response.statusCode} elapsedMs=${stopwatch.elapsedMilliseconds}',
      );
      if (response.statusCode >= 400) {
        debugPrint(
          'BACKEND RESULT shopId=${shopId.trim()} success=false body=${response.body}',
        );
        return false;
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final success = payload['success'] == true;
      debugPrint(
        'BACKEND RESULT shopId=${shopId.trim()} success=$success body=${response.body}',
      );
      return success;
    } catch (error, stackTrace) {
      debugPrint(
        'CLOUD DELETE FAILED shopId=${shopId.trim()} elapsedMs=${stopwatch.elapsedMilliseconds} error=$error stackTrace=$stackTrace',
      );
      rethrow;
    }
  }

  @override
  Future<bool> registerDevice({
    required String shopId,
    required String userId,
    required String authToken,
    required DeviceRegistration device,
  }) async {
    final response = await httpClient.post(
      Uri.parse('$baseUrl/api/auth/register-device'),
      headers: _headers(authToken),
      body: jsonEncode({
        'shopId': shopId,
        'userId': userId,
        'deviceId': device.deviceId,
        'deviceName': device.deviceName,
        'deviceType': device.deviceType,
        'imei': device.deviceId,
      }),
    );
    if (response.statusCode >= 400) {
      return false;
    }
    return true;
  }

  @override
  Future<void> reportConflict(SyncConflict conflict, String authToken) async {
    await httpClient.post(
      Uri.parse('$baseUrl/api/sync/conflict-report'),
      headers: _headers(authToken),
      body: jsonEncode({
        'conflict': {
          'entityType': conflict.entityType,
          'entityId': conflict.entityId,
          'shopId': conflict.shopId,
          'localData': conflict.localData,
          'remoteData': conflict.remoteData,
          'localUpdatedAt': conflict.localUpdatedAt.toIso8601String(),
          'remoteUpdatedAt': conflict.remoteUpdatedAt.toIso8601String(),
        },
      }),
    );
  }
}

/// Mock implementation for local development/testing
/// Replace with actual backend integration (Firebase, Supabase, custom API, etc.)
class MockCloudApiService implements CloudApiService {
  MockCloudApiService() {
    _initializeMockData();
  }

  // Mock data storage
  final Map<String, Map<String, dynamic>> _users = {};
  final Map<String, List<Map<String, dynamic>>> _shopData = {};
  final Map<String, CloudAuthSession> _activeSessions = {};
  final Map<String, DeviceRegistration> _registeredDevices = {};
  bool _networkAvailable = true;

  void _initializeMockData() {
    // Initialize with test data
    _users['admin'] = {
      'password_hash': 'admin123',
      'role': 'super_admin',
      'shops': [],
    };
  }

  void setNetworkAvailable(bool available) {
    _networkAvailable = available;
  }

  @override
  Future<CloudAuthSession?> authenticate({
    required String username,
    required String password,
    required String shopId,
  }) async {
    await Future.delayed(
      const Duration(milliseconds: 500),
    ); // Simulate network delay

    if (!_networkAvailable) {
      throw Exception('No network connection');
    }

    // Mock validation: in production, validate against real backend
    if (username.isEmpty || password.isEmpty) {
      return null;
    }

    // For demo purposes, accept any non-empty credentials
    final session = CloudAuthSession(
      userId: 'user_${username}_$shopId',
      username: username,
      shopId: shopId,
      role: 'admin',
      authToken: 'token_${username}_${DateTime.now().millisecondsSinceEpoch}',
      expiresAt: DateTime.now().add(const Duration(hours: 24)),
      createdAt: DateTime.now(),
    );

    _activeSessions[session.authToken] = session;
    return session;
  }

  @override
  Future<void> logout(String authToken) async {
    await Future.delayed(const Duration(milliseconds: 300));
    _activeSessions.remove(authToken);
  }

  @override
  Future<bool> isNetworkAvailable() async {
    await Future.delayed(const Duration(milliseconds: 100));
    return _networkAvailable;
  }

  @override
  Future<bool> uploadSyncItem(SyncQueueItem item, String authToken) async {
    await Future.delayed(const Duration(milliseconds: 300));

    if (!_networkAvailable) {
      throw Exception('No network connection');
    }

    final session = _activeSessions[authToken];
    if (session == null) {
      throw Exception('Invalid auth token');
    }

    if (session.shopId != item.shopId) {
      throw Exception('Shop ID mismatch');
    }

    // Mock storage
    final shopKey = item.shopId;
    if (!_shopData.containsKey(shopKey)) {
      _shopData[shopKey] = [];
    }

    final data = {...item.data};
    data['_id'] = item.entityId;
    data['_type'] = item.entityType;
    data['_operation'] = item.operation;
    data['_synced_at'] = DateTime.now().toIso8601String();

    _shopData[shopKey]!.add(data);
    return true;
  }

  @override
  Future<List<Map<String, dynamic>>> downloadChanges({
    required String shopId,
    required String authToken,
    required DateTime sinceTime,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));

    if (!_networkAvailable) {
      throw Exception('No network connection');
    }

    final session = _activeSessions[authToken];
    if (session == null) {
      throw Exception('Invalid auth token');
    }

    if (session.shopId != shopId) {
      throw Exception('Shop ID mismatch');
    }

    final shopData = _shopData[shopId] ?? [];
    return shopData.where((item) {
      final syncedAt = DateTime.tryParse(item['_synced_at'] as String? ?? '');
      return syncedAt != null && syncedAt.isAfter(sinceTime);
    }).toList();
  }

  @override
  Future<Map<String, List<Map<String, dynamic>>>> getInitialSync({
    required String shopId,
    required String authToken,
  }) async {
    await Future.delayed(const Duration(milliseconds: 800));

    if (!_networkAvailable) {
      throw Exception('No network connection');
    }

    final session = _activeSessions[authToken];
    if (session == null) {
      throw Exception('Invalid auth token');
    }

    if (session.shopId != shopId) {
      throw Exception('Shop ID mismatch');
    }

    // Return all shop data organized by entity type
    return {
      'products': <Map<String, dynamic>>[],
      'sales': <Map<String, dynamic>>[],
      'customers': <Map<String, dynamic>>[],
      'mobile_devices': <Map<String, dynamic>>[],
      'accessories': <Map<String, dynamic>>[],
      'repairs': <Map<String, dynamic>>[],
      'debtors': <Map<String, dynamic>>[],
      'employees': <Map<String, dynamic>>[],
    };
  }

  @override
  Future<bool> validateShopAccess({
    required String shopId,
    required String authToken,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));

    if (!_networkAvailable) {
      throw Exception('No network connection');
    }

    final session = _activeSessions[authToken];
    return session != null && session.shopId == shopId;
  }

  @override
  Future<bool> registerDevice({
    required String shopId,
    required String userId,
    required String authToken,
    required DeviceRegistration device,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));

    if (!_networkAvailable) {
      throw Exception('No network connection');
    }

    final session = _activeSessions[authToken];
    if (session == null) {
      throw Exception('Invalid auth token');
    }

    _registeredDevices[device.deviceId] = device;
    return true;
  }

  @override
  Future<List<Map<String, dynamic>>> listShops(String authToken) async =>
      const [];

  @override
  Future<bool> createShop({
    required String authToken,
    required Map<String, dynamic> shop,
  }) async => true;

  @override
  Future<bool> deleteShop({
    required String authToken,
    required String shopId,
  }) async => true;

  @override
  Future<void> reportConflict(SyncConflict conflict, String authToken) async {
    await Future.delayed(const Duration(milliseconds: 300));

    if (!_networkAvailable) {
      throw Exception('No network connection');
    }

    final session = _activeSessions[authToken];
    if (session == null) {
      throw Exception('Invalid auth token');
    }

    if (kDebugMode) {
      print('Conflict reported: ${conflict.entityType}/${conflict.entityId}');
    }
  }
}
