import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'force_update_manager.dart';
import 'force_update_screen.dart';

/// Wraps the whole app and decides, before any app screen is built, whether
/// this build may be used. Put it in `MaterialApp(.router)`'s `builder`:
///
/// ```dart
/// MaterialApp.router(
///   builder: (context, child) => ForceUpdateGate(child: child!),
///   ...
/// )
/// ```
///
/// - First launch: a plain loading screen until the first check finishes.
///   The app's own screens are not built until then.
/// - Blocked (outdated build or maintenance): [ForceUpdateScreen] replaces
///   the app. The router and its screens are not built at all, so there is
///   nothing to navigate to, and the system Back button is swallowed.
/// - Checks again whenever the app returns to the foreground, and at once
///   when an admin publishes a Remote Config change (real-time updates).
class ForceUpdateGate extends StatefulWidget {
  ForceUpdateGate({
    super.key,
    required this.child,
    this.manager,
    this.logo,
    bool? enforce,
  }) : enforce = enforce ??
            (!kIsWeb &&
                (defaultTargetPlatform == TargetPlatform.android ||
                    defaultTargetPlatform == TargetPlatform.iOS));

  final Widget child;

  /// Defaults to a [ForceUpdateManager] with standard settings.
  final ForceUpdateManager? manager;

  /// App logo on the update screen. Falls back to an icon.
  final ImageProvider? logo;

  /// Off on web and desktop by default: they are not installed from a store
  /// and always run the build they were given.
  final bool enforce;

  @override
  State<ForceUpdateGate> createState() => _ForceUpdateGateState();
}

class _ForceUpdateGateState extends State<ForceUpdateGate>
    with WidgetsBindingObserver {
  late final ForceUpdateManager _manager =
      widget.manager ?? ForceUpdateManager();
  ForceUpdateResult? _result;
  StreamSubscription<void>? _policySub;
  bool _checking = false;
  bool _updating = false;
  String? _error;

  bool get _blocked {
    final status = _result?.status;
    return status == ForceUpdateStatus.updateRequired ||
        status == ForceUpdateStatus.maintenance;
  }

  @override
  void initState() {
    super.initState();
    if (!widget.enforce) return;
    WidgetsBinding.instance.addObserver(this);
    _check();
    _policySub = _manager.onPolicyChanged().listen((_) => _check());
  }

  @override
  void dispose() {
    _policySub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  /// While blocked (or before the first check), Back does nothing. Returning
  /// true stops Flutter from passing it on, so it cannot reach the router
  /// underneath.
  @override
  Future<bool> didPopRoute() async => _result == null || _blocked;

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    try {
      final result = await _manager.check();
      if (mounted) setState(() => _result = result);
    } catch (e) {
      // Only reached if the check itself breaks (not a network failure,
      // which check() handles). Don't lock anyone out on a bug — but keep an
      // existing block in place.
      debugPrint('Force update: check failed: $e');
      if (mounted && _result == null) {
        setState(() => _result = const ForceUpdateResult(
              status: ForceUpdateStatus.allowed,
              installedVersionCode: 0,
              installedVersionName: '',
              policy: ForceUpdatePolicy(),
              fromNetwork: false,
            ));
      }
    } finally {
      _checking = false;
    }
  }

  Future<void> _onPressed() async {
    final result = _result;
    if (result == null) return;
    setState(() {
      _updating = true;
      _error = null;
    });
    if (result.status == ForceUpdateStatus.maintenance) {
      await _check();
    } else {
      final opened = await _manager.startUpdate(result.policy);
      if (!opened && mounted) {
        _error = 'Could not open the update page. Check your internet '
            'connection and try again.';
      }
      await _check();
    }
    if (mounted) setState(() => _updating = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enforce) return widget.child;

    final result = _result;
    if (result == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_blocked) return widget.child;

    final screen = ForceUpdateScreen(
      maintenance: result.status == ForceUpdateStatus.maintenance,
      message: result.status == ForceUpdateStatus.maintenance
          ? result.policy.maintenanceMessage
          : result.policy.updateMessage,
      installedVersion:
          '${result.installedVersionName} (${result.installedVersionCode})',
      requiredVersionCode: result.policy.minVersionCode,
      busy: _updating,
      onPressed: _onPressed,
      logo: widget.logo,
      error: _error,
    );

    // A navigator of its own, holding only the update page, so the PopScope
    // on that page has a route to guard.
    return Navigator(
      pages: [
        MaterialPage<void>(
          key: const ValueKey('force_update'),
          child: screen,
        ),
      ],
      onDidRemovePage: (_) {},
    );
  }
}
