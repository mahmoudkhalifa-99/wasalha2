// تشغيل: node --test functions/verification.test.js  (من غير ما تحتاج firebase-admin مثبّتة)
const test = require('node:test');
const assert = require('node:assert');
const Module = require('module');

const origLoad = Module._load;
Module._load = function (request, ...rest) {
  if (request === 'firebase-admin') {
    const fs = () => ({});
    fs.Timestamp = { fromMillis: (m) => ({ toMillis: () => m }) };
    fs.FieldValue = { serverTimestamp: () => 'TS' };
    return { apps: [1], initializeApp() {}, firestore: fs };
  }
  if (request.startsWith('firebase-functions')) return { onDocumentWritten: () => null, onSchedule: () => null };
  return origLoad.call(this, request, ...rest);
};
const { _test } = require('./verification');
Module._load = origLoad;
const { computeGate, uniqueKeyId, reminderFor, requiredDocuments } = _test;

const DAY = 86400000;
const now = Date.UTC(2026, 9, 4, 12);
const doc = (extra = {}) => ({ path: 'p', version: 1, ...extra });
const decl = { termsVersion: '1.0', acceptedAt: 1, acceptedDocumentHash: 'h', captainId: 'c' };
const identity = { idFront: doc(), idBack: doc(), selfieWithId: doc(), poseRight: doc(), poseLeft: doc() };
const carDocs = (exp1, exp2) => ({
  ...identity,
  drivingLicense: doc({ expiresAt: exp1 }),
  vehicleLicense: doc({ expiresAt: exp2 }),
  vehiclePhoto: doc(),
});
const base = (over = {}) => ({
  v: { status: 'VERIFIED', activeDocs: identity, declaration: decl, serverFlags: [], ...(over.v || {}) },
  user: { role: 'DRIVER', status: 'APPROVED', vehicleType: 'TOKTOK', ...(over.user || {}) },
  emailVerified: over.emailVerified ?? true,
  now,
});

test('كابتن توكتوك موثّق بدون مستندات سيارة: يستقبل', () => {
  const g = computeGate(base());
  assert.deepStrictEqual(g.reasons, []);
  assert.strictEqual(g.canReceive, true);
});

test('VERIFIED لوحده لا يكفي: البريد غير مؤكد', () => {
  const g = computeGate(base({ emailVerified: false }));
  assert.strictEqual(g.canReceive, false);
  assert.ok(g.reasons.includes('EMAIL_NOT_VERIFIED'));
});

test('حساب موقوف أو كابتن غير موثّق', () => {
  assert.ok(computeGate(base({ user: { status: 'SUSPENDED' } })).reasons.includes('ACCOUNT_SUSPENDED'));
  assert.ok(computeGate(base({ v: { status: 'SUSPENDED' } })).reasons.includes('ACCOUNT_SUSPENDED'));
  assert.ok(computeGate(base({ v: { status: 'PENDING_REVIEW' } })).reasons.includes('NOT_VERIFIED'));
});

test('سيارة: تحتاج الرخصتين وصورة المركبة', () => {
  const car = { user: { vehicleType: 'CAR' } };
  const missing = computeGate(base({ ...car }));
  assert.ok(missing.reasons.includes('MISSING_DOCUMENT'));
  const ok = computeGate(base({ ...car, v: { activeDocs: carDocs(now + 60 * DAY, now + 90 * DAY) } }));
  assert.strictEqual(ok.canReceive, true);
  assert.strictEqual(ok.validUntilMs, Date.UTC(2026, 11, 3, 23, 59, 59)); // أقرب انتهاء
});

test('رخصة منتهية تمنع الاستقبال', () => {
  const g = computeGate(base({ user: { vehicleType: 'CAR' }, v: { activeDocs: carDocs(now - 2 * DAY, now + 90 * DAY) } }));
  assert.strictEqual(g.canReceive, false);
  assert.ok(g.reasons.includes('DOCUMENT_EXPIRED'));
});

test('رخصة بتنتهي النهاردة لسه صالحة طول اليوم', () => {
  const g = computeGate(base({ user: { vehicleType: 'CAR' }, v: { activeDocs: carDocs(now, now + 90 * DAY) } }));
  assert.strictEqual(g.canReceive, true);
});

test('الإقرار والتكرار', () => {
  assert.ok(computeGate(base({ v: { declaration: null } })).reasons.includes('MISSING_DECLARATION'));
  assert.ok(computeGate(base({ v: { serverFlags: ['DUPLICATE_NID'] } })).reasons.includes('DUPLICATE_IDENTITY'));
  // علامة غير حاجبة (صورة مكررة) لا تمنع الاستقبال، المراجع هو اللي يقرر
  assert.strictEqual(computeGate(base({ v: { serverFlags: ['DUPLICATE_IMAGE'] } })).canReceive, true);
});

test('المفاتيح الفريدة: نفس القيمة بصيغ مختلفة = نفس المفتاح', () => {
  const nid = 'nid_e35fb85ab07e0a5d2dd025c5875bbef7775878acabfeaef5bd9e98fd69b3d184';
  assert.strictEqual(uniqueKeyId('nid', '29001011234567'), nid);
  assert.strictEqual(uniqueKeyId('nid', '٢٩٠٠١٠١١٢٣٤٥٦٧'), nid);
  assert.strictEqual(uniqueKeyId('nid', '2900 1011 2345 67'), nid);
  const ph = 'phone_e60124f2fe2045215abda1ae912aa80bb66dab5fc231a758387682c9c0e70c01';
  for (const p of ['01012345678', '+201012345678', '00201012345678', '٠١٠١٢٣٤٥٦٧٨']) assert.strictEqual(uniqueKeyId('phone', p), ph);
  assert.strictEqual(uniqueKeyId('plate', 'أ ب ج 123'), uniqueKeyId('plate', 'ا ب ج ١٢٣'));
  assert.strictEqual(uniqueKeyId('nid', ''), null);
});

test('التذكيرات: 30 يوم و7 أيام', () => {
  assert.strictEqual(reminderFor(now + 45 * DAY, now), null);
  assert.strictEqual(reminderFor(now + 20 * DAY, now), 'REMINDER');
  assert.strictEqual(reminderFor(now + 5 * DAY, now), 'URGENT');
  assert.strictEqual(reminderFor(now - 1 * DAY, now), null);
});

test('المستندات المطلوبة حسب نوع المركبة', () => {
  assert.strictEqual(requiredDocuments('MOTORCYCLE').length, 5);
  assert.strictEqual(requiredDocuments('CAR').length, 8);
});
