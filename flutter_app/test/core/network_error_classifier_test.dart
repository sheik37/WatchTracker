import 'package:flutter_app/src/core/network_error_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isOfflineOrServerUnreachableError', () {
    test('detects common offline/unreachable error substrings', () {
      expect(
        isOfflineOrServerUnreachableError(
          'SocketException: Failed host lookup',
        ),
        isTrue,
      );
      expect(isOfflineOrServerUnreachableError('Connection refused'), isTrue);
      expect(
        isOfflineOrServerUnreachableError('Erreur de connexion réseau'),
        isTrue,
      );
      expect(isOfflineOrServerUnreachableError('ClientException: x'), isTrue);
      expect(isOfflineOrServerUnreachableError('Request timed out'), isTrue);
      expect(isOfflineOrServerUnreachableError('Délai dépassé'), isTrue);
      expect(
        isOfflineOrServerUnreachableError('Impossible de contacter le serveur'),
        isTrue,
      );
      expect(
        isOfflineOrServerUnreachableError(
          'Vérifiez que le serveur est accessible',
        ),
        isTrue,
      );
    });

    test('is case-insensitive', () {
      expect(
        isOfflineOrServerUnreachableError('SOCKETEXCEPTION: oops'),
        isTrue,
      );
    });

    test('returns false for unrelated errors', () {
      expect(isOfflineOrServerUnreachableError('Invalid argument'), isFalse);
      expect(isOfflineOrServerUnreachableError('404 Not Found'), isFalse);
    });
  });
}
