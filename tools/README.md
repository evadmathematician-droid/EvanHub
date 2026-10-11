# Tools

## Rebuild the public Look Up index (`rebuild_public_index.js`)

The app's **Look Up a Record** screen (on the login screen, no sign-in
needed) reads two public parts of the database:

- `publicSchools` — the list of schools in the **Select your school** box
  (name, town/location, badge, whether Lookup is approved, and the
  administrator's name and phone);
- `publicLookup` — one record per pupil (by admission number) and per
  teacher (by NIN), readable only by someone who knows the exact ID.

The app keeps both up to date as schools save their data, and rebuilds a
school's index once when one of its admins signs in. This script rebuilds
the index for **all** schools at once, including schools whose admins have
not opened the new app version yet. It never copies passwords, PINs,
guardian phone numbers or dates of birth.

It also:

- removes public records of pupils/teachers that no longer exist;
- removes all records of a school that switched Lookup **OFF** (the school
  stays in the list, with the "contact the school" message);
- treats schools registered before the Lookup choice existed as
  **approved** and saves "Lookup ON" on their profile (admins can switch it
  off any time in **Settings → Public Look Up**).

Running it again is safe.

### 1. Get a service-account key (one time)

1. Open <https://console.firebase.google.com> and choose the project
   **studio-1123859931-74e89**.
2. Click the gear icon (next to *Project Overview*) and choose
   **Project settings**.
3. Open the **Service accounts** tab.
4. Click **Generate new private key**, then **Generate key**. A `.json`
   file downloads.
5. Move that file into this `tools` folder, for example as
   `E:\APACHE\Evangelist_Global\tools\service-account.json`.

**Keep this file secret.** It gives full access to the database. Git
ignores `.json` files in this folder (except `package.json`), so it won't be
committed. Delete it when you are done.

### 2. Run the script (Windows PowerShell)

You need Node.js (already installed on this PC). Open PowerShell and run:

```powershell
cd E:\APACHE\Evangelist_Global\tools
npm install
node rebuild_public_index.js .\service-account.json --dry-run
```

The dry run only prints each school and how many records it would write.
Nothing is written. If it looks right, run it for real:

```powershell
node rebuild_public_index.js .\service-account.json
```

It ends with `Done: N school(s) listed, … record(s) written, …`.

To rebuild just one school, add `--school <schoolId>` (the id is the key
under `schools` in the Firebase console).

### 3. Check

Open the app without signing in and tap **Look Up a Record**. Every school
should be in the **Select your school** list, and a pupil's admission
number should open their record. You can also see the data in the Firebase
console under **Realtime Database → publicSchools / publicLookup**.

### Without the script

An admin can rebuild their own school from the app: **Settings → Public
Look Up → Publish Lookup Data**.

### If it fails

- `Key file not found`: check the file name and path you typed.
- `Could not list schools: HTTP 401/403`: the key is for another project,
  or it was deleted. Generate a new one (step 1).
- `Cannot find module 'firebase-admin'`: run `npm install` in this folder
  first.
