import 'package:flutter_test/flutter_test.dart';

import 'package:evangelistglobal/core/phone.dart';
import 'package:evangelistglobal/models/school.dart';

void main() {
  test('Sierra Leone formats become +232…', () {
    for (final input in [
      '079150079',
      '079 150 079',
      '079-150-079',
      '+23279150079',
      '23279150079',
      '0023279150079',
      '79150079',
    ]) {
      expect(normalizePhone(input), '+23279150079', reason: input);
    }
  });

  test('other countries with + are kept; junk is refused', () {
    expect(normalizePhone('+44 7700 900123'), '+447700900123');
    expect(normalizePhone('12'), isNull);
    expect(normalizePhone('abc'), isNull);
    expect(normalizePhone(''), isNull);
  });

  test('phoneProblem', () {
    expect(phoneProblem('', required: true), 'Required');
    expect(phoneProblem(''), isNull);
    expect(phoneProblem('079 150 079', required: true), isNull);
    expect(phoneProblem('12'), isNotNull);
  });

  test('SchoolMeta: missing lookupEnabled counts as approved', () {
    expect(SchoolMeta.fromMap({'name': 'A'}).lookupApproved, isTrue);
    expect(SchoolMeta.fromMap({'name': 'A', 'lookupEnabled': false})
        .lookupApproved, isFalse);
    final m = const SchoolMeta(name: 'A', adminPhone: '079 150 079').toMap();
    expect(m['adminPhone'], '079 150 079');
    expect(m['adminPhoneIntl'], '+23279150079');
  });
}
