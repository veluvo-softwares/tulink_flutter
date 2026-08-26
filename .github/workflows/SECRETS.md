# CI/CD secrets reference

Set these in GitHub → Settings → Secrets and variables → Actions.
Values that are base64-encoded files don't carry a `_B64` suffix —
the encoding is implicit (matching the existing ci.yml convention).

## Reused from existing ci.yml

| Secret | Used by | Source |
|---|---|---|
| `MAPBOX_ACCESS_TOKEN` | ci, android-release, alpha-ios | Mapbox account |
| `GOOGLE_SERVICES_JSON` | ci, android-release | Base64 of `android/app/google-services.json` |
| `GOOGLE_SERVICE_INFO_PLIST` | ci, alpha-ios | Base64 of `ios/Runner/GoogleService-Info.plist` |
| `GOOGLE_SERVER_CLIENT_ID` | ci, android-release, alpha-ios | Firebase **Web** OAuth client id (Google sign-in `serverClientId`). Plain string — written into `.env` as `GOOGLE_SERVER_CLIENT_ID`. Found in `google-services.json` under the `oauth_client` entry with `"client_type": 3`. |

> **After enabling Google/Apple in Firebase**, refresh the two file secrets with the
> newly downloaded configs (they now contain the OAuth clients):
> ```bash
> base64 -i ios/Runner/GoogleService-Info.plist | pbcopy   # → GOOGLE_SERVICE_INFO_PLIST
> base64 -i android/app/google-services.json | pbcopy      # → GOOGLE_SERVICES_JSON
> ```

## Android distribution — Google Play

Android tester releases now ship exclusively through Google Play:

| Workflow | Trigger | Destination |
|---|---|---|
| `android-release.yml` | every push to `develop`; manual dispatch; `v*` tag | Google Play (AAB) |

Every `develop` push builds a signed AAB and publishes it to the track named by
`PLAY_CLOSED_TESTING_TRACK`. Enrolled testers receive updates through Google
Play; Firebase App Distribution is no longer part of Android delivery.

### Google Play

| Secret | Used by | How to produce |
|---|---|---|
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | android-release | See [Google Play service account](#google-play-service-account) below |

This is an **environment** secret, not a repo-wide one, so the testing and
production identities stay isolated.

> **Environment secrets are not shared between environments.** The workflow's
> two jobs run under different environments, so the secret must be stored
> **twice**, under the same name:
>
> | Environment | Used by | Status |
> |---|---|---|
> | `play-testing` | the `upload` job (`dry-run`, `upload`) | set |
> | `production` | the `promote` job (`v*` tags, `mode: promote`) | **not yet set** |
>
> Until a credential exists on the `production` environment, every `promote`
> run — including any `v*` tag push — fails at preflight with a clear message.
> That is intentional while production access is pending: nothing can reach the
> production track by accident. Add it as part of enabling production releases,
> ideally as a *separate* service account so a testing credential leak can
> never publish to production.

### Android signing secrets

| Secret | Used by | How to produce |
|---|---|---|
| `ANDROID_KEYSTORE` | android-release | See [Android keystore](#android-keystore) below |
| `ANDROID_KEYSTORE_PASSWORD` | android-release | Password set during keytool generation |
| `ANDROID_KEY_ALIAS` | android-release | `tulink-upload` |
| `ANDROID_KEY_PASSWORD` | android-release | Key password set during keytool generation |

### Repo variables

Set under Settings → Secrets and variables → Actions → **Variables** tab (not
Secrets — none of these are sensitive):

| Variable | Used by | Value |
|---|---|---|
| `PLAY_CLOSED_TESTING_TRACK` | android-release | The exact Play API track identifier. **For this app it is `Tu-link Closed Testing`.** |
| `IOS_PRODUCTION_ENABLED` | production | `true` once the iOS App Store lane is implemented. Unset = the job never runs. |

> ### ⚠️ The track identifier contains spaces
>
> Play's API track id for a custom closed track is its Play Console **display
> name**, verbatim — here `Tu-link Closed Testing`, capitals and spaces
> included. It is *not* a slug, and it is not `alpha`.
>
> Every shell use must be quoted (`track:"$TRACK"`). Unquoted, bash splits it
> into three arguments and fastlane silently receives `track:Tu-link`, which
> fails as an unknown track only after the build has finished.
>
> To re-derive the identifier, call `edits.tracks.list` on the Play Developer
> API with the service account — the Console UI does not display it.

### Release modes

`android-release.yml` takes a `mode` input on manual dispatch:

| Mode | What it does |
|---|---|
| `dry-run` (default) | Builds and validates against Play via `validate_only` — uploads nothing. Safe to run any time. |
| `upload` | Builds a signed AAB and uploads it to the closed testing track. |
| `promote` | Promotes an **existing** closed-testing versionCode to production. Never rebuilds, so the exact bytes testers vetted are what ship. Also what a `v*` tag triggers. |

Production is reachable *only* through `promote`; the workflow refuses any other
mode targeting it. The first production release is forced to 100% / `completed`,
because Play rejects a staged rollout when production has no previous release.

Note that the service account is intentionally granted only "View app
information" and "Release apps to testing tracks" in Play Console — **not**
production release permission. Until that is granted, a `promote` run will fail
at the API, by design.

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

### Google Play service account

Before this works, the app must already have **one manual release uploaded**
through the Play Console UI — the Play Developer API refuses uploads for an
app that has never had a manual release, even to closed testing.

1. Play Console → Setup → API access → link (or create) a Google Cloud
   project, then create a new service account from that page (or in GCP
   Console → IAM & Admin → Service Accounts).
2. In Play Console → **Users and permissions** → Invite user, paste the
   service account's email and grant it app access to `xyz.tulink.app` with
   exactly these two permissions:
   - **View app information (read only)**
   - **Release apps to testing tracks**

   Deliberately do **not** grant *Release to production, exclude devices and
   use Play app signing* yet. Withholding it means no workflow, tag, or
   misconfiguration can publish to production — CI simply cannot. Add it (or
   better, grant it to a separate production-only service account) at the point
   you are ready to ship production, which is also when you populate the
   `production` environment secret above.
3. In GCP Console, open the service account → Keys tab → Add key → JSON →
   download the file.
4. Base64-encode and copy to clipboard:
   ```bash
   base64 -i play-sa.json | pbcopy
   ```
5. Paste as the `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` secret value.

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

- **Google Play service account** (`play-publisher-ci@tulink-app-1a942`): no
  fixed expiry. Rotate on suspected compromise or offboarding — create a new key
  in GCP first, update the secret, then delete the old key.
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
