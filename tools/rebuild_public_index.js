#!/usr/bin/env node
// Rebuilds the whole public Look Up index for EVERY school, or one school:
//   - publicSchools/{schoolId}            name, location, badge, active, Look Up
//                                         approval and the administrator contact;
//   - publicLookup/{schoolId}/{key}       one record per pupil (key "student_" +
//                                         admission number) and per teacher
//                                         ("teacher_" + NIN), the same fields the
//                                         app's "Publish Lookup Data" writes.
// Records of pupils/teachers that no longer exist are removed. A school that
// switched Look Up OFF stays listed but has all its records removed.
// It then marks each school's profile with publicIndexVersion, so the app's
// one-time rebuild at admin sign-in is skipped. Safe to run again.
//
//   node rebuild_public_index.js <service-account-key.json> [--dry-run] [--school <id>]
//
// See tools/README.md for step-by-step instructions. Never commit the key.
// Keep the record shapes in step with lib/models/lookup_record.dart.

const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

const DATABASE_URL = 'https://studio-1123859931-74e89-default-rtdb.firebaseio.com';

// Must match PublicLookupService.publicIndexVersion in the app.
const PUBLIC_INDEX_VERSION = 1;

const LEVEL_LABELS = { pre_primary: 'Pre-primary', primary: 'Primary', secondary: 'Secondary' };

// Same as the app's normalizePhone (lib/core/phone.dart).
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

// Same as the app's lookupKey (lib/models/lookup_record.dart): trimmed,
// upper-cased, . $ # [ ] / turned into _, with the type as prefix.
function lookupKey(type, id) {
  const norm = String(id || '').trim().toUpperCase().replace(/[.$#[\]/]/g, '_');
  return norm ? `${type}_${norm}` : '';
}

const str = (v) => (v === undefined || v === null ? '' : String(v));
const fullName = (...parts) => parts.map(str).filter((p) => p.trim()).join(' ');
const num = (v) => (typeof v === 'number' ? v : null);

// LookupRecord.clean: empty text and empty maps are left out.
function clean(fields) {
  const out = {};
  for (const [k, v] of Object.entries(fields)) {
    if (v === null || v === undefined) continue;
    if (typeof v === 'string' && !v.trim()) continue;
    if (typeof v === 'object' && Object.keys(v).length === 0) continue;
    out[k] = v;
  }
  return out;
}

function schoolEntry(p) {
  const location = str(p.address).trim().slice(0, 300);
  const logoUrl = str(p.logoUrl);
  const entry = {
    name: str(p.name).trim().slice(0, 120),
    logoUrl: logoUrl.startsWith('https://') ? logoUrl.slice(0, 500) : '',
    location,
    town: location, // older app versions read "town"
    active: true,
    lookupEnabled: p.lookupEnabled !== false,
    adminName: str(p.adminName).trim().slice(0, 100),
    updatedAt: admin.database.ServerValue.TIMESTAMP,
  };
  const phone = normalizePhone(p.adminPhone);
  const whatsApp = normalizePhone(p.adminWhatsApp);
  if (phone) entry.adminPhone = phone;
  if (whatsApp) entry.adminWhatsApp = whatsApp;
  return entry;
}

// Promotion history per pupil, oldest first, with class names.
function historyByStudent(promotions, classNames) {
  const records = Object.values(promotions || {})
    .filter((r) => r && typeof r === 'object')
    .sort((a, b) => (num(a.promotedAt) || 0) - (num(b.promotedAt) || 0));
  const out = {};
  for (const r of records) {
    const toId = str(r.toClassId);
    const item = {
      fromClass: classNames[r.fromClassId] || '',
      toClass: toId ? classNames[toId] || '' : '',
      academicYear: str(r.academicYear),
    };
    if (num(r.promotedAt) !== null) item.date = r.promotedAt;
    (out[str(r.studentId)] = out[str(r.studentId)] || []).push(item);
  }
  return out;
}

function studentRecord(id, pub, priv, classNames, history) {
  // Very old records kept every field in one place.
  const p = Object.keys(priv || {}).length ? priv : pub;
  const h = {};
  (history[id] || []).forEach((item, i) => { h[`p${String(i).padStart(3, '0')}`] = item; });
  return clean({
    type: 'student',
    id: str(pub.admissionNo).trim(),
    firstName: str(pub.firstName),
    middleName: str(pub.middleName),
    lastName: str(pub.lastName),
    fullName: fullName(pub.firstName, pub.middleName, pub.lastName),
    photoUrl: str(pub.photoUrl).startsWith('https://') ? str(pub.photoUrl) : '',
    gender: str(pub.gender),
    status: str(pub.status) || 'active',
    className: classNames[pub.classId] || '',
    level: LEVEL_LABELS[pub.level] || '',
    department: str(pub.department),
    admissionYear: str(pub.admissionYear),
    address: str(p.address),
    npseId: str(p.npseId),
    npseYear: str(p.npseYear),
    beceId: str(p.beceId),
    beceYear: str(p.beceYear),
    wassceId: str(p.wassceId),
    wassceYear: str(p.wassceYear),
    registeredAt: num(pub.createdAt) ?? admin.database.ServerValue.TIMESTAMP,
    lastPromotedAt: num(pub.lastPromotedAt),
    history: h,
    updatedAt: admin.database.ServerValue.TIMESTAMP,
  });
}

function teacherRecord(pub, priv) {
  const p = Object.keys(priv || {}).length ? priv : pub;
  const subjects = Array.isArray(pub.subjects)
    ? pub.subjects
    : Object.values(pub.subjects || {});
  const status = str(pub.status).trim().toLowerCase();
  return clean({
    type: 'teacher',
    id: str(p.nin).trim(),
    firstName: str(pub.firstName),
    middleName: str(pub.middleName),
    lastName: str(pub.lastName),
    fullName: fullName(pub.firstName, pub.middleName, pub.lastName),
    photoUrl: str(pub.photoUrl).startsWith('https://') ? str(pub.photoUrl) : '',
    gender: str(pub.gender),
    status: status === 'inactive' || status === 'past' ? 'inactive' : 'active',
    rank: str(pub.rank).trim(),
    subjects: subjects.map(str).join(', '),
    teachingLevel: str(pub.level),
    stream: str(pub.stream),
    updatedAt: admin.database.ServerValue.TIMESTAMP,
  });
}

// All records of one school, keyed by lookup key.
async function buildRecords(db, id) {
  const read = (child) => db.ref(`schools/${id}/${child}`).get().then((s) => s.val() || {});
  const [classes, students, studentPrivate, teachers, teacherPrivate, promotions] =
    await Promise.all(['classes', 'students', 'studentPrivate', 'teachers', 'teacherPrivate', 'promotions'].map(read));
  const classNames = {};
  for (const [cid, c] of Object.entries(classes)) classNames[cid] = str(c && c.name);
  const history = historyByStudent(promotions, classNames);

  const records = {};
  const skipped = [];
  const add = (key, record, who) => {
    if (!key) return; // no ID: can't be looked up
    if (!record.fullName || record.id.length > 40 || key.length > 60) {
      skipped.push(who);
      return;
    }
    records[key] = record;
  };
  for (const [sid, pub] of Object.entries(students)) {
    if (!pub || typeof pub !== 'object') continue;
    const r = studentRecord(sid, pub, studentPrivate[sid], classNames, history);
    add(lookupKey('student', r.id), r, `student ${sid}`);
  }
  for (const [tid, pub] of Object.entries(teachers)) {
    if (!pub || typeof pub !== 'object') continue;
    const r = teacherRecord(pub, teacherPrivate[tid]);
    add(lookupKey('teacher', r.id), r, `teacher ${tid}`);
  }
  return { records, skipped };
}

async function main() {
  const args = process.argv.slice(2);
  const dryRun = args.includes('--dry-run');
  const schoolArg = args.indexOf('--school');
  const onlySchool = schoolArg >= 0 ? args[schoolArg + 1] : null;
  const keyPath = args.find((a, i) => !a.startsWith('--') && args[i - 1] !== '--school');
  if (!keyPath) {
    console.error('Usage: node rebuild_public_index.js <service-account-key.json> [--dry-run] [--school <id>]');
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

  let ids;
  if (onlySchool) {
    ids = [onlySchool];
  } else {
    // School ids only (shallow REST read).
    const { access_token: token } = await credential.getAccessToken();
    const res = await fetch(`${DATABASE_URL}/schools.json?shallow=true`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok) throw new Error(`Could not list schools: HTTP ${res.status}`);
    ids = Object.keys((await res.json()) || {});
  }
  console.log(`Found ${ids.length} school(s).${dryRun ? ' DRY RUN: nothing will be written.' : ''}`);

  let listed = 0;
  let written = 0;
  let removed = 0;
  for (const id of ids) {
    // Current layout keeps the identity in "profile"; very old schools still
    // have it in "meta" until their admin signs in and the app moves it.
    const [profileSnap, metaSnap, existingSnap] = await Promise.all([
      db.ref(`schools/${id}/profile`).get(),
      db.ref(`schools/${id}/meta`).get(),
      db.ref(`publicLookup/${id}`).get(),
    ]);
    const hasProfile = profileSnap.exists();
    const p = profileSnap.val() || metaSnap.val() || {};
    if (!str(p.name).trim()) {
      console.log(`  SKIP  ${id}  (no school name saved)`);
      continue;
    }
    const entry = schoolEntry(p);
    const existing = Object.keys(existingSnap.val() || {});
    const updates = { [`publicSchools/${id}`]: entry };
    let records = {};
    let skipped = [];
    if (entry.lookupEnabled) {
      ({ records, skipped } = await buildRecords(db, id));
      for (const [key, r] of Object.entries(records)) updates[`publicLookup/${id}/${key}`] = r;
      for (const key of existing) {
        if (!records[key]) updates[`publicLookup/${id}/${key}`] = null;
      }
    } else if (existing.length) {
      updates[`publicLookup/${id}`] = null;
    }
    // Only on the current layout: writing into "profile" of a school still
    // on "meta" would make the app think it was already moved.
    if (hasProfile) {
      if (p.lookupEnabled === undefined) updates[`schools/${id}/profile/lookupEnabled`] = true;
      updates[`schools/${id}/profile/publicIndexVersion`] = PUBLIC_INDEX_VERSION;
    }

    const count = Object.keys(records).length;
    const gone = entry.lookupEnabled ? existing.filter((k) => !records[k]).length : existing.length;
    console.log(`  OK    ${id}  ${entry.name}  (Lookup ${entry.lookupEnabled ? 'ON' : 'OFF'}: ` +
      `${count} record(s), ${gone} stale removed${hasProfile ? '' : ', old "meta" layout'})`);
    for (const who of skipped) console.log(`        skipped ${who}: no name, or ID too long`);

    if (!dryRun) await db.ref().update(updates);
    listed += 1;
    written += count;
    removed += gone;
  }

  console.log(`${dryRun ? 'Dry run' : 'Done'}: ${listed} school(s) listed, ${written} record(s) ` +
    `${dryRun ? 'would be ' : ''}written, ${removed} stale record(s) ${dryRun ? 'would be ' : ''}removed.`);
  await admin.app().delete();
}

main().catch((e) => {
  console.error('Rebuild failed:', e.message || e);
  process.exit(1);
});
