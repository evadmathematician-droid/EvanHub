# Data model

Firebase **Realtime Database**. There are two top-level nodes: `users` (a
per-account tenant binding) and `schools` (one branch per tenant, with
everything else nested beneath it). Keys like `{schoolId}` and `{studentId}` are
RTDB push IDs. Dates are epoch milliseconds. Files are not stored in the
database; records hold Cloudinary URLs.

## `users/{uid}`

Read at launch by `AuthController` to find which school an account belongs to.
Only that user may read or write it.

| field | type | notes |
| --- | --- | --- |
| `email` | string | |
| `displayName` | string | |
| `schoolId` | string \| missing | missing => account not linked yet => onboarding |
| `role` | string | `schoolAdmin` \| `teacher` \| `parentStudent` \| `superAdmin` (drives the UI only) |
| `createdAt` / `updatedAt` | number (ms) | |

## `schools/{schoolId}`

| field | type | notes |
| --- | --- | --- |
| `ownerUid` | string | set at creation, cannot change |
| `meta` | object | `{ name, logoUrl, coverUrl, address, phone, email }` - `logoUrl` is the badge, `coverUrl` the dashboard banner photo |
| `subscription` | object | `{ plan, status, trialEndsAt }` - written once at creation (`free` / `trialing`); display only |
| `createdAt` / `updatedAt` | number (ms) | |

### `schools/{schoolId}/members/{uid}`

The membership record and **the source of truth for access control**. If it
exists, the user can read the school; its `role` decides what they can write.

`{ role, displayName, email, addedBy, addedAt }`

### `schools/{schoolId}/classes/{classId}`

`{ name, level, stage, academicYear, classTeacherId, createdAt }`

- `level`: `pre_primary` | `primary` | `secondary`
- `stage` (secondary only): `junior` | `senior`
- Standard ladders (`SchoolLevel.standardClasses`):
  Nursery 1, Nursery 2, Pre 1, Pre 2 | Class 1 to Class 6 |
  JSS 1 to JSS 3, SSS 1 to SSS 3. Section names like "JSS 1 A" count as JSS 1.

### `schools/{schoolId}/students/{studentId}`

`{ firstName, middleName, lastName, dob, gender, level, classId, department,
admissionNo, admissionYear, address, guardianName, guardianPhone,
npseId, npseYear, beceId, beceYear, wassceId, wassceYear,
photoUrl, status, createdAt }`

- `status`: `active` | `graduated` | `inactive` | `transferred`
- `classId`: `''` when unassigned (for example after the class was deleted)
- `department` (SSS only): `Science` | `Commercial` | `Arts`
- `admissionNo` is unique per school (checked by the app, not the rules)
- `photoUrl`: Cloudinary URL

### `schools/{schoolId}/teachers/{teacherId}`

`{ firstName, lastName, email, phone, subjects[], employmentType, status,
linkedUid, createdAt, nin, gender, maritalStatus, dob, address, isPincoded,
pincode, qualification, experience, level, stream, photoUrl,
documents[] }`

- `employmentType`: `full_time` | `part_time` | `contract`
- `nin`: 8 characters, A-Z (no I or O) and 0-9, unique per school (checked by
  the app)
- `level`: `JSS` | `SSS` | `BOTH`; `stream` (SSS/BOTH): `Science` |
  `Commercial` | `Arts`
- `documents[]`: `{ title, url, fileName, sizeBytes }` (Cloudinary URLs)
- `linkedUid`: meant to link the HR record to a `members/{uid}` login (not set
  by the app yet)

### `schools/{schoolId}/documents/{docId}`

`{ title, category, storagePath, downloadUrl, sizeBytes, uploadedBy, uploadedAt }`

`storagePath` is the Cloudinary public id; `downloadUrl` the Cloudinary URL.

### `schools/{schoolId}/events/{eventId}`

`{ title, text, imageUrl, authorUid, createdAt }` - the dashboard's "School
events" feed.

### `schools/{schoolId}/announcements/{id}`

`{ title, body, audience, authorUid, createdAt }`

`audience` is the sentinel `"school"` or a specific `classId`.

### `schools/{schoolId}/promotions/{id}`

An audit trail written by the class-promotion flow, one record per student.

`{ studentId, fromClassId, toClassId, academicYear, promotedBy, promotedAt }`

`toClassId` is `null` when the student graduated.

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

None. Lists are loaded whole and sorted/filtered in Dart, so the rules need no
`.indexOn` entries.
