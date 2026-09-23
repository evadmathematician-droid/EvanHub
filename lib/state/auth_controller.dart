import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../core/rtdb.dart';
import '../core/tenant/tenant_refs.dart';
import '../models/app_user.dart';
import '../models/school.dart';
import '../models/user_role.dart';
import '../services/auth_service.dart';
import '../services/school_service.dart';

enum AuthStatus {
  /// Still resolving the initial Firebase auth state.
  unknown,

  /// No user signed in.
  signedOut,

  /// Signed in, but the account is not linked to any school yet.
  needsOnboarding,

  /// Signed in and bound to a school — the app proper is usable.
  ready,
}

/// App-wide auth + tenant state. Drives the router via [ChangeNotifier].
class AuthController extends ChangeNotifier {
  AuthController({
    AuthService? authService,
    SchoolService? schoolService,
    FirebaseDatabase? database,
  })  : _auth = authService ?? AuthService(),
        _schools = schoolService ?? SchoolService(),
        _db = database ?? FirebaseDatabase.instance {
    _authSub = _auth.authStateChanges().listen(_onAuthChanged);
  }

  final AuthService _auth;
  final SchoolService _schools;
  final FirebaseDatabase _db;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<DatabaseEvent>? _userDocSub;

  AuthStatus _status = AuthStatus.unknown;
  AuthStatus get status => _status;

  User? _firebaseUser;
  User? get firebaseUser => _firebaseUser;

  AppUser? _appUser;
  AppUser? get appUser => _appUser;

  String? get schoolId => _appUser?.schoolId;
  UserRole get role => _appUser?.role ?? UserRole.parentStudent;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// Tenant-scoped database paths for the current school, or null when the user
  /// has no school.
  TenantRefs? get tenant =>
      schoolId == null ? null : TenantRefs(schoolId!, database: _db);

  Future<void> _onAuthChanged(User? user) async {
    await _userDocSub?.cancel();
    _userDocSub = null;
    _firebaseUser = user;

    if (user == null) {
      _appUser = null;
      _set(AuthStatus.signedOut);
      return;
    }

    _userDocSub = _db.ref('users/${user.uid}').onValue.listen(
      (event) {
        final data = event.snapshot.exists ? asMap(event.snapshot.value) : null;
        if (data == null || data['schoolId'] == null) {
          _appUser = AppUser(
            uid: user.uid,
            email: user.email ?? '',
            displayName: user.displayName ?? '',
          );
          _set(AuthStatus.needsOnboarding);
        } else {
          _appUser = AppUser.fromMap(user.uid, data);
          _set(AuthStatus.ready);
        }
      },
      onError: (_) {
        _appUser = AppUser(uid: user.uid, email: user.email ?? '');
        _set(AuthStatus.needsOnboarding);
      },
    );
  }

  void _set(AuthStatus status) {
    _status = status;
    notifyListeners();
  }

  // --- Actions -------------------------------------------------------------

  Future<void> signIn({required String email, required String password}) async {
    _errorMessage = null;
    try {
      await _auth.signIn(email: email, password: password);
    } on AuthException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
      rethrow;
    }
  }

  /// Registers the admin account and provisions a fresh isolated school in one
  /// flow. The `users/{uid}` write inside [SchoolService.createSchool] flips
  /// [status] to [AuthStatus.ready].
  Future<School> onboardNewSchool({
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

  Future<void> sendPasswordReset(String email) => _auth.sendPasswordReset(email);

  Future<void> signOut() => _auth.signOut();

  @override
  void dispose() {
    _authSub?.cancel();
    _userDocSub?.cancel();
    super.dispose();
  }
}
