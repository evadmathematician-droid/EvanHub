#!/usr/bin/env node
// One-time backfill: lists EVERY school in publicSchools/{schoolId}, so the
// app's "Look Up a Record" screen shows them all without each admin having
// to sign in first. Writes name, town, badge, Look Up approval and the
// administrator's name and phones (nothing else).
//
// Schools registered before Look Up had no choice to make: a missing
// lookupEnabled counts as approved, and this saves lookupEnabled = true on
// their profile. Safe to run again.
//
//   node backfill_public_schools.js <path-to-service-account-key.json> [--dry-run]
//
// See tools/README.md for step-by-step instructions. Never commit the key.

const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

const DATABASE_URL = 'https://studio-1123859931-74e89-default-rtdb.firebaseio.com';

// Same rules as the app's normalizePhone (lib/core/phone.dart): +232... for
// Sierra Leone numbers typed with a leading 0, or null when not a phone.
function normalizePhone(input) {
  let d = String(input || '').trim().replace(/[\s\-.()]/g, '');
  if (!d) return null;
  let intl = false;
  if (d.startsWith('+')) { intl = true; d = d.slice(1); }
  else if (d.startsWith('00')) { intl = true; d = d.slice(2); }
  if (!/^[0-9]+$/.test(d)) return null;
  if (!intl && d.startsWith('0') && d.length === 9) return '+232' + d.slice(1);
  if (d.startsWith('232')) return d.length === 11 ? '+' + d : null;
  if (!intl && d.length === 8) return '+232' + d;
  if (intl && d.length >= 8 && d.length <= 15) return '+' + d;
  return null;
}

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
    const hasProfile = profileSnap.exists();
    const p = profileSnap.val() || metaSnap.val() || {};
    const name = String(p.name || '').trim();
    if (!name) {
      console.log(`  SKIP  ${id}  (no school name saved)`);
      continue;
    }
    const logoUrl = String(p.logoUrl || '');
    const lookupEnabled = p.lookupEnabled !== false;
    const phone = normalizePhone(p.adminPhone);
    const whatsApp = normalizePhone(p.adminWhatsApp);
    const entry = {
      name: name.slice(0, 120),
      logoUrl: logoUrl.startsWith('https://') ? logoUrl.slice(0, 500) : '',
      town: String(p.address || '').trim().slice(0, 300),
      lookupEnabled,
      adminName: String(p.adminName || '').trim().slice(0, 100),
      updatedAt: admin.database.ServerValue.TIMESTAMP,
    };
    if (phone) entry.adminPhone = phone;
    if (whatsApp) entry.adminWhatsApp = whatsApp;
    updates[`publicSchools/${id}`] = entry;
    // Only on the current layout: writing into "profile" of a school still
    // on "meta" would make the app think it was already moved.
    if (hasProfile && p.lookupEnabled === undefined) {
      updates[`schools/${id}/profile/lookupEnabled`] = true;
    }
    console.log(`  OK    ${id}  ${name}  (Lookup ${lookupEnabled ? 'ON' : 'OFF'}${phone ? ', phone ' + phone : ', no admin phone'})`);
  }

  const count = Object.keys(updates).filter((k) => k.startsWith('publicSchools/')).length;
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
