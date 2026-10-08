#!/usr/bin/env python3
"""يظبط مجلد web/ اللي بيولّده `flutter create` على هوية وصلها (عربي RTL + الأيقونات).
آمن للتشغيل أكتر من مرة، وأي خطوة بتفشل بتتخطى من غير ما توقف البناء."""
import json, os, re, sys

WEB = sys.argv[1] if len(sys.argv) > 1 else "web"
ICON = sys.argv[2] if len(sys.argv) > 2 else "assets/images/icon-512.png"
NAME = "وصلها"
DESC = "وصلها - خدمة التوصيل الذكية"

def rw(path, fn):
    if not os.path.exists(path):
        print("skip (missing):", path); return
    with open(path, encoding="utf-8") as f: s = f.read()
    n = fn(s)
    if n != s:
        with open(path, "w", encoding="utf-8") as f: f.write(n)
        print("patched:", path)

def index(s):
    s = re.sub(r"<html(\s[^>]*)?>", '<html lang="ar" dir="rtl">', s, count=1)
    s = re.sub(r"<title>.*?</title>", f"<title>{NAME}</title>", s, count=1, flags=re.S)
    s = re.sub(r'(<meta name="description" content=")[^"]*(")', rf"\g<1>{DESC}\g<2>", s, count=1)
    s = re.sub(r'(<meta name="apple-mobile-web-app-title" content=")[^"]*(")', rf"\g<1>{NAME}\g<2>", s, count=1)
    return s
rw(os.path.join(WEB, "index.html"), index)

mf = os.path.join(WEB, "manifest.json")
if os.path.exists(mf):
    try:
        with open(mf, encoding="utf-8") as f: m = json.load(f)
        m.update({"name": NAME, "short_name": NAME, "description": DESC, "lang": "ar", "dir": "rtl"})
        with open(mf, "w", encoding="utf-8") as f: json.dump(m, f, ensure_ascii=False, indent=2)
        print("patched:", mf)
    except Exception as e:
        print("manifest skipped:", e)

try:
    from PIL import Image
    if os.path.exists(ICON):
        img = Image.open(ICON).convert("RGBA")
        targets = {"icons/Icon-192.png": 192, "icons/Icon-512.png": 512,
                   "icons/Icon-maskable-192.png": 192, "icons/Icon-maskable-512.png": 512,
                   "favicon.png": 48}
        for rel, size in targets.items():
            dst = os.path.join(WEB, rel)
            if os.path.exists(dst):
                img.resize((size, size), Image.LANCZOS).save(dst)
        print("icons replaced")
except Exception as e:
    print("icons skipped:", e)
