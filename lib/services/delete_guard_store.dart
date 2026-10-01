import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import 'delete_password_service.dart';

/// Per-phone state for the history delete password, per school:
/// wrong-attempt count and lockout, plus a copy of the password hash so posts
/// still waiting to upload can be deleted while offline.
///
/// Kept in a Hive box; if that can't open, it falls back to memory (the
/// lockout then only lasts until the app closes).
class DeleteGuardStore {
  DeleteGuardStore._();

  static final instance = DeleteGuardStore._();

  static const maxAttempts = 5;
  static const lockDuration = Duration(minutes: 5);

  Box<dynamic>? _box;
  final _memory = <String, dynamic>{};

  /// Opens the box. Call once from `main()` after `Hive.initFlutter()`.
  static Future<void> init() async {
    instance._box = await Hive.openBox<dynamic>('delete_guard');
  }

  dynamic _get(String key) => _box != null ? _box!.get(key) : _memory[key];

  Future<void> _put(String key, dynamic value) async {
    if (_box != null) {
      value == null ? await _box!.delete(key) : await _box!.put(key, value);
    } else {
      value == null ? _memory.remove(key) : _memory[key] = value;
    }
  }

  /// Time left on the lockout, or null when delete isn't locked.
  Duration? lockRemaining(String schoolId) {
    final until = _get('lockedUntil:$schoolId');
    if (until is! int) return null;
    final left = DateTime.fromMillisecondsSinceEpoch(until)
        .difference(DateTime.now());
    return left.isNegative ? null : left;
  }

  /// Counts a wrong password. Returns the attempts left; 0 means delete is now
  /// locked for [lockDuration].
  Future<int> recordFailure(String schoolId) async {
    final failures = ((_get('failures:$schoolId') as int?) ?? 0) + 1;
    if (failures >= maxAttempts) {
      await _put('failures:$schoolId', null);
      await _put('lockedUntil:$schoolId',
          DateTime.now().add(lockDuration).millisecondsSinceEpoch);
      return 0;
    }
    await _put('failures:$schoolId', failures);
    return maxAttempts - failures;
  }

  Future<void> clearFailures(String schoolId) async {
    await _put('failures:$schoolId', null);
    await _put('lockedUntil:$schoolId', null);
  }

  DeletePasswordHash? cachedHash(String schoolId) {
    final data = _get('hash:$schoolId');
    if (data is! Map) return null;
    return DeletePasswordHash.fromMap(
        data.map((k, v) => MapEntry(k.toString(), v)));
  }

  /// Remembers the school's hash (null forgets it, e.g. after a reset).
  Future<void> cacheHash(String schoolId, DeletePasswordHash? hash) async {
    try {
      await _put('hash:$schoolId', hash?.toMap());
    } catch (e) {
      debugPrint('Could not cache delete password: $e');
    }
  }
}
