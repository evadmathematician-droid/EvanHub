# Setup

The app is already configured for the Firebase project
**`studio-1123859931-74e89`**: `lib/firebase_options.dart` holds its settings and
`android/app/google-services.json` (git-ignored) holds the Android config. Data
lives in the **Realtime Database**; photos and files go to **Cloudinary**.

## 1. Prerequisites

```bash
flutter --version          # Flutter 3.44+ with Dart >= 3.12
npm install -g firebase-tools
firebase login
```

On this PC Flutter is installed at `E:\APACHE\flutter`. Add
`E:\APACHE\flutter\bin` to your PATH, or call `E:\APACHE\flutter\bin\flutter.bat`
directly.

## 2. Firebase project

In the [Firebase console](https://console.firebase.google.com) for
`studio-1123859931-74e89` (already done for the current project):

1. **Build -> Authentication -> Sign-in method -> Email/Password -> Enable.**
2. **Build -> Realtime Database -> Create database** (start in locked mode).

Firestore and Firebase Storage are **not** used.

### Using a different Firebase project

```bash
dart pub global activate flutterfire_cli
flutterfire configure --project=<your-project-id>
firebase use <your-project-id>      # updates .firebaserc
```

This rewrites `lib/firebase_options.dart` and `android/app/google-services.json`.
Make sure the generated options include a `databaseURL`.

## 3. Deploy the database rules

```bash
firebase deploy --only database
```

This publishes `database.rules.json`, which enforces per-school isolation. Deploy
it before anyone signs in. See `docs/MULTI_TENANCY.md`.

## 4. Cloudinary

Uploads (student/teacher photos, teacher documents, school documents, event
images, school cover and badge) go to the Cloudinary account configured in
`lib/core/cloudinary_config.dart`:

- Cloud name: `yal4fg9h`
- Upload preset: `upload_preset`, which must exist in Cloudinary
  (**Settings -> Upload -> Upload presets**) with signing mode **Unsigned**.

No API secret is shipped in the app. Because the preset is unsigned, restrict it
in Cloudinary: allowed formats, maximum file size, and so on. Files are public
URLs, so anyone with a link can open them. The app cannot delete files from
Cloudinary: deleting a document or replacing a photo removes only the database
entry, so clean up old files from the Cloudinary console.

## 5. Run

```bash
flutter pub get
flutter run
```

- **First launch:** "Register your school" -> fill in the school details and an
  admin account -> you land on the dashboard of a brand-new isolated
  `schools/{id}`.
- Then: create classes (More -> Classes -> "Add standard classes"), register
  students and teachers, post announcements and events, and upload documents.
  Each of these writes only under your school.

## 6. Adding more users to a school

Onboarding creates the first School Admin. There is no in-app invite flow yet,
so add teachers and parents by hand. The Firebase console bypasses the database
rules, which is why this works.

1. **Authentication -> Users -> Add user** (email + password). Copy the new
   user's **UID**.
2. In **Realtime Database -> Data**, add:
   - `schools/{schoolId}/members/{uid}` =
     `{ "role": "teacher", "displayName": "...", "email": "...", "addedBy": "<admin uid>" }`
     (use `"parentStudent"` for a parent/student account)
   - `users/{uid}` =
     `{ "schoolId": "{schoolId}", "role": "teacher", "email": "...", "displayName": "..." }`

The rules check `members/{uid}`; the app uses `users/{uid}` to find the school
and show the right buttons. Keep both roles the same.

## Tests

```bash
flutter analyze
flutter test
```

The tests cover the non-Firebase logic (models, roles, route helpers). Tests for
the database rules (with the Firebase emulator) are a planned follow-up.
