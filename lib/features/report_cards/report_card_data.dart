import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../core/rtdb.dart';
import '../../core/offline_write.dart';
import '../../core/tenant/tenant_refs.dart';
import '../../models/school.dart';
import '../../models/school_class.dart';
import '../../models/student.dart';
import '../../services/export/export_images.dart';
import '../../services/upload_queue.dart';
import 'report_card_texts.dart';

/// Junior or senior secondary report cards.
enum ReportLevel {
  jss('JSS', 'JSS Report Card', ReportCardTexts.juniorLevelLine),
  ss('SS', 'SS Report Card', ReportCardTexts.seniorLevelLine);

  const ReportLevel(this.code, this.title, this.levelLine);

  /// "JSS" / "SS", as printed in the form ("JSS-2").
  final String code;
  final String title;

  /// "JUNIOR SECONDARY SCHOOL" / "SENIOR SECONDARY SCHOOL".
  final String levelLine;
}

/// One form (year group) such as JSS-2 or SS-3. Sections (JSS 2 A, JSS 2 B)
/// all belong to the same form.
@immutable
class ReportForm implements Comparable<ReportForm> {
  const ReportForm(this.level, this.number);

  final ReportLevel level;
  final int number;

  /// "JSS-2" / "SS-2".
  String get label => '${level.code}-$number';

  @override
  int compareTo(ReportForm other) => level != other.level
      ? level.index - other.level.index
      : number - other.number;

  @override
  bool operator ==(Object other) =>
      other is ReportForm && other.level == level && other.number == number;

  @override
  int get hashCode => Object.hash(level, number);

  @override
  String toString() => label;
}

final _formPattern = RegExp(
  r'^(JSS|JHS|JS|SSS|SHS|SS)[\s\-_/]*(?:(\d+)(?!\d)|(IV|III|II|I)(?![A-Z]))',
);

const _roman = {'I': 1, 'II': 2, 'III': 3, 'IV': 4};

/// The form a class name stands for, however it was typed: "JSS 2", "JSS2",
/// "Jss-2", "J.S.S. 2", "JSS II" and "JSS 2 A" are all JSS-2; "SSS 2", "SS2",
/// "SS II" and "SHS 2" are all SS-2. Null for anything else (primary classes,
/// unrecognised names). Use this everywhere classes are matched.
ReportForm? normalizeClassName(String className) {
  final s = className.toUpperCase().replaceAll('.', '').trim();
  final m = _formPattern.firstMatch(s);
  if (m == null) return null;
  final number = m.group(2) != null ? int.parse(m.group(2)!) : _roman[m.group(3)]!;
  if (number < 1 || number > 4) return null;
  final level = m.group(1)!.startsWith('J') ? ReportLevel.jss : ReportLevel.ss;
  return ReportForm(level, number);
}

/// Department choice for SS cards. [all] means no filter.
enum DepartmentFilter {
  all('All'),
  science('Science'),
  commercial('Commercial'),
  arts('Arts');

  const DepartmentFilter(this.label);
  final String label;

  bool matches(String? department) =>
      this == all ||
      (department ?? '').trim().toLowerCase() == label.toLowerCase();
}

/// A pupil as the cover page prints them.
class ReportCardPupil {
  const ReportCardPupil({
    required this.surname,
    required this.firstName,
    this.middleName = '',
    this.admissionNo = '',
    required this.form,
  });

  factory ReportCardPupil.fromStudent(Student s, ReportForm form) =>
      ReportCardPupil(
        surname: s.lastName,
        firstName: s.firstName,
        middleName: s.middleName,
        admissionNo: s.admissionNo,
        form: form,
      );

  final String surname;
  final String firstName;
  final String middleName;
  final String admissionNo;
  final ReportForm form;

  /// "CONTEH AMARA PATRICK": surname first, upper case.
  String get printedName => [surname, firstName, middleName]
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .join(' ')
      .toUpperCase();
}

/// The school details printed on the cover page. Every text may be empty;
/// [logo] may be null.
class ReportCardSchool {
  const ReportCardSchool({
    this.name = '',
    this.town = '',
    this.district = '',
    this.motto = '',
    this.founded = '',
    this.principal = '',
    this.logo,
  });

  /// From the `profile` map. The app has no town / district / motto /
  /// founded fields yet, so each is read if a profile carries it; otherwise
  /// town and district come from the address ("Tonko Limba, Kambia
  /// District": the part with "district" is the district, the rest the town).
  factory ReportCardSchool.fromProfile(Map<String, dynamic> profile,
      {Uint8List? logo}) {
    String text(List<String> keys) {
      for (final k in keys) {
        final v = profile[k];
        if (v != null && v.toString().trim().isNotEmpty) {
          return v.toString().trim();
        }
      }
      return '';
    }

    final meta = SchoolMeta.fromMap(profile);
    final (addrTown, addrDistrict) = splitAddress(meta.address);
    return ReportCardSchool(
      name: meta.name.trim(),
      town: text(const ['town', 'location']).isNotEmpty
          ? text(const ['town', 'location'])
          : addrTown,
      district: text(const ['district']).isNotEmpty
          ? text(const ['district'])
          : addrDistrict,
      motto: text(const ['motto']),
      founded: text(const [
        'founded',
        'foundedYear',
        'yearFounded',
        'funded',
        'established',
        'yearEstablished',
      ]),
      principal: meta.headName.trim(),
      logo: logo,
    );
  }

  final String name;
  final String town;
  final String district;
  final String motto;
  final String founded;

  /// The Head Teacher / Principal on the profile: the default for the
  /// export screen's "Principal's name".
  final String principal;
  final Uint8List? logo;

  /// The school name without a trailing "Junior Secondary School",
  /// "Secondary School", "JSS", "S.S.S." …, since the cover prints the level
  /// on its own line. The full name when nothing is left.
  String get nameWithoutLevel {
    final stripped = name
        .replaceFirst(
            RegExp(
                r'[\s,\-]*\(?\b((junior|senior)\s+)?(secondary|high)\s+school\)?\s*$',
                caseSensitive: false),
            '')
        .replaceFirst(
            RegExp(r'[\s,\-]*\(?\b(j\.?\s?s\.?\s?s|s\.?\s?s\.?\s?s|j\.?\s?h\.?\s?s|s\.?\s?h\.?\s?s)\.?\)?\s*$',
                caseSensitive: false),
            '')
        .trim();
    return stripped.isEmpty ? name : stripped;
  }
}

/// (town, district) from a free-text address.
(String, String) splitAddress(String address) {
  final parts = address
      .split(RegExp(r'[,\n;]'))
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
  final i = parts.lastIndexWhere((p) => p.toLowerCase().contains('district'));
  if (i < 0) return (parts.join(', '), '');
  final district = parts.removeAt(i);
  return (parts.join(', '), district);
}

/// Pupils in each [level] form, built from the school's real classes and
/// students: only active pupils (graduated, inactive and transferred are
/// left out), only [department] for SS, each form sorted by surname, then
/// first and middle name. Forms with no pupils are not included.
Map<ReportForm, List<Student>> groupPupils({
  required List<SchoolClass> classes,
  required List<Student> students,
  required ReportLevel level,
  DepartmentFilter department = DepartmentFilter.all,
}) {
  final formOfClass = <String, ReportForm>{
    for (final c in classes)
      if (normalizeClassName(c.name) case final f? when f.level == level)
        c.id: f,
  };
  final groups = <ReportForm, List<Student>>{};
  for (final s in students) {
    final form = formOfClass[s.classId];
    if (form == null) continue;
    if (s.status.isNotEmpty && s.status != StudentStatus.active) continue;
    if (level == ReportLevel.ss && !department.matches(s.department)) continue;
    groups.putIfAbsent(form, () => []).add(s);
  }
  for (final list in groups.values) {
    list.sort(comparePupils);
  }
  final sorted = groups.keys.toList()..sort();
  return {for (final f in sorted) f: groups[f]!};
}

/// Surname, then first name, then middle name, ignoring case.
int comparePupils(Student a, Student b) {
  for (final (x, y) in [
    (a.lastName, b.lastName),
    (a.firstName, b.firstName),
    (a.middleName, b.middleName),
  ]) {
    final c = compareText(x.trim(), y.trim());
    if (c != 0) return c;
  }
  return 0;
}

/// Reads the school's cover-page details from the phone's copy of the
/// profile (works offline), with the logo from the image cache. Never
/// throws: anything missing comes back blank.
Future<ReportCardSchool> loadReportCardSchool(TenantRefs refs) async {
  Map<String, dynamic> profile = const {};
  try {
    profile = asMap((await readOnce(refs.profile)).value);
  } catch (e) {
    debugPrint('Report cards: school profile unavailable: $e');
  }
  Uint8List? logo;
  try {
    // A logo still waiting to upload is taken straight from the phone.
    final local = kIsWeb
        ? null
        : UploadQueue.instance
            ?.localSchoolImage(refs.schoolId, 'profile', 'logoUrl');
    logo = local != null
        ? await File(local).readAsBytes()
        : await ExportImages.load(
            ExportImages.badgeUrl(profile['logoUrl'] as String?));
  } catch (e) {
    debugPrint('Report cards: logo unavailable: $e');
  }
  return ReportCardSchool.fromProfile(profile, logo: logo);
}
