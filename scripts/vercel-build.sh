#!/usr/bin/env bash
set -euo pipefail

FLUTTER_VERSION="stable"
FLUTTER_DIR="$HOME/flutter"

if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  rm -rf "$FLUTTER_DIR"
  git clone --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git "$FLUTTER_DIR"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"
flutter config --enable-web
flutter --version
flutter pub get
flutter build web --release --pwa-strategy=none
