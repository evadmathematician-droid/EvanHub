# Evangelist Global

A multi-tenant school-management app built with Flutter. Every school gets an
isolated `schools/{schoolId}` branch in the **Firebase Realtime Database**;
users sign in with Firebase Authentication and belong to exactly one school.
Database rules (`database.rules.json`) stop any account from reading or writing
another school's data. Photos and files are uploaded to **Cloudinary**.

## Status

| Module | State |
| --- | --- |
| Authentication (email/password, roles) | functional |
| School onboarding (new tenant sign-up) | functional |
| Multi-tenant data layer + database rules | functional - per-branch reads, private student/teacher branches, field validation, unique admission no. / NIN |
| Parent / student portal | placeholder screen ("coming soon") |
| Students (photos, exam records, levels/classes) | functional |
| Teachers (photos, NIN, documents) | functional |
| Classes + standard class ladders | functional |
| Class promotion (next class in the ladder / graduate; admins only) | functional |
| Dashboard (school banner, counts, school events feed) | functional |
| Documents (Cloudinary upload + list) | upload/list/delete; no in-app viewer yet |
| Announcements | post/list/delete; no push notifications yet |
| Member management (inviting teachers/parents) | not built - manual, see `SETUP.md` |

See `docs/` for the data model, architecture and tenancy design.

## First run

The app is already wired to the Firebase project `studio-1123859931-74e89`
(`lib/firebase_options.dart`). Follow [`SETUP.md`](SETUP.md) to deploy the
database rules, set up Cloudinary and run the app.

## Tech

Flutter 3.44 / Dart 3.12 - `provider` + `go_router` - `firebase_core`,
`firebase_auth`, `firebase_database`, `firebase_analytics`,
`firebase_performance` - Cloudinary (unsigned uploads over `http`) -
`cached_network_image`, `file_picker`, `intl`.

```
lib/
  app/        MaterialApp, router, route constants
  core/       Realtime Database helpers, tenant path helper, Cloudinary config
  models/     database record models
  services/   database / Cloudinary access (one per concern)
  state/      AuthController (auth + tenant, drives the router)
  features/   one folder per screen area
  widgets/    shared UI (shell, status views, photo avatar, delete helpers)
  theme/      colors + ThemeData
```
