import 'package:cloudreve/utils/app_update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release parser selects the APK matching the device ABI', () {
    final release = AppRelease.fromJson({
      'tag_name': 'v1.3.0',
      'html_url': 'https://github.com/example/project/releases/tag/v1.3.0',
      'assets': [
        {
          'name': 'cloudreve-android-1.3.0-armeabi-v7a.apk',
          'browser_download_url': 'https://example.com/armv7.apk',
          'size': 20,
        },
        {
          'name': 'cloudreve-android-1.3.0-arm64-v8a.apk',
          'browser_download_url': 'https://example.com/arm64.apk',
          'size': 30,
        },
        {
          'name': 'SHA256SUMS.txt',
          'browser_download_url': 'https://example.com/SHA256SUMS.txt',
          'size': 10,
        },
      ],
    });

    expect(release.version, '1.3.0');
    expect(
      release.apkFor(AndroidReleaseAbi.arm64)?.name,
      endsWith('arm64-v8a.apk'),
    );
    expect(
      release.apkFor(AndroidReleaseAbi.armv7)?.name,
      endsWith('armeabi-v7a.apk'),
    );
  });

  test(
    'version comparison handles v prefixes, build metadata and prereleases',
    () {
      expect(AppUpdateService.isNewer('v1.2.9', '1.2.8'), isTrue);
      expect(AppUpdateService.compareVersions('1.2.8+48', '1.2.8+47'), 0);
      expect(AppUpdateService.compareVersions('1.2.8', '1.2.8-beta.1'), 1);
      expect(AppUpdateService.isNewer('1.2.7', '1.2.8'), isFalse);
    },
  );

  test('invalid release URLs are rejected', () {
    expect(
      () => AppRelease.fromJson({
        'tag_name': 'v1.0.0',
        'html_url': 'http://insecure.example/release',
      }),
      throwsFormatException,
    );
  });
}
