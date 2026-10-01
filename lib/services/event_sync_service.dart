import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import '../core/internet_check.dart';
import '../core/tenant/tenant_refs.dart';
import '../state/auth_controller.dart';
import 'event_service.dart';
import 'pending_event_store.dart';

/// Uploads events that were saved offline ([PendingEventStore]).
///
/// Runs when the app starts, when the user signs in, when it comes back to the
/// foreground, and whenever the network changes — each time only after a real
/// internet check. Only the signed-in user's posts for their own school are
/// sent (the database rules require `authorUid == auth.uid`); anyone else's
/// stay on the phone until they sign in.
class EventSyncService with WidgetsBindingObserver {
  EventSyncService(this._auth, this._store);

  final AuthController _auth;
  final PendingEventStore _store;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  final _uploaded = StreamController<int>.broadcast();
  bool _running = false;
  String? _lastReadyUid;

  /// Emits the number of posts uploaded by each sync that uploaded any.
  Stream<int> get uploaded => _uploaded.stream;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (!results.contains(ConnectivityResult.none)) syncNow();
    });
    _auth.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySub?.cancel();
    _auth.removeListener(_onAuthChanged);
    _uploaded.close();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) syncNow();
  }

  /// Syncs once each time a user becomes ready (app start or sign-in).
  void _onAuthChanged() {
    final uid =
        _auth.status == AuthStatus.ready ? _auth.appUser?.uid : null;
    if (uid != null && uid != _lastReadyUid) syncNow();
    _lastReadyUid = uid;
  }

  /// Uploads every pending post it may. Returns how many were uploaded. A
  /// failed post stays pending and the rest still run; a second call while one
  /// is in progress returns 0 straight away.
  Future<int> syncNow() async {
    if (_running) return 0;
    final user = _auth.appUser;
    final schoolId = user?.schoolId;
    if (_auth.status != AuthStatus.ready || user == null || schoolId == null) {
      return 0;
    }
    final mine = _store
        .all()
        .where((e) => e.schoolId == schoolId && e.authorUid == user.uid)
        .toList();
    if (mine.isEmpty) return 0;

    _running = true;
    var done = 0;
    try {
      if (!await hasInternet()) return 0;
      final service = EventService(TenantRefs(schoolId));
      for (final event in mine) {
        try {
          final image = await _store.readImage(event);
          if (event.imagePath.isNotEmpty && image == null) {
            debugPrint('Pending event ${event.id}: image file missing, '
                'uploading without it.');
          }
          await service.add(
            id: event.id,
            title: event.title,
            text: event.text,
            authorUid: event.authorUid,
            imageBytes: image,
            imageName: event.imageName,
          );
          await _store.remove(event);
          done++;
        } catch (e) {
          debugPrint('Pending event ${event.id} not uploaded yet: $e');
        }
      }
    } finally {
      _running = false;
    }
    if (done > 0 && !_uploaded.isClosed) _uploaded.add(done);
    return done;
  }
}
