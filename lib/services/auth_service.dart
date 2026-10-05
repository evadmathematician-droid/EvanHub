import 'package:firebase_auth/firebase_auth.dart';

/// Thin wrapper over [FirebaseAuth]. No credentials are stored in the app — every
/// sign-in goes through Firebase Authentication (Email/Password provider).
class AuthService {
  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<User> signIn({required String email, required String password}) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return cred.user!;
    } on FirebaseAuthException catch (e) {
      throw AuthException.from(e);
    }
  }

  Future<User> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      if (displayName != null && displayName.isNotEmpty) {
        await cred.user!.updateDisplayName(displayName);
      }
      return cred.user!;
    } on FirebaseAuthException catch (e) {
      throw AuthException.from(e);
    }
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw AuthException.from(e);
    }
  }

  Future<void> signOut() => _auth.signOut();
}

/// User-presentable auth error.
class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  factory AuthException.from(FirebaseAuthException e) {
    final message = switch (e.code) {
      'invalid-email' => 'That email address is not valid.',
      'user-disabled' => 'This account has been disabled.',
      'user-not-found' ||
      'wrong-password' ||
      'invalid-credential' =>
        'Incorrect email or password.',
      'email-already-in-use' => 'An account already exists for that email.',
      'weak-password' => 'Password is too weak — use at least 6 characters.',
      'network-request-failed' =>
        'No internet connection. First login (or creating an account) needs '
            'internet. After that you can use the app offline.',
      'too-many-requests' => 'Too many attempts. Try again later.',
      _ => e.message ?? 'Authentication failed (${e.code}).',
    };
    return AuthException(message);
  }

  @override
  String toString() => message;
}
