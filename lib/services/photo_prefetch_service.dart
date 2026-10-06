import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import '../core/internet_check.dart';
import '../core/offline_write.dart';
import '../core/rtdb.dart';
import '../state/auth_controller.dart';
import 'student_photo_cache.dart';

/// While online, quietly saves small copies of the signed-in school's pupil
/// photos on the phone ([StudentPhotoCache]), so exports show them even with
/// data off later. Runs when the user reaches their school, when the network
/// comes back and when the app returns to the foreground — at most once every
/// [_every] per school. Phones only.
class PhotoPrefetchService with WidgetsBindingObserver {
  PhotoPrefetchService(this._auth);

  final AuthController _auth;

  static const _every = Duration(minutes: 30);

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _running = false;
  String? _lastSchool;
  DateTime? _lastRun;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (!results.contains(ConnectivityResult.none)) _maybeRun();
    });
    _auth.addListener(_maybeRun);
    _maybeRun();
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySub?.cancel();
    _auth.removeListener(_maybeRun);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _maybeRun();
  }

  Future<void> _maybeRun() async {
    final refs = _auth.tenant;
    if (_running ||
        refs == null ||
        _auth.status != AuthStatus.ready ||
        !_auth.role.canManageStudents) {
      return;
    }
    final last = _lastRun;
    if (_lastSchool == refs.schoolId &&
        last != null &&
        DateTime.now().difference(last) < _every) {
      return;
    }
    _running = true;
    try {
      if (!await hasInternet()) return;
      _lastSchool = refs.schoolId;
      _lastRun = DateTime.now();
      final students = await readOnce(refs.students);
      final photos = <(String, String)>[
        for (final s in students.children)
          if (s.key != null &&
              (asMap(s.value)['photoUrl'] ?? '').toString().isNotEmpty)
            (s.key!, asMap(s.value)['photoUrl'].toString()),
      ];
      // The school may have changed while this ran (sign-out / switch).
      if (_auth.tenant?.schoolId != refs.schoolId) return;
      final saved = await StudentPhotoCache.instance.prefetch(photos);
      if (saved > 0) debugPrint('Saved $saved pupil photo(s) for offline use.');
    } catch (e) {
      debugPrint('Photo prefetch stopped: $e');
    } finally {
      _running = false;
    }
  }
}
