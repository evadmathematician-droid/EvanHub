import 'dart:io';
import 'dart:typed_data';

import 'package:evangelistglobal/features/report_cards/report_card_data.dart';
import 'package:evangelistglobal/features/report_cards/report_card_pdf.dart';
import 'package:evangelistglobal/models/school_class.dart';
import 'package:evangelistglobal/models/school_level.dart';
import 'package:evangelistglobal/models/student.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pages in a saved PDF: counts the `/Type /Page` objects.
int pageCount(Uint8List pdf) =>
    RegExp(r'/Type\s*/Page(?!s)').allMatches(String.fromCharCodes(pdf)).length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('normalizeClassName', () {
    const jss2 = ReportForm(ReportLevel.jss, 2);
    const ss2 = ReportForm(ReportLevel.ss, 2);

    test('JSS spellings', () {
      for (final n in [
        'JSS 2', 'JSS2', 'Jss-2', 'jss 2', 'JSS II', 'J.S.S. 2', 'JSS 2 A',
        'JSS2B', 'JSS-II', 'JHS 2', ' jss_2 ',
      ]) {
        expect(normalizeClassName(n), jss2, reason: n);
      }
    });

    test('SS spellings', () {
      for (final n in ['SSS 2', 'SS2', 'SS II', 'S.S.S 2', 'sss-2', 'SHS 2']) {
        expect(normalizeClassName(n), ss2, reason: n);
      }
    });

    test('other classes are not forms', () {
      for (final n in ['Class 2', 'Pre 1', 'JSS', 'JSS 22', 'JSS IIX', '']) {
        expect(normalizeClassName(n), isNull, reason: n);
      }
      expect(normalizeClassName('JSS III')?.number, 3);
      expect(normalizeClassName('SS 1')?.label, 'SS-1');
    });
  });

  group('school details', () {
    test('town and district from the address', () {
      final s = ReportCardSchool.fromProfile({
        'name': 'Bubuya Community Junior Secondary School',
        'address': 'Tonko – Limba, Kambia District',
        'headName': 'Mr. Mohamed Bangura',
      });
      expect(s.town, 'Tonko – Limba');
      expect(s.district, 'Kambia District');
      expect(s.nameWithoutLevel, 'Bubuya Community');
      expect(s.principal, 'Mr. Mohamed Bangura');
      expect(s.motto, '');
      expect(s.founded, '');
    });

    test('explicit fields win; missing profile is blank', () {
      final s = ReportCardSchool.fromProfile({
        'name': 'Ahmadiyya S.S.S.',
        'address': 'Bo',
        'district': 'Bo District',
        'motto': 'Knowledge is power',
        'founded': 1965,
      });
      expect(s.nameWithoutLevel, 'Ahmadiyya');
      expect(s.town, 'Bo');
      expect(s.district, 'Bo District');
      expect(s.founded, '1965');
      final empty = ReportCardSchool.fromProfile(const {});
      expect(empty.name, '');
      expect(empty.nameWithoutLevel, '');
    });
  });

  group('groupPupils', () {
    final classes = [
      const SchoolClass(id: 'a', name: 'JSS 2 A', level: SchoolLevel.secondary),
      const SchoolClass(id: 'b', name: 'Jss2B', level: SchoolLevel.secondary),
      const SchoolClass(id: 'c', name: 'SSS 2', level: SchoolLevel.secondary),
      const SchoolClass(id: 'd', name: 'Class 4', level: SchoolLevel.primary),
    ];
    Student st(String id, String last, String classId,
            {String status = StudentStatus.active, String? dept}) =>
        Student(
          id: id,
          firstName: 'F$id',
          lastName: last,
          classId: classId,
          status: status,
          department: dept,
        );
    final students = [
      st('1', 'Kamara', 'a'),
      st('2', 'conteh', 'b'),
      st('3', 'Bangura', 'a', status: StudentStatus.graduated),
      st('4', 'Sesay', 'c', dept: 'Science'),
      st('5', 'Turay', 'c', dept: 'Arts'),
      st('6', 'Koroma', 'd'),
      st('7', 'Jalloh', 'a', status: StudentStatus.transferred),
    ];

    test('sections merge, inactive left out, sorted by surname', () {
      final g = groupPupils(
          classes: classes, students: students, level: ReportLevel.jss);
      expect(g.keys.map((f) => f.label), ['JSS-2']);
      expect(g.values.single.map((s) => s.lastName), ['conteh', 'Kamara']);
    });

    test('SS department filter', () {
      final all = groupPupils(
          classes: classes, students: students, level: ReportLevel.ss);
      expect(all.values.single.length, 2);
      final arts = groupPupils(
          classes: classes,
          students: students,
          level: ReportLevel.ss,
          department: DepartmentFilter.arts);
      expect(arts.values.single.single.lastName, 'Turay');
      final commercial = groupPupils(
          classes: classes,
          students: students,
          level: ReportLevel.ss,
          department: DepartmentFilter.commercial);
      expect(commercial, isEmpty);
    });
  });

  group('PDF', () {
    const jss2 = ReportForm(ReportLevel.jss, 2);
    const school = ReportCardSchool(
      name: 'Bubuya Community Junior Secondary School',
      town: 'Tonko – Limba',
      district: 'Kambia District',
      motto: 'Education for Development',
      founded: '1998',
    );
    final out = Directory(
        Platform.environment['REPORT_CARD_OUT'] ?? Directory.systemTemp.path);

    Future<Uint8List> build(List<ReportCardPupil> pupils,
        {ReportCardSchool s = school, String principal = 'Mr. Mohamed Bangura'}) =>
        buildReportCardsPdf(
          pupils: pupils,
          school: s,
          level: ReportLevel.jss,
          principal: principal,
        );

    test('one pupil = one page', () async {
      final pdf = await build(const [
        ReportCardPupil(
          surname: 'Conteh',
          firstName: 'Amara',
          middleName: 'Patrick',
          admissionNo: 'BCJ/2024/017',
          form: jss2,
        ),
      ]);
      expect(pageCount(pdf), 1);
      File('${out.path}/report_card_one.pdf').writeAsBytesSync(pdf);
    });

    test('a class of 30 = 30 pages; long name, no admission number',
        () async {
      final pupils = [
        const ReportCardPupil(
          surname: 'Kamarakeh-Sesay-Bangura',
          firstName: 'Mohamed Abubakarr Alhassan',
          middleName: 'Fatmata-Christiana',
          form: jss2,
        ),
        for (var i = 1; i < 30; i++)
          ReportCardPupil(
            surname: 'Pupil$i',
            firstName: 'First',
            admissionNo: 'A$i',
            form: jss2,
          ),
      ];
      // The app icon stands in for a school crest.
      final logo = File('assets/icon/app_icon.png').readAsBytesSync();
      final pdf = await build(pupils,
          s: ReportCardSchool(
            name: school.name,
            town: school.town,
            district: school.district,
            motto: school.motto,
            logo: logo,
          ));
      expect(pageCount(pdf), 30);
      File('${out.path}/report_card_class.pdf').writeAsBytesSync(pdf);
    });

    test('an empty profile never crashes', () async {
      final pdf = await build(
        const [ReportCardPupil(surname: '', firstName: 'X', form: jss2)],
        s: const ReportCardSchool(),
        principal: '',
      );
      expect(pageCount(pdf), 1);
      File('${out.path}/report_card_blank.pdf').writeAsBytesSync(pdf);
    });

    test('a broken logo is left out', () async {
      final pdf = await build(
        const [ReportCardPupil(surname: 'A', firstName: 'B', form: jss2)],
        s: ReportCardSchool(name: 'Test', logo: Uint8List.fromList([1, 2, 3])),
      );
      expect(pageCount(pdf), 1);
    });

    test('built-in fonts fallback prints plain quotes', () {
      final f = ReportCardFonts.builtIn();
      expect(f.text('“Motto” – x'), '"Motto" - x');
    });

    test('no pupils is refused', () {
      expect(build(const []), throwsArgumentError);
    });
  });
}
