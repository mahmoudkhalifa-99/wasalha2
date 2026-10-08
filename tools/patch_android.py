#!/usr/bin/env python3
"""يعدّل مشروع الأندرويد اللي طلّعه `flutter create` عشان يطابق تطبيق وصلها."""
import os, re, shutil, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, 'android', 'app')
if not os.path.isdir(APP):
    sys.exit('android/app مش موجود — شغّل: flutter create --org com.wasalah --platforms=android .')

# 1) applicationId + minSdk (Firebase محتاج 23 على الأقل)
for name in ('build.gradle.kts', 'build.gradle'):
    p = os.path.join(APP, name)
    if not os.path.exists(p):
        continue
    s = open(p, encoding='utf-8').read()
    s = re.sub(r'applicationId\s*=?\s*"[^"]+"', lambda m: m.group(0).split('"')[0] + '"com.wasalah.app"', s)
    s = re.sub(r'minSdk(Version)?\s*=?\s*flutter\.minSdkVersion',
               lambda m: m.group(0).replace('flutter.minSdkVersion', '23'), s)
    open(p, 'w', encoding='utf-8').write(s)
    print('patched', name)

# 2) AndroidManifest
mp = os.path.join(APP, 'src', 'main', 'AndroidManifest.xml')
m = open(mp, encoding='utf-8').read()
perms = [
    'android.permission.INTERNET',
    'android.permission.ACCESS_FINE_LOCATION',
    'android.permission.ACCESS_COARSE_LOCATION',
    'android.permission.CAMERA',
    'android.permission.ACCESS_NETWORK_STATE',
    'android.permission.POST_NOTIFICATIONS',
]
block = ''.join(f'    <uses-permission android:name="{p}" />\n'
                for p in perms if p not in m)
if block:
    m = m.replace('<application', block + '    <application', 1)
m = re.sub(r'android:label="[^"]*"', 'android:label="وصلها"', m, count=1)
if 'default_notification_icon' not in m:
    meta = ('        <meta-data android:name="com.google.firebase.messaging.default_notification_icon"\n'
            '            android:resource="@mipmap/ic_launcher" />\n'
            '        <meta-data android:name="com.google.firebase.messaging.default_notification_color"\n'
            '            android:resource="@color/colorPrimary" />\n')
    m = m.replace('</application>', meta + '    </application>', 1)
if '<queries>' not in m:
    q = ('    <queries>\n'
         '        <intent><action android:name="android.intent.action.VIEW" /><data android:scheme="https" /></intent>\n'
         '    </queries>\n')
    m = m.replace('</manifest>', q + '</manifest>', 1)
open(mp, 'w', encoding='utf-8').write(m)
print('patched AndroidManifest.xml')

# 3) الأيقونات + السبلاش + الألوان
src = os.path.join(ROOT, 'android_overrides', 'res')
dst = os.path.join(APP, 'src', 'main', 'res')
for dp, _, files in os.walk(src):
    for f in files:
        rel = os.path.relpath(os.path.join(dp, f), src)
        out = os.path.join(dst, rel)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        shutil.copy2(os.path.join(dp, f), out)
# نفس الـ launch_background في drawable-v21 لو موجود
v21 = os.path.join(dst, 'drawable-v21')
if os.path.isdir(v21):
    shutil.copy2(os.path.join(src, 'drawable', 'launch_background.xml'),
                 os.path.join(v21, 'launch_background.xml'))
print('copied icons / splash / colors')


# 4) google-services.json + إضافة الـ plugin (مطلوب لتسجيل الدخول بجوجل)
gs_src = os.path.join(ROOT, 'android_overrides', 'google-services.json')
if os.path.exists(gs_src):
    shutil.copy2(gs_src, os.path.join(APP, 'google-services.json'))
    import json
    try:
        pkgs = [c['client_info']['android_client_info']['package_name']
                for c in json.load(open(gs_src, encoding='utf-8'))['client']]
        print('google-services.json packages:', pkgs)
        if 'com.wasalah.app' not in pkgs:
            sys.exit('google-services.json مش لـ com.wasalah.app — نزّل الملف الصح من Firebase')
    except (KeyError, ValueError) as e:
        sys.exit(f'google-services.json شكله غير صحيح: {e}')

    PLUGIN_ID = 'com.google.gms.google-services'
    # settings.gradle.kts (طريقة plugins الجديدة)
    sp = os.path.join(ROOT, 'android', 'settings.gradle.kts')
    if os.path.exists(sp):
        t = open(sp, encoding='utf-8').read()
        if PLUGIN_ID not in t:
            t = re.sub(r'(id\("com\.android\.application"\)\s+version\s+"[^"]+"\s+apply\s+false)',
                       r'\1\n    id("' + PLUGIN_ID + '") version "4.4.2" apply false', t, count=1)
            open(sp, 'w', encoding='utf-8').write(t)
    for name in ('build.gradle.kts', 'build.gradle'):
        bp = os.path.join(APP, name)
        if not os.path.exists(bp):
            continue
        t = open(bp, encoding='utf-8').read()
        if PLUGIN_ID not in t:
            anchor = 'dev.flutter.flutter-gradle-plugin'
            line = ('    id("' + PLUGIN_ID + '")') if name.endswith('.kts') else ("    id '" + PLUGIN_ID + "'")
            if anchor in t:
                t = re.sub(r'([^\n]*' + re.escape(anchor) + r'[^\n]*\n)', lambda m: m.group(1) + line + '\n', t, count=1)
            else:
                t = t.replace('plugins {', 'plugins {\n' + line, 1)
            open(bp, 'w', encoding='utf-8').write(t)
            print('added google-services plugin to', name)
else:
    print('WARNING: android_overrides/google-services.json مش موجود — تسجيل الدخول بجوجل مش هيشتغل')

# 5) تأكيد اسم التطبيق
m = open(mp, encoding='utf-8').read()
print('APP LABEL =>', re.findall(r'android:label="([^"]*)"', m))
