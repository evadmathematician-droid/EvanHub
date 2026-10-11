#!/usr/bin/env node
// One-time backfill: lists EVERY school in publicSchools/{schoolId}, so the
// app's "Look Up a Record" screen shows them all without each admin having
// to sign in first. Safe to run again: it only (re)writes publicSchools.
//
//   node backfill_public_schools.js <path-to-service-account-key.json> [--dry-run]
//
// See tools/README.md for step-by-step instructions. Never commit the key.

const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

const DATABASE_URL = 'https://studio-1123859931-74e89-default-rtdb.firebaseio.com';

async function main() {
  const args = process.argv.slice(2);
  const dryRun = args.includes('--dry-run');
  const keyPath = args.find((a) => !a.startsWith('--'));
  if (!keyPath) {
    console.error('Usage: node backfill_public_schools.js <service-account-key.json> [--dry-run]');
    process.exit(1);
  }
  const resolved = path.resolve(keyPath);
  if (!fs.existsSync(resolved)) {
    console.error(`Key file not found: ${resolved}`);
    process.exit(1);
  }

  const credential = admin.credential.cert(require(resolved));
  admin.initializeApp({ credential, databaseURL: DATABASE_URL });
  const db = admin.database();

  // School ids only (shallow REST read), so student data is never downloaded.
  const { access_token: token } = await credential.getAccessToken();
  const res = await fetch(`${DATABASE_URL}/schools.json?shallow=true`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!res.ok) throw new Error(`Could not list schools: HTTP ${res.status}`);
  const ids = Object.keys((await res.json()) || {});
  console.log(`Found ${ids.length} school(s).`);

  const updates = {};
  for (const id of ids) {
    // Current layout keeps the identity in "profile"; very old schools still
    // have it in "meta" until their admin signs in and the app moves it.
    const [profileSnap, metaSnap] = await Promise.all([
      db.ref(`schools/${id}/profile`).get(),
      db.ref(`schools/${id}/meta`).get(),
    ]);
    const p = profileSnap.val() || metaSnap.val() || {};
    const name = String(p.name || '').trim();
    if (!name) {
      console.log(`  SKIP  ${id}  (no school name saved)`);
      continue;
    }
    const logoUrl = String(p.logoUrl || '');
    updates[`publicSchools/${id}`] = {
      name: name.slice(0, 120),
      logoUrl: logoUrl.startsWith('https://') ? logoUrl.slice(0, 500) : '',
      town: String(p.address || '').trim().slice(0, 300),
      updatedAt: admin.database.ServerValue.TIMESTAMP,
    };
    console.log(`  OK    ${id}  ${name}`);
  }

  const count = Object.keys(updates).length;
  if (dryRun) {
    console.log(`Dry run: ${count} school(s) would be listed. Nothing was written.`);
  } else if (count > 0) {
    await db.ref().update(updates);
    console.log(`Done: ${count} school(s) listed in publicSchools.`);
  } else {
    console.log('Nothing to write.');
  }
  await admin.app().delete();
}

main().catch((e) => {
  console.error('Backfill failed:', e.message || e);
  process.exit(1);
});
