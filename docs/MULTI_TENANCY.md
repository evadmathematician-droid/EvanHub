# Multi-tenancy & isolation

## The rule

An account may touch data for a school **only** if
`schools/{schoolId}/members/{uid}` exists. Role on that membership document
decides what it may write. This is enforced in `firestore.rules` and
`storage.rules`, and mirrored in the client by `TenantRefs`.

## Enforcement layers

1. **Firestore rules** (`firestore.rules`) — every `schools/{sid}/**` path checks
   `exists(schools/$(sid)/members/$(uid))`. Writes to `teachers`, `students`,
   etc. additionally check `get(...).data.role`. There is no catch-all `allow`;
   unlisted paths are denied.
2. **Storage rules** (`storage.rules`) — `firestore.exists(...)` against the same
   membership doc gates every file under `schools/{sid}/`.
3. **Client** (`lib/core/tenant/tenant_refs.dart`) — services never build
   `schools/...` strings. They receive a `TenantRefs` created from
   `AuthController.schoolId`, so a query is structurally incapable of naming
   another tenant.

## Onboarding bootstrap

A new school is created by `SchoolService.createSchool` as one `WriteBatch`:

| write | rule that passes it |
| --- | --- |
| `schools/{newId}` with `ownerUid == request.auth.uid` | `schools` create rule (new id, owner is caller) |
| `schools/{newId}/members/{uid}` with `role == 'schoolAdmin'` | members create rule: caller is `muid` **and** `getAfter(school).ownerUid` is the caller |
| `users/{uid}` with `schoolId == newId` | `users` rule: caller owns the doc |

Batched writes are evaluated independently and `get()`/`exists()` see only
pre-batch state, so the membership rule uses **`getAfter()`** — the school
document as it will exist once the batch commits. The school's `ownerUid` (not a
"is this the first member?" list query, which rules cannot express) is what
authorises the first membership.

## Roles

`schoolAdmin` — full control of one school, manages members.
`teacher` — read all, write students / classes / documents / announcements.
`parentStudent` — read-only.
`superAdmin` — reserved for a future franchise/network mode where one account
spans several schools. Modelled today (`UserRole.superAdmin`,
`role.canManageSchool`) but no screen targets it and the rules treat it like any
other non-member for schools it has no membership in. To enable it later, add a
`superAdmins/{uid}` doc check to the rule helpers.

## Planned: custom claims fast-path

`isMember()` currently does a `get()` per rule evaluation. To cut that:

1. A Cloud Function on `schools/{sid}/members/{uid}` create/delete calls
   `admin.auth().setCustomUserClaims(uid, { schoolId: sid, role })`.
2. Add to the rule helper:
   `request.auth.token.schoolId == sid || exists(memberPath(sid))`.
3. The client refreshes the ID token (`user.getIdToken(true)`) after onboarding.

The lookup path stays as the authoritative fallback while claims propagate.
