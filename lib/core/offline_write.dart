import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

/// How long a save waits for the server before trusting the phone's copy.
/// Online, the server answers well within this, so a rejected save still
/// shows its error on the form as before.
const _confirmWait = Duration(seconds: 2);

/// How long a read waits for the phone's copy (or the server) before giving
/// up. Kept-synced paths answer at once; only data never loaded on this phone
/// can take this long offline.
const _readWait = Duration(seconds: 6);

/// Runs a database write the offline-first way.
///
/// Phones: the database saves [write] on disk immediately and sends it when
/// the connection is back (it survives app restarts). This waits up to
/// [_confirmWait] for the server: an error in that time is thrown as before;
/// after it, the change is counted in [PendingWrites] and the caller carries
/// on as if saved. Web: plain `await` (online-only, as before).
Future<void> commitWrite(Future<void> write) async {
  if (kIsWeb) return write;
  final pending = PendingWrites.instance;
  pending._begin();
  final tracked = write.whenComplete(pending._end);
  // A queued change the server rejects later (after the form closed) can
  // only be logged; nobody is waiting for it any more.
  unawaited(tracked.catchError(
      (Object e) => debugPrint('Queued change rejected by the server: $e')));
  try {
    await tracked.timeout(_confirmWait);
  } on TimeoutException {
    // Offline or slow: kept on the phone, sent when online.
  }
}

/// Reads [query] once from the phone's copy when there is one (offline too),
/// otherwise from the server. Unlike `get()`, it never fails just because the
/// phone is offline; it throws [TimeoutException] only when the data was
/// never loaded on this phone and there is no connection.
Future<DataSnapshot> readOnce(Query query) async =>
    (await query.once().timeout(_readWait)).snapshot;

/// Counts database changes made on this phone that the server has not
/// confirmed yet, for the "changes will sync" banner.
///
/// Changes made since the app started are tracked one by one. Changes left
/// over from before a restart can't be followed individually (the database
/// resends them by itself), so their number is saved on disk and cleared by
/// [confirmCarriedOver] once the database is back online.
class PendingWrites extends ChangeNotifier {
  PendingWrites._();

  static final instance = PendingWrites._();

  static const _boxName = 'pending_writes';
  Box<dynamic>? _box;

  /// Unconfirmed changes made since the app started.
  int _live = 0;

  /// Unconfirmed changes left over from earlier runs of the app.
  int _carried = 0;

  int get count => _live + _carried;
  bool get hasCarriedOver => _carried > 0;

  /// Opens the box. Call once from `main()` after `Hive.initFlutter()`.
  static Future<void> init() async {
    if (kIsWeb) return;
    final box = await Hive.openBox<dynamic>(_boxName);
    instance
      .._box = box
      .._carried = (box.get('count') as int?) ?? 0;
  }

  void _begin() {
    _live++;
    _changed();
  }

  void _end() {
    if (_live > 0) _live--;
    _changed();
  }

  /// Called when a write made after reconnecting has been confirmed. The
  /// database sends changes in the order they were made, so every change
  /// left over from before the restart has been confirmed too.
  void confirmCarriedOver() {
    if (_carried == 0) return;
    _carried = 0;
    _changed();
  }

  /// Forgets every count (sign-out, after the queued changes were dropped).
  void reset() {
    _live = 0;
    _carried = 0;
    _changed();
  }

  void _changed() {
    try {
      _box?.put('count', count);
    } catch (e) {
      debugPrint('Could not save pending-change count: $e');
    }
    notifyListeners();
  }
}
