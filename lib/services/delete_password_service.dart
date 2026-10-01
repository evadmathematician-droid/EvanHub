import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_database/firebase_database.dart';

import '../core/rtdb.dart';
import '../core/tenant/tenant_refs.dart';

/// A school's delete password as stored: a random salt and
/// SHA-256(salt + ':' + password) in hex. The plain password is never stored.
class DeletePasswordHash {
  final String hash;
  final String salt;

  const DeletePasswordHash({required this.hash, required this.salt});

  /// Hashes [password] with a fresh random salt.
  factory DeletePasswordHash.create(String password) {
    final random = Random.secure();
    final salt = base64UrlEncode(
        List<int>.generate(16, (_) => random.nextInt(256)));
    return DeletePasswordHash(hash: hashOf(password, salt), salt: salt);
  }

  /// Null when the stored record is incomplete.
  static DeletePasswordHash? fromMap(Map<String, dynamic> data) {
    final hash = data['hash'];
    final salt = data['salt'];
    if (hash is! String || salt is! String || hash.isEmpty || salt.isEmpty) {
      return null;
    }
    return DeletePasswordHash(hash: hash, salt: salt);
  }

  Map<String, dynamic> toMap() =>
      {'hash': hash, 'salt': salt, 'algorithm': 'sha256'};

  static String hashOf(String password, String salt) =>
      sha256.convert(utf8.encode('$salt:$password')).toString();

  bool matches(String password) {
    final candidate = hashOf(password, salt);
    // Constant-time compare.
    if (candidate.length != hash.length) return false;
    var diff = 0;
    for (var i = 0; i < hash.length; i++) {
      diff |= candidate.codeUnitAt(i) ^ hash.codeUnitAt(i);
    }
    return diff == 0;
  }
}

/// Reads and creates `schools/{schoolId}/settings/deletePassword`. There is
/// deliberately no change or reset: the developer resets it by deleting the
/// node in the Firebase console.
class DeletePasswordService {
  DeletePasswordService(this._refs);

  final TenantRefs _refs;

  static const _timeout = Duration(seconds: 10);

  /// The school's password, or null when none has been created yet. Throws
  /// when the database can't be reached.
  Future<DeletePasswordHash?> load() async {
    final snap = await _refs.deletePassword.get().timeout(_timeout);
    return snap.exists ? DeletePasswordHash.fromMap(asMap(snap.value)) : null;
  }

  /// Saves [password] only if the school has none yet (a transaction, so two
  /// phones can't both create one). Returns the stored hash, or null when
  /// another device created a password first.
  Future<DeletePasswordHash?> create(String password,
      {required String uid}) async {
    final hash = DeletePasswordHash.create(password);
    final data = {
      ...hash.toMap(),
      'createdBy': uid,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };
    final result = await _refs.deletePassword
        .runTransaction((current) =>
            current == null ? Transaction.success(data) : Transaction.abort())
        .timeout(_timeout);
    return result.committed ? hash : null;
  }
}
