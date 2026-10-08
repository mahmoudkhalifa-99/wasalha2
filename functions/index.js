// يبعت Push (FCM) أول ما يتكتب إشعار جديد في collection اسمه notifications.
// ده اللي بيخلي الإشعار يوصل والتطبيق مقفول (الإشعارات المحلية لوحدها مش كفاية).
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

const ROLES = ['DRIVER', 'CUSTOMER', 'ADMIN', 'OPERATOR'];

async function tokensFor(userId) {
  if (ROLES.includes(userId)) {
    // إشعار لدور كامل: للكباتن بنبعت للأونلاين بس
    let q = db.collection('users').where('role', '==', userId);
    if (userId === 'DRIVER') q = q.where('isOnline', '==', true);
    const snap = await q.get();
    return snap.docs.map((d) => d.get('fcmToken')).filter(Boolean);
  }
  if (userId === 'ALL') return []; // البث للجميع مش مفعّل عشان التكلفة
  const u = await db.collection('users').doc(userId).get();
  const t = u.exists ? u.get('fcmToken') : null;
  return t ? [t] : [];
}

exports.pushOnNotification = onDocumentCreated(
  'notifications/{id}',
  async (event) => {
    const n = event.data && event.data.data();
    if (!n || n.read === true) return;

    const tokens = [...new Set(await tokensFor(n.userId))];
    if (!tokens.length) return;

    const data = {
      title: String(n.title || 'وصلها'),
      body: String(n.body || ''),
      key: String(n.key || `n_${event.params.id}`),
      orderId: String(n.orderId || ''),
    };

    // notification + data + أولوية عالية: أندرويد بيعرض الإشعار لوحده حتى والتطبيق مقفول،
    // والـ tag = key عشان نفس الإشعار ما يتكررش لو وصل من أكتر من مسار.
    for (let i = 0; i < tokens.length; i += 500) {
      const res = await admin.messaging().sendEachForMulticast({
        tokens: tokens.slice(i, i + 500),
        notification: { title: data.title, body: data.body },
        data,
        android: {
          priority: 'high',
          notification: { channelId: 'wasalha_high_importance', tag: data.key, sound: 'default' },
        },
      });
      res.responses.forEach((r, idx) => {
        if (!r.success) console.warn('FCM failed', tokens[i + idx], r.error && r.error.code);
      });
    }
  }
);

// توثيق الكباتن (البوابة + منع الازدواج + الصلاحية)
const verification = require('./verification');
exports.onVerificationWrite = verification.onVerificationWrite;
exports.onDriverUserWrite = verification.onDriverUserWrite;
exports.verificationExpirySweep = verification.verificationExpirySweep;
