# Data model

Cloud Firestore. Two top-level collections: `users` (per-account tenant binding)
and `schools` (one document per tenant, everything else nested beneath it).

## `users/{uid}`

Read at launch by `AuthController` to discover which school an account belongs to.
The user may read/write only their own document.

| field | type | notes |
| --- | --- | --- |
| `email` | string | |
| `displayName` | string | |
| `schoolId` | string \| null | null ⇒ account not yet linked ⇒ onboarding |
| `role` | string | `schoolAdmin` \| `teacher` \| `parentStudent` \| `superAdmin` |
| `createdAt` / `updatedAt` | timestamp | |

## `schools/{schoolId}`

| field | type | notes |
| --- | --- | --- |
| `ownerUid` | string | set at creation, immutable; bootstraps the first admin membership |
| `meta` | map | `{ name, logoUrl, address, phone, email }` |
| `subscription` | map | `{ plan, status, trialEndsAt }` — defaults to free / trialing |
| `createdAt` | timestamp | |

### `schools/{schoolId}/members/{uid}`

The membership record — **the source of truth for access control**. Its mere
existence grants read access to the school; its `role` gates writes.

`{ role, displayName, email, addedBy, addedAt }`

### `schools/{schoolId}/classes/{classId}`

`{ name, level, academicYear, classTeacherId?, createdAt }`

### `schools/{schoolId}/students/{studentId}`

`{ firstName, lastName, dob?, gender, classId?, admissionNo, guardianName,
guardianPhone, status, createdAt }`

`status`: `active` \| `inactive` \| `graduated` \| `transferred`.

### `schools/{schoolId}/teachers/{teacherId}`

`{ firstName, lastName, email, phone, subjects[], employmentType, status,
linkedUid?, createdAt }`

`linkedUid` connects an HR record to a `members/{uid}` login once the teacher has
an account.

### `schools/{schoolId}/documents/{docId}`

`{ title, category, storagePath, downloadUrl, sizeBytes, uploadedBy, uploadedAt }`

Bytes live in Storage at `schools/{schoolId}/documents/{fileName}`.

### `schools/{schoolId}/announcements/{id}`

`{ title, body, audience, authorUid, createdAt }`

`audience` is the sentinel `"school"` or a specific `classId`.

### `schools/{schoolId}/promotions/{id}`

Audit trail written by the class-promotion flow.

`{ studentId, fromClassId?, toClassId?, academicYear, promotedBy, promotedAt }`

## Indexes

`firestore.indexes.json` declares composite indexes for
`students(classId, lastName)` and `announcements(audience, createdAt desc)`.
Deploy with `firebase deploy --only firestore:indexes`.
