import 'dart:async';

import 'package:flutter/foundation.dart';

/// Tracks a countdown towards an optional deadline (milliseconds since
/// epoch) and notifies listeners once per second while the countdown is
/// active.
///
/// Mutualizes the "deadline in millis + `Timer.periodic` ticking every
/// second" pattern that used to be duplicated across screens. Widgets that
/// only display or react to the countdown can listen to this controller
/// (e.g. via `AnimatedBuilder`/`ValueListenableBuilder`) instead of the
/// whole screen rebuilding on every tick.
class CooldownController extends ChangeNotifier {
  // Can't use an initializing formal here because the constructor body
  // needs to start the ticker right after the deadline is assigned.
  // ignore: prefer_initializing_formals
  CooldownController({int? deadlineMillis}) : _deadlineMillis = deadlineMillis {
    _refreshTicker();
  }

  int? _deadlineMillis;
  Timer? _ticker;

  /// The current deadline, in milliseconds since epoch, or `null` if no
  /// cooldown is active.
  int? get deadlineMillis => _deadlineMillis;

  /// Updates the deadline and (re)starts or stops the internal ticker as
  /// needed. A no-op when the deadline is unchanged.
  void updateDeadline(int? deadlineMillis) {
    if (_deadlineMillis == deadlineMillis) return;
    _deadlineMillis = deadlineMillis;
    _refreshTicker();
    notifyListeners();
  }

  /// Whole seconds remaining before [deadlineMillis], rounded up, or `0` if
  /// there is no active cooldown.
  int get remainingSeconds {
    final deadline = _deadlineMillis;
    if (deadline == null) return 0;
    final remainingMillis = deadline - DateTime.now().millisecondsSinceEpoch;
    if (remainingMillis <= 0) return 0;
    return (remainingMillis / 1000).ceil();
  }

  /// Whether the deadline is set and still in the future.
  bool get isActive =>
      _deadlineMillis != null &&
      _deadlineMillis! > DateTime.now().millisecondsSinceEpoch;

  void _refreshTicker() {
    _ticker?.cancel();
    _ticker = null;
    if (!isActive) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!isActive) {
        timer.cancel();
        _ticker = null;
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
