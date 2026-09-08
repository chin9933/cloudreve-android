/// Build-time configuration, never credentials.
///
/// Existing installations keep their chosen server in local preferences.
/// Values are public APK metadata. Never put secrets in compilation arguments.
abstract final class AppConfig {
  static const appName = String.fromEnvironment(
    'APP_NAME',
    defaultValue: 'Cloudreve',
  );
  static const applicationId = String.fromEnvironment(
    'APP_APPLICATION_ID',
    defaultValue: 'com.example.cloudreve',
  );
  static const description = String.fromEnvironment(
    'APP_DESCRIPTION',
    defaultValue: '安全存储 · 随时访问 · 轻松分享',
  );
  // An unconfigured client must ask for a server, not contact a maintainer's site.
  static const defaultSiteUrl = String.fromEnvironment('CLOUDREVE_SITE_URL');
}
