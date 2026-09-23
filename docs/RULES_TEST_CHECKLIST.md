# Rules test checklist (Firebase Rules Playground)

Manual tests for `database.rules.json`. The Rules Playground **never changes
data**: it only answers "Allowed" or "Denied".

## How to run a test

1. Firebase console → project `studio-1123859931-74e89` → **Realtime Database**
   → **Rules** tab.
2. Paste the contents of `database.rules.json` into the editor. For Round A,
   **do not click Publish**: the Playground tests the rules in the editor.
3. Click **Rules Playground**. For each row below set:
   - **Simulation type**: `read`, `set` or `update` (a remove is a `set` with
     data `null`);
   - **Location**: the path, with the placeholders replaced;
   - **Data** (set/update): the JSON shown;
   - **Authenticated**: on, provider *Custom*, **UID** as given (off for
     "nobody");
   - then **Run** and compare with *Expected*.
4. Tick the box. Any row that doesn't match the expected result is a bug: stop
   and report it.

`{".sv": "timestamp"}` means "server time now". Rules require it for
`createdAt`, `addedAt`, `uploadedAt` and `promotedAt` on new records.

## Setup (placeholders)

Look these up in **Realtime Database → Data**:

| Placeholder | What it is |
| --- | --- |
| `SID` | your school id (the key under `schools/`) |
| `ADMIN` | the school owner's UID (`schools/SID/ownerUid`) |
| `S1` | the key of any existing student under `schools/SID/students` |
| `C1` | the key of any existing class under `schools/SID/classes` |

The Playground only needs a UID to be *listed* as a member; no real login is
required. Add two **temporary** test members by hand in **Data** (the console
bypasses the rules):

- `schools/SID/members/pg-teacher` = `{ "role": "teacher" }`
- `schools/SID/members/pg-parent` = `{ "role": "parentStudent" }`

`pg-outsider` is a UID that is **not** a member. **Delete the two test members
when you're finished.**

---

## Round A: before deploying (new rules in the editor, old data)

### Reads

| # | UID | Type | Location | Expected | ✓ |
| --- | --- | --- | --- | --- | --- |
| A1 | *(nobody)* | read | `/schools/SID/profile` | Denied | ☐ |
| A2 | `pg-outsider` | read | `/schools/SID/profile` | Denied | ☐ |
| A3 | `pg-parent` | read | `/schools/SID/profile` | Allowed | ☐ |
| A4 | `pg-parent` | read | `/schools/SID/classes` | Allowed | ☐ |
| A5 | `pg-parent` | read | `/schools/SID/students` | **Denied** | ☐ |
| A6 | `pg-parent` | read | `/schools/SID/studentPrivate` | **Denied** | ☐ |
| A7 | `pg-teacher` | read | `/schools/SID/students` | Allowed | ☐ |
| A8 | `pg-teacher` | read | `/schools/SID/studentPrivate` | Allowed | ☐ |
| A9 | `pg-teacher` | read | `/schools/SID/teachers` | Allowed | ☐ |
| A10 | `pg-teacher` | read | `/schools/SID/teacherPrivate` | **Denied** | ☐ |
| A11 | `pg-teacher` | read | `/schools/SID/promotions` | **Denied** | ☐ |
| A12 | `pg-teacher` | read | `/schools/SID/index/nin` | **Denied** | ☐ |
| A13 | `pg-teacher` | read | `/schools/SID/members` | **Denied** | ☐ |
| A14 | `pg-teacher` | read | `/schools/SID/members/pg-teacher` | Allowed (own entry) | ☐ |
| A15 | `pg-teacher` | read | `/schools/SID/members/ADMIN` | **Denied** | ☐ |
| A16 | `ADMIN` | read | `/schools/SID` (whole school) | **Denied** | ☐ |
| A17 | `ADMIN` | read | `/schools/SID/teacherPrivate` | Allowed | ☐ |
| A18 | `ADMIN` | read | `/schools/SID/members` | Allowed | ☐ |
| A19 | `ADMIN` | read | `/schools/SID/meta` | Allowed (temporary, migration) | ☐ |
| A20 | `pg-teacher` | read | `/schools/SID/meta` | Denied | ☐ |
| A21 | `pg-teacher` | read | `/users/ADMIN` | Denied | ☐ |

### Whole-list writes and deletes

| # | UID | Type | Location | Data | Expected | ✓ |
| --- | --- | --- | --- | --- | --- | --- |
| A22 | `pg-teacher` | set | `/schools/SID/students` | `{}` | **Denied** (whole list) | ☐ |
| A23 | `ADMIN` | set | `/schools/SID/students` | `null` | **Denied** (whole list) | ☐ |
| A24 | `ADMIN` | set | `/schools/SID/classes` | `null` | **Denied** (whole list) | ☐ |
| A25 | `ADMIN` | set | `/schools/SID` | `null` | **Denied** (whole school) | ☐ |
| A26 | `pg-teacher` | set | `/schools/SID/students/S1` | `null` | **Denied** (only admins delete students) | ☐ |
| A27 | `pg-teacher` | set | `/schools/SID/classes/C1` | `null` | **Denied** (only admins delete classes) | ☐ |

### Profile, subscription, members

| # | UID | Type | Location | Data | Expected | ✓ |
| --- | --- | --- | --- | --- | --- | --- |
| A28 | `ADMIN` | set | `/schools/SID/profile/name` | `"New name"` | Allowed | ☐ |
| A29 | `ADMIN` | set | `/schools/SID/profile/name` | `""` | **Denied** (empty name) | ☐ |
| A30 | `pg-teacher` | set | `/schools/SID/profile/name` | `"New name"` | **Denied** | ☐ |
| A31 | `ADMIN` | set | `/schools/SID/subscription/plan` | `"premium"` | **Denied** | ☐ |
| A32 | `pg-teacher` | set | `/schools/SID/members/pg-teacher/role` | `"schoolAdmin"` | **Denied** (self-promotion) | ☐ |
| A33 | `ADMIN` | set | `/schools/SID/members/ADMIN` | `null` | **Denied** (owner can't be removed) | ☐ |
| A34 | `ADMIN` | set | `/schools/SID/members/ADMIN/role` | `"teacher"` | **Denied** (owner can't be demoted) | ☐ |
| A35 | `ADMIN` | set | `/schools/SID/members/pg-new` | `{"role": "teacher", "addedBy": "ADMIN", "addedAt": {".sv": "timestamp"}}` | Allowed | ☐ |
| A36 | `ADMIN` | set | `/schools/SID/members/pg-new` | `{"role": "superAdmin"}` | **Denied** (role not allowed) | ☐ |
| A37 | `ADMIN` | set | `/schools/SID/meta` | `null` | Allowed (temporary, migration) | ☐ |
| A38 | `ADMIN` | set | `/schools/SID/meta/name` | `"x"` | **Denied** (meta can only be deleted) | ☐ |

In A35, replace `ADMIN` inside the data with the real UID too.

### Creating records (validation + index)

All rows use **type `update`**, **location `/schools/SID`**, and **UID
`pg-teacher`** unless stated.

| # | Data | Expected | ✓ |
| --- | --- | --- | --- |
| A39 | see **J1** | Allowed (student + private + index together) | ☐ |
| A40 | J1 **without** the `index/admissionNo/...` line | **Denied** (no index entry) | ☐ |
| A41 | J1 with the index value changed to `"SOMEONE_ELSE"` | **Denied** (index points elsewhere) | ☐ |
| A42 | J1 with `"gender": "male"` added to the student | **Denied** (must be `Male`/`Female`) | ☐ |
| A43 | J1 with `"admissionYear": "24"` added to the student | **Denied** (4 digits) | ☐ |
| A44 | J1 with `"nickname": "x"` added to the student | **Denied** (unknown field) | ☐ |
| A45 | J1 with `"createdAt": 123` | **Denied** (must be server time) | ☐ |
| A46 | `{"classes/pgc1": {"name": "Test", "level": "primary", "createdAt": {".sv": "timestamp"}}}` | Allowed | ☐ |
| A47 | `{"classes/pgc1": {"name": "Test", "level": "college", "createdAt": {".sv": "timestamp"}}}` | **Denied** (level) | ☐ |
| A48 | `{"events/pge1": {"title": "Sports day", "authorUid": "pg-teacher", "createdAt": {".sv": "timestamp"}}}` | Allowed | ☐ |
| A49 | as A48 with `"authorUid": "ADMIN"` | **Denied** (can't post as someone else) | ☐ |
| A50 | see **J2** (a teacher record) | **Denied** (teachers are admin-only) | ☐ |
| A51 | J2 with UID **`ADMIN`** | Allowed | ☐ |
| A52 | `{"promotions/pgp1": {"studentId": "S1", "fromClassId": "C1", "academicYear": "2026", "promotedBy": "pg-teacher", "promotedAt": {".sv": "timestamp"}}}` | **Denied** (promotions are admin-only) | ☐ |

**J1** (new student, admission number `PG-TEST-1` → index key `pg-test-1`):

```json
{
  "students/pgs1": {
    "firstName": "Test", "lastName": "Pupil", "admissionNo": "PG-TEST-1",
    "status": "active", "createdAt": {".sv": "timestamp"}
  },
  "studentPrivate/pgs1": { "guardianName": "Test Guardian", "beceYear": "2025" },
  "index/admissionNo/pg-test-1": "pgs1"
}
```

**J2** (new teacher with NIN `ZZ99ZZ99`):

```json
{
  "teachers/pgt1": {
    "firstName": "Test", "lastName": "Teacher", "status": "active",
    "employmentType": "full_time", "createdAt": {".sv": "timestamp"}
  },
  "teacherPrivate/pgt1": { "nin": "ZZ99ZZ99" },
  "index/nin/ZZ99ZZ99": "pgt1"
}
```

### Creating a new school (onboarding)

UID `pg-newowner`, type **set**, location **`/schools/pgschool`**.

| # | Data | Expected | ✓ |
| --- | --- | --- | --- |
| A53 | see **J3** | Allowed | ☐ |
| A54 | J3 with `"plan": "premium"` | **Denied** (free trial only) | ☐ |
| A55 | J3 with a second member `"pg-other": {"role": "teacher"}` | **Denied** (creator must be the only member) | ☐ |
| A56 | J3 with `"ownerUid": "someone-else"` | **Denied** | ☐ |
| A57 | J3, but location `/schools/SID` (your real school) | **Denied** (existing school) | ☐ |

**J3**:

```json
{
  "ownerUid": "pg-newowner",
  "createdAt": {".sv": "timestamp"},
  "profile": { "name": "Test School" },
  "subscription": { "plan": "free", "status": "trialing" },
  "members": {
    "pg-newowner": {
      "role": "schoolAdmin", "addedBy": "pg-newowner",
      "addedAt": {".sv": "timestamp"}
    }
  }
}
```

---

## Round B: after deploying and running the migration

Publish the rules, install the new app, sign in as the admin and run **Update
school data** first. These rows need the `index/` entries the migration
creates. Look up:

| Placeholder | What it is |
| --- | --- |
| `S1` | an existing student id |
| `NO1` | S1's admission number |
| `KEY1` | S1's index key: `NO1` lower-cased, with `/` → `%2f`, `.` → `%2e` (see `index/admissionNo` in Data) |
| `T1` / `NIN1` | an existing teacher id and their NIN (from `teacherPrivate/T1/nin`) |

All rows: type **update**, location **`/schools/SID`**.

| # | UID | Data | Expected | ✓ |
| --- | --- | --- | --- | --- |
| B1 | `pg-teacher` | J1, but with `"admissionNo": "NO1"` and index key `KEY1` | **Denied** (duplicate admission number) | ☐ |
| B2 | `pg-teacher` | Optional; needs test data. First register a real student with admission no. `PG-TEST-1` in the app. Then run J1 with the id `pgs1` changed to `pgs2` in all three lines and `"admissionNo": "pg-test-1"` (lower case) | **Denied** (duplicate, case-insensitive). Delete the test student afterwards. | ☐ |
| B3 | `pg-teacher` | `{"students/S1/admissionNo": "PG-NEW-9", "index/admissionNo/pg-new-9": "S1", "index/admissionNo/KEY1": null}` | Allowed (renumber + release old key) | ☐ |
| B4 | `pg-teacher` | `{"students/S1/admissionNo": "PG-NEW-9", "index/admissionNo/pg-new-9": "S1"}` | **Denied** (old key not released) | ☐ |
| B5 | `pg-teacher` | `{"index/admissionNo/KEY1": null}` | **Denied** (S1 still uses it) | ☐ |
| B6 | `ADMIN` | `{"students/S1": null}` | **Denied** (private + index must go too) | ☐ |
| B7 | `ADMIN` | `{"students/S1": null, "studentPrivate/S1": null, "index/admissionNo/KEY1": null}` | Allowed (complete delete) | ☐ |
| B8 | `ADMIN` | J2 with NIN `NIN1` (`"nin": "NIN1"` and `"index/nin/NIN1": "pgt1"`) | **Denied** (duplicate NIN) | ☐ |
| B9 | `ADMIN` | `{"teachers/T1": null}` | **Denied** (private record must go too) | ☐ |
| B10 | `ADMIN` | `{"teachers/T1": null, "teacherPrivate/T1": null, "index/nin/NIN1": null}` | Allowed (complete delete) | ☐ |
| B11 | `pg-teacher` | `{"students/S1/classId": "does-not-exist"}` | **Denied** (class must exist) | ☐ |
| B12 | `ADMIN` | `{"students/S1/classId": ""}` | Allowed (unassigned) | ☐ |

If the school has promotions (`promotions/P1`), also check:

| # | UID | Type | Location | Data | Expected | ✓ |
| --- | --- | --- | --- | --- | --- | --- |
| B13 | `ADMIN` | set | `/schools/SID/promotions/P1/academicYear` | `"1999"` | **Denied** (audit trail is append-only) | ☐ |

If an event or announcement was posted by the admin (`events/E1`):

| # | UID | Type | Location | Data | Expected | ✓ |
| --- | --- | --- | --- | --- | --- | --- |
| B14 | `pg-teacher` | set | `/schools/SID/events/E1` | `null` | **Denied** (not the author) | ☐ |
| B15 | `ADMIN` | set | `/schools/SID/events/E1` | `null` | Allowed | ☐ |

---

## In-app smoke test (after Round B)

With real logins on a phone or emulator:

| # | Do | Expected | ✓ |
| --- | --- | --- | --- |
| C1 | Admin signs in before migrating | "Update school data" screen → Check data → Update → dashboard | ☐ |
| C2 | Teacher signs in before the admin migrates | "Your school is being upgraded" | ☐ |
| C3 | Admin edits a student, changes the admission number, saves | Saved; searching Data shows the new index key and the old key gone | ☐ |
| C4 | Admin registers a student with an existing admission number | "Admission number … is already in use." | ☐ |
| C5 | Teacher opens a student | Private details load; no Delete button | ☐ |
| C6 | Parent account signs in | "Parent portal coming soon" | ☐ |
| C7 | Admin removes a teacher's `members/{uid}` in Data while the teacher is signed in | Teacher's app switches to "You no longer have access to this school" | ☐ |
| C8 | Admin deletes a student | Student, `studentPrivate` and index entry all gone | ☐ |

## Clean-up

- Delete `members/pg-teacher`, `members/pg-parent` (and `pg-new` if you
  created it in the app).
- After every school has migrated, remove the **TEMPORARY** `meta` /
  `updatedAt` block from `database.rules.json` and deploy again.
