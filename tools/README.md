# Tools

## List every school on the Look Up screen (`backfill_public_schools.js`)

The app's **Look Up a Record** screen lists the schools saved under
`publicSchools` in the database. Schools registered before Look Up existed
are only added when one of their admins signs in. This script adds **all**
schools at once. It writes each school's name, town (address), badge,
whether Lookup is approved, and the administrator's name and phone. It never
copies pupils, teachers or anything private.

Schools registered before the Lookup choice existed are treated as
**approved**: the script saves "Lookup ON" on their profile. Their admins can
switch it off any time in **Settings → Public Look Up**.

You only need to do this once. Running it again is safe.

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
node backfill_public_schools.js .\service-account.json --dry-run
```

The dry run only prints the schools it found. Nothing is written. If the
list looks right, run it for real:

```powershell
node backfill_public_schools.js .\service-account.json
```

It ends with `Done: N school(s) listed in publicSchools.`

### 3. Check

Open the app without signing in and tap **Look Up a Record**. Every school
should now be in the **Select your school** list. You can also see them in
the Firebase console under **Realtime Database → publicSchools**.

### If it fails

- `Key file not found`: check the file name and path you typed.
- `Could not list schools: HTTP 401/403`: the key is for another project,
  or it was deleted. Generate a new one (step 1).
- `Cannot find module 'firebase-admin'`: run `npm install` in this folder
  first.
