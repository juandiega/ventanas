#!/bin/bash
# Builds and packages Ventanas.app (ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=build/Ventanas.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Ventanas "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/Ventanas.icns "$APP/Contents/Resources/"
codesign --force --sign - --identifier app.ventanas.Ventanas "$APP"

echo "Done: $(pwd)/$APP"
