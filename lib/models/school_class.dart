import 'package:firebase_database/firebase_database.dart';

import '../core/rtdb.dart';
import 'school_level.dart';

/// A class/grade within a school — `schools/{schoolId}/classes/{classId}`.
class SchoolClass {
  final String id;
  final String name;

  /// Null only for records created before levels existed.
  final SchoolLevel? level;

  /// Set only for [SchoolLevel.secondary] classes.
  final SecondaryStage? stage;
  final String academicYear;
  final String? classTeacherId;
  final DateTime? createdAt;

  const SchoolClass({
    required this.id,
    required this.name,
    this.level,
    this.stage,
    this.academicYear = '',
    this.classTeacherId,
    this.createdAt,
  });

  factory SchoolClass.fromMap(String id, Map<String, dynamic> data) {
    return SchoolClass(
      id: id,
      name: (data['name'] ?? '') as String,
      level: SchoolLevel.fromWire(data['level']),
      stage: SecondaryStage.fromWire(data['stage']),
      academicYear: (data['academicYear'] ?? '') as String,
      classTeacherId: data['classTeacherId'] as String?,
      createdAt: fromMillis(data['createdAt']),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'level': level?.wire,
        'stage': level == SchoolLevel.secondary ? stage?.wire : null,
        'academicYear': academicYear,
        'classTeacherId': classTeacherId,
        'createdAt':
            createdAt == null ? ServerValue.timestamp : toMillis(createdAt),
      };
}
