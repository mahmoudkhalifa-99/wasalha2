# إشعارات والتطبيق مقفول — بدون Blaze

1. افتح https://script.google.com ← مشروع جديد ← الصق محتوى `Code.gs`.
2. من Firebase Console ← Project settings ← Service accounts ← **Generate new private key**.
   افتح ملف الـ JSON، وانسخ محتواه كله.
3. في Apps Script: Project Settings ← Script properties ← أضف
   `SERVICE_ACCOUNT_JSON` = محتوى الملف كامل.
4. Deploy ← New deployment ← Web app:
   Execute as: **Me** — Who has access: **Anyone**. انسخ الرابط (ينتهي بـ `/exec`).
5. على Codemagic، في المجموعة `Wasalha` أضف متغيّر `PUSH_RELAY_URL` = الرابط، وأعد البناء.

- الإرسال بيتحقق من توكن Firebase للمستخدم، فمحدش من برا التطبيق يقدر يبعت.
- لو الخطوة 4 اتعدّلت لاحقاً لازم New deployment جديد (أو Manage deployments ← Edit ← New version).
- مع Cloud Function مفعّلة مش هيحصل تكرار: نفس المفتاح بيستبدل الإشعار.
