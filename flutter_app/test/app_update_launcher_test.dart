import 'package:flutter_app/src/core/app_update_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
