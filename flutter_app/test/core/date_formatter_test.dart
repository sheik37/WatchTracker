import 'package:flutter_app/src/core/date_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatWatchDateLabel', () {
    test('formats a timestamp as dd/MM/yyyy with zero-padding', () {
      final millis = DateTime(2025, 3, 5).millisecondsSinceEpoch;
      expect(formatWatchDateLabel(millis), '05/03/2025');
    });

    test('pads single-digit day and month', () {
      final millis = DateTime(2024, 1, 9).millisecondsSinceEpoch;
      expect(formatWatchDateLabel(millis), '09/01/2024');
    });

    test('does not pad four-digit years', () {
      final millis = DateTime(2031, 12, 25).millisecondsSinceEpoch;
      expect(formatWatchDateLabel(millis), '25/12/2031');
    });
  });
}
