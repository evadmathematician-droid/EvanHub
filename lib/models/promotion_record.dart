import 'package:firebase_database/firebase_database.dart';

import '../core/rtdb.dart';

/// An audit record written whenever a student is moved between classes —
/// `schools/{schoolId}/promotions/{id}`.
class PromotionRecord {
  final String id;
  final String studentId;
  final String? fromClassId;
  final String toClassId;
  final String academicYear;
  final String promotedBy;
  final DateTime? promotedAt;

  const PromotionRecord({
    required this.id,
    required this.studentId,
    required this.fromClassId,
    required this.toClassId,
    this.academicYear = '',
    this.promotedBy = '',
    this.promotedAt,
  });

  factory PromotionRecord.fromMap(String id, Map<String, dynamic> data) {
    return PromotionRecord(
      id: id,
      studentId: (data['studentId'] ?? '') as String,
      fromClassId: data['fromClassId'] as String?,
      toClassId: (data['toClassId'] ?? '') as String,
      academicYear: (data['academicYear'] ?? '') as String,
      promotedBy: (data['promotedBy'] ?? '') as String,
      promotedAt: fromMillis(data['promotedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
        'studentId': studentId,
        'fromClassId': fromClassId,
        'toClassId': toClassId,
        'academicYear': academicYear,
        'promotedBy': promotedBy,
        'promotedAt': ServerValue.timestamp,
      };
}
