import 'package:fake_async/fake_async.dart';
import 'package:flutter_app/src/core/cooldown_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CooldownController', () {
    test('starts with no active cooldown by default', () {
      final controller = CooldownController();
      expect(controller.deadlineMillis, isNull);
      expect(controller.remainingSeconds, 0);
      expect(controller.isActive, isFalse);
      controller.dispose();
    });

    test('reports remaining seconds for a future deadline', () {
      final deadline = DateTime.now().millisecondsSinceEpoch + 5000;
      final controller = CooldownController(deadlineMillis: deadline);
      expect(controller.isActive, isTrue);
      expect(controller.remainingSeconds, greaterThan(0));
      expect(controller.remainingSeconds, lessThanOrEqualTo(5));
      controller.dispose();
    });

    test('treats a past deadline as inactive with 0 remaining seconds', () {
      final deadline = DateTime.now().millisecondsSinceEpoch - 1000;
      final controller = CooldownController(deadlineMillis: deadline);
      expect(controller.isActive, isFalse);
      expect(controller.remainingSeconds, 0);
      controller.dispose();
    });

    test('updateDeadline is a no-op for an identical value', () {
      final controller = CooldownController();
      var notifyCount = 0;
      controller.addListener(() => notifyCount++);
      controller.updateDeadline(null);
      expect(notifyCount, 0);
      controller.dispose();
    });

    test('updateDeadline notifies listeners when the value changes', () {
      final controller = CooldownController();
      var notifyCount = 0;
      controller.addListener(() => notifyCount++);
      final deadline = DateTime.now().millisecondsSinceEpoch + 5000;
      controller.updateDeadline(deadline);
      expect(notifyCount, 1);
      expect(controller.deadlineMillis, deadline);
      controller.dispose();
    });

    test('ticks every second while active and notifies listeners', () {
      fakeAsync((async) {
        // Use a deadline far enough in the future that the ticker stays
        // active for the whole test, so tick counts are deterministic
        // regardless of how much real wall-clock time the test run takes.
        final deadline = DateTime.now().millisecondsSinceEpoch + 100000;
        final controller = CooldownController(deadlineMillis: deadline);
        var notifyCount = 0;
        controller.addListener(() => notifyCount++);

        async.elapse(const Duration(seconds: 1));
        expect(notifyCount, 1);

        async.elapse(const Duration(seconds: 1));
        expect(notifyCount, 2);

        async.elapse(const Duration(seconds: 3));
        expect(notifyCount, 5);
        expect(controller.isActive, isTrue);

        controller.dispose();
      });
    });

    test('clearing the deadline stops future ticks', () {
      fakeAsync((async) {
        final deadline = DateTime.now().millisecondsSinceEpoch + 100000;
        final controller = CooldownController(deadlineMillis: deadline);
        controller.updateDeadline(null);
        expect(controller.isActive, isFalse);
        expect(controller.remainingSeconds, 0);

        var notifyCount = 0;
        controller.addListener(() => notifyCount++);
        async.elapse(const Duration(seconds: 5));
        expect(notifyCount, 0);

        controller.dispose();
      });
    });
  });
}
