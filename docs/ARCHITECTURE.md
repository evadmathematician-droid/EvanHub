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
  `needsOnboarding -> /onboarding`, `ready -> /dashboard` (when in the auth
  area).
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
                          |            |
             no schoolId  |            |  schoolId present
                  needsOnboarding    ready
```

`onboardNewSchool()` registers the admin account and calls
`SchoolService.createSchool`. The `users/{uid}` write in that multi-path update
flips the listener to `ready`, and the router redirects to the dashboard.

## Roles in the UI

`UserRole` (`lib/models/user_role.dart`) decides which buttons show:

- `canManageSchool` (schoolAdmin, superAdmin): teachers, school profile.
- `canManageStudents` (schoolAdmin, superAdmin, teacher): students, classes,
  documents, announcements, events.
- Class promotion: `schoolAdmin` only, matching the database rules.

The UI reads the role from `users/{uid}`; the database rules use
`schools/{sid}/members/{uid}`. Hiding a button is only a convenience - the rules
are what actually enforce access.

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
