class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'AK_API_BASE_URL',
    defaultValue: 'https://backend-of-mobile-management.onrender.com',
  );

  static String get normalizedApiBaseUrl =>
      apiBaseUrl.endsWith('/') ? apiBaseUrl.substring(0, apiBaseUrl.length - 1) : apiBaseUrl;

  static bool get isProductionConfigured =>
      normalizedApiBaseUrl.startsWith('https://') &&
      !normalizedApiBaseUrl.contains('127.0.0.1') &&
      !normalizedApiBaseUrl.contains('localhost');

  static String get configuredApiBaseUrl => normalizedApiBaseUrl;
}
