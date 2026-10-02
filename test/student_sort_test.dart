import 'package:evangelistglobal/features/students/student_filters.dart';
import 'package:evangelistglobal/models/school_class.dart';
import 'package:evangelistglobal/models/school_level.dart';
import 'package:evangelistglobal/models/student.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final classes = [
    const SchoolClass(id: 'p4', name: 'Class 4', level: SchoolLevel.primary),
    const SchoolClass(id: 'p1', name: 'Class 1', level: SchoolLevel.primary),
    const SchoolClass(id: 'j2', name: 'JSS 2', level: SchoolLevel.secondary),
  ];

  final ama = Student(
    id: 'a',
    firstName: 'Ama',
    lastName: 'Kamara',
    classId: 'j2',
    admissionNo: 'EG/10',
    createdAt: DateTime(2026, 1, 5),
  );
  final ben = Student(
    id: 'b',
    firstName: 'Ben',
    lastName: 'Bangura',
    classId: 'p4',
    admissionNo: 'EG/2',
    createdAt: DateTime(2026, 3, 1),
  );
  const cole = Student(
    id: 'c',
    firstName: 'Cole',
    lastName: 'Conteh',
    classId: 'p1',
  );
  const dan = Student(
    id: 'd',
    firstName: 'Dan',
    lastName: 'bangura',
    classId: 'gone',
    admissionNo: 'EG/9',
  );

  final f = StudentFilters(classes, [ama, ben, cole, dan]);
  List<String> order(StudentSort s) =>
      f.sorted(f.students, s).map((s) => s.firstName).toList();

  test('name: last name, then first name, ignoring case', () {
    expect(order(StudentSort.name), ['Ben', 'Dan', 'Cole', 'Ama']);
  });

  test('id: numbers by value, missing IDs last', () {
    expect(order(StudentSort.id), ['Ben', 'Dan', 'Ama', 'Cole']);
  });

  test('class: ladder order, unknown class last', () {
    expect(order(StudentSort.className), ['Cole', 'Ben', 'Ama', 'Dan']);
  });

  test('date of registration: newest first, missing dates last by name', () {
    expect(order(StudentSort.registered), ['Ben', 'Ama', 'Dan', 'Cole']);
  });

  test('sorting returns a new list', () {
    final input = [ama, ben];
    f.sorted(input, StudentSort.name);
    expect(input, [ama, ben]);
  });

  test('compareNatural', () {
    expect(compareNatural('EG/2', 'EG/10'), lessThan(0));
    expect(compareNatural('a9', 'A10'), lessThan(0));
    expect(compareNatural('abc', 'abc'), 0);
  });
}
