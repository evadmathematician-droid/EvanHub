# Architecture

## Layers

```
features/*  ── screens (StatelessWidget / small State)
   │  read via context.watch/read
state/AuthController  ── ChangeNotifier: auth + tenant, drives the router
   │
services/*  ── one class per collection/concern; take a TenantRefs
   │
core/tenant/TenantRefs  ── the only place school paths are built
   │
Firebase (Auth, Firestore, Storage)
```

State management is `provider`. `AuthController` is the single app-wide
`ChangeNotifier`; feature screens construct the small per-collection services
on demand from `context.read<AuthController>().tenant!`.

## Routing

`go_router`, configured in `lib/app/router.dart`.

- `refreshListenable: authController` re-runs `redirect` on every auth/tenant
  change.
- `redirect` maps `AuthController.status` to a location:
  `unknown → /splash`, `signedOut → /login` (`/onboarding` also allowed),
  `needsOnboarding → /onboarding`, `ready → /dashboard` (when in the auth area).
- The signed-in area is a `StatefulShellRoute.indexedStack` with four branches
  (Dashboard, Students, Teachers, More). Forms and detail screens are top-level
  routes rendered above the shell.

## AuthController status machine

```
          Firebase authStateChanges
                     │
        null ────────┴──────── User
         │                      │
     signedOut         listen users/{uid}
                          │            │
             no schoolId  │            │  schoolId present
                  needsOnboarding    ready
```

`onboardNewSchool()` registers the admin account and calls
`SchoolService.createSchool`; the `users/{uid}` write inside that batch flips the
listener to `ready`, and the router redirects to the dashboard.

## Why services are constructed per-screen

Keeps the scaffold small and avoids a provider tree that has to rebuild when the
tenant changes. If a screen grows heavy (real-time listeners, caching), promote
its service to a `ChangeNotifierProvider` scoped under the shell.

## Testing

- `flutter test` covers models, roles and route helpers (no Firebase).
- Firestore/Storage rule tests belong in a `@firebase/rules-unit-testing` suite
  run against the emulator — a planned follow-up, not yet in the repo.
- Manual end-to-end verification is in `SETUP.md`.
