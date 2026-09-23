import 'package:firebase_database/firebase_database.dart';

import '../core/rtdb.dart';
import '../core/tenant/tenant_refs.dart';
import '../models/school.dart';
import '../models/student.dart';
import '../models/teacher.dart';

/// What the Phase 1 migration will do for one school, worked out before
/// anything is written.
class MigrationPlan {
  const MigrationPlan({
    required this.updates,
    required this.problems,
    required this.students,
    required this.teachers,
    required this.unassigned,
  });

  /// The single multi-path update, relative to `schools/{schoolId}`.
  final Map<String, Object?> updates;

  /// Records the new database rules would reject. The migration can't run
  /// until these are fixed (in the Firebase console, which bypasses rules).
  final List<String> problems;

  final int students;
  final int teachers;

  /// Students whose class no longer exists; their classId becomes ''.
  final int unassigned;

  bool get ready => problems.isEmpty;
}

/// One-time move from the pre-Phase-1 layout (everything in `students`,
/// `teachers`, `meta`) to the split layout (`profile`, `studentPrivate`,
/// `teacherPrivate`, `index/`). Run by a school admin; see docs/MULTI_TENANCY.md.
class MigrationService {
  MigrationService(this._refs);

  final TenantRefs _refs;

  Future<MigrationPlan> prepare() async {
    final results = await Future.wait([
      _refs.legacyMeta.get(),
      _refs.students.get(),
      _refs.teachers.get(),
      _refs.classes.get(),
    ]);
    final metaSnap = results[0];
    final classIds = {for (final c in results[3].children) c.key};

    final updates = <String, Object?>{};
    final problems = <String>[];

    // --- School profile: meta -> profile -------------------------------------
    if (!metaSnap.exists) {
      problems.add('School profile: no "meta" or "profile" found.');
    } else {
      final meta = SchoolMeta.fromMap(asMap(metaSnap.value));
      problems.addAll(profileProblems(meta).map((p) => 'School profile: $p'));
      updates['profile'] = {...meta.toMap(), 'updatedAt': ServerValue.timestamp};
      updates['meta'] = null;
      updates['updatedAt'] = null;
    }

    // --- Students: split + admission-number index -----------------------------
    final admissionOwners = <String, String>{};
    var students = 0, unassigned = 0;
    for (final child in results[1].children) {
      final id = child.key;
      if (id == null) continue;
      final data = asMap(child.value);
      final Student s;
      try {
        s = Student.fromParts(id, data, data);
      } catch (_) {
        problems.add('Student $id: record has fields of the wrong type.');
        continue;
      }
      final label = 'Student "${s.fullName}" (Adm ${s.admissionNo})';
      problems.addAll(studentProblems(s).map((p) => '$label: $p'));

      final key = indexKey(s.admissionNo);
      if (s.admissionNo.isNotEmpty) {
        final other = admissionOwners[key];
        if (other != null) {
          problems.add('$label: admission number also used by $other.');
        }
        admissionOwners[key] = label;
      }

      final public = s.toPublicMap();
      final classId = s.classId;
      if (classId != null && classId.isNotEmpty && !classIds.contains(classId)) {
        public['classId'] = '';
        unassigned++;
      }
      updates['students/$id'] = public;
      updates['studentPrivate/$id'] = s.toPrivateMap();
      if (s.admissionNo.isNotEmpty) updates['index/admissionNo/$key'] = id;
      students++;
    }

    // --- Teachers: split + NIN index -------------------------------------------
    final ninOwners = <String, String>{};
    var teachers = 0;
    for (final child in results[2].children) {
      final id = child.key;
      if (id == null) continue;
      final data = asMap(child.value);
      final Teacher t;
      try {
        t = Teacher.fromParts(id, data, data);
      } catch (_) {
        problems.add('Teacher $id: record has fields of the wrong type.');
        continue;
      }
      final label = 'Teacher "${t.fullName}"';
      problems.addAll(teacherProblems(t).map((p) => '$label: $p'));

      if (t.nin.isNotEmpty) {
        final other = ninOwners[t.nin];
        if (other != null) problems.add('$label: NIN also used by $other.');
        ninOwners[t.nin] = label;
        updates['index/nin/${t.nin}'] = id;
      }
      updates['teachers/$id'] = t.toPublicMap();
      updates['teacherPrivate/$id'] = t.toPrivateMap();
      teachers++;
    }

    return MigrationPlan(
      updates: updates,
      problems: problems,
      students: students,
      teachers: teachers,
      unassigned: unassigned,
    );
  }

  /// Writes the whole plan as ONE atomic multi-path update.
  Future<void> run(MigrationPlan plan) {
    if (!plan.ready) {
      throw StateError('Fix the listed problems before migrating.');
    }
    return _refs.school.update(plan.updates);
  }
}

// --- Checks mirroring database.rules.json ---------------------------------------

bool _len(String v, int min, int max) => v.length >= min && v.length <= max;
bool _url(String? v) =>
    v == null || v.isEmpty || (v.length <= 500 && v.startsWith('https://'));
bool _year(String v) => v.isEmpty || RegExp(r'^[0-9]{4}$').hasMatch(v);
bool _trimmed(String v) => v.trim() == v;

List<String> profileProblems(SchoolMeta m) => [
      if (!_len(m.name, 1, 120)) 'name must be 1-120 characters',
      if (!_url(m.logoUrl)) 'badge link is not an https:// link',
      if (!_url(m.coverUrl)) 'cover photo link is not an https:// link',
      if (m.address.length > 300) 'address is longer than 300 characters',
      if (m.phone.length > 40) 'phone is longer than 40 characters',
      if (m.email.length > 120) 'email is longer than 120 characters',
    ];

List<String> studentProblems(Student s) => [
      if (!_len(s.firstName, 1, 60)) 'first name must be 1-60 characters',
      if (s.middleName.length > 60) 'middle name is longer than 60 characters',
      if (!_len(s.lastName, 1, 60)) 'last name must be 1-60 characters',
      if (!['', 'Male', 'Female'].contains(s.gender))
        'gender "${s.gender}" must be Male, Female or empty',
      if (!_len(s.admissionNo, 1, 30) || !_trimmed(s.admissionNo))
        'admission number must be 1-30 characters without leading/trailing spaces',
      if (!_year(s.admissionYear)) 'admission year must be 4 digits',
      if (s.department != null &&
          !['Science', 'Commercial', 'Arts'].contains(s.department))
        'department "${s.department}" is not Science, Commercial or Arts',
      if (!StudentStatus.all.contains(s.status)) 'status "${s.status}" is invalid',
      if (!_url(s.photoUrl)) 'photo link is not an https:// link',
      if (s.address.length > 300) 'address is longer than 300 characters',
      if (s.guardianName.length > 100) 'guardian name is longer than 100 characters',
      if (s.guardianPhone.length > 40) 'guardian phone is longer than 40 characters',
      for (final (label, id, year) in [
        ('NPSE', s.npseId, s.npseYear),
        ('BECE', s.beceId, s.beceYear),
        ('WASSCE', s.wassceId, s.wassceYear),
      ]) ...[
        if (id.length > 20) '$label ID is longer than 20 characters',
        if (!_year(year)) '$label year must be 4 digits',
      ],
    ];

List<String> teacherProblems(Teacher t) => [
      if (!_len(t.firstName, 1, 60)) 'first name must be 1-60 characters',
      if (!_len(t.lastName, 1, 60)) 'last name must be 1-60 characters',
      if (!['', 'Male', 'Female'].contains(t.gender))
        'gender "${t.gender}" must be Male, Female or empty',
      if (t.subjects.any((s) => !_len(s, 1, 60)))
        'each subject must be 1-60 characters',
      if (!['', 'JSS', 'SSS', 'BOTH'].contains(t.level))
        'level "${t.level}" must be JSS, SSS or BOTH',
      if (!['', 'Science', 'Commercial', 'Arts'].contains(t.stream))
        'stream "${t.stream}" is invalid',
      if (!['full_time', 'part_time', 'contract'].contains(t.employmentType))
        'employment type "${t.employmentType}" is invalid',
      if (!['active', 'inactive'].contains(t.status))
        'status "${t.status}" is invalid',
      if (!_url(t.photoUrl)) 'photo link is not an https:// link',
      if ((t.linkedUid ?? '').length > 128) 'linked login id is too long',
      if (t.nin.isNotEmpty && !RegExp(r'^[A-HJ-NP-Z0-9]{8}$').hasMatch(t.nin))
        'NIN "${t.nin}" must be 8 capital letters/digits without I or O',
      if (t.isPincoded && !RegExp(r'^[0-9]{6}$').hasMatch(t.pincode))
        'pincode must be 6 digits',
      if (!['', 'Single', 'Married'].contains(t.maritalStatus))
        'marital status "${t.maritalStatus}" is invalid',
      if (t.email.length > 120) 'email is longer than 120 characters',
      if (t.phone.length > 40) 'phone is longer than 40 characters',
      if (t.address.length > 300) 'address is longer than 300 characters',
      if (t.qualification.length > 200) 'qualification is longer than 200 characters',
      if (t.experience.length > 200) 'experience is longer than 200 characters',
      for (final d in t.documents)
        if (!_len(d.title, 1, 120) || !_url(d.url) || d.url.isEmpty)
          'document "${d.title}" has an invalid title or link',
    ];
