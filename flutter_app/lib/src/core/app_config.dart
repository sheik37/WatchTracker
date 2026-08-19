class AppConfig {
  const AppConfig._();

  static const tmdbApiKey = String.fromEnvironment(
    'TMDB_API_KEY',
    defaultValue: '',
  );
  static const backendBaseUrl = String.fromEnvironment(
    'BACKEND_BASE_URL',
    defaultValue: '',
  );
  static const updateManifestUrl = String.fromEnvironment(
    'UPDATE_MANIFEST_URL',
    defaultValue:
        'https://github.com/sheik37/WatchTracker/releases/latest/download/version.json',
  );
  static const androidUpdateUrl = String.fromEnvironment(
    'ANDROID_UPDATE_URL',
    defaultValue: '',
  );
  static const iosUpdateUrl = String.fromEnvironment(
    'IOS_UPDATE_URL',
    defaultValue: '',
  );
  static const updateDownloadUrl = String.fromEnvironment(
    'UPDATE_DOWNLOAD_URL',
    defaultValue: '',
  );
  static const appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '2.0.0',
  );
  static const appBuildNumber = int.fromEnvironment(
    'APP_BUILD_NUMBER',
    defaultValue: 1,
  );
  static const tvdbApiKey = String.fromEnvironment(
    'TVDB_API_KEY',
    defaultValue: '',
  );
}
