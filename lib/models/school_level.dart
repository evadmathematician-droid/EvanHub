/// A class in the standard ladder of a [SchoolLevel] (e.g. "JSS 1").
class StandardClass {
  final String name;
  final SecondaryStage? stage;

  const StandardClass(this.name, {this.stage});
}

/// The three levels a school can run. Stored on classes and students as
/// [wire] (`pre_primary`, `primary`, `secondary`) so the app can filter by level.
enum SchoolLevel {
  prePrimary('pre_primary', 'Pre-primary'),
  primary('primary', 'Primary'),
  secondary('secondary', 'Secondary');

  const SchoolLevel(this.wire, this.label);

  final String wire;
  final String label;

  /// Null for a missing / unrecognised value (e.g. records without a level).
  static SchoolLevel? fromWire(Object? value) {
    for (final l in SchoolLevel.values) {
      if (l.wire == value) return l;
    }
    return null;
  }

  /// True when [className] is the last class of this level's standard ladder
  /// (Class 6, SSS 3). Pre-primary has no leaving exam, so it is never final.
  bool isFinalClassName(String className) =>
      this != SchoolLevel.prePrimary &&
      standardClasses.last.name.toLowerCase() ==
          className.trim().toLowerCase();

  /// The usual class ladder for this level, in promotion order.
  List<StandardClass> get standardClasses => switch (this) {
        SchoolLevel.prePrimary => const [
            StandardClass('Nursery 1'),
            StandardClass('Nursery 2'),
            StandardClass('Pre 1'),
            StandardClass('Pre 2'),
          ],
        SchoolLevel.primary => [
            for (var i = 1; i <= 6; i++) StandardClass('Class $i'),
          ],
        SchoolLevel.secondary => [
            for (var i = 1; i <= 3; i++)
              StandardClass('JSS $i', stage: SecondaryStage.junior),
            for (var i = 1; i <= 3; i++)
              StandardClass('SSS $i', stage: SecondaryStage.senior),
          ],
      };
}

/// True when [className] is the last junior secondary class (JSS 3 / JSS3).
/// Promoting out of it needs each pupil's BECE record first.
bool isFinalJuniorClassName(String className) =>
    className.replaceAll(RegExp(r'\s+'), '').toLowerCase() == 'jss3';

/// Junior / senior split within the secondary level. Only senior secondary
/// classes carry a department.
enum SecondaryStage {
  junior('junior', 'Junior secondary'),
  senior('senior', 'Senior secondary');

  const SecondaryStage(this.wire, this.label);

  final String wire;
  final String label;

  static SecondaryStage? fromWire(Object? value) {
    for (final s in SecondaryStage.values) {
      if (s.wire == value) return s;
    }
    return null;
  }
}

/// Senior secondary departments / streams.
const kDepartments = ['Science', 'Commercial', 'Arts'];
