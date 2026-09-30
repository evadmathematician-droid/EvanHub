import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/announcements/announcement_form_screen.dart';
import '../features/announcements/announcements_list_screen.dart';
import '../features/access/no_access_screen.dart';
import '../features/access/parent_portal_screen.dart';
import '../features/access/upgrade_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/splash_screen.dart';
import '../features/classes/class_form_screen.dart';
import '../features/classes/classes_list_screen.dart';
import '../features/classes/promotion_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/documents/documents_screen.dart';
import '../features/join/join_screen.dart';
import '../features/more/more_screen.dart';
import '../features/onboarding/school_onboarding_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/students/student_form_screen.dart';
import '../features/students/students_list_screen.dart';
import '../features/teachers/teacher_form_screen.dart';
import '../features/teachers/teachers_list_screen.dart';
import '../models/school_class.dart';
import '../models/student.dart';
import '../models/teacher.dart';
import '../state/auth_controller.dart';
import '../widgets/home_shell.dart';
import 'routes.dart';

/// Builds the app router. [auth] both gates navigation (via [redirect]) and
/// triggers re-evaluation (via [GoRouter.refreshListenable]).
GoRouter buildRouter(AuthController auth) {
  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: auth,
    observers: [
      FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance),
    ],
    redirect: (context, state) {
      final loc = state.matchedLocation;
      // Screens shown instead of the app proper.
      const gates = {
        Routes.splash,
        Routes.login,
        Routes.onboarding,
        Routes.noAccess,
        Routes.upgrade,
        Routes.parentPortal,
      };
      String? only(String route) => loc == route ? null : route;

      // The join screen works in every state: signed out, signed in without
      // a school, removed from a school, or already signed in elsewhere (it
      // explains that case itself). It opens the app when the join is done.
      if (loc == Routes.join) return null;

      switch (auth.status) {
        case AuthStatus.unknown:
          return only(Routes.splash);
        case AuthStatus.signedOut:
          // Onboarding starts before an account exists, so allow it too.
          return (loc == Routes.login || loc == Routes.onboarding)
              ? null
              : Routes.login;
        case AuthStatus.needsOnboarding:
          return only(Routes.onboarding);
        case AuthStatus.noAccess:
          return only(Routes.noAccess);
        case AuthStatus.upgradeRequired:
          return only(Routes.upgrade);
        case AuthStatus.parentPortal:
          return only(Routes.parentPortal);
        case AuthStatus.ready:
          return gates.contains(loc) ? Routes.dashboard : null;
      }
    },
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (_, _) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.login,
        builder: (_, _) => const LoginScreen(),
      ),
      GoRoute(
        path: Routes.onboarding,
        builder: (_, _) => const SchoolOnboardingScreen(),
      ),
      GoRoute(
        path: Routes.join,
        builder: (_, _) => const JoinScreen(),
      ),
      GoRoute(
        path: Routes.noAccess,
        builder: (_, _) => const NoAccessScreen(),
      ),
      GoRoute(
        path: Routes.upgrade,
        builder: (_, _) => const UpgradeScreen(),
      ),
      GoRoute(
        path: Routes.parentPortal,
        builder: (_, _) => const ParentPortalScreen(),
      ),

      // --- Forms / secondary screens (rendered above the bottom-nav shell) ---
      GoRoute(
        path: Routes.studentNew,
        builder: (_, _) => const StudentFormScreen(),
      ),
      GoRoute(
        path: '/students/:id/edit',
        builder: (_, state) =>
            StudentFormScreen(existing: state.extra as Student?),
      ),
      GoRoute(
        path: Routes.teacherNew,
        builder: (_, _) => const TeacherFormScreen(),
      ),
      GoRoute(
        path: '/teachers/:id/edit',
        builder: (_, state) =>
            TeacherFormScreen(existing: state.extra as Teacher?),
      ),
      GoRoute(
        path: Routes.classes,
        builder: (_, _) => const ClassesListScreen(),
      ),
      GoRoute(
        path: Routes.classNew,
        builder: (_, _) => const ClassFormScreen(),
      ),
      GoRoute(
        path: Routes.promote,
        builder: (_, _) => const PromotionScreen(),
      ),
      GoRoute(
        path: '/classes/:id/edit',
        builder: (_, state) =>
            ClassFormScreen(existing: state.extra as SchoolClass?),
      ),
      GoRoute(
        path: Routes.documents,
        builder: (_, _) => const DocumentsScreen(),
      ),
      GoRoute(
        path: Routes.announcements,
        builder: (_, _) => const AnnouncementsListScreen(),
      ),
      GoRoute(
        path: Routes.announcementNew,
        builder: (_, _) => const AnnouncementFormScreen(),
      ),
      GoRoute(
        path: Routes.settings,
        builder: (_, _) => const SettingsScreen(),
      ),

      // --- Bottom-nav shell ---
      StatefulShellRoute.indexedStack(
        builder: (_, _, navigationShell) =>
            HomeShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.dashboard,
              builder: (_, _) => const DashboardScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.students,
              builder: (_, _) => const StudentsListScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.teachers,
              builder: (_, _) => const TeachersListScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.more,
              builder: (_, _) => const MoreScreen(),
            ),
          ]),
        ],
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      appBar: AppBar(title: const Text('Not found')),
      body: Center(child: Text('No route for ${state.uri}')),
    ),
  );
}
