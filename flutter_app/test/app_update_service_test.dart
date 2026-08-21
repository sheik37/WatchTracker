import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_app/src/core/app_config.dart';
import 'package:flutter_app/src/core/app_update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('AppUpdateResult', () {
    test('detects update when semantic version is higher', () {
      const result = AppUpdateResult(
        currentVersion: '2.0.0',
        currentBuildNumber: 1,
        latestVersion: '2.1.0',
        latestBuildNumber: 1,
        downloadUrl: 'https://example.com/app.apk',
        releaseNotes: null,
      );

      expect(result.isUpdateAvailable, isTrue);
      expect(result.currentLabel, '2.0.0+1');
      expect(result.latestLabel, '2.1.0+1');
    });

    test('detects update when build number is higher on same version', () {
      const result = AppUpdateResult(
        currentVersion: '2.0.0',
        currentBuildNumber: 4,
        latestVersion: '2.0.0',
        latestBuildNumber: 5,
        downloadUrl: 'https://example.com/app.apk',
        releaseNotes: null,
      );

      expect(result.isUpdateAvailable, isTrue);
    });

    test('does not report update when version and build are not newer', () {
      const result = AppUpdateResult(
        currentVersion: '2.0.0',
        currentBuildNumber: 5,
        latestVersion: '2.0.0',
        latestBuildNumber: 5,
        downloadUrl: 'https://example.com/app.apk',
        releaseNotes: null,
      );

      expect(result.isUpdateAvailable, isFalse);
    });

    test('uses plain version label when latest build number is missing', () {
      const result = AppUpdateResult(
        currentVersion: '2.0.0',
        currentBuildNumber: 1,
        latestVersion: '2.0.1',
        latestBuildNumber: null,
        downloadUrl: null,
        releaseNotes: null,
      );

      expect(result.latestLabel, '2.0.1');
    });
  });

  group('AppUpdateService', () {
    test('can be created with the default HTTP client and disposed', () {
      final service = AppUpdateService();

      service.dispose();
    });

    test('returns fallback data when the manifest URL is empty', () async {
      final service = AppUpdateService(
        manifestUrl: '',
        currentVersion: '2.0.0',
        currentBuildNumber: 7,
        androidUpdateUrl: 'https://example.com/android.apk',
        targetPlatform: TargetPlatform.android,
      );

      final result = await service.checkForUpdates();

      expect(result.currentVersion, '2.0.0');
      expect(result.currentBuildNumber, 7);
      expect(result.latestVersion, '2.0.0');
      expect(result.latestBuildNumber, 7);
      expect(result.downloadUrl, 'https://example.com/android.apk');
      expect(result.isUpdateAvailable, isFalse);
    });

    test(
      'parses the update manifest and returns the latest metadata',
      () async {
        final service = AppUpdateService(
          httpClient: MockClient((request) async {
            expect(request.headers['Accept'], 'application/json');
            return http.Response(
              jsonEncode({
                'latest_version': '2.1.0',
                'latest_build': '12',
                'android_url': 'https://example.com/android.apk',
                'desktop_url': 'https://example.com/android.apk',
                'release_notes': 'Voir les notes: https://example.com/release',
              }),
              200,
            );
          }),
        );

        final result = await service.checkForUpdates();

        expect(result.currentVersion, AppConfig.appVersion.trim());
        expect(result.currentBuildNumber, AppConfig.appBuildNumber);
        expect(result.latestVersion, '2.1.0');
        expect(result.latestBuildNumber, 12);
        expect(result.downloadUrl, 'https://example.com/android.apk');
        expect(
          result.releaseNotes,
          'Voir les notes: https://example.com/release',
        );
        expect(result.isUpdateAvailable, isTrue);
      },
    );

    test('uses iOS platform URL when the target platform is iOS', () async {
      final service = AppUpdateService(
        targetPlatform: TargetPlatform.iOS,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'latest_version': '2.1.0',
              'ios_url': 'https://example.com/ios',
            }),
            200,
          ),
        ),
      );

      final result = await service.checkForUpdates();

      expect(result.downloadUrl, 'https://example.com/ios');
    });

    test('uses desktop URL then generic URL for non mobile targets', () async {
      final desktopService = AppUpdateService(
        targetPlatform: TargetPlatform.windows,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'latest_version': '2.1.0',
              'desktop_url': 'https://example.com/desktop',
            }),
            200,
          ),
        ),
      );
      final genericService = AppUpdateService(
        targetPlatform: TargetPlatform.windows,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'latest_version': '2.1.0',
              'url': 'https://example.com/generic',
            }),
            200,
          ),
        ),
      );

      expect(
        (await desktopService.checkForUpdates()).downloadUrl,
        'https://example.com/desktop',
      );
      expect(
        (await genericService.checkForUpdates()).downloadUrl,
        'https://example.com/generic',
      );
    });

    test(
      'keeps a null download URL when manifest has no platform link',
      () async {
        final service = AppUpdateService(
          httpClient: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'latest_version': '2.0.0',
                'latest_build': 1,
                'release_notes': 'Aucune note',
              }),
              200,
            ),
          ),
        );

        final result = await service.checkForUpdates();

        expect(result.downloadUrl, isNull);
        expect(result.latestLabel, '2.0.0+1');
        expect(result.isUpdateAvailable, isFalse);
      },
    );

    test(
      'uses fallback iOS and generic URLs when manifest omits platform URL',
      () async {
        final iosService = AppUpdateService(
          targetPlatform: TargetPlatform.iOS,
          iosUpdateUrl: 'https://example.com/appstore',
          httpClient: MockClient(
            (_) async =>
                http.Response(jsonEncode({'latest_version': '2.1.0'}), 200),
          ),
        );
        final desktopService = AppUpdateService(
          targetPlatform: TargetPlatform.windows,
          updateDownloadUrl: 'https://example.com/download',
          httpClient: MockClient(
            (_) async =>
                http.Response(jsonEncode({'latest_version': '2.1.0'}), 200),
          ),
        );

        expect(
          (await iosService.checkForUpdates()).downloadUrl,
          'https://example.com/appstore',
        );
        expect(
          (await desktopService.checkForUpdates()).downloadUrl,
          'https://example.com/download',
        );
      },
    );

    test('compares version strings with different lengths', () async {
      final service = AppUpdateService(
        currentVersion: '2.0',
        currentBuildNumber: 1,
        manifestUrl: 'https://example.com/version.json',
        httpClient: MockClient(
          (_) async =>
              http.Response(jsonEncode({'latest_version': '2.0.1'}), 200),
        ),
      );

      final result = await service.checkForUpdates();

      expect(result.isUpdateAvailable, isTrue);
    });

    test('throws when the manifest cannot be fetched', () async {
      final service = AppUpdateService(
        httpClient: MockClient((_) async => http.Response('oops', 500)),
      );

      await expectLater(
        service.checkForUpdates(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Impossible de récupérer les mises à jour.',
          ),
        ),
      );
    });

    test('throws when latest_version is missing from manifest', () async {
      final service = AppUpdateService(
        httpClient: MockClient(
          (_) async => http.Response(jsonEncode({'latest_build': 5}), 200),
        ),
      );

      await expectLater(
        service.checkForUpdates(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'latest_version manquant dans le manifest.',
          ),
        ),
      );
    });

    test('throws when the manifest payload is not an object', () async {
      final service = AppUpdateService(
        httpClient: MockClient(
          (_) async => http.Response(jsonEncode(['bad']), 200),
        ),
      );

      await expectLater(
        service.checkForUpdates(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Format de manifest invalide.',
          ),
        ),
      );
    });
  });
}
