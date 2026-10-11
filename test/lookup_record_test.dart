import 'package:flutter_test/flutter_test.dart';

import 'package:evangelistglobal/models/lookup_record.dart';
import 'package:evangelistglobal/models/student.dart';
import 'package:evangelistglobal/models/teacher.dart';

void main() {
  group('lookupKey', () {
    test('trims, upper-cases, replaces illegal characters, adds the type', () {
      expect(lookupKey(LookupType.student, '  egs/2024.01 '),
          'student_EGS_2024_01');
      expect(lookupKey(LookupType.student, r'a#b$c[d]'), 'student_A_B_C_D_');
      expect(lookupKey(LookupType.teacher, 'ab12cd34'), 'teacher_AB12CD34');
      expect(lookupKey(LookupType.student, '   '), '');
    });
  });

  group('published fields', () {
    const student = Student(
      id: 's1',
      firstName: 'Mary',
      lastName: 'Kamara',
      admissionNo: 'EGS-001',
      guardianPhone: '076000000',
      guardianName: 'Mr Kamara',
      address: 'Freetown',
      npseId: '12345',
      npseYear: '2022',
    );

    test('a student record never holds guardian phone or date of birth', () {
      final f = LookupRecord.studentFields(student, className: 'JSS 1');
      expect(f.keys, isNot(contains('guardianPhone')));
      expect(f.keys, isNot(contains('guardianName')));
      expect(f.keys, isNot(contains('dob')));
      expect(f['id'], 'EGS-001');
      expect(f['className'], 'JSS 1');
      // Without history the saved history is left alone.
      expect(f.keys, isNot(contains('history')));
    });

    test('empty values are removed', () {
      final f = LookupRecord.clean(
          LookupRecord.studentFields(student, className: '', history: []));
      expect(f['className'], isNull);
      expect(f.containsKey('className'), isTrue);
      expect(f['history'], isNull);
      expect(f['address'], 'Freetown');
    });

    test('a teacher record holds rank and status, never private details', () {
      const t = Teacher(
        id: 't1',
        firstName: 'John',
        lastName: 'Bangura',
        nin: 'AB12CD34',
        rank: 'Principal',
        status: TeacherStatus.past,
        phone: '077',
        pincode: '123456',
      );
      final f = LookupRecord.teacherFields(t);
      expect(f['id'], 'AB12CD34');
      expect(f['rank'], 'Principal');
      expect(f['status'], TeacherStatus.past);
      expect(f.keys, isNot(contains('phone')));
      expect(f.keys, isNot(contains('pincode')));
    });

    test('reads back from the database map', () {
      final r = LookupRecord.fromMap({
        'type': 'student',
        'id': 'EGS-001',
        'firstName': 'Mary',
        'lastName': 'Kamara',
        'status': 'active',
        'history': {
          'p001': {'fromClass': 'JSS 1', 'toClass': 'JSS 1', 'date': 2},
          'p000': {'fromClass': 'Class 6', 'toClass': 'JSS 1', 'date': 1},
        },
      });
      expect(r.fullName, 'Mary Kamara');
      expect(r.history.first.fromClass, 'Class 6');
      expect(r.history.last.repeated, isTrue);
      expect(r.promotionStatus(), 'Repeat');
    });
  });

  group('promotionStatus', () {
    final now = DateTime(2026, 10, 11);
    LookupRecord rec({String status = 'active', DateTime? promoted, DateTime? reg}) =>
        LookupRecord(
          type: LookupType.student,
          id: '1',
          firstName: 'A',
          lastName: 'B',
          status: status,
          lastPromotedAt: promoted,
          registeredAt: reg,
        );

    test('graduated, repeat by time, promoted, not yet promoted', () {
      expect(rec(status: 'graduated').promotionStatus(now), 'Completed school');
      expect(rec(promoted: DateTime(2025, 9, 1)).promotionStatus(now), 'Repeat');
      expect(rec(promoted: DateTime(2026, 9, 1)).promotionStatus(now), 'Promoted');
      expect(rec(reg: DateTime(2026, 5, 1)).promotionStatus(now),
          'Not yet promoted');
    });
  });

  group('results and fees', () {
    test('ordinals', () {
      expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 112].map(ordinal).toList(),
          ['1st', '2nd', '3rd', '4th', '11th', '12th', '13th', '21st', '22nd', '112th']);
    });

    test('position text', () {
      expect(LookupResults({'position': 12, 'classSize': 45}).positionText,
          '12th out of 45');
      expect(LookupResults({'position': 3}).positionText, '3rd');
      expect(LookupResults({}).positionText, isNull);
    });

    test('automatic guidance by thirds and average', () {
      String? g(Map<String, dynamic> m) => LookupResults(m).automaticGuidance;
      expect(g({'position': 1, 'classSize': 30}), startsWith('Good'));
      expect(g({'position': 15, 'classSize': 30}), startsWith('Fair'));
      expect(g({'position': 25, 'classSize': 30}), startsWith('Performance needs'));
      // An average below 50% is "needs improvement" whatever the position.
      expect(g({'position': 1, 'classSize': 30, 'average': 45}),
          startsWith('Performance needs'));
      expect(g({}), isNull);
    });

    test('fees: balance and payment status', () {
      final part = LookupFees({'total': 500000, 'paid': 200000});
      expect(part.balance, 300000);
      expect(part.paymentStatus, 'Part payment');
      expect(LookupFees({'total': 100, 'paid': 100}).paymentStatus,
          'Paid in full');
      expect(LookupFees({'total': 100, 'paid': 0}).paymentStatus, 'Not paid');
      expect(LookupFees({}).hasAny, isFalse);
    });
  });
}
