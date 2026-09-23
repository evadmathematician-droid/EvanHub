# Setup

This repo ships **no** Firebase credentials. `lib/firebase_options.dart` contains
placeholders and every getter throws until you run `flutterfire configure`.

## 1. Prerequisites

```bash
flutter --version          # Flutter with Dart >= 3.12
dart pub global activate flutterfire_cli
npm install -g firebase-tools
firebase login
```

## 2. Create the Firebase project

1. In the [Firebase console](https://console.firebase.google.com) create a
   project (e.g. `evangelist-global`).
2. **Build → Authentication → Sign-in method → Email/Password → Enable.**
3. **Build → Firestore Database → Create database** (start in production mode).
4. **Build → Storage → Get started.**

## 3. Wire the app to the project

From the repo root:

```bash
flutter pub get
flutterfire configure --project=<your-project-id>
```

`flutterfire configure` overwrites `lib/firebase_options.dart` with real values
and writes `android/app/google-services.json` (git-ignored). Pick at least the
Android and (optionally) iOS/web platforms.

Then point the Firebase CLI at the same project:

```bash
# edit .firebaserc — replace REPLACE_WITH_FIREBASE_PROJECT_ID with <your-project-id>
firebase use <your-project-id>
```

## 4. Deploy the security rules

```bash
firebase deploy --only firestore:rules,firestore:indexes,storage
```

`firestore.rules` and `storage.rules` enforce per-school isolation — deploy them
before anyone signs in. See `docs/MULTI_TENANCY.md`.

## 5. Run

```bash
flutter run
```

- **First launch:** "Register your school" → fill the school details and an admin
  account → you land on the dashboard for a brand-new isolated `schools/{id}`.
- Add a class, a student, a teacher, an announcement, upload a document — each
  writes under your school only.

## 6. Adding more users to a school

This scaffold creates the first School Admin during onboarding. Teachers and
parents are added later (module to be built out):

- **Now:** create the Firebase Auth user (console or app), then add
  `schools/{schoolId}/members/{uid}` with `role: "teacher"` / `"parentStudent"`
  and set `users/{uid}.schoolId` to the same school. The rules already gate all
  writes on that membership doc.
- **Planned:** an in-app "Invite member" flow + a Cloud Function that mints a
  `schoolId` custom claim (see `docs/MULTI_TENANCY.md`).

## Tests

```bash
flutter analyze
flutter test
```

The tests cover the non-Firebase logic (models, roles, route helpers).
Rule tests via the emulator suite are a planned follow-up.
