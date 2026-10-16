#!/usr/bin/env bash
# Generates the Android platform folder and applies API Pilot's manifest
# (INTERNET permission + cleartext HTTP for local/LAN APIs).
set -euo pipefail
cd "$(dirname "$0")"

# android/ is committed (app ID com.theminds.apipilot, signing, launcher icons).
# Only generate it when missing: `flutter create` derives the package from
# --org + project name (com.theminds.api_pilot), which doesn't match, so a
# fresh android/ needs applicationId/namespace and MainActivity's package fixed.
if [ ! -d android ]; then
  flutter create --platforms=android --org com.theminds --project-name api_pilot .
fi
cp android_overrides/AndroidManifest.xml android/app/src/main/AndroidManifest.xml
flutter pub get

echo
echo "Done. Next:"
echo "  flutter run                 # on a connected phone / emulator"
echo "  flutter build apk --release # APK in build/app/outputs/flutter-apk/"
