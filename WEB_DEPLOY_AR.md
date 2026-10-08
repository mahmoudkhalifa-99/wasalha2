# نسخة الويب من وصلها — رفع على Vercel (ومجانًا على غيره)

الهدف: رابط يفتحه أي حد من المتصفح (أندرويد / آيفون / كمبيوتر) من غير ما يحمّل APK.

> مهم: Flutter لازم يتبني (build) لنسخة ويب قبل الرفع. الملفات دي بتعمل البناء والرفع
> أوتوماتيك. **ما اتجرّبتش على بناء حقيقي** (مفيش Flutter SDK عندي)، فأول تشغيل ممكن يحتاج تعديل بسيط.

## الطريقة 1 — الأسهل: Codemagic (مفيش حاجة تتثبّت على جهازك)
1. فك الـ zip فوق مجلد المشروع (الملفات هتستبدل/تتضاف في أماكنها) وارفعها على Git.
2. من https://vercel.com/account/tokens اعمل Token.
3. في Codemagic: Teams → Global variables and secrets (أو Environment variables) → Group جديد اسمه **Vercel**
   فيه متغير **VERCEL_TOKEN** (علّمه Secure).
4. شغّل الـ workflow اسمه **وصلها - Web (Vercel)**.
5. آخر الـ log هيطلّع رابط `https://wasalha-xxxx.vercel.app`. (لو مفيش توكن، نزّل `wasalha-web.zip` من Artifacts.)

## الطريقة 2 — من جهازك
```bash
bash tools/build_web.sh          # بيطلّع build/web
cd build/web
npx vercel --prod                # أول مرة هيسألك تسجّل دخول
```

## خطوة لازمة وإلا تسجيل الدخول بجوجل مش هيشتغل
Firebase Console → Authentication → Settings → **Authorized domains** → Add domain →
ضيف دومين Vercel (مثلًا `wasalha.vercel.app`) ودومينك المخصص لو فيه.

## بدائل مجانية (من غير Vercel)
| الخدمة | ليه | الرفع |
|---|---|---|
| **Firebase Hosting** (الأنسب) | نفس مشروع `sada-51292`، ودومين `sada-51292.web.app` بيتضاف لوحده في Authorized domains | `npm i -g firebase-tools` ← `firebase login` ← `firebase init hosting` (public = `build/web`, single-page = yes) ← `firebase deploy --only hosting` |
| **Cloudflare Pages** | مجاني وبدون حد للـ bandwidth، ويسمح بالاستخدام التجاري | Dashboard ← Workers & Pages ← Create ← **Upload assets** ← ارفع `wasalha-web.zip` أو مجلد `build/web` |
| **Netlify Drop** | سحب وإفلات | https://app.netlify.com/drop ← اسحب مجلد `build/web` (ملف `_redirects` جاهز جواه) |

تنبيه: Vercel Hobby المجاني مخصّص للاستخدام الشخصي غير التجاري حسب علمي، وتطبيق توصيل مشروع تجاري —
راجع شروطهم الحالية، أو استخدم Firebase Hosting / Cloudflare Pages.

## اللي اتغيّر في الكود (كله إضافات، الأندرويد زي ما هو)
- `lib/main.dart`: تسجيل handler الخلفية بس لو مش ويب (`if (!kIsWeb)`).
- `lib/services/auth_service.dart`: على الويب تسجيل جوجل بـ popup من Firebase (`kIsWeb`)، والأندرويد كما هو.
- `lib/screens/notifications_view.dart`: القراءة التلقائية للإشعارات (من الطلب السابق).
- `codemagic.yaml`: أُضيف `web-workflow` في الآخر، والـ android-workflow ما اتلمسش.
- جديد: `tools/build_web.sh` و `tools/patch_web.py` و `web_deploy/vercel.json` و `web_deploy/_redirects`.

## حدود نسخة الويب
- إشعارات Push على الهاتف مش شغالة على الويب (محتاجة service worker + VAPID key). الإشعارات **داخل التطبيق** (Firestore) شغالة عادي،
  وزر «تفعيل الإشعارات» هيطلّع رسالة فشل على الويب.
- الموقع والكاميرا محتاجين HTTPS (متوفر) وموافقة المتصفح، وشاشات توثيق الكابتن بالكاميرا ما اتجرّبتش على الويب.
- بعد النشر اتأكد: تسجيل دخول، طلب جديد، الخريطة، الإشعارات.
