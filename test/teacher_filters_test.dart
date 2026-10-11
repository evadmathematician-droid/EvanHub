import 'package:flutter_test/flutter_test.dart';

import 'package:evangelistglobal/features/teachers/teacher_filters.dart';
import 'package:evangelistglobal/models/teacher.dart';

Teacher _t(
  String id,
  String first,
  String last, {
  String rank = '',
  String status = TeacherStatus.active,
  String nin = '',
  int? created,
}) =>
    Teacher(
      id: id,
      firstName: first,
      lastName: last,
      rank: rank,
      status: status,
      nin: nin,
      createdAt:
          created == null ? null : DateTime.fromMillisecondsSinceEpoch(created),
    );

void main() {
  final teachers = [
    _t('a', 'Mary', 'Kamara',
        rank: 'Principal', nin: 'ZZ111111', created: 100),
    _t('b', 'John', 'Bangura',
        rank: 'Teacher', status: TeacherStatus.past, created: 300),
    _t('c', 'Fatu', 'Sesay', nin: 'AA222222', created: 200),
    _t('d', 'Abu', 'Conteh', rank: 'Head of Exams', nin: 'MM333333'),
  ];
  final f = TeacherFilters(teachers);

  group('Teacher model', () {
    test('missing status is Active, missing rank is Unassigned', () {
      final t = Teacher.fromMap('x', {'firstName': 'A', 'lastName': 'B'});
      expect(t.isActive, isTrue);
      expect(t.statusLabel, 'Active');
      expect(t.rankLabel, 'Unassigned');
    });

    test('rank and status are written to and read back from the record', () {
      final t = _t('x', 'A', 'B', rank: 'Senior Teacher', status: 'past');
      final map = t.toPublicMap();
      expect(map['rank'], 'Senior Teacher');
      expect(map['status'], TeacherStatus.past);
      final back = Teacher.fromMap('x', {...map, 'createdAt': 1});
      expect(back.rank, 'Senior Teacher');
      expect(back.statusLabel, 'Past');
    });
  });

  group('TeacherFilters', () {
    test('totals', () {
      expect(f.total, 4);
      expect(f.activeCount, 3);
      expect(f.pastCount, 1);
    });

    test('rank options: standard list, extra ranks, then Unassigned', () {
      expect(f.rankOptions, [
        ...TeacherRank.options,
        'Head of Exams',
        TeacherRank.unassigned,
      ]);
    });

    test('search matches name, NIN and id, ignoring case', () {
      expect(f.apply(search: 'kamara').map((t) => t.id), ['a']);
      expect(f.apply(search: 'aa22').map((t) => t.id), ['c']);
      expect(f.apply(search: 'D').map((t) => t.id), contains('d'));
    });

    test('filters combine', () {
      expect(
          f.apply(status: TeacherStatusFilter.active).map((t) => t.id).toSet(),
          {'a', 'c', 'd'});
      expect(f.apply(rank: TeacherRank.unassigned).map((t) => t.id), ['c']);
      expect(
          f.apply(status: TeacherStatusFilter.past, rank: 'Principal'),
          isEmpty);
    });

    test('sorts', () {
      List<String> ids(TeacherSort s) =>
          f.apply(sort: s).map((t) => t.id).toList();
      expect(ids(TeacherSort.nameAz), ['d', 'c', 'b', 'a']);
      expect(ids(TeacherSort.nameZa), ['a', 'b', 'c', 'd']);
      expect(ids(TeacherSort.rank), ['a', 'b', 'd', 'c']);
      // No NIN last.
      expect(ids(TeacherSort.nin), ['c', 'd', 'a', 'b']);
      // No date last.
      expect(ids(TeacherSort.newest), ['b', 'c', 'a', 'd']);
    });
  });
}
