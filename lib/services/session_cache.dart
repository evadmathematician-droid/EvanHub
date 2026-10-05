import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../models/app_user.dart';
import '../models/user_role.dart';

/// Where the signed-in user was last allowed in, saved on this phone so the
/// next launch can open the app at once — even with no internet — instead of
/// waiting for `users/{uid}` and the member record.
///
/// Holds one session (the last signed-in user): uid, email, name, school id,
/// role and which part of the app they reached. No password or token is kept;
/// Firebase Auth stores its own sign-in. Android/iOS only: web has no entry,
/// so it always loads online as before.
class SessionCache {
  SessionCache._(this._box);

  static const _boxName = 'session';
  static SessionCache? _instance;

  /// Null until [init] has run, if the box could not open, and always on web.
  static SessionCache? get instance => _instance;

  final Box<dynamic> _box;

  /// Opens the box. Call once from `main()` after `Hive.initFlutter()`.
  static Future<void> init() async {
    if (kIsWeb || _instance != null) return;
    _instance = SessionCache._(await Hive.openBox<dynamic>(_boxName));
  }

  /// The saved session for [uid], or null when there is none (first launch
  /// after install or update) or it belongs to another account.
  CachedSession? read(String uid) {
    final data = _box.get('session');
    if (data is! Map || data['uid'] != uid) return null;
    final schoolId = data['schoolId'];
    final area = data['area'];
    if (schoolId is! String || schoolId.isEmpty || area is! String) return null;
    return CachedSession(
      user: AppUser(
        uid: uid,
        email: (data['email'] ?? '') as String,
        displayName: (data['displayName'] ?? '') as String,
        schoolId: schoolId,
        role: UserRole.fromWire(data['role']),
      ),
      area: area,
    );
  }

  /// Saves [user] as the current session. [area] is the name of the
  /// `AuthStatus` they reached (only "ready" and "parentPortal" are saved).
  Future<void> save(AppUser user, String area) async {
    try {
      await _box.put('session', {
        'uid': user.uid,
        'email': user.email,
        'displayName': user.displayName,
        'schoolId': user.schoolId,
        'role': user.role.wire,
        'area': area,
        'savedAt': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint('Could not save session: $e');
    }
  }

  /// Forgets the session (sign-out, removed from the school, no school).
  Future<void> clear() async {
    try {
      await _box.delete('session');
    } catch (e) {
      debugPrint('Could not clear session: $e');
    }
  }
}

/// A session read back from [SessionCache].
class CachedSession {
  const CachedSession({required this.user, required this.area});

  final AppUser user;

  /// Name of the `AuthStatus` the user was in.
  final String area;
}
