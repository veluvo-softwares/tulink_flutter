# CI/CD secrets reference

Set these in GitHub → Settings → Secrets and variables → Actions.
Values that are base64-encoded files don't carry a `_B64` suffix —
the encoding is implicit (matching the existing ci.yml convention).

## Reused from existing ci.yml

| Secret | Used by | Source |
|---|---|---|
| `MAPBOX_ACCESS_TOKEN` | ci, alpha-android | Mapbox account |
| `GOOGLE_SERVICES_JSON` | ci, alpha-android | Base64 of `android/app/google-services.json` |
| `GOOGLE_SERVICE_INFO_PLIST` | ci | Base64 of `ios/Runner/GoogleService-Info.plist` |

## New for alpha distribution

| Secret | Used by | Source |
|---|---|---|
| `FIREBASE_SERVICE_ACCOUNT_JSON` | alpha-android | Base64 of GCP service account JSON (see Section 0.2) |
| `FIREBASE_ANDROID_APP_ID` | alpha-android | `1:547231952199:android:2dd41036abf563b1b9b062` |
| `FIREBASE_IOS_APP_ID` | alpha-ios (pending) | `1:547231952199:ios:bfaa22172ba03f51b9b062` |
| `ANDROID_KEYSTORE` | alpha-android | Base64 of `tulink-upload.jks` (see Section 0.3) |
| `ANDROID_KEYSTORE_PASSWORD` | alpha-android | Keystore password |
| `ANDROID_KEY_ALIAS` | alpha-android | `tulink-upload` |
| `ANDROID_KEY_PASSWORD` | alpha-android | Key password |
| `IOS_CERT_P12` | alpha-ios (pending) | Base64 of Apple Distribution `.p12` (see Section 0.4) |
| `IOS_CERT_PASSWORD` | alpha-ios (pending) | `.p12` export password |
| `IOS_PROVISIONING_PROFILE` | alpha-ios (pending) | Base64 of Ad Hoc `.mobileprovision` (see Section 0.4) |
| `IOS_KEYCHAIN_PASSWORD` | alpha-ios (pending) | Any strong random string |
| `APPLE_TEAM_ID` | alpha-ios (pending) | `29M86UUNK8` |

> Secrets marked **pending** are not yet in use — the `alpha-ios.yml` workflow
> will be added once Apple Developer Program enrollment is complete.

## Rotation

- **Firebase service account:** rotate yearly, on offboarding, or after any
  suspected leak. Delete the old key from GCP after the new one is active.
- **iOS cert:** expires yearly. Generate a new one, re-export `.p12`, update
  the secret. Regenerate the Ad Hoc profile if the cert changes.
- **iOS provisioning profile:** refresh whenever a new tester UDID is added.
  Update `IOS_PROVISIONING_PROFILE` with the re-exported base64 value.
- **Android keystore:** never rotate. Play Store rejects APKs signed with a
  different key than the original upload. Keep multiple offline backups.
