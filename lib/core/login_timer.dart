import 'package:flutter/foundation.dart';

/// TEMPORARY diagnostics for the slow-login report: prints how long each step
/// between tapping "Sign in" and seeing the dashboard takes. Debug and
/// profile builds only; prints nothing in release. Remove once fixed.
class LoginTimer {
  LoginTimer._();

  static final _watch = Stopwatch();

  static void start() {
    if (kReleaseMode) return;
    _watch
      ..reset()
      ..start();
    mark('tapped Sign in');
  }

  static void mark(String step) {
    if (kReleaseMode || !_watch.isRunning) return;
    debugPrint('[login-timing] ${'${_watch.elapsedMilliseconds}'.padLeft(6)} ms'
        '  $step');
  }

  static void finish(String step) {
    mark(step);
    _watch.stop();
  }
}
