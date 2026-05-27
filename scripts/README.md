# Tu-Link Release Scripts

## release-alpha.sh

Builds a signed release APK and distributes it to testers via Firebase App Distribution.

### Prerequisites

- Flutter SDK installed and on PATH
- Firebase CLI installed (`npm install -g firebase-tools`)
- Logged in to Firebase CLI (`firebase login`)
- Android release signing configured (currently uses debug keystore — update before Play Store submission)

### Usage

**Distribute to the entire alpha group**
```bash
./scripts/release-alpha.sh "Your release notes here"
```

**Distribute to a single tester**
```bash
./scripts/release-alpha.sh "Your release notes here" --tester "email@example.com"
```

**Distribute to a specific subset of testers**
```bash
./scripts/release-alpha.sh "Your release notes here" --testers "email1@example.com,email2@example.com"
```

**Omit release notes — falls back to the last git commit message**
```bash
./scripts/release-alpha.sh
```

### What the script does

1. Runs `flutter clean` and `flutter pub get`
2. Builds `app-release.apk` via `flutter build apk --release`
3. Uploads the APK to Firebase App Distribution
4. Attaches the release notes
5. Notifies the target testers by email

### Firebase config

| Key | Value |
|---|---|
| Project | `tulink-app-1a942` |
| Android App ID | `1:547231952199:android:2dd41036abf563b1b9b062` |
| Package name | `xyz.tulink.app` |
| Default tester group | `tulink-alpha-testers` |

### Managing testers

Testers are managed in the Firebase Console:
**Firebase Console → App Distribution → Testers & Groups → tulink-alpha-testers**

Current testers in the group:
- `adrian.ignat@yahoo.com`
- `blaisenyange10@gmail.com`
- `wesley@minmo.to`

### Viewing releases and crashes

- **Releases:** Firebase Console → App Distribution → `xyz.tulink.app` → Releases
- **Crashes:** Firebase Console → Crashlytics → `xyz.tulink.app` → Android

### First-time tester setup

Testers receive an email invite when added. They need to:
1. Accept the invite via the email link
2. Install the **Firebase App Tester** companion app (one-time)
3. Future releases appear as notifications inside App Tester automatically

### Notes

- Crashlytics is **disabled in debug builds** (`kDebugMode = true`) — use `--release` or `--profile` to test crash reporting
- The release APK lands at `build/app/outputs/flutter-apk/app-release.apk` after a successful build
- Build artifacts are git-ignored — never commit the APK
