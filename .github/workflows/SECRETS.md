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

| Secret | Used by | How to produce |
|---|---|---|
| `FIREBASE_SERVICE_ACCOUNT_JSON` | alpha-android | See [Firebase service account](#firebase-service-account) below |
| `FIREBASE_ANDROID_APP_ID` | alpha-android | `1:547231952199:android:2dd41036abf563b1b9b062` |
| `FIREBASE_IOS_APP_ID` | alpha-ios (pending) | `1:547231952199:ios:bfaa22172ba03f51b9b062` |
| `ANDROID_KEYSTORE` | alpha-android | See [Android keystore](#android-keystore) below |
| `ANDROID_KEYSTORE_PASSWORD` | alpha-android | Password set during keytool generation |
| `ANDROID_KEY_ALIAS` | alpha-android | `tulink-upload` |
| `ANDROID_KEY_PASSWORD` | alpha-android | Key password set during keytool generation |
| `IOS_CERT_P12` | alpha-ios (pending) | See [iOS signing assets](#ios-signing-assets) below |
| `IOS_CERT_PASSWORD` | alpha-ios (pending) | Password used when exporting the `.p12` from Keychain |
| `IOS_PROVISIONING_PROFILE` | alpha-ios (pending) | See [iOS signing assets](#ios-signing-assets) below |
| `IOS_PROVISIONING_PROFILE_NAME` | alpha-ios (pending) | Display name of the Ad Hoc profile (e.g. `Tu-Link Ad Hoc`) |
| `IOS_KEYCHAIN_PASSWORD` | alpha-ios (pending) | Any strong random string (used for the temporary CI keychain) |
| `APPLE_TEAM_ID` | alpha-ios (pending) | `29M86UUNK8` |

> Secrets marked **pending** are not yet in use — `alpha-ios.yml` will be
> added once Apple Developer Program enrollment is complete.

---

## How to produce each secret value

### Firebase service account

1. GCP Console → IAM & Admin → Service Accounts → select `firebase-app-distribution-ci`
2. Keys tab → Add key → JSON → download the file
3. Base64-encode and copy to clipboard:
   ```bash
   base64 -i firebase-sa.json | pbcopy
   ```
4. Paste as the `FIREBASE_SERVICE_ACCOUNT_JSON` secret value.

### Android keystore

Generate once and store the `.jks` file in a secure offline backup immediately.

```bash
mkdir -p ~/keys
keytool -genkey -v \
  -keystore ~/keys/tulink-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias tulink-upload
```

Base64-encode for GitHub:
```bash
base64 -i ~/keys/tulink-upload.jks | pbcopy
```

Paste as `ANDROID_KEYSTORE`. Record the passwords as `ANDROID_KEYSTORE_PASSWORD`
and `ANDROID_KEY_PASSWORD` in your password manager.

### iOS signing assets

1. Apple Developer → Certificates → create an **Apple Distribution** certificate
2. Export from Keychain as `.p12` with a strong password
3. Apple Developer → Devices → register tester UDIDs
4. Apple Developer → Profiles → create **Ad Hoc** profile for `xyz.tulink.app`,
   include registered devices, download it
5. Base64-encode both files:
   ```bash
   base64 -i tulink-distribution.p12 | pbcopy   # → IOS_CERT_P12
   base64 -i Tu_Link_Ad_Hoc.mobileprovision | pbcopy  # → IOS_PROVISIONING_PROFILE
   ```
6. Set `IOS_PROVISIONING_PROFILE_NAME` to the profile's display name exactly as
   it appears in Apple Developer (e.g. `Tu-Link Ad Hoc`).

---

## Rotation

- **Firebase service account:** rotate yearly, on offboarding, or after any
  suspected leak. Create a new key in GCP first, update the secret, then delete
  the old key.
- **iOS cert:** expires yearly. Generate a new one, re-export `.p12`, update
  `IOS_CERT_P12`. Regenerate the Ad Hoc profile if the cert changes and update
  `IOS_PROVISIONING_PROFILE`.
- **iOS provisioning profile:** refresh whenever a new tester UDID is added.
  Re-download from Apple Developer, re-encode, update `IOS_PROVISIONING_PROFILE`.
- **Android keystore:** the Play Store permanently binds an app to the first
  upload key. **Do not rotate under normal circumstances.** Maintain at least
  two offline backups in separate locations (e.g. encrypted password manager +
  encrypted external drive). If the key is compromised, contact Google Play
  support immediately to initiate an upload-key reset via Play App Signing —
  this requires identity verification and Google's approval. Rotation without
  Google's involvement will make future updates uninstallable by existing users.
