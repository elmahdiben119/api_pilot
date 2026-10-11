#!/usr/bin/env bash
# Generates the Android platform folder and applies API Pilot's manifest
# (INTERNET permission + cleartext HTTP for local/LAN APIs).
set -euo pipefail
cd "$(dirname "$0")"

flutter create --platforms=android --org dev.apipilot --project-name api_pilot .
cp android_overrides/AndroidManifest.xml android/app/src/main/AndroidManifest.xml
flutter pub get

echo
echo "Done. Next:"
echo "  flutter run                 # on a connected phone / emulator"
echo "  flutter build apk --release # APK in build/app/outputs/flutter-apk/"
