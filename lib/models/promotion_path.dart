import 'school_class.dart';
import 'school_level.dart';

/// Where the pupils of a class go when it is promoted, following the ladders
/// in [SchoolLevel.standardClasses]:
///  - Nursery: Pre 1 → Pre 2 → primary Class 1, or Past (graduated) when the
///    school has no primary classes.
///  - Primary: Class 1 → … → Class 6 → Past.
///  - Secondary: JSS 1 → JSS 2 → JSS 3 → SSS 1 → SSS 2 → SSS 3 → Past.
///    JSS 3 → SSS 1 needs each pupil's BECE ID and year; a school with no SSS
///    classes sends JSS 3 to Past instead.
///
/// Every step is exactly one rung: a class is never skipped, and the only
/// moves into another level are Pre 2 → Class 1 and JSS 3 → SSS 1.
class PromotionPath {
  const PromotionPath._(this.level, this.rung);

  /// Pupils leave the school and show under the "Past" filter.
  static const graduate = PromotionPath._(null, -1);

  /// Target level and ladder position; null / -1 when pupils graduate.
  final SchoolLevel? level;
  final int rung;

  bool get graduates => level == null;

  StandardClass get next => level!.standardClasses[rung];

  /// True for classes at the target rung, including sections like "JSS 2 B".
  bool isTarget(SchoolClass c) =>
      !graduates && c.level == level && level!.rungOf(c.name) == rung;

  /// The path out of [from], given all of the school's [classes]. Null when
  /// [from] has no level or a non-standard name, so its next class is unknown.
  static PromotionPath? of(SchoolClass from, Iterable<SchoolClass> classes) {
    final level = from.level;
    final rung = level?.rungOf(from.name) ?? -1;
    if (level == null || rung < 0) return null;

    final ladder = level.standardClasses;
    if (isFinalJuniorClassName(from.name)) {
      final runsSenior = classes.any((c) =>
          c.level == SchoolLevel.secondary &&
          _stageOf(c) == SecondaryStage.senior);
      return runsSenior ? PromotionPath._(level, rung + 1) : graduate;
    }
    if (rung < ladder.length - 1) return PromotionPath._(level, rung + 1);
    if (level == SchoolLevel.prePrimary &&
        classes.any((c) =>
            c.level == SchoolLevel.primary &&
            SchoolLevel.primary.rungOf(c.name) >= 0)) {
      return const PromotionPath._(SchoolLevel.primary, 0);
    }
    return graduate;
  }

  /// JSS 3 → SSS 1: each pupil needs a BECE ID and year first.
  bool needsBece(SchoolClass from) =>
      !graduates &&
      next.stage == SecondaryStage.senior &&
      isFinalJuniorClassName(from.name);

  /// Graduating SSS 3: each pupil needs a WASSCE ID and year. (JSS 3 pupils
  /// graduating from a school without SSS do not.)
  bool needsWassce(SchoolClass from) =>
      graduates &&
      from.level == SchoolLevel.secondary &&
      _stageOf(from) == SecondaryStage.senior;

  static SecondaryStage? _stageOf(SchoolClass c) {
    final rung = SchoolLevel.secondary.rungOf(c.name);
    return rung < 0 ? null : SchoolLevel.secondary.standardClasses[rung].stage;
  }
}
