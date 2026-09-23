// Unit tests for the pieces that do not require a live Firebase connection.
// Firestore-backed flows are exercised manually per SETUP.md and, later, with
// the Firebase emulator suite.

import 'package:flutter_test/flutter_test.dart';

import 'package:evangelistglobal/app/routes.dart';
import 'package:evangelistglobal/models/announcement.dart';
import 'package:evangelistglobal/models/school.dart';
import 'package:evangelistglobal/models/user_role.dart';

void main() {
  group('UserRole', () {
    test('round-trips through its wire value', () {
      for (final role in UserRole.values) {
        expect(UserRole.fromWire(role.wire), role);
      }
    });

    test('unknown wire value falls back to parentStudent', () {
      expect(UserRole.fromWire('nonsense'), UserRole.parentStudent);
      expect(UserRole.fromWire(null), UserRole.parentStudent);
    });

    test('permission helpers', () {
      expect(UserRole.schoolAdmin.canManageSchool, isTrue);
      expect(UserRole.teacher.canManageSchool, isFalse);
      expect(UserRole.teacher.canManageStudents, isTrue);
      expect(UserRole.parentStudent.canManageStudents, isFalse);
      expect(UserRole.superAdmin.canManageSchool, isTrue);
    });
  });

  group('SchoolMeta', () {
    test('toMap / fromMap round-trip', () {
      const meta = SchoolMeta(
        name: 'Evangelist Primary',
        address: '12 Church Rd',
        phone: '+250700000000',
        email: 'office@ep.example',
      );
      final restored = SchoolMeta.fromMap(meta.toMap());
      expect(restored.name, meta.name);
      expect(restored.address, meta.address);
      expect(restored.phone, meta.phone);
      expect(restored.email, meta.email);
      expect(restored.logoUrl, isNull);
    });

    test('copyWith overrides only the given field', () {
      const meta = SchoolMeta(name: 'A');
      expect(meta.copyWith(name: 'B').name, 'B');
      expect(meta.copyWith(phone: '1').name, 'A');
    });
  });

  group('Subscription', () {
    test('defaults to a free trial', () {
      const sub = Subscription();
      expect(sub.plan, 'free');
      expect(sub.status, 'trialing');
      expect(Subscription.fromMap(sub.toMap()).plan, 'free');
    });
  });

  group('Announcement', () {
    test('school-wide audience is the default', () {
      const a = Announcement(id: '1', title: 't', body: 'b');
      expect(a.isSchoolWide, isTrue);
    });

    test('a class id audience is not school-wide', () {
      const a = Announcement(
          id: '1', title: 't', body: 'b', audience: 'class_123');
      expect(a.isSchoolWide, isFalse);
    });
  });

  group('Routes', () {
    test('parameterised paths', () {
      expect(Routes.studentEdit('abc'), '/students/abc/edit');
      expect(Routes.teacherEdit('xy'), '/teachers/xy/edit');
      expect(Routes.classEdit('9'), '/classes/9/edit');
    });
  });
}
