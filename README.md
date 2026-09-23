# Evangelist Global

A multi-tenant school-management app. Every school gets an isolated
`schools/{schoolId}` workspace in Cloud Firestore; users authenticate with
Firebase Authentication and belong to exactly one school. Security Rules enforce
that no account can read or write another school's data.

## Status

| Module | State |
| --- | --- |
| Authentication (email/password, roles) | functional |
| School onboarding (new tenant sign-up) | functional |
| Multi-tenant data layer + Security Rules | functional |
| Student / Class management (+ promotion) | basic CRUD |
| Teacher management | basic CRUD |
| Documents (per-tenant file storage) | basic CRUD |
| Dashboard / statistics | functional |
| Notifications / Announcements | basic CRUD (no push yet) |

See `docs/` for the data model, architecture and tenancy design, and the
"Out of scope / next steps" list.

## First run

Firebase is **not** configured in this repo — no keys are committed. Follow
[`SETUP.md`](SETUP.md): `flutterfire configure`, enable the Email/Password
provider, deploy the rules, then `flutter run`.

## Tech

Flutter · `provider` + `go_router` · `firebase_core` / `firebase_auth` /
`cloud_firestore` / `firebase_storage`.

```
lib/
  app/        MaterialApp, router, route constants
  core/       tenant path helpers
  models/     Firestore document models
  services/   Firebase access (one per collection/concern)
  state/      AuthController (auth + tenant, drives the router)
  features/   one folder per screen area
  widgets/    shared UI (shell, status views)
  theme/      colors + ThemeData
```
