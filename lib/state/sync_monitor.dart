import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../core/offline_write.dart';
import '../services/upload_queue.dart';
import 'auth_controller.dart';

/// What the sync banner shows.
enum SyncState {
  /// Online with nothing waiting: no banner.
  idle,

  /// No connection to the database.
  offline,

  /// Online, changes or photos still going up.
  syncing,

  /// Everything just went up; shown for a few seconds.
  synced,
}

/// Follows the database connection and the changes waiting on this phone,
/// for the "Offline – changes will sync" banner. Phones only.
///
/// Also confirms changes left over from before an app restart: once online,
/// it re-saves the user's own email (same value). The database sends changes
/// in the order they were made, so when that write is confirmed, every older
/// one has been too.
class SyncMonitor extends ChangeNotifier {
  SyncMonitor(this._auth, {FirebaseDatabase? database, UploadQueue? uploads})
      : _db = database ?? FirebaseDatabase.instance,
        _uploads = uploads ?? UploadQueue.instance;

  final AuthController _auth;
  final FirebaseDatabase _db;
  final UploadQueue? _uploads;

  /// The connection flag starts false for a moment at every launch; only a
  /// longer drop counts as offline, so the banner doesn't flash.
  static const _offlineAfter = Duration(seconds: 3);
  static const _syncedFor = Duration(seconds: 3);

  StreamSubscription<DatabaseEvent>? _connectedSub;
  Timer? _offlineTimer;
  Timer? _syncedTimer;
  bool _connected = true;
  bool _justSynced = false;

  /// Changes piled up while offline (or from before a restart). Only then
  /// are "Syncing…" and "All changes synced" shown; an ordinary online save
  /// confirms within moments and needs no banner.
  bool _backlog = false;
  bool _confirming = false;
  int _lastPending = 0;

  bool get online => _connected;

  /// Changes plus photos still waiting for the current school.
  int get pending =>
      PendingWrites.instance.count + (_uploads?.countFor(_auth.schoolId) ?? 0);

  SyncState get state {
    if (!_connected) return SyncState.offline;
    if (pending > 0 && _backlog) return SyncState.syncing;
    if (_justSynced) return SyncState.synced;
    return SyncState.idle;
  }

  void start() {
    _connectedSub = _db.ref('.info/connected').onValue.listen(
          (e) => _onConnected(e.snapshot.value == true),
          onError: (Object e) => debugPrint('Connection status failed: $e'),
        );
    PendingWrites.instance.addListener(_onPendingChanged);
    _uploads?.listenable().addListener(_onPendingChanged);
    _auth.addListener(_onPendingChanged);
    _lastPending = pending;
    _backlog = PendingWrites.instance.hasCarriedOver || pending > 0;
  }

  void _onConnected(bool connected) {
    _offlineTimer?.cancel();
    if (connected) {
      if (!_connected) {
        _connected = true;
        notifyListeners();
      }
      _confirmCarriedOver();
    } else {
      _offlineTimer = Timer(_offlineAfter, () {
        _connected = false;
        _justSynced = false;
        if (pending > 0) _backlog = true;
        notifyListeners();
      });
    }
  }

  void _onPendingChanged() {
    final now = pending;
    if (now > 0 && (!_connected || PendingWrites.instance.hasCarriedOver)) {
      _backlog = true;
    }
    if (_lastPending > 0 && now == 0 && _connected && _backlog) {
      _backlog = false;
      _justSynced = true;
      _syncedTimer?.cancel();
      _syncedTimer = Timer(_syncedFor, () {
        _justSynced = false;
        notifyListeners();
      });
    }
    _lastPending = now;
    _confirmCarriedOver();
    notifyListeners();
  }

  Future<void> _confirmCarriedOver() async {
    final user = _auth.appUser;
    if (_confirming ||
        !_connected ||
        !PendingWrites.instance.hasCarriedOver ||
        _auth.status != AuthStatus.ready ||
        user == null) {
      return;
    }
    _confirming = true;
    try {
      final email = _db.ref('users/${user.uid}/email');
      final current = (await readOnce(email)).value;
      if (current != null) await email.set(current);
      PendingWrites.instance.confirmCarriedOver();
    } catch (e) {
      debugPrint('Could not confirm earlier changes yet: $e');
    } finally {
      _confirming = false;
    }
  }

  @override
  void dispose() {
    _connectedSub?.cancel();
    _offlineTimer?.cancel();
    _syncedTimer?.cancel();
    PendingWrites.instance.removeListener(_onPendingChanged);
    _uploads?.listenable().removeListener(_onPendingChanged);
    _auth.removeListener(_onPendingChanged);
    super.dispose();
  }
}
