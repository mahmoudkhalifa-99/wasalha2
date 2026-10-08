#!/usr/bin/env bash
# تشغيل مرة واحدة بعد تثبيت Flutter:  bash setup_android.sh
set -e
flutter create --org com.wasalah --project-name wasalha --platforms=android .
python3 tools/patch_android.py
flutter pub get
echo
echo "✅ جاهز. الخطوة الجاية: ربط Firebase (appId الأندرويد الحقيقي):"
echo "   dart pub global activate flutterfire_cli"
echo "   flutterfire configure --project=sada-51292 --platforms=android --android-package-name=com.wasalah.app"
echo "ثم:  flutter run   أو   flutter build apk --release"
