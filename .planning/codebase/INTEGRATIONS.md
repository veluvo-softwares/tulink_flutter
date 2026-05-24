# External Integrations

**Analysis Date:** 2026-05-24

## APIs & External Services

**TuLink Backend (REST):**
- Service — Custom NestJS backend (per project memory: `tulink-backend`)
  - SDK/Client: `DioClient` singleton (`lib/core/network/dio_client.dart`) using `dio 5.7.0`
  - Base URL dev: `https://api.dev.tulink.xyz` (configured in `lib/core/config/app_config.dart`)
  - Auth: Bearer token in `Authorization` header; auto-injected by `QueuedInterceptorsWrapper` auth interceptor
  - Retry: exponential backoff up to 3 attempts; 5xx and network timeouts only

**TuLink Backend (WebSocket / Socket.IO):**
- Service — Same NestJS backend, `/location` namespace
  - SDK/Client: `socket_io_client 2.0.3+1` (`lib/features/convoy/data/datasources/convoy_websocket_data_source.dart`)
  - WebSocket URL dev: `https://api.dev.tulink.xyz` (`AppConfig.webSocketUrl`)
  - Auth: JWT passed via Socket.IO `auth` handshake `{ token: <idToken> }`
  - Transport: WebSocket only (polling disabled)
  - Heartbeat: 4-second interval (`HEARTBEAT_TIMEOUT_MS=7000` on backend)
  - Reconnect: exponential backoff [1, 2, 4, 8, 15, 30]s, max 10 attempts; circuit breaker after 3 short-lived connections

**Mapbox Maps:**
- Service — Map rendering, routing, and place search
  - SDK/Client: `mapbox_maps_flutter 2.19.1`
  - Auth: `MAPBOX_ACCESS_TOKEN` env var; set at boot via `MapboxOptions.setAccessToken()` in `lib/main.dart`
  - Map rendering: `MapboxMap` widget in `lib/features/maps/presentation/tulink_map_screen.dart`
  - Routing: proxied through TuLink backend `POST /maps/route` — backend calls Mapbox Directions API and returns normalized response (`lib/features/maps/data/datasources/route_remote_data_source.dart`)
  - Place search: proxied through TuLink backend `GET /maps/search` — backend calls Mapbox Geocoding and returns normalized response (`lib/features/maps/data/datasources/place_search_remote_data_source.dart`)
  - iOS: integrated via CocoaPods (`ios/Podfile.lock`)
  - Android: integrated via Gradle (standard Mapbox Maven setup)

**Device Text-to-Speech (System):**
- Service — Platform TTS engine (no cloud API)
  - SDK/Client: `flutter_tts 4.2.5`
  - Usage: turn-by-turn voice instructions at 500m, 100m, and on arrival (`lib/features/maps/presentation/services/voice_instruction_service.dart`)
  - Language: `en-US`, speech rate 0.5, pitch 1.0

## Data Storage

**Databases:**
- Hive (embedded NoSQL)
  - Client: `hive 2.2.3` + `hive_flutter 1.1.0`
  - Initialization: `Hive.initFlutter()` at app boot in `lib/main.dart`
  - Registered adapters: `UserModelAdapter` (typeId: 0, `lib/features/auth/data/models/user_model.dart`)
  - Usage: caching authenticated user data, journey data
  - Location: device local storage (no external server)

**File Storage:**
- Local filesystem only (assets in `assets/icons/`, icon at `assets/icon/icon.png`)

**Caching:**
- Hive boxes — tiered TTL strategy defined in `AppConfig`:
  - Short cache: 15 minutes
  - Default cache: 24 hours
  - Long cache: 7 days

## Authentication & Identity

**Auth Provider:**
- Custom — TuLink backend issues Firebase-format JWT tokens (idToken + refreshToken)
  - Tokens are described internally as "Firebase ID tokens" but are issued by the TuLink backend at `POST /auth/login` and `POST /auth/register`
  - No Firebase SDK dependency detected in `pubspec.yaml` or platform config
  - The backend likely uses Firebase Admin SDK to mint tokens server-side

**Token Storage:**
- `flutter_secure_storage 9.2.2` — platform keychain/keystore
- Managed by `TokenManager` singleton (`lib/core/auth/token_manager.dart`)
- Keys: `StorageKeys.authToken`, `StorageKeys.refreshToken` (`lib/core/constants/storage_keys.dart`)
- JWT payload decoded client-side for expiry detection (base64 decode, no verify)

**Token Lifecycle:**
- Access token expiry buffer: 5 minutes (`AppConfig.tokenExpiryBufferMinutes`)
- Preemptive refresh triggered if token expires within buffer
- On 401 + `TOKEN_EXPIRED` response code: auto-refresh via `POST /auth/refresh` using bare Dio instance (avoids interceptor deadlock)
- Concurrent refresh deduplication via `Completer` in `TokenManager`
- On refresh failure: all tokens cleared, `onAuthLost` callback fires → navigation to login

**Session Endpoints:**
- Sign in: `POST /auth/login`
- Register: `POST /auth/register`
- Sign out: `POST /auth/logout`
- Token refresh: `POST /auth/refresh` — body `{ refreshToken: <token> }`, returns `data.idToken` + `data.refreshToken`
- Current user: `GET /auth/profile`
- Delete account: `DELETE /auth/account`

## Monitoring & Observability

**Error Tracking:**
- `AppConfig.enableCrashReporting` flag exists (production only) — no crash reporting SDK detected in `pubspec.yaml`; flag is declared but wired to nothing in current code

**Logs:**
- `logger 2.7.0` used via `lib/core/utils/logger.dart`
- `pretty_dio_logger 1.4.0` for HTTP request/response logging (disabled in production via `AppConfig.enableDetailedLogging`)
- Raw `print()` statements present throughout (not controlled by feature flags)

## CI/CD & Deployment

**Hosting:**
- Not configured in repo (no Fastlane, Codemagic, Bitrise, or GitHub Actions workflows found)

**CI Pipeline:**
- Not detected — `github/` directory present but contents not explored; no `.github/workflows/` found

## Environment Configuration

**Required env vars:**
- `MAPBOX_ACCESS_TOKEN` — Mapbox SDK access token; loaded from `.env` via `flutter_dotenv`

**Optional dart-define:**
- `FLUTTER_ENV` — selects environment tier (`development` | `staging` | `production`); defaults to `development`

**Secrets location:**
- `.env` file at project root (gitignored; template at `.env.example`)
- JWT tokens stored in platform keychain via `flutter_secure_storage`

## Webhooks & Callbacks

**Incoming:**
- None — app is a mobile client only; no incoming webhooks

**Outgoing:**
- WebSocket events emitted to backend: `join-journey`, `leave-journey`, `location-update`, `heartbeat`, `acknowledge`, `request-resync`
- WebSocket events received from backend: `connection-status`, `joined-journey`, `left-journey`, `journey-ended`, `journey-started`, `participant-joined`, `participant-left`, `participant-disconnected`, `location-update`, `location-update-ack`, `latest-locations`, `lag-alert`, `participant-arrived`, `acknowledge-received`, `heartbeat-ack`, `resync-data`

## Location Services

**GPS:**
- `geolocator 13.0.4` — device location stream
- `permission_handler 11.4.0` — runtime permission requests (`lib/core/services/location_permission_service.dart`)
- Android permissions declared: `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `ACCESS_BACKGROUND_LOCATION` (`android/app/src/main/AndroidManifest.xml`)
- iOS permissions: declared in `ios/Runner/Info.plist`

**Battery:**
- `battery_plus 6.2.3` — battery level included as metadata in WebSocket `location-update` payloads (`lib/features/convoy/presentation/providers/convoy_provider.dart`)

---

*Integration audit: 2026-05-24*
