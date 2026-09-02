import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'core/cloud/cloud_api_service.dart';
import 'core/cloud/cloud_sync_service.dart';
import 'core/config/app_config.dart';
import 'core/database/database_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final applicationSupportDirectory = await getApplicationSupportDirectory();
  await DatabaseService.initialize(applicationSupportDirectory.path);
  CloudSyncService.configure(
    apiService: RestCloudApiService(baseUrl: AppConfig.normalizedApiBaseUrl),
  );
  runApp(const App());
}
