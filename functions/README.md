# Cloud Function للإشعارات (Push والتطبيق مقفول)

الإشعارات اللي بتظهر والتطبيق شغال (مقدمة/خلفية) مش محتاجة أي حاجة هنا.
الدالة دي مطلوبة بس عشان الإشعار يوصل لو التطبيق اتقفل خالص.

## التفعيل (مرة واحدة)
1. لازم مشروع Firebase `sada-51292` يكون على خطة Blaze (الـ Functions بتتطلبها).
2. من جذر المشروع:
```bash
npm i -g firebase-tools
firebase login
firebase init functions   # اختار المشروع الحالي، JavaScript، وما تستبدلش index.js
cd functions && npm install && cd ..
firebase deploy --only functions
```
3. الكباتن لازم يفتحوا التطبيق مرة بعد التحديث (عشان حقل `isOnline` يتسجّل).

## ملاحظات
- لو Firestore Rules بتمنع العميل من كتابة إشعار للكباتن (`userId: "DRIVER"`)، الكابتن الأونلاين لسه هيوصله إشعار محلي أول ما الطلب ينزل.
- البث لـ `ALL` متعطّل في الدالة عن قصد.
