# Multi-tenancy & isolation

## The rule

An account may touch data for a school **only** if
`schools/{schoolId}/members/{uid}` exists. The role on that membership record
decides what it may write. This is enforced by the Realtime Database rules in
`database.rules.json` (deploy with `firebase deploy --only database`) and
mirrored in the client by `TenantRefs`.

## Enforcement layers

1. **Database rules** (`database.rules.json`)
   - The root is closed (`.read` / `.write` false); only `users` and `schools`
     are reachable.
   - `users/{uid}`: read/write only by that user.
   - `schools/{sid}`: readable when `members/{auth.uid}` exists. The read rule
     sits on the whole school branch, so every member can read everything in
     their own school.
   - Writes, by node:

     | node | who may write |
     | --- | --- |
     | `meta`, `updatedAt`, `members`, `teachers`, `promotions` | `schoolAdmin` |
     | `classes`, `students`, `documents`, `events`, `announcements` | `schoolAdmin`, `teacher` |
     | `ownerUid`, `subscription`, `createdAt` | only at creation (see below) |

   - `ownerUid` can never change once set, and an existing school can't be
     overwritten or deleted.
2. **Client** (`lib/core/tenant/tenant_refs.dart`): services never build
   `schools/...` strings. They receive a `TenantRefs` created from
   `AuthController.schoolId`, so a query can't name another school's path.
3. **Files** (Cloudinary): uploads are *sorted* into
   `schools/{schoolId}/...` folders, but Cloudinary does **not** check
   membership. Files are public URLs, so tenant isolation for files relies on
   the URLs not being shared.

## Onboarding bootstrap

A new school is created by `SchoolService.createSchool` as **one multi-path
`update()`** from the database root:

| path written | rule that allows it |
| --- | --- |
| `schools/{newId}` (whole branch: `ownerUid`, `meta`, `subscription`, `createdAt`, `members/{uid}`) | `schools/$sid/.write`: the school must not exist yet, `ownerUid == auth.uid`, and `members/{auth.uid}/role == 'schoolAdmin'` in the new data |
| `users/{uid}` (`schoolId`, `role`, ...) | `users/$uid/.write`: the caller owns it |

RTDB checks every path of a multi-path update, and the update commits only if
all of them pass. The school is written as a single node, so the rule can check
the owner and their admin membership together.

## Roles

| role | can do |
| --- | --- |
| `schoolAdmin` | full control of one school: profile, members, teachers, promotions, and everything a teacher can |
| `teacher` | read everything; write students, classes, documents, events, announcements |
| `parentStudent` | read-only |
| `superAdmin` | reserved for a future multi-school mode. Modelled (`UserRole.superAdmin`) but the rules give it no special access, and no screen targets it |

The app shows or hides buttons using `users/{uid}.role`. Real access is decided
by `members/{uid}.role` in the rules, so keep the two in sync when adding users
(see `SETUP.md`, "Adding more users to a school").

## Known limitations

- Any member (including `parentStudent`) can read all of their school's data,
  such as student guardian phones and teacher NINs.
- There are no `.validate` rules, so field shapes and types are not checked.
- Teachers can overwrite or delete whole nodes they can write
  (e.g. all of `students`).
- `subscription` is written by the client at creation. Billing must move to a
  server before it can be trusted.
- Cloudinary uses an unsigned preset: anyone with the cloud name and preset can
  upload, and uploaded files are public.

## Planned: custom claims fast-path

Each rule check currently looks up `members/{uid}`. To speed this up:

1. A Cloud Function on `schools/{sid}/members/{uid}` create/delete calls
   `admin.auth().setCustomUserClaims(uid, { schoolId: sid, role })`.
2. The rules also accept
   `auth.token.schoolId === $sid` as a fast-path.
3. The client refreshes its ID token (`user.getIdToken(true)`) after being
   added.

The membership lookup stays as the authoritative fallback.
