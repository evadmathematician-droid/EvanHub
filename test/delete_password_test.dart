import 'package:flutter_test/flutter_test.dart';

import 'package:evangelistglobal/services/delete_guard_store.dart';
import 'package:evangelistglobal/services/delete_password_service.dart';

void main() {
  group('DeletePasswordHash', () {
    test('matches only the original password', () {
      final hash = DeletePasswordHash.create('1234');
      expect(hash.matches('1234'), isTrue);
      expect(hash.matches('12345'), isFalse);
      expect(hash.matches(''), isFalse);
    });

    test('stores a 64-char hex hash and a random salt, never the password',
        () {
      final a = DeletePasswordHash.create('secret');
      final b = DeletePasswordHash.create('secret');
      expect(a.hash, hasLength(64));
      expect(a.salt, isNot(b.salt));
      expect(a.hash, isNot(b.hash));
      expect(a.toMap().values, isNot(contains('secret')));
    });

    test('round-trips through its stored map', () {
      final a = DeletePasswordHash.create('abcd');
      final b = DeletePasswordHash.fromMap(a.toMap())!;
      expect(b.matches('abcd'), isTrue);
      expect(DeletePasswordHash.fromMap({'hash': ''}), isNull);
    });
  });

  group('DeleteGuardStore (in memory)', () {
    final guard = DeleteGuardStore.instance;

    test('locks after 5 wrong attempts, per school', () async {
      await guard.clearFailures('s1');
      for (var left = 4; left >= 1; left--) {
        expect(await guard.recordFailure('s1'), left);
        expect(guard.lockRemaining('s1'), isNull);
      }
      expect(await guard.recordFailure('s1'), 0);
      expect(guard.lockRemaining('s1'), isNotNull);
      expect(guard.lockRemaining('s2'), isNull);
      await guard.clearFailures('s1');
      expect(guard.lockRemaining('s1'), isNull);
    });
  });
}
