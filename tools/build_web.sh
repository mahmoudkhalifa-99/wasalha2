#!/usr/bin/env bash
# يبني نسخة الويب من وصلها جاهزة للرفع على Vercel / Firebase Hosting / Cloudflare / Netlify.
# الاستخدام (من جذر المشروع):   bash tools/build_web.sh
# الناتج: build/web  +  build/wasalha-web.zip
set -euo pipefail

# 1) توليد منصة الويب لو مش موجودة (زي ما بنعمل مع android في codemagic.yaml)
if [ ! -f web/index.html ]; then
  echo ">> توليد مجلد web ..."
  flutter create --platforms=web --org com.wasalah --project-name wasalha .
  # flutter create بيضيف widget_test افتراضي بيكسر flutter test — نشيله لو هو الافتراضي بس
  if [ -f test/widget_test.dart ] && grep -q "const MyApp()" test/widget_test.dart; then
    rm -f test/widget_test.dart
  fi
fi

# 2) هوية وصلها (عربي RTL + أيقونات)
python3 tools/patch_web.py web assets/images/icon-512.png || true

# 3) البناء
flutter pub get
flutter build web --release --dart-define=PUSH_RELAY_URL="${PUSH_RELAY_URL:-}"

# 4) ملفات الاستضافة (SPA rewrite + كاش) جنب الناتج
cp web_deploy/vercel.json build/web/vercel.json
cp web_deploy/_redirects build/web/_redirects

# 5) نسخة zip جاهزة للرفع اليدوي
python3 - <<'PY'
import os, zipfile
src, dst = "build/web", "build/wasalha-web.zip"
with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as z:
    for root, _, files in os.walk(src):
        for f in files:
            p = os.path.join(root, f)
            z.write(p, os.path.relpath(p, src))
print("ZIP:", dst)
PY
echo ">> تمام: build/web جاهز  (و build/wasalha-web.zip)"
