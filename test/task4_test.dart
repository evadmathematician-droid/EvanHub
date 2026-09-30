// Task 4: Title Case person names and the teacher middle name.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evangelistglobal/core/person_name.dart';
import 'package:evangelistglobal/models/teacher.dart';

void main() {
  group('titleCaseName', () {
    test('capitalises each word and tidies spaces', () {
      expect(titleCaseName('aBU bAKARR  kamara'), 'Abu Bakarr Kamara');
      expect(titleCaseName('  mohamed   '), 'Mohamed');
      expect(titleCaseName('FATMATA\tsesay'), 'Fatmata Sesay');
      expect(titleCaseName(''), '');
      expect(titleCaseName('   '), '');
    });

    test('capitalises each part of a hyphenated name', () {
      expect(titleCaseName('sesay-KAMARA'), 'Sesay-Kamara');
    });

    test('isTitleCaseName', () {
      expect(isTitleCaseName('Abu Bakarr Kamara'), isTrue);
      expect(isTitleCaseName(''), isTrue);
      expect(isTitleCaseName('abu'), isFalse);
      expect(isTitleCaseName('Abu  Kamara'), isFalse);
      expect(isTitleCaseName('Abu '), isFalse);
      expect(isTitleCaseName('McCarthy'), isFalse);
    });
  });

  group('NameCaseFormatter', () {
    TextEditingValue type(String text) => const NameCaseFormatter()
        .formatEditUpdate(
          TextEditingValue.empty,
          TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          ),
        );

    test('shows Title Case while typing, keeping spaces and cursor', () {
      final v = type('aBU bAKARR ');
      expect(v.text, 'Abu Bakarr ');
      expect(v.selection.baseOffset, 'aBU bAKARR '.length);
    });
  });

  group('middleNameProblem', () {
    test('allows empty, one or two words', () {
      expect(middleNameProblem(''), isNull);
      expect(middleNameProblem(null), isNull);
      expect(middleNameProblem('Abu'), isNull);
      expect(middleNameProblem(' Abu  Bakarr '), isNull);
    });

    test('rejects three or more words', () {
      expect(middleNameProblem('Abu Bakarr Musa'), isNotNull);
    });
  });

  group('Teacher middle name', () {
    test('is stored publicly and shown in the full name', () {
      const t = Teacher(
          id: 't', firstName: 'Abu', middleName: 'Bakarr', lastName: 'Kamara');
      expect(t.fullName, 'Abu Bakarr Kamara');
      expect(t.toPublicMap()['middleName'], 'Bakarr');
      final back = Teacher.fromMap('t', t.toPublicMap());
      expect(back.middleName, 'Bakarr');
      expect(back.copyWith(firstName: 'Musa').middleName, 'Bakarr');
    });

    test('older records without one still load', () {
      final t = Teacher.fromMap('t', {'firstName': 'Abu', 'lastName': 'Kamara'});
      expect(t.middleName, '');
      expect(t.fullName, 'Abu Kamara');
    });
  });
}
