import 'package:firebase_database/firebase_database.dart';

import '../core/rtdb.dart';
import 'promotion_record.dart';
import 'student.dart';
import 'teacher.dart';

/// Who a public lookup record is about.
enum LookupType {
  student('Student'),
  teacher('Teacher');

  const LookupType(this.label);
  final String label;

  static LookupType? fromWire(Object? v) =>
      v == 'student' ? student : (v == 'teacher' ? teacher : null);
}

/// `publicLookup/{schoolId}/{key}`: the key for [id] (a student's admission
/// number, a teacher's NIN). The id is trimmed, upper-cased and the
/// characters a database key can't hold (`. $ # [ ] /`) become `_`; the
/// prefix keeps a student and a teacher with the same number apart.
/// `database.rules.json` checks the prefix against the record's type.
String lookupKey(LookupType type, String id) {
  final norm = id.trim().toUpperCase().replaceAll(RegExp(r'[.$#\[\]/]'), '_');
  return norm.isEmpty ? '' : '${type.name}_$norm';
}

/// One promotion / repeat / graduation on a pupil's public record. Class
/// names, not ids, so it reads without the school's private class list.
class LookupPromotion {
  const LookupPromotion({
    required this.fromClass,
    required this.toClass,
    this.academicYear = '',
    this.date,
  });

  final String fromClass;

  /// Empty when the pupil completed school (graduated).
  final String toClass;
  final String academicYear;
  final DateTime? date;

  bool get completed => toClass.isEmpty;
  bool get repeated => !completed && toClass == fromClass;

  factory LookupPromotion.fromRecord(
          PromotionRecord r, String Function(String? id) className) =>
      LookupPromotion(
        fromClass: className(r.fromClassId),
        // A repeat keeps the same id; graduation has none.
        toClass: r.toClassId.isEmpty ? '' : className(r.toClassId),
        academicYear: r.academicYear,
        date: r.promotedAt,
      );

  factory LookupPromotion.fromMap(Map<String, dynamic> m) => LookupPromotion(
        fromClass: (m['fromClass'] ?? '') as String,
        toClass: (m['toClass'] ?? '') as String,
        academicYear: (m['academicYear'] ?? '') as String,
        date: fromMillis(m['date']),
      );

  Map<String, dynamic> toMap() => {
        'fromClass': fromClass,
        'toClass': toClass,
        'academicYear': academicYear,
        'date': toMillis(date),
      };
}

/// A record anyone can read by school + ID, with no sign-in: the Look Up
/// screen shows it. Holds only what a pupil, parent or teacher may see about
/// themselves — never passwords, PINs, guardian phone numbers, dates of
/// birth or admin data.
///
/// Fees, results and remarks are read when present (`fees`, `results`,
/// `remarks` maps); the app does not record them yet, so their sections
/// stay hidden until it does.
class LookupRecord {
  const LookupRecord({
    required this.type,
    required this.id,
    required this.firstName,
    required this.lastName,
    this.middleName = '',
    this.photoUrl = '',
    this.gender = '',
    this.status = '',
    this.className = '',
    this.levelLabel = '',
    this.department = '',
    this.admissionYear = '',
    this.address = '',
    this.npseId = '',
    this.npseYear = '',
    this.beceId = '',
    this.beceYear = '',
    this.wassceId = '',
    this.wassceYear = '',
    this.registeredAt,
    this.lastPromotedAt,
    this.history = const [],
    this.rank = '',
    this.subjects = '',
    this.teachingLevel = '',
    this.stream = '',
    this.fees = const {},
    this.results = const {},
    this.remarks = const {},
  });

  final LookupType type;

  /// The ID as the school entered it (admission number / NIN).
  final String id;
  final String firstName;
  final String middleName;
  final String lastName;
  final String photoUrl;
  final String gender;

  /// Students: active | graduated | inactive | transferred.
  /// Teachers: active | inactive (shown as Past).
  final String status;

  // ---- Students ----
  final String className;
  final String levelLabel;
  final String department;
  final String admissionYear;
  final String address;
  final String npseId;
  final String npseYear;
  final String beceId;
  final String beceYear;
  final String wassceId;
  final String wassceYear;
  final DateTime? registeredAt;
  final DateTime? lastPromotedAt;

  /// Oldest first. Only written by an admin (promotion history is
  /// admin-only), so a record saved by a teacher keeps the last one.
  final List<LookupPromotion> history;

  // ---- Teachers ----
  final String rank;
  final String subjects;

  /// JSS | SSS | BOTH.
  final String teachingLevel;
  final String stream;

  // ---- Read when present (not recorded by the app yet) ----
  final Map<String, dynamic> fees;
  final Map<String, dynamic> results;
  final Map<String, dynamic> remarks;

  String get fullName => [firstName, middleName, lastName]
      .where((p) => p.trim().isNotEmpty)
      .join(' ');

  bool get isStudent => type == LookupType.student;

  /// Built from a student with the private half loaded. [history] is null
  /// when the caller can't read promotion history (a teacher's phone); the
  /// record's saved history is then left as it is.
  static Map<String, Object?> studentFields(
    Student s, {
    required String className,
    List<LookupPromotion>? history,
  }) =>
      {
        'type': LookupType.student.name,
        'id': s.admissionNo.trim(),
        'firstName': s.firstName,
        'middleName': s.middleName,
        'lastName': s.lastName,
        'fullName': s.fullName,
        'photoUrl': s.photoUrl,
        'gender': s.gender,
        'status': s.status,
        'className': className,
        'level': s.level?.label ?? '',
        'department': s.department ?? '',
        'admissionYear': s.admissionYear,
        'address': s.address,
        'npseId': s.npseId,
        'npseYear': s.npseYear,
        'beceId': s.beceId,
        'beceYear': s.beceYear,
        'wassceId': s.wassceId,
        'wassceYear': s.wassceYear,
        'registeredAt': s.createdAt == null
            ? ServerValue.timestamp
            : toMillis(s.createdAt),
        'lastPromotedAt': toMillis(s.lastPromotedAt),
        if (history != null)
          'history': {
            for (var i = 0; i < history.length; i++)
              'p${i.toString().padLeft(3, '0')}': history[i].toMap(),
          },
        'updatedAt': ServerValue.timestamp,
      };

  /// Built from a teacher. The NIN is the teacher's lookup ID.
  static Map<String, Object?> teacherFields(Teacher t) => {
        'type': LookupType.teacher.name,
        'id': t.nin.trim(),
        'firstName': t.firstName,
        'middleName': t.middleName,
        'lastName': t.lastName,
        'fullName': t.fullName,
        'photoUrl': t.photoUrl,
        'gender': t.gender,
        'status': TeacherStatus.normalize(t.status),
        'rank': t.rank.trim(),
        'subjects': t.subjects.join(', '),
        'teachingLevel': t.level,
        'stream': t.stream,
        'updatedAt': ServerValue.timestamp,
      };

  /// [fields] ready for a database update: empty text and empty maps become
  /// null, so a field cleared on the form disappears from the record.
  static Map<String, Object?> clean(Map<String, Object?> fields) => {
        for (final e in fields.entries)
          e.key: switch (e.value) {
            final String v when v.trim().isEmpty => null,
            final Map<Object?, Object?> v when v.isEmpty => null,
            final v => v,
          },
      };

  factory LookupRecord.fromMap(Map<String, dynamic> m) {
    String s(String k) => (m[k] ?? '').toString();
    final history = [
      for (final e in asMap(m['history']).entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key)))
        if (e.value is Map) LookupPromotion.fromMap(asMap(e.value)),
    ];
    return LookupRecord(
      type: LookupType.fromWire(m['type']) ?? LookupType.student,
      id: s('id'),
      firstName: s('firstName'),
      middleName: s('middleName'),
      lastName: s('lastName'),
      photoUrl: s('photoUrl'),
      gender: s('gender'),
      status: s('status'),
      className: s('className'),
      levelLabel: s('level'),
      department: s('department'),
      admissionYear: s('admissionYear'),
      address: s('address'),
      npseId: s('npseId'),
      npseYear: s('npseYear'),
      beceId: s('beceId'),
      beceYear: s('beceYear'),
      wassceId: s('wassceId'),
      wassceYear: s('wassceYear'),
      registeredAt: fromMillis(m['registeredAt']),
      lastPromotedAt: fromMillis(m['lastPromotedAt']),
      history: history,
      rank: s('rank'),
      subjects: s('subjects'),
      teachingLevel: s('teachingLevel'),
      stream: s('stream'),
      fees: asMap(m['fees']),
      results: asMap(m['results']),
      remarks: asMap(m['remarks']),
    );
  }

  /// Where the pupil stands with promotion, judged today: Completed school,
  /// Repeat (the last promotion kept them back, or none for 10 months),
  /// Promoted, or Not yet promoted. Empty for teachers.
  String promotionStatus([DateTime? now]) {
    if (!isStudent) return '';
    if (status == StudentStatus.graduated) return 'Completed school';
    if (history.isNotEmpty && history.last.repeated) return 'Repeat';
    final since = lastPromotedAt ?? registeredAt;
    if (status == StudentStatus.active && since != null) {
      final n = now ?? DateTime.now();
      final cutoff =
          DateTime(n.year, n.month - Student.repeaterMonths, n.day);
      if (!since.isAfter(cutoff)) return 'Repeat';
    }
    return lastPromotedAt != null ? 'Promoted' : 'Not yet promoted';
  }
}

/// Simple, plain-words view of the optional fee figures.
class LookupFees {
  LookupFees(Map<String, dynamic> m)
      : total = _num(m['total']),
        paid = _num(m['paid']),
        lastPaymentAt = fromMillis(m['lastPaymentAt']);

  final num? total;
  final num? paid;
  final DateTime? lastPaymentAt;

  bool get hasAny => total != null || paid != null;

  /// Total minus paid; null when either is unknown.
  num? get balance =>
      (total == null || paid == null) ? null : (total! - paid!);

  /// Paid in full / Part payment / Not paid.
  String get paymentStatus {
    final b = balance, p = paid ?? 0;
    if (b != null && b <= 0) return 'Paid in full';
    return p > 0 ? 'Part payment' : 'Not paid';
  }
}

/// The optional results figures.
class LookupResults {
  LookupResults(Map<String, dynamic> m)
      : position = _num(m['position'])?.toInt(),
        classSize = _num(m['classSize'])?.toInt(),
        totalScore = _num(m['totalScore']),
        average = _num(m['average']),
        subjects = {
          for (final e in asMap(m['subjects']).entries)
            if (_num(e.value) != null) e.key: _num(e.value)!,
        };

  final int? position;
  final int? classSize;
  final num? totalScore;

  /// Percent, 0–100.
  final num? average;
  final Map<String, num> subjects;

  bool get hasAny =>
      position != null ||
      totalScore != null ||
      average != null ||
      subjects.isNotEmpty;

  /// "12th out of 45", or "12th" when the class size is unknown.
  String? get positionText {
    final p = position;
    if (p == null || p <= 0) return null;
    final n = classSize;
    return n != null && n > 0 ? '${ordinal(p)} out of $n' : ordinal(p);
  }

  /// The automatic note shown when the school wrote no remark, or null when
  /// there is nothing to judge by.
  String? get automaticGuidance {
    const poor = 'Performance needs improvement. The pupil should put in '
        'more effort and parents are advised to see the school '
        'administration.';
    const fair = 'Fair performance. More effort is encouraged.';
    const good = 'Good performance. Keep it up.';
    final avg = average;
    if (avg != null && avg < 50) return poor;
    final p = position, n = classSize;
    if (p != null && n != null && p > 0 && n > 0 && p <= n) {
      // Whole-number thirds: bottom third, middle third, top third.
      if (p * 3 > n * 2) return poor;
      if (p * 3 > n) return fair;
      return good;
    }
    if (avg != null) return avg >= 70 ? good : fair;
    return null;
  }
}

num? _num(Object? v) => v is num ? v : num.tryParse('${v ?? ''}');

/// 1st, 2nd, 3rd, 4th … 11th, 12th, 13th … 21st.
String ordinal(int n) {
  final mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 13) return '${n}th';
  return switch (n % 10) {
    1 => '${n}st',
    2 => '${n}nd',
    3 => '${n}rd',
    _ => '${n}th',
  };
}
