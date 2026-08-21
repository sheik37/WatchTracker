import 'package:flutter/services.dart';
import 'package:flutter_app/src/core/app_update_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('watchtracker/system');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('extracts first HTTP URL from release notes', () {
    expect(
      AppUpdateLauncher.extractFirstHttpUrl(
        'Voir les notes : https://github.com/sheik37/WatchTracker/releases/tag/v2.0.8',
      ),
      'https://github.com/sheik37/WatchTracker/releases/tag/v2.0.8',
    );
  });

  test('returns null when release notes contain no valid URL', () {
    expect(AppUpdateLauncher.extractFirstHttpUrl('Aucune URL ici'), isNull);
  });

  test('opens update download through method channel', () async {
    final launcher = AppUpdateLauncher();

    await launcher.openDownload(' https://example.com/update.apk ');

    expect(calls, hasLength(1));
    expect(calls.single.method, 'openUrl');
    expect(calls.single.arguments, {
      'url': 'https://example.com/update.apk',
      'mode': 'download',
    });
  });

  test('opens release notes through method channel', () async {
    final launcher = AppUpdateLauncher();

    await launcher.openReleaseNotes(
      'Voir les notes : https://example.com/release/v2.0.8',
    );

    expect(calls, hasLength(1));
    expect(calls.single.arguments, {
      'url': 'https://example.com/release/v2.0.8',
      'mode': 'view',
    });
  });

  test('throws a friendly error when release note url is invalid', () async {
    final launcher = AppUpdateLauncher();

    await expectLater(
      launcher.openReleaseNotes('aucun lien'),
      throwsA(
        isA<AppUpdateLaunchException>().having(
          (e) => e.message,
          'message',
          'Lien de note de version invalide.',
        ),
      ),
    );
  });

  test('throws a friendly error when platform open fails', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => false);

    final launcher = AppUpdateLauncher();

    await expectLater(
      launcher.openDownload('https://example.com/update.apk'),
      throwsA(
        isA<AppUpdateLaunchException>().having(
          (e) => e.message,
          'message',
          'Impossible de lancer le téléchargement de la mise à jour.',
        ),
      ),
    );
  });

  test('throws a friendly error when platform channel throws', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => throw PlatformException(code: 'boom'),
        );

    final launcher = AppUpdateLauncher();

    await expectLater(
      launcher.openDownload('https://example.com/update.apk'),
      throwsA(
        isA<AppUpdateLaunchException>().having(
          (e) => e.message,
          'message',
          'Impossible de lancer le téléchargement de la mise à jour.',
        ),
      ),
    );
  });

  test('launcher exception stringifies to its message', () {
    const exception = AppUpdateLaunchException('Erreur');

    expect(exception.toString(), 'Erreur');
  });
}
