#!/usr/bin/env bash
set -euo pipefail

# Tu-Link — Alpha release script
# Builds a signed release APK and distributes it via Firebase App Distribution.
#
# Usage:
#   ./scripts/release-alpha.sh "Release notes"
#       → distributes to the whole alpha-testers group
#
#   ./scripts/release-alpha.sh "Release notes" --tester "email@example.com"
#       → distributes to a single tester
#
#   ./scripts/release-alpha.sh "Release notes" --testers "email1@x.com,email2@x.com"
#       → distributes to a specific list of testers

APP_ID="1:547231952199:android:2dd41036abf563b1b9b062"
DIST_GROUPS="tulink-alpha-testers"
APK_PATH="build/app/outputs/flutter-apk/app-release.apk"

RELEASE_NOTES=""
TESTER_EMAILS=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tester|--testers)
      TESTER_EMAILS="$2"
      shift 2
      ;;
    *)
      if [[ -z "$RELEASE_NOTES" ]]; then
        RELEASE_NOTES="$1"
      fi
      shift
      ;;
  esac
done

# Fall back to last git commit message if no release notes provided
if [[ -z "$RELEASE_NOTES" ]]; then
  RELEASE_NOTES="$(git log -1 --pretty=%B)"
fi

echo "Building release APK..."
flutter clean
flutter pub get
flutter build apk --release

if [ ! -f "$APK_PATH" ]; then
  echo "APK not found at $APK_PATH"
  exit 1
fi

if [[ -n "$TESTER_EMAILS" ]]; then
  echo "Distributing to tester(s): $TESTER_EMAILS"
  firebase appdistribution:distribute "$APK_PATH" \
    --app "$APP_ID" \
    --testers "$TESTER_EMAILS" \
    --release-notes "$RELEASE_NOTES"
else
  echo "Distributing to group: $DIST_GROUPS"
  firebase appdistribution:distribute "$APK_PATH" \
    --app "$APP_ID" \
    --groups "$DIST_GROUPS" \
    --release-notes "$RELEASE_NOTES"
fi

echo "Distribution complete. Testers will receive an email shortly."
