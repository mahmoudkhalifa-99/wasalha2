// نظام توثيق الكباتن (السيرفر): البوابة gate، منع الازدواج، صلاحية المستندات والتذكيرات.
// الكلاينت ما يقدرش يكتب gate ولا serverFlags ولا unique_keys (القواعد بتمنع)، فالحماية
// حقيقية حتى لو اتعدّل التطبيق. المنطق هنا لازم يطابق lib/features/verification/domain.
const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');
const crypto = require('crypto');

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
const { Timestamp, FieldValue } = admin.firestore;

// ───────── متطلبات المستندات (نفس document_requirements.dart) ─────────
const IDENTITY_DOCS = [
  { type: 'idFront' }, { type: 'idBack' }, { type: 'selfieWithId' },
  { type: 'poseRight' }, { type: 'poseLeft' },
];
const VEHICLE_DOCS = {
  CAR: [
    { type: 'drivingLicense', hasExpiry: true },
    { type: 'vehicleLicense', hasExpiry: true },
    { type: 'vehiclePhoto' },
  ],
};
const requiredDocuments = (vt) => [...IDENTITY_DOCS, ...(VEHICLE_DOCS[vt] || [])];

// ───────── التطبيع والمفاتيح الفريدة (نفس unique_keys.dart) ─────────
const AR_DIGITS = '٠١٢٣٤٥٦٧٨٩';
function normalizeDigits(s) {
  let out = '';
  for (const c of String(s || '')) {
    const i = AR_DIGITS.indexOf(c);
    if (i >= 0) out += i;
    else if (c >= '0' && c <= '9') out += c;
  }
  return out;
}
function normalizeEgyptPhone(raw) {
  let d = normalizeDigits(raw);
  if (d.startsWith('0020')) d = d.slice(4);
  if (d.startsWith('20') && d.length === 12) d = d.slice(2);
  if (d.length === 10 && d.startsWith('1')) d = '0' + d;
  return d;
}
function normalizeArabicName(s) {
  return String(s || '')
    .replace(/[\u064B-\u065F\u0670\u0640]/g, '')
    .replace(/[أإآٱ]/g, 'ا').replace(/ى/g, 'ي').replace(/ة/g, 'ه')
    .replace(/\s+/g, ' ').trim().toLowerCase();
}
function normalizeAlnum(raw) {
  let t = '';
  for (const c of String(raw || '')) {
    const i = AR_DIGITS.indexOf(c);
    t += i >= 0 ? String(i) : c;
  }
  return normalizeArabicName(t).replace(/[^0-9a-z\u0621-\u064A]/g, '');
}
const NORMALIZERS = {
  nid: normalizeDigits, phone: normalizeEgyptPhone, license: normalizeAlnum, plate: normalizeAlnum,
};
function uniqueKeyId(type, raw) {
  const v = NORMALIZERS[type](raw);
  if (!v) return null;
  return `${type}_${crypto.createHash('sha256').update(v, 'utf8').digest('hex')}`;
}

// ───────── حساب البوابة (نقي، قابل للاختبار) ─────────
const FAR_FUTURE_MS = Date.UTC(2100, 0, 1);
const endOfDay = (ms) => { const d = new Date(ms); return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(), 23, 59, 59); };
const BLOCKING_FLAGS = ['DUPLICATE_NID', 'DUPLICATE_PHONE', 'DUPLICATE_LICENSE', 'DUPLICATE_PLATE'];

// v = وثيقة التوثيق، user = وثيقة users، emailVerified من Auth، now بالميلي.
function computeGate({ v, user, emailVerified, now }) {
  const reasons = [];
  if (!emailVerified) reasons.push('EMAIL_NOT_VERIFIED');
  if (!user || user.role !== 'DRIVER' || (user.status || 'APPROVED') !== 'APPROVED' || v.status === 'SUSPENDED') {
    reasons.push('ACCOUNT_SUSPENDED');
  }
  if (v.status !== 'VERIFIED') reasons.push('NOT_VERIFIED');
  const active = v.activeDocs || {};
  let validUntil = FAR_FUTURE_MS;
  for (const req of requiredDocuments(user && user.vehicleType)) {
    const d = active[req.type];
    if (!d) { reasons.push('MISSING_DOCUMENT'); continue; }
    if (req.hasExpiry) {
      if (!d.expiresAt) { reasons.push('MISSING_DOCUMENT'); continue; }
      const end = endOfDay(Number(d.expiresAt));
      if (now > end) reasons.push('DOCUMENT_EXPIRED');
      else validUntil = Math.min(validUntil, end);
    }
  }
  const dec = v.declaration;
  if (!dec || !dec.termsVersion || !dec.acceptedDocumentHash || !dec.acceptedAt) reasons.push('MISSING_DECLARATION');
  if ((v.serverFlags || []).some((f) => BLOCKING_FLAGS.includes(f))) reasons.push('DUPLICATE_IDENTITY');
  const uniq = [...new Set(reasons)];
  return { canReceive: uniq.length === 0, reasons: uniq, validUntilMs: validUntil };
}

// ───────── منع الازدواج: الـ Function هي السلطة ─────────
// كل قيمة فريدة لها وثيقة unique_keys/{type_hash} فيها captainId. لو المالك كابتن تاني = تكرار.
async function claimKeys(captainId, v, user) {
  const wanted = [];
  const push = (type, raw, flag) => { const id = uniqueKeyId(type, raw); if (id) wanted.push({ type, id, flag }); };
  push('nid', v.nationalId, 'DUPLICATE_NID');
  push('phone', user && user.phone, 'DUPLICATE_PHONE');
  if (user && VEHICLE_DOCS[user.vehicleType]) {
    push('license', v.licenseNumber, 'DUPLICATE_LICENSE');
    push('plate', v.plateNumber, 'DUPLICATE_PLATE');
  }
  const flags = [];
  for (const k of wanted) {
    const ref = db.collection('unique_keys').doc(k.id);
    const res = await db.runTransaction(async (tx) => {
      const s = await tx.get(ref);
      if (!s.exists) {
        tx.set(ref, { captainId, type: k.type, createdAt: FieldValue.serverTimestamp() });
        return 'claimed';
      }
      return s.get('captainId') === captainId ? 'own' : 'duplicate';
    });
    if (res === 'duplicate') flags.push(k.flag);
  }
  // مفاتيح قديمة لنفس الكابتن (لو غيّر رقم) نحررها عشان ما تفضلش محجوزة.
  const mine = await db.collection('unique_keys').where('captainId', '==', captainId).get();
  const keep = new Set(wanted.map((k) => k.id));
  for (const d of mine.docs) if (!keep.has(d.id)) await d.ref.delete();
  return flags;
}

// نفس الصورة (SHA-256) مستخدمة في حساب كابتن تاني = مؤشر خطر عالٍ (بيحصل بس لو اتحقنت صورة).
async function duplicateImageFlag(captainId, v) {
  try {
    const hashes = Object.values(v.pendingDocs || {}).map((d) => d && d.sha256).filter(Boolean);
    for (const h of hashes.slice(0, 8)) {
      const q = await db.collectionGroup('documents').where('sha256', '==', h).limit(3).get();
      if (q.docs.some((d) => d.ref.parent.parent && d.ref.parent.parent.id !== captainId)) return true;
    }
  } catch (e) {
    // غالبًا فهرس collection-group على documents.sha256 مش متفعّل (راجع firestore.indexes.json).
    // الفحص ده إضافي، فمنسيبوش يكسر حساب البوابة.
    console.warn('duplicateImageFlag skipped:', e && e.message);
  }
  return false;
}

async function recompute(captainId) {
  const ref = db.collection('captain_verifications').doc(captainId);
  const snap = await ref.get();
  if (!snap.exists) return;
  const v = snap.data();
  const userSnap = await db.collection('users').doc(captainId).get();
  const user = userSnap.exists ? userSnap.data() : null;
  let emailVerified = false;
  try { emailVerified = (await admin.auth().getUser(captainId)).emailVerified === true; } catch (_) { /* حساب محذوف */ }

  // الازدواج بيتفحص من أول ما الكابتن يدخل أرقامه (مش بس عند الإرسال).
  const flags = await claimKeys(captainId, v, user);
  if (await duplicateImageFlag(captainId, v)) flags.push('DUPLICATE_IMAGE');

  const g = computeGate({ v: { ...v, serverFlags: flags }, user, emailVerified, now: Date.now() });
  const prev = v.gate || {};
  const prevUntil = prev.validUntil && prev.validUntil.toMillis ? prev.validUntil.toMillis() : null;
  const sameGate = prev.canReceive === g.canReceive &&
    JSON.stringify(prev.reasons || []) === JSON.stringify(g.reasons) &&
    prevUntil === g.validUntilMs;
  const sameFlags = JSON.stringify([...(v.serverFlags || [])].sort()) === JSON.stringify([...flags].sort());
  if (sameGate && sameFlags) return; // ما نكتبش لو ما اتغيّرش (بيمنع التكرار اللانهائي للـ trigger)
  await ref.update({
    gate: { canReceive: g.canReceive, reasons: g.reasons, validUntil: Timestamp.fromMillis(g.validUntilMs), computedAt: FieldValue.serverTimestamp() },
    serverFlags: flags,
  });
}

// أي كتابة على وثيقة التوثيق (حالة/مستندات/أرقام/طلب تحديث من الكابتن بعد تأكيد بريده).
exports.onVerificationWrite = onDocumentWritten('captain_verifications/{id}', async (event) => {
  if (!event.data || !event.data.after.exists) return;
  await recompute(event.params.id);
});

// تعليق الحساب/تغيير نوع المركبة في users بيحدّث البوابة فورًا.
exports.onDriverUserWrite = onDocumentWritten('users/{id}', async (event) => {
  const b = event.data && event.data.before.exists ? event.data.before.data() : null;
  const a = event.data && event.data.after.exists ? event.data.after.data() : null;
  if (!a || a.role !== 'DRIVER') return;
  if (b && b.status === a.status && b.vehicleType === a.vehicleType && b.phone === a.phone) return;
  await recompute(event.params.id);
});

// ───────── صلاحية المستندات والتذكيرات (يوميًا) ─────────
async function notify(userId, title, body, key) {
  await db.collection('notifications').add({
    userId, title, body, type: 'WARNING', key, orderId: '', createdAt: Date.now(), read: false, senderId: 'SYSTEM', senderName: 'وصلها',
  });
}
async function audit(captainId, action, oldStatus, newStatus, reason) {
  await db.collection('captain_verifications').doc(captainId).collection('audit').add({
    captainId, action, performedBy: 'SYSTEM', timestamp: Date.now(), oldStatus: oldStatus || null, newStatus: newStatus || null, reason: reason || null,
  });
}
const LABELS = { drivingLicense: 'رخصة القيادة', vehicleLicense: 'رخصة المركبة' };

// مستند ينتهي بعد days يوم أو أقل ولسه ما اتبعتش تذكير بنفس المستوى لنفس النسخة.
function reminderFor(expiresMs, nowMs) {
  const days = Math.floor((endOfDay(expiresMs) - nowMs) / 86400000);
  if (days < 0) return null;
  if (days <= 7) return 'URGENT';
  if (days < 30) return 'REMINDER';
  return null;
}

async function runExpirySweep(nowMs = Date.now()) {
  const snap = await db.collection('captain_verifications').where('status', '==', 'VERIFIED').get();
  let expired = 0; let reminded = 0;
  for (const doc of snap.docs) {
    const v = doc.data();
    const sent = v.reminders || {};
    const newSent = { ...sent };
    let hasExpired = false;
    for (const [type, d] of Object.entries(v.activeDocs || {})) {
      if (!d || !d.expiresAt) continue;
      const exp = Number(d.expiresAt);
      if (nowMs > endOfDay(exp)) { hasExpired = true; continue; }
      const level = reminderFor(exp, nowMs);
      const key = `${type}_v${d.version || 1}`;
      if (level && sent[key] !== level && !(sent[key] === 'URGENT')) {
        const days = Math.max(0, Math.ceil((endOfDay(exp) - nowMs) / 86400000));
        await notify(doc.id, level === 'URGENT' ? 'تنبيه عاجل: مستند على وشك الانتهاء' : 'تذكير: مستند قارب على الانتهاء',
          `${LABELS[type] || type} ينتهي بعد ${days} يوم. جدّد المستند من شاشة التوثيق عشان تفضل تستقبل الطلبات.`, `exp_${doc.id}_${key}_${level}`);
        newSent[key] = level; reminded++;
      }
    }
    if (hasExpired) {
      await doc.ref.update({ status: 'EXPIRED', expiredAt: Date.now() });
      await audit(doc.id, 'DOCUMENT_EXPIRED', 'VERIFIED', 'EXPIRED', 'مستند منتهي الصلاحية');
      await notify(doc.id, 'انتهت صلاحية مستند', 'تم إيقاف استقبال الطلبات لحين تجديد المستند وإعادة المراجعة.', `expired_${doc.id}_${nowMs}`);
      expired++;
    } else if (JSON.stringify(newSent) !== JSON.stringify(sent)) {
      await doc.ref.update({ reminders: newSent });
    }
  }
  return { expired, reminded };
}

exports.verificationExpirySweep = onSchedule({ schedule: 'every day 03:00', timeZone: 'Africa/Cairo' }, async () => {
  const r = await runExpirySweep();
  console.log('verification expiry sweep', r);
});

// للاختبار فقط
exports._test = { computeGate, uniqueKeyId, normalizeDigits, normalizeEgyptPhone, reminderFor, requiredDocuments };
