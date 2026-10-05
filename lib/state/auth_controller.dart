import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../core/internet_check.dart';
import '../core/login_timer.dart';
import '../core/offline_write.dart';
import '../core/rtdb.dart';
import '../core/tenant/tenant_refs.dart';
import '../models/app_user.dart';
import '../models/school.dart';
import '../models/user_role.dart';
import '../services/auth_service.dart';
import '../services/pending_event_store.dart';
import '../services/school_service.dart';
import '../services/session_cache.dart';
import '../services/upload_queue.dart';

enum AuthStatus {
  /// Still resolving the initial Firebase auth state.
  unknown,

  /// No user signed in.
  signedOut,

  /// Signed in on this phone before, but nothing is saved here yet (first
  /// launch after install/update) and there is no internet to load it.
  needsConnection,

  /// Signed in, but the account is not linked to any school yet.
  needsOnboarding,

  /// `users/{uid}` names a school, but `schools/{sid}/members/{uid}` is gone.
  noAccess,

  /// The school still uses the pre-Phase-1 layout. Admins run the migration;
  /// everyone else waits.
  upgradeRequired,

  /// A parent/student account. They have no screens yet.
  parentPortal,

  /// Signed in as an admin or teacher of a ready school — the app proper.
  ready,
}

/// App-wide auth + tenant state. Drives the router via [ChangeNotifier].
///
/// The school comes from `users/{uid}.schoolId`; the ROLE comes only from
/// `schools/{sid}/members/{uid}.role`, the same record the database rules use.
///
/// Offline-first on phones: the last session reached is saved in
/// [SessionCache], and the next launch opens straight from it while the
/// database listeners confirm (or correct) it in the background.
class AuthController extends ChangeNotifier {
  AuthController({
    AuthService? authService,
    SchoolService? schoolService,
    FirebaseDatabase? database,
    SessionCache? sessionCache,
  })  : _auth = authService ?? AuthService(),
        _schools = schoolService ?? SchoolService(),
        _db = database ?? FirebaseDatabase.instance,
        _session = sessionCache ?? SessionCache.instance {
    _authSub = _auth.authStateChanges().listen(_onAuthChanged);
  }

  final AuthService _auth;
  final SchoolService _schools;
  final FirebaseDatabase _db;

  /// Null on web and when local storage could not open.
  final SessionCache? _session;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<DatabaseEvent>? _userDocSub;
  StreamSubscription<DatabaseEvent>? _memberSub;
  String? _watchedSchoolId;

  AuthStatus _status = AuthStatus.unknown;
  AuthStatus get status => _status;

  User? _firebaseUser;
  User? get firebaseUser => _firebaseUser;

  AppUser? _appUser;
  AppUser? get appUser => _appUser;

  String? get schoolId => _appUser?.schoolId;
  UserRole get role => _appUser?.role ?? UserRole.parentStudent;
  bool get isAdmin => role == UserRole.schoolAdmin;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// Tenant-scoped database paths for the current school, or null when the user
  /// has no school.
  TenantRefs? get tenant =>
      schoolId == null ? null : TenantRefs(schoolId!, database: _db);

  Future<void> _onAuthChanged(User? user) async {
    await _userDocSub?.cancel();
    await _stopMemberWatch();
    _userDocSub = null;
    _firebaseUser = user;
    LoginTimer.mark('auth state changed (signed in: ${user != null})');

    if (user == null) {
      _appUser = null;
      _set(AuthStatus.signedOut);
      return;
    }

    // Reopen where this account was last time, without waiting for the
    // network. The listeners below confirm it or move the user on.
    final restored = _restoreSession(user);
    if (!restored) _watchForNoInternet(user);

    _userDocSub = _db.ref('users/${user.uid}').onValue.listen(
      (event) {
        LoginTimer.mark('users/{uid} record loaded');
        final data = event.snapshot.exists ? asMap(event.snapshot.value) : null;
        final schoolId = data?['schoolId'] as String?;
        if (schoolId == null || schoolId.isEmpty) {
          _stopMemberWatch();
          _appUser = AppUser(
            uid: user.uid,
            email: user.email ?? '',
            displayName: user.displayName ?? '',
          );
          _set(AuthStatus.needsOnboarding);
        } else if (schoolId != _watchedSchoolId) {
          _watchMember(user, schoolId, data!);
        }
      },
      onError: (Object e) {
        LoginTimer.mark('users/{uid} read FAILED: $e');
        _appUser = AppUser(uid: user.uid, email: user.email ?? '');
        _set(AuthStatus.needsOnboarding);
      },
    );
  }

  /// Opens the app from the saved session for [user], if there is one.
  bool _restoreSession(User user) {
    final cached = _session?.read(user.uid);
    if (cached == null) return false;
    final status = switch (cached.area) {
      'ready' => AuthStatus.ready,
      'parentPortal' => AuthStatus.parentPortal,
      _ => null,
    };
    if (status == null) return false;
    _appUser = cached.user;
    LoginTimer.mark('opened from saved session (${cached.area})');
    _set(status);
    return true;
  }

  /// With nothing saved, the first load needs the database. If the phone is
  /// offline, say so instead of leaving the splash spinning; the listeners
  /// keep waiting and open the app by themselves once the internet is back.
  Future<void> _watchForNoInternet(User user) async {
    if (kIsWeb) return;
    if (await hasInternet()) return;
    if (_firebaseUser?.uid == user.uid && _status == AuthStatus.unknown) {
      LoginTimer.mark('no internet and nothing saved: asking to connect');
      _set(AuthStatus.needsConnection);
    }
  }

  /// "Retry" on the connect-once screen: checks the internet again. The
  /// database listeners are still running and finish the load on their own.
  Future<void> retryConnection() async {
    final user = _firebaseUser;
    if (user == null || _status != AuthStatus.needsConnection) return;
    _set(AuthStatus.unknown);
    await _watchForNoInternet(user);
  }

  /// Follows `schools/{schoolId}/members/{uid}` so a role change or removal
  /// takes effect immediately.
  void _watchMember(User user, String schoolId, Map<String, dynamic> userDoc) {
    _memberSub?.cancel();
    _watchedSchoolId = schoolId;
    AppUser build(UserRole role) => AppUser(
          uid: user.uid,
          email: (userDoc['email'] ?? user.email ?? '') as String,
          displayName: (userDoc['displayName'] ?? user.displayName ?? '') as String,
          schoolId: schoolId,
          role: role,
        );

    _memberSub = _db.ref('schools/$schoolId/members/${user.uid}').onValue.listen(
      (event) async {
        LoginTimer.mark('member record loaded');
        if (!event.snapshot.exists) {
          _appUser = build(UserRole.parentStudent);
          _set(AuthStatus.noAccess);
          return;
        }
        _appUser = build(UserRole.fromWire(asMap(event.snapshot.value)['role']));
        await recheckSchool();
      },
      onError: (Object e) {
        LoginTimer.mark('member read FAILED: $e');
        _appUser = build(UserRole.parentStudent);
        _set(AuthStatus.noAccess);
      },
    );
  }

  Future<void> _stopMemberWatch() async {
    await _memberSub?.cancel();
    _memberSub = null;
    _watchedSchoolId = null;
  }

  /// Decides between parent portal, upgrade (migration) and the app proper.
  /// Call again after the migration has run.
  Future<void> recheckSchool() async {
    final refs = tenant;
    if (refs == null) return;
    if (role == UserRole.parentStudent) {
      _set(AuthStatus.parentPortal);
      return;
    }
    try {
      // once() (not get()) so the copy saved on the phone answers offline.
      final profile = (await refs.profile.once()).snapshot;
      LoginTimer.mark('school profile loaded, opening the school');
      _set(profile.exists ? AuthStatus.ready : AuthStatus.upgradeRequired);
    } catch (e) {
      LoginTimer.mark('school profile read FAILED: $e');
      _set(AuthStatus.noAccess);
    }
  }

  void _set(AuthStatus status) {
    _status = status;
    _rememberSession(status);
    _keepSchoolSynced(status);
    notifyListeners();
  }

  /// Paths kept permanently synced on this phone, by path.
  final _syncedRefs = <String, DatabaseReference>{};

  /// Phones only: while the user is in their school, keep a full, fresh copy
  /// of the lists the app's screens use on disk (`keepSynced`), so every
  /// screen works offline — even one never opened before. Released when the
  /// user signs out or loses the school.
  void _keepSchoolSynced(AuthStatus status) {
    if (kIsWeb) return;
    final user = _appUser;
    final refs = tenant;
    final List<DatabaseReference> wanted;
    switch (status) {
      case AuthStatus.ready:
      case AuthStatus.parentPortal:
        if (user == null || refs == null) return;
        wanted = [
          _db.ref('users/${user.uid}'),
          refs.members.child(user.uid),
          refs.profile,
          refs.subscription,
          if (role.canManageStudents) ...[
            refs.classes,
            refs.students,
            refs.studentPrivate,
            refs.teachers,
            refs.school.child('index'),
            refs.announcements,
            refs.events,
            refs.documents,
          ],
          // Private teacher details and promotion history are admin-only
          // (see database.rules.json).
          if (role.canManageSchool) ...[refs.teacherPrivate, refs.promotions],
        ];
      case AuthStatus.signedOut:
      case AuthStatus.needsOnboarding:
      case AuthStatus.noAccess:
        wanted = const [];
      case AuthStatus.unknown:
      case AuthStatus.needsConnection:
      case AuthStatus.upgradeRequired:
        return;
    }

    final keep = {for (final r in wanted) r.path: r};
    for (final path in _syncedRefs.keys.toList()) {
      if (keep.containsKey(path)) continue;
      _setKeepSynced(_syncedRefs.remove(path)!, false);
    }
    for (final entry in keep.entries) {
      if (_syncedRefs.containsKey(entry.key)) continue;
      _syncedRefs[entry.key] = entry.value;
      _setKeepSynced(entry.value, true);
    }
  }

  void _setKeepSynced(DatabaseReference ref, bool on) {
    ref.keepSynced(on).catchError(
        (Object e) => debugPrint('keepSynced(${ref.path}, $on) failed: $e'));
  }

  /// Keeps [SessionCache] in step with what the database last confirmed:
  /// saved when the user reaches the app, forgotten when they lose it.
  void _rememberSession(AuthStatus status) {
    final session = _session;
    if (session == null) return;
    final user = _appUser;
    switch (status) {
      case AuthStatus.ready:
      case AuthStatus.parentPortal:
        if (user != null && user.hasSchool) session.save(user, status.name);
      case AuthStatus.signedOut:
      case AuthStatus.needsOnboarding:
      case AuthStatus.noAccess:
        session.clear();
      case AuthStatus.unknown:
      case AuthStatus.needsConnection:
      case AuthStatus.upgradeRequired:
        break;
    }
  }

  // --- Actions -------------------------------------------------------------

  Future<User> signIn({required String email, required String password}) async {
    _errorMessage = null;
    try {
      return await _auth.signIn(email: email, password: password);
    } on AuthException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
      rethrow;
    }
  }

  /// Registers the admin account and provisions a fresh isolated school in one
  /// flow. The `users/{uid}` write inside [SchoolService.createSchool] flips
  /// [status] to [AuthStatus.ready]. Returns the new school id.
  Future<String> onboardNewSchool({
    required String adminName,
    required String adminEmail,
    required String adminPassword,
    required SchoolMeta meta,
  }) async {
    _errorMessage = null;
    try {
      final existing = _auth.currentUser;
      final user = existing ??
          await _auth.register(
            email: adminEmail,
            password: adminPassword,
            displayName: adminName,
          );
      return await _schools.createSchool(
        ownerUid: user.uid,
        // When resuming after a failed earlier attempt the admin form is hidden,
        // so fall back to the signed-in account's own details.
        ownerName: adminName.isNotEmpty ? adminName : (user.displayName ?? ''),
        ownerEmail: user.email ?? adminEmail,
        meta: meta,
      );
    } on AuthException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
      rethrow;
    }
  }

  /// Creates an account (used when joining with an invite code). The account
  /// has no school until the join update is written.
  Future<User> register({
    required String name,
    required String email,
    required String password,
  }) async {
    _errorMessage = null;
    try {
      return await _auth.register(
          email: email, password: password, displayName: name);
    } on AuthException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> sendPasswordReset(String email) => _auth.sendPasswordReset(email);

  /// Signs out and leaves nothing of this account on the phone's to-do list:
  /// stops keeping the school synced, drops database changes not yet sent,
  /// queued photos and event posts, and forgets the saved session — so the
  /// next account starts clean and needs a fresh online sign-in. Buttons
  /// call this through `confirmSignOut`, which warns about unsynced changes.
  Future<void> signOut() async {
    // While still signed in, so releasing the paths isn't refused.
    _keepSchoolSynced(AuthStatus.signedOut);
    if (!kIsWeb) {
      try {
        await _db.purgeOutstandingWrites();
      } catch (e) {
        debugPrint('Could not drop unsent changes: $e');
      }
      PendingWrites.instance.reset();
      try {
        await UploadQueue.instance?.clearAll();
        await PendingEventStore.instance?.clearAll();
      } catch (e) {
        debugPrint('Could not clear queued uploads: $e');
      }
    }
    await _session?.clear();
    await _auth.signOut();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _userDocSub?.cancel();
    _memberSub?.cancel();
    super.dispose();
  }
}
