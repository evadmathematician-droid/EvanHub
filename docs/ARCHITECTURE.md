# Architecture

## Layers

```
features/*  -- screens (StatelessWidget / small State)
   |  read via context.watch/read
state/AuthController  -- ChangeNotifier: auth + tenant, drives the router
   |
services/*  -- one class per concern; take a TenantRefs
   |
core/tenant/TenantRefs  -- the only place school paths are built
   |
Firebase Auth + Realtime Database          Cloudinary (files, via http)
```

State management is `provider`. `AuthController` is the single app-wide
`ChangeNotifier`. Feature screens construct the small per-concern services on
demand from `context.read<AuthController>().tenant!`.

## Data access

- **Realtime Database** (`firebase_database`). Lists are streamed with
  `watchList()` in `lib/core/rtdb.dart`, which listens to a node's `onValue` and
  parses every child. Ordering and filtering happen in Dart, so no `.indexOn`
  rules are needed. RTDB values arrive as nested `Map<Object?, Object?>`;
  `asMap()` converts them for the models.
- **Dates** are stored as epoch milliseconds (`ServerValue.timestamp` for
  "now"); see `fromMillis` / `toMillis`.
- **Atomic changes** use multi-path `update()` calls:
  - onboarding writes `schools/{id}` and `users/{uid}` together
    (`SchoolService.createSchool`);
  - saving or deleting a student or teacher writes the public record, the
    private record and the index entry together (`StudentService.save` /
    `delete`, `TeacherService.save` / `delete`);
  - the one-time Phase 1 migration moves a whole school in one update
    (`MigrationService.run`);
  - promotion moves students and writes audit records together
    (`PromotionService.promoteClass`);
  - deleting a class removes it and clears `classId` on its students together
    (`ClassService.delete`).
- **Files** go to Cloudinary through `CloudinaryService` (unsigned upload
  preset). Only the returned URL / public id is stored in the database.
  Cloudinary folders mirror the tenant: `schools/{schoolId}/students`,
  `.../teachers`, `.../teachers/documents`, `.../documents`, `.../events`,
  `.../profile`.

## Routing

`go_router`, configured in `lib/app/router.dart`.

- `refreshListenable: authController` re-runs `redirect` on every auth/tenant
  change.
- `redirect` maps `AuthController.status` to a location:
  `unknown -> /splash`, `signedOut -> /login` (`/onboarding` also allowed),
  `needsOnboarding -> /onboarding`, `noAccess -> /no-access`,
  `upgradeRequired -> /upgrade`, `parentPortal -> /parent`,
  `ready -> /dashboard` (when on any of those gate screens).
- The signed-in area is a `StatefulShellRoute.indexedStack` with four branches
  (Dashboard, Students, Teachers, More). Forms and detail screens are top-level
  routes rendered above the shell.

## AuthController status machine

```
          Firebase authStateChanges
                     |
        null --------+-------- User
         |                      |
     signedOut         listen users/{uid}
                          |              |
             no schoolId  |              |  schoolId present
                  needsOnboarding   listen schools/{sid}/members/{uid}
                                         |
                    missing -------------+------------- present (role)
                       |                                     |
                    noAccess             parentStudent? -> parentPortal
                                         profile missing? -> upgradeRequired
                                         otherwise        -> ready
```

The role comes **only** from `members/{uid}`, the same record the database
rules check. The member entry is watched live, so a role change or removal
takes effect immediately. `recheckSchool()` re-runs the last step (used after
the migration).

`onboardNewSchool()` registers the admin account and calls
`SchoolService.createSchool`. The `users/{uid}` write in that multi-path update
starts the chain above, which ends in `ready`, and the router redirects to the
dashboard.

## Roles in the UI

`UserRole` (`lib/models/user_role.dart`) decides which buttons show:

- `canManageSchool` (schoolAdmin, superAdmin): teachers, school profile.
- `canManageStudents` (schoolAdmin, superAdmin, teacher): students, classes,
  documents, announcements, events.
- `AuthController.isAdmin` (schoolAdmin): class promotion, deleting students
  and classes, deleting other people's documents / events / announcements.
- Authors (`authorUid` / `uploadedBy`) may delete their own posts and uploads.

The role comes from `schools/{sid}/members/{uid}`, like the database rules.
Hiding a button is only a convenience - the rules are what actually enforce
access.

## Public and private records

Students and teachers are stored as a public record plus a private record with
the same id (`students` / `studentPrivate`, `teachers` / `teacherPrivate`).
Lists load only the public half. The edit forms load the private half with
`loadPrivate()` and keep **Save** and **Delete** disabled until it has
arrived, so a half-loaded form can never overwrite private data.

## Shared UI helpers

- `widgets/status_views.dart`: loading / error / empty views and
  `StreamListView`.
- `widgets/photo_avatar.dart`: round photo in list rows; tap to open full
  screen.
- `widgets/delete_helpers.dart`: `confirmDelete()` ("Are you sure?") and
  `runDelete()` (try/catch + SnackBar), used by every delete.

## Why services are constructed per-screen

This keeps the code small and avoids a provider tree that has to rebuild when
the tenant changes. If a screen grows heavy (many listeners, caching), promote
its service to a `ChangeNotifierProvider` scoped under the shell.

## Testing

- `flutter test` covers models, roles and route helpers (no Firebase).
- Rule tests against the Realtime Database emulator are a planned follow-up.
- Manual end-to-end steps are in `SETUP.md`.
