# Data model

Firebase **Realtime Database**. There are two top-level nodes: `users` (a
per-account tenant binding) and `schools` (one branch per tenant, with
everything else nested beneath it). Keys like `{schoolId}` and `{studentId}` are
RTDB push IDs. Dates are epoch milliseconds. Files are not stored in the
database; records hold Cloudinary URLs.

Since Phase 1, sensitive fields live in separate branches so they can have
stricter read rules. The access for each branch is shown with it below; the
rules themselves are in `database.rules.json` and explained in
`MULTI_TENANCY.md`.

```
users/{uid}
schools/{schoolId}/
├── ownerUid, createdAt
├── profile/            (was "meta" before Phase 1)
├── subscription/
├── members/{uid}
├── classes/{classId}
├── events/{eventId}
├── announcements/{id}
├── documents/{docId}
├── students/{studentId}         ┐ same id
├── studentPrivate/{studentId}   ┘
├── teachers/{teacherId}         ┐ same id
├── teacherPrivate/{teacherId}   ┘
├── promotions/{id}
└── index/
    ├── admissionNo/{key} → studentId
    └── nin/{nin}         → teacherId
```

## `users/{uid}`

Read at launch by `AuthController` to find which school an account belongs to.
Only that user may read or write it.

| field | type | notes |
| --- | --- | --- |
| `schoolId` | string \| missing | missing => account not linked yet => onboarding |
| `email`, `displayName` | string | |
| `role` | string | a hint only; the app takes the role from `members/{uid}` |
| `createdAt` / `updatedAt` | number (ms) | |

## `schools/{schoolId}`

### `ownerUid`, `createdAt`
Read by all members. Set once when the school is created and never changed. The
owner can't be removed from `members` or demoted.

### `profile` (all members read · admin writes)
`{ name, logoUrl, coverUrl, address, phone, email, updatedAt }`. `logoUrl` is
the badge and `coverUrl` the dashboard banner (Cloudinary `https://` links).
`name` is required, 1-120 characters.

### `subscription` (all members read · no client writes)
`{ plan, status, trialEndsAt }`. It is written only when the school is created,
and then only as `plan: "free"`, `status: "trialing"`.

### `members/{uid}` (admin reads all · each member reads own · admin writes)
`{ role, displayName, email, addedBy, addedAt }` - **the source of truth for
access**. `role` is `schoolAdmin` | `teacher` | `parentStudent`.

### `classes/{classId}` (all members read · admin + teacher write · admin deletes)
`{ name, level, stage, academicYear, classTeacherId, createdAt }`

- `level` (required): `pre_primary` | `primary` | `secondary`
- `stage` (secondary only): `junior` | `senior`
- Standard ladders (`SchoolLevel.standardClasses`): Nursery 1, Nursery 2,
  Pre 1, Pre 2 | Class 1 to Class 6 | JSS 1 to JSS 3, SSS 1 to SSS 3. Section
  names like "JSS 1 A" count as JSS 1.

### `events/{eventId}` · `announcements/{id}` (all members read · admin + teacher create · author or admin edit/delete)
- events: `{ title, text, imageUrl, authorUid, createdAt }`
- announcements: `{ title, body, audience, authorUid, createdAt }`. `audience` is
  `"school"` or an existing `classId`.

### `documents/{docId}` (all members read · admin + teacher upload · uploader or admin delete)
`{ title, category, storagePath, downloadUrl, sizeBytes, uploadedBy, uploadedAt }`

`storagePath` is the Cloudinary public id; `downloadUrl` the Cloudinary URL.

### `students/{studentId}` (admin + teacher read/write · admin deletes)
`{ firstName, middleName, lastName, gender, level, classId, department,
admissionNo, admissionYear, status, photoUrl, createdAt }`

- required: `firstName`, `lastName`, `admissionNo`, `status`, `createdAt`
- `gender`: `Male` | `Female` | `''`
- `classId`: an existing class, or `''` when unassigned (for example after the
  class was deleted); removed when the student graduates
- `department` (SSS only): `Science` | `Commercial` | `Arts`
- `admissionNo`: 1-30 characters, unique per school (enforced by
  `index/admissionNo`)
- `status`: `active` | `graduated` | `inactive` | `transferred`

### `studentPrivate/{studentId}` (admin + teacher read/write · admin deletes)
`{ dob, address, guardianName, guardianPhone, npseId, npseYear, beceId,
beceYear, wassceId, wassceYear }`. Exam years are 4 digits or `''`.

### `teachers/{teacherId}` (admin + teacher read · admin writes)
`{ firstName, lastName, gender, subjects[], level, stream, employmentType,
status, photoUrl, linkedUid, createdAt }`

- `level`: `JSS` | `SSS` | `BOTH` | `''`; `stream`: `Science` | `Commercial` |
  `Arts` | `''`
- `employmentType`: `full_time` | `part_time` | `contract`; `status`:
  `active` | `inactive`
- `linkedUid`: meant to link the HR record to a `members/{uid}` login (not set
  by the app yet)

### `teacherPrivate/{teacherId}` (admin only)
`{ nin, isPincoded, pincode, maritalStatus, dob, email, phone, address,
qualification, experience, documents[] }`

- `nin`: 8 characters A-Z (no I or O) / 0-9, or `''` for older records; unique
  per school (enforced by `index/nin`)
- `pincode`: 6 digits when `isPincoded`
- `documents[]`: `{ title, url, fileName, sizeBytes }` (Cloudinary links)

### `promotions/{id}` (admin only · append-only)
`{ studentId, fromClassId, toClassId, academicYear, promotedBy, promotedAt }` -
one audit record per promoted student. `toClassId` is missing when the student
graduated. Records can't be edited or deleted.

### `index/admissionNo/{key}` → studentId (admin + teacher read)
`key` is the admission number lower-cased, with `%` `.` `#` `$` `[` `]` `/`
replaced by `%25` `%2e` `%23` `%24` `%5b` `%5d` `%2f` (`indexKey()` in
`lib/core/rtdb.dart`; the rules re-check it). So `EG/2024/001` →
`eg%2f2024%2f001`, and `ABC1` and `abc1` count as the same number.

### `index/nin/{nin}` → teacherId (admin only)
Keyed by the NIN itself (it only contains A-Z and 0-9).

## Saving and deleting (always atomic)

| Action | One multi-path update from `schools/{schoolId}` |
| --- | --- |
| Save student | `students/{id}` + `studentPrivate/{id}` + `index/admissionNo/{key}`, and `index/admissionNo/{oldKey}: null` if the number changed |
| Delete student | `students/{id}`, `studentPrivate/{id}` and `index/admissionNo/{key}` all `null` |
| Save teacher | `teachers/{id}` + `teacherPrivate/{id}` + `index/nin/{nin}`, and `index/nin/{oldNin}: null` if the NIN changed |
| Delete teacher | `teachers/{id}`, `teacherPrivate/{id}` and `index/nin/{nin}` all `null` |
| Delete class | `classes/{id}: null` and `students/{sid}/classId: ''` for each of its students |
| Promote class | `students/{sid}/classId` (+ `status: graduated`), BECE into `studentPrivate/{sid}`, and one `promotions/{new}` per student |

The rules reject a save or delete that leaves out any of these parts.

## Cloudinary folders

| folder | contents |
| --- | --- |
| `schools/{schoolId}/students` | student photos |
| `schools/{schoolId}/teachers` | teacher photos |
| `schools/{schoolId}/teachers/documents` | teacher documents |
| `schools/{schoolId}/documents` | school documents |
| `schools/{schoolId}/events` | event images |
| `schools/{schoolId}/profile` | school cover photo and badge |

## Indexes

No `.indexOn` entries are needed: lists are loaded whole and sorted/filtered in
Dart. (`index/` above is a uniqueness index, not a query index.)

## Pre-Phase-1 layout (migration)

Before Phase 1 the profile lived at `meta` (with `updatedAt` beside it), and
all private student and teacher fields were inside `students/{id}` and
`teachers/{id}`. The app's one-time **Update school data** screen
(`MigrationService`) moves an old school to this layout; see
`MULTI_TENANCY.md`.
