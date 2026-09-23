# Multi-tenancy & isolation

## The rule

An account may touch a school's data **only** if
`schools/{schoolId}/members/{uid}` exists, and its `role` there decides what it
may read and write. This is enforced by the Realtime Database rules in
`database.rules.json` (deploy with `firebase deploy --only database`) and
mirrored in the client by `TenantRefs` and `AuthController`.

## Design principles (Phase 1)

1. **No read rule on `schools/{sid}` itself.** In the Realtime Database a read
   granted on a parent can't be revoked on a child. So every branch grants its
   own reads, and sensitive fields live in separate branches
   (`studentPrivate`, `teacherPrivate`) with stricter rules.
2. **Writes only at the record level** (`students/{id}`, never `students`), so
   no single write can replace or wipe a whole list.
3. **Every field is validated**: required fields, length limits, allowed values,
   no unknown fields, and `createdAt` / `addedAt` / `uploadedAt` / `promotedAt`
   must be the server's `now` on creation and can't change afterwards.
4. **Uniqueness is enforced by the database.** A student is valid only if
   `index/admissionNo/{key}` points back to it, and an index key can't be
   claimed while it belongs to someone else. The same applies to teachers and
   `index/nin`. Both are written in the same atomic update as the record.
5. **Deletes must be complete.** A student can't be deleted unless its
   `studentPrivate` record and index entry go in the same update (the same for
   teachers).

## Who can do what

| Branch | Read | Create / edit | Delete |
| --- | --- | --- | --- |
| `ownerUid`, `createdAt` | all members | at school creation only | – |
| `profile` | all members | admin | – |
| `subscription` | all members | at creation only, `free` / `trialing` | – |
| `members/{uid}` | admin: all · member: own entry | admin (owner stays `schoolAdmin`) | admin (not the owner) |
| `classes/{id}` | all members | admin, teacher | admin |
| `events/{id}`, `announcements/{id}` | all members | admin, teacher · edits: author or admin | author or admin |
| `documents/{id}` | all members | admin, teacher | uploader or admin |
| `students/{id}` | admin, teacher | admin, teacher | admin (complete delete only) |
| `studentPrivate/{id}` | admin, teacher | admin, teacher | admin |
| `teachers/{id}` | admin, teacher | admin | admin (complete delete only) |
| `teacherPrivate/{id}` | admin | admin | admin (complete delete only) |
| `promotions/{id}` | admin | admin, append-only | nobody |
| `index/admissionNo/{key}` | admin, teacher | admin, teacher (with the student) | only when the student no longer uses it |
| `index/nin/{nin}` | admin | admin (with the teacher) | only when the teacher no longer uses it |
| `users/{uid}` | that user | that user | that user |

`parentStudent` members can read the profile, subscription, classes, events,
announcements and documents, but no student, teacher or private data. The app
shows them a "Parent portal coming soon" screen.

## Enforcement layers

1. **Database rules** (`database.rules.json`): the table above. The root is
   closed; anything not listed is denied.
2. **Client**:
   - `TenantRefs` (`lib/core/tenant/tenant_refs.dart`) builds every path from
     the signed-in user's `schoolId`, so a query can't name another school.
   - `AuthController` takes the **role only from `members/{uid}`** and follows
     it live. If the entry disappears the app shows "You no longer have access
     to this school"; parents get the parent-portal screen. `users/{uid}.role`
     is not trusted.
   - Buttons are shown only when the rules would allow the action. This is a
     convenience; the rules are the real guard.
3. **Files (Cloudinary)**: uploads are *sorted* into `schools/{schoolId}/...`
   folders, but Cloudinary does **not** check membership. File URLs are public,
   so file isolation relies on the links not being shared.

## Onboarding bootstrap

A new school is created by `SchoolService.createSchool` as **one multi-path
`update()`** from the database root:

| Path written | Rule that allows it |
| --- | --- |
| `schools/{newId}` (`ownerUid`, `createdAt`, `profile`, `subscription`, `members/{uid}`) | `schools/$sid/.write`: the school must not exist yet, `ownerUid == auth.uid`, all five parts present, exactly one member, and that member is the caller as `schoolAdmin`. Each part's `.validate` rules still apply (free trial only, `createdAt == now`, …). |
| `users/{uid}` (`schoolId`, …) | `users/$uid/.write`: the caller owns it |

RTDB checks every path of a multi-path update and commits only if all of them
pass.

## Migrating a pre-Phase-1 school

Old schools keep the profile in `meta` and private fields inside `students` and
`teachers`. After the new rules are deployed:

1. **Back up**: Firebase console → Realtime Database → ⋮ → **Export JSON**.
2. **Deploy** the rules and install the new app build in the same sitting. The
   old app stops working once the rules are live.
3. A **school admin signs in**. `AuthController` sees `profile` is missing and
   opens **Update school data** (`UpgradeScreen`). Teachers and parents see
   "Your school is being upgraded".
4. **Check data** (`MigrationService.prepare`) validates every record against
   the same limits as the rules and lists problems by name: duplicate admission
   numbers or NINs, over-long text, invalid values. Fix them in the Firebase
   console (**Data**, which bypasses the rules), then check again. Students
   whose class no longer exists are unassigned automatically (`classId: ''`).
5. **Update school data** (`MigrationService.run`) writes everything as **one
   atomic update**: `meta` → `profile` (old `meta` and `updatedAt` removed);
   each student and teacher split into public + private records; all
   `index/` entries created. If anything is rejected, nothing changes.
6. Once **every** school has migrated, delete the block marked **TEMPORARY** in
   `database.rules.json` (admin read/delete of `meta` and delete of the old
   `updatedAt`) and deploy again.

## Testing the rules

`docs/RULES_TEST_CHECKLIST.md` has step-by-step Rules Playground tests:
Round A before deploying, Round B after migrating, then an in-app smoke test.

## Known limitations

- Cloudinary uses an unsigned upload preset: anyone with the cloud name and
  preset can upload, and uploaded files (including student photos and teacher
  documents) are public links.
- Deleting a record doesn't delete its Cloudinary files.
- Staff reads download whole lists (students, teachers); fine for one school,
  but may need paging for very large schools.
- There is no in-app member management yet: members are added in the console
  (see `SETUP.md`).
- `superAdmin` has no powers in the rules and isn't an allowed member role.

## Planned: custom claims fast-path

Each rule check looks up `members/{uid}`. To speed this up later:

1. A Cloud Function on `schools/{sid}/members/{uid}` create/delete calls
   `admin.auth().setCustomUserClaims(uid, { schoolId: sid, role })`.
2. The rules also accept `auth.token.schoolId === $sid` as a fast-path.
3. The client refreshes its ID token (`user.getIdToken(true)`) after being
   added.

The membership lookup stays as the authoritative fallback.
