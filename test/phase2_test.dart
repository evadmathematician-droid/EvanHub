// Phase 2: invite codes. The format must match database.rules.json
// (^[A-HJ-NP-Z2-9]{8}$).

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:evangelistglobal/core/invite_code.dart';
import 'package:evangelistglobal/models/invite.dart';
import 'package:evangelistglobal/models/user_role.dart';

void main() {
  final rulesPattern = RegExp(r'^[A-HJ-NP-Z2-9]{8}$');

  group('InviteCode', () {
    test('alphabet has 32 unambiguous characters', () {
      expect(InviteCode.alphabet.length, 32);
      for (final c in ['0', 'O', '1', 'I']) {
        expect(InviteCode.alphabet.contains(c), isFalse, reason: c);
      }
    });

    test('generated codes match the rules pattern', () {
      final r = Random(42);
      for (var i = 0; i < 500; i++) {
        expect(rulesPattern.hasMatch(InviteCode.generate(r)), isTrue);
      }
    });

    test('normalize accepts any typing style', () {
      expect(InviteCode.normalize('k7pm-x3qd'), 'K7PMX3QD');
      expect(InviteCode.normalize(' K7PM X3QD '), 'K7PMX3QD');
      expect(InviteCode.normalize('K7PMX3QD'), 'K7PMX3QD');
    });

    test('normalize rejects wrong length and look-alike characters', () {
      expect(InviteCode.normalize('K7PMX3Q'), isNull);
      expect(InviteCode.normalize('K7PMX3QD9'), isNull);
      expect(InviteCode.normalize('K0PMX3QD'), isNull); // zero
      expect(InviteCode.normalize('KOPMX3QD'), isNull); // letter O
      expect(InviteCode.normalize('K1PMX3QD'), isNull);
      expect(InviteCode.normalize('KIPMX3QD'), isNull);
    });

    test('format shows XXXX-XXXX', () {
      expect(InviteCode.format('K7PMX3QD'), 'K7PM-X3QD');
    });

    test('formatter upper-cases and inserts the dash', () {
      final out = InviteCodeFormatter().formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: 'k7pmx3qdzz'),
      );
      expect(out.text, 'K7PM-X3QD');
    });
  });

  group('Invite', () {
    final future = DateTime.now().add(const Duration(days: 3));

    Invite parse(Map<String, dynamic> extra) => Invite.fromMap('K7PMX3QD', {
          'schoolId': 's1',
          'schoolName': 'Evangelist Primary',
          'role': 'parentStudent',
          'createdBy': 'admin',
          'createdAt': 1000,
          'expiresAt': future.millisecondsSinceEpoch,
          ...extra,
        });

    test('reads role and linked students', () {
      final i = parse({
        'linkedStudentIds': {'st1': true, 'st2': true},
      });
      expect(i.role, UserRole.parentStudent);
      expect(i.linkedStudentIds, {'st1', 'st2'});
      expect(i.isPending, isTrue);
    });

    test('used and expired codes are not pending', () {
      expect(parse({'usedBy': 'someone'}).isPending, isFalse);
      expect(parse({'expiresAt': 1}).isExpired, isTrue);
    });
  });
}
