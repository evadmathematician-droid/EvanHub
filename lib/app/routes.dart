/// Route path constants. Kept in one place so screens never hard-code strings.
class Routes {
  Routes._();

  static const splash = '/splash';
  static const login = '/login';
  static const connect = '/connect';
  static const onboarding = '/onboarding';
  static const noAccess = '/no-access';
  static const upgrade = '/upgrade';
  static const parentPortal = '/parent';
  static const join = '/join';

  /// Public record look-up; works signed in or out.
  static const lookup = '/lookup';

  static const dashboard = '/dashboard';

  static const students = '/students';
  static const studentNew = '/students/new';
  static String studentEdit(String id) => '/students/$id/edit';

  static const teachers = '/teachers';
  static const teacherNew = '/teachers/new';
  static String teacherEdit(String id) => '/teachers/$id/edit';

  static const classes = '/classes';
  static const classNew = '/classes/new';
  static String classEdit(String id) => '/classes/$id/edit';
  static const promote = '/classes/promote';

  /// [level] is a `ReportLevel` name: `jss` or `ss`.
  static const reportCards = '/report-cards';
  static String reportCardLevel(String level) => '/report-cards/$level';

  static const documents = '/documents';

  static const announcements = '/announcements';
  static const announcementNew = '/announcements/new';

  static const more = '/more';
  static const settings = '/settings';
}
