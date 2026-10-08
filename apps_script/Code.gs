/**
 * Relay لإرسال إشعارات FCM بدون Cloud Functions / Blaze.
 * التطبيق بيبعت: { idToken, userId, title, body, key, orderId }
 *  - idToken: توكن Firebase للمستخدم الحالي (للتأكد إنه مستخدم حقيقي في المشروع).
 *  - userId: معرّف مستخدم، أو دور كامل (DRIVER = الكباتن الأونلاين بس).
 * وللرسائل الجماعية: { idToken, broadcast: true, roles: ['CUSTOMER','DRIVER'], title, body, key }
 *  - مسموح بس لو اللي بيبعت ADMIN أو OPERATOR (بيتأكد من وثيقته في Firestore).
 *
 * الإشعار بيتبعت كـ notification + data: أندرويد نفسه بيعرضه حتى لو التطبيق
 * مقفول خالص (من غير ما يعتمد على كود التطبيق)، وبنفس الـ key/tag عشان ميتكررش.
 *
 * Script Properties المطلوبة:
 *   SERVICE_ACCOUNT_JSON : محتوى ملف الـ service account كامل (Firebase Admin SDK)
 *   WEB_API_KEY          : (اختياري) الـ API key بتاع Firebase، الافتراضي تحت
 */
const PROJECT_ID = 'sada-51292';
const DEFAULT_API_KEY = 'AIzaSyDlfpN0JCsmpCKdTyb4ZX_QN0sZbypIv48';
const ROLES = ['DRIVER', 'CUSTOMER', 'ADMIN', 'OPERATOR'];
const CHANNEL_ID = 'wasalha_high_importance';
const FCM_CHUNK = 100;
const MAX_BROADCAST = 1000;

function doPost(e) {
  try {
    const body = JSON.parse(e.postData.contents);
    const caller = verifyIdToken_(body.idToken);
    if (!caller) return out_({ ok: false, error: 'unauthorized' });

    var tokens;
    if (body.broadcast === true) {
      if (!isStaff_(caller)) return out_({ ok: false, error: 'forbidden' });
      tokens = broadcastTokens_(body.roles || []);
    } else {
      tokens = tokensFor_(String(body.userId || ''));
    }
    if (!tokens.length) return out_({ ok: true, sent: 0 });

    const access = getAccessToken_();
    const url = 'https://fcm.googleapis.com/v1/projects/' + PROJECT_ID + '/messages:send';
    const title = String(body.title || 'وصلها');
    const text = String(body.body || '');
    const key = String(body.key || '');

    const reqs = tokens.map(function (t) {
      const androidNotification = { channel_id: CHANNEL_ID, sound: 'default' };
      if (key) androidNotification.tag = key;
      return {
        url: url,
        method: 'post',
        contentType: 'application/json',
        headers: { Authorization: 'Bearer ' + access },
        muteHttpExceptions: true,
        payload: JSON.stringify({
          message: {
            token: t,
            // notification: أندرويد بيعرضه لوحده والتطبيق مقفول
            notification: { title: title, body: text },
            // data: التطبيق بيستخدمها لما يكون مفتوح
            data: { title: title, body: text, key: key, orderId: String(body.orderId || '') },
            android: { priority: 'HIGH', notification: androidNotification },
          },
        }),
      };
    });

    var ok = 0;
    for (var i = 0; i < reqs.length; i += FCM_CHUNK) {
      const res = UrlFetchApp.fetchAll(reqs.slice(i, i + FCM_CHUNK));
      ok += res.filter(function (r) { return r.getResponseCode() === 200; }).length;
    }
    return out_({ ok: true, sent: ok, total: tokens.length });
  } catch (err) {
    return out_({ ok: false, error: String(err) });
  }
}

function out_(o) {
  return ContentService.createTextOutput(JSON.stringify(o)).setMimeType(ContentService.MimeType.JSON);
}

// بيرجّع uid المستخدم لو التوكن سليم، أو '' لو لا.
function verifyIdToken_(idToken) {
  if (!idToken) return '';
  const key = PropertiesService.getScriptProperties().getProperty('WEB_API_KEY') || DEFAULT_API_KEY;
  const res = UrlFetchApp.fetch(
    'https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=' + key,
    { method: 'post', contentType: 'application/json', payload: JSON.stringify({ idToken: idToken }), muteHttpExceptions: true }
  );
  if (res.getResponseCode() !== 200) return '';
  const j = JSON.parse(res.getContentText());
  return (j.users && j.users.length && j.users[0].localId) || '';
}

function fsBase_() {
  return 'https://firestore.googleapis.com/v1/projects/' + PROJECT_ID + '/databases/(default)/documents';
}

// هل اللي بيبعت إدارة (ADMIN / OPERATOR) وحسابه مش معطّل؟
function isStaff_(uid) {
  const res = UrlFetchApp.fetch(fsBase_() + '/users/' + encodeURIComponent(uid), {
    headers: { Authorization: 'Bearer ' + getAccessToken_() }, muteHttpExceptions: true,
  });
  if (res.getResponseCode() !== 200) return false;
  const f = JSON.parse(res.getContentText()).fields || {};
  const role = f.role && f.role.stringValue;
  const status = f.status && f.status.stringValue;
  return (role === 'ADMIN' || role === 'OPERATOR') && status !== 'SUSPENDED';
}

// توكنات كل مستخدمي الأدوار المطلوبة (عملاء/كباتن) من غير المعطّلين.
function broadcastTokens_(roles) {
  const allowed = ['CUSTOMER', 'DRIVER'];
  const seen = {};
  const out = [];
  roles.forEach(function (role) {
    if (allowed.indexOf(role) < 0) return;
    const res = UrlFetchApp.fetch(fsBase_() + ':runQuery', {
      method: 'post', contentType: 'application/json',
      headers: { Authorization: 'Bearer ' + getAccessToken_() }, muteHttpExceptions: true,
      payload: JSON.stringify({
        structuredQuery: {
          from: [{ collectionId: 'users' }],
          where: fieldEq_('role', { stringValue: role }),
          limit: MAX_BROADCAST,
        },
      }),
    });
    if (res.getResponseCode() !== 200) return;
    JSON.parse(res.getContentText()).forEach(function (r) {
      const f = r.document && r.document.fields;
      if (!f || !f.fcmToken || !f.fcmToken.stringValue) return;
      if (f.status && f.status.stringValue === 'SUSPENDED') return;
      const t = f.fcmToken.stringValue;
      if (!seen[t]) { seen[t] = true; out.push(t); }
    });
  });
  return out.slice(0, MAX_BROADCAST);
}

function tokensFor_(userId) {
  const access = getAccessToken_();
  const base = 'https://firestore.googleapis.com/v1/projects/' + PROJECT_ID + '/databases/(default)/documents';
  const headers = { Authorization: 'Bearer ' + access };

  if (ROLES.indexOf(userId) >= 0) {
    const filters = [fieldEq_('role', { stringValue: userId })];
    if (userId === 'DRIVER') filters.push(fieldEq_('isOnline', { booleanValue: true }));
    const res = UrlFetchApp.fetch(base + ':runQuery', {
      method: 'post', contentType: 'application/json', headers: headers, muteHttpExceptions: true,
      payload: JSON.stringify({
        structuredQuery: {
          from: [{ collectionId: 'users' }],
          where: { compositeFilter: { op: 'AND', filters: filters } },
          limit: 300,
        },
      }),
    });
    if (res.getResponseCode() !== 200) return [];
    return JSON.parse(res.getContentText())
      .map(function (r) { return r.document && r.document.fields && r.document.fields.fcmToken && r.document.fields.fcmToken.stringValue; })
      .filter(Boolean);
  }

  if (!userId || userId === 'ALL') return [];
  const res = UrlFetchApp.fetch(base + '/users/' + encodeURIComponent(userId), { headers: headers, muteHttpExceptions: true });
  if (res.getResponseCode() !== 200) return [];
  const f = JSON.parse(res.getContentText()).fields || {};
  return f.fcmToken && f.fcmToken.stringValue ? [f.fcmToken.stringValue] : [];
}

function fieldEq_(path, value) {
  return { fieldFilter: { field: { fieldPath: path }, op: 'EQUAL', value: value } };
}

function getAccessToken_() {
  const cache = CacheService.getScriptCache();
  const cached = cache.get('access_token');
  if (cached) return cached;

  const sa = JSON.parse(PropertiesService.getScriptProperties().getProperty('SERVICE_ACCOUNT_JSON'));
  const now = Math.floor(Date.now() / 1000);
  const enc = function (o) { return Utilities.base64EncodeWebSafe(JSON.stringify(o)).replace(/=+$/, ''); };
  const unsigned = enc({ alg: 'RS256', typ: 'JWT' }) + '.' + enc({
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/datastore https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  });
  const sig = Utilities.base64EncodeWebSafe(Utilities.computeRsaSha256Signature(unsigned, sa.private_key)).replace(/=+$/, '');
  const res = UrlFetchApp.fetch('https://oauth2.googleapis.com/token', {
    method: 'post',
    payload: { grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: unsigned + '.' + sig },
  });
  const token = JSON.parse(res.getContentText()).access_token;
  cache.put('access_token', token, 3000);
  return token;
}
