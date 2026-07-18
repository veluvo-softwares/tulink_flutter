# CI/CD secrets reference

Set these in GitHub → Settings → Secrets and variables → Actions.
Values that are base64-encoded files don't carry a `_B64` suffix —
the encoding is implicit (matching the existing ci.yml convention).

## Reused from existing ci.yml

| Secret | Used by | Source |
|---|---|---|
| `MAPBOX_ACCESS_TOKEN` | ci, alpha-android, alpha-ios | Mapbox account |
| `GOOGLE_SERVICES_JSON` | ci, alpha-android | Base64 of `android/app/google-services.json` |
| `GOOGLE_SERVICE_INFO_PLIST` | ci, alpha-ios | Base64 of `ios/Runner/GoogleService-Info.plist` |
| `GOOGLE_SERVER_CLIENT_ID` | ci, alpha-android, alpha-ios | Firebase **Web** OAuth client id (Google sign-in `serverClientId`). Plain string — written into `.env` as `GOOGLE_SERVER_CLIENT_ID`. Found in `google-services.json` under the `oauth_client` entry with `"client_type": 3`. |

> **After enabling Google/Apple in Firebase**, refresh the two file secrets with the
> newly downloaded configs (they now contain the OAuth clients):
> ```bash
> base64 -i ios/Runner/GoogleService-Info.plist | pbcopy   # → GOOGLE_SERVICE_INFO_PLIST
> base64 -i android/app/google-services.json | pbcopy      # → GOOGLE_SERVICES_JSON
> ```

## New for alpha distribution (Android)

| Secret | Used by | How to produce |
|---|---|---|
| `FIREBASE_SERVICE_ACCOUNT_JSON` | alpha-android | See [Firebase service account](#firebase-service-account) below |
| `FIREBASE_ANDROID_APP_ID` | alpha-android | `1:547231952199:android:2dd41036abf563b1b9b062` |
| `ANDROID_KEYSTORE` | alpha-android | See [Android keystore](#android-keystore) below |
| `ANDROID_KEYSTORE_PASSWORD` | alpha-android | Password set during keytool generation |
| `ANDROID_KEY_ALIAS` | alpha-android | `tulink-upload` |
| `ANDROID_KEY_PASSWORD` | alpha-android | Key password set during keytool generation |

## New for TestFlight distribution (iOS)

| Secret | Used by | How to produce |
|---|---|---|
| `IOS_CERT_P12` | alpha-ios | See [iOS signing assets](#ios-signing-assets) below |
| `IOS_CERT_PASSWORD` | alpha-ios | Password used when exporting the `.p12` from Keychain |
| `IOS_PROVISIONING_PROFILE` | alpha-ios | See [iOS signing assets](#ios-signing-assets) below |
| `IOS_PROVISIONING_PROFILE_NAME` | alpha-ios | `TuLink App Store` |
| `IOS_WIDGET_PROVISIONING_PROFILE` | alpha-ios | App Store profile for `xyz.tulink.app.TulinkJourneyWidget` named `TuLink Widget App Store`, base64-encoded like the main profile |
| `IOS_KEYCHAIN_PASSWORD` | alpha-ios | Any strong random string (used for the temporary CI keychain) |
| `APP_STORE_CONNECT_API_KEY` | alpha-ios | See [App Store Connect API key](#app-store-connect-api-key) below |
| `APP_STORE_CONNECT_API_KEY_ID` | alpha-ios | `Z2ACV7GS97` |
| `APP_STORE_CONNECT_API_ISSUER_ID` | alpha-ios | `9b1bc669-a95a-4a48-8b95-5d7650bc7651` |
| `APPLE_TEAM_ID` | alpha-ios | `29M86UUNK8` |

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

TestFlight distribution uses manual signing with a pre-generated Apple
Distribution certificate and an App Store type provisioning profile. No
tester device registration is required — TestFlight handles tester devices
server-side.

1. Apple Developer → Certificates → create an **Apple Distribution** certificate
2. Export from Keychain as `.p12` with a strong password
3. Apple Developer → Profiles → create an **App Store** type provisioning
   profile for `xyz.tulink.app`, name it `TuLink App Store`, and download it
4. Base64-encode both files:
   ```bash
   base64 -i tulink-distribution.p12 | pbcopy           # → IOS_CERT_P12
   base64 -i TuLink_App_Store.mobileprovision | pbcopy  # → IOS_PROVISIONING_PROFILE
   ```
5. Set `IOS_PROVISIONING_PROFILE_NAME` to the profile's display name exactly as
   it appears in Apple Developer (`TuLink App Store`).
6. Widget extension (Live Activity, added 2026-07-18): the app and its
   extension are separate bundle ids, each needing its own App Store profile,
   and both App IDs carry the **App Groups** capability
   (`group.xyz.tulink.app`). In Apple Developer:
   - Identifiers → App Groups: register `group.xyz.tulink.app` if missing.
   - App ID `xyz.tulink.app`: enable App Groups, assign the group — this
     **invalidates the existing profile**; edit + re-save `TuLink App Store`,
     re-download, re-encode into `IOS_PROVISIONING_PROFILE`.
   - App ID `xyz.tulink.app.TulinkJourneyWidget` (Xcode may have created it):
     enable App Groups, assign the group; create an App Store profile named
     `TuLink Widget App Store` with the same distribution cert; download and
     base64 into `IOS_WIDGET_PROVISIONING_PROFILE`.

### App Store Connect API key

Used only to authenticate `upload_to_testflight` (the fastlane TestFlight
upload step) — it is not used for generating signing assets, since signing
is done manually with the cert and profile above.

1. App Store Connect → Users and Access → Integrations → App Store Connect API
2. Generate a new key (App Manager role is sufficient) and download the
   `.p8` file immediately — Apple only allows downloading it once
3. Base64-encode it the same way as the other files:
   ```bash
   base64 -i AuthKey_Z2ACV7GS97.p8 | pbcopy   # → APP_STORE_CONNECT_API_KEY
   ```
4. Record the Key ID and Issuer ID shown on that page as
   `APP_STORE_CONNECT_API_KEY_ID` and `APP_STORE_CONNECT_API_ISSUER_ID`.

---

## Rotation

- **Firebase service account:** rotate yearly, on offboarding, or after any
  suspected leak. Create a new key in GCP first, update the secret, then delete
  the old key.
- **iOS cert:** expires yearly. Generate a new one, re-export `.p12`, update
  `IOS_CERT_P12`. Regenerate the App Store profile if the cert changes.
- **iOS provisioning profile:** the App Store profile expires 2027-06-15.
  Re-download from Apple Developer before expiry, re-encode, update
  `IOS_PROVISIONING_PROFILE`.
- **App Store Connect API key:** no fixed expiry. Revoke and regenerate in
  App Store Connect if leaked or compromised; rotate on suspected compromise.
- **Android keystore:** the Play Store permanently binds an app to the first
  upload key. **Do not rotate under normal circumstances.** Maintain at least
  two offline backups in separate locations (e.g. encrypted password manager +
  encrypted external drive). If the key is compromised, contact Google Play
  support immediately to initiate an upload-key reset via Play App Signing —
  this requires identity verification and Google's approval. Rotation without
  Google's involvement will make future updates uninstallable by existing users.
