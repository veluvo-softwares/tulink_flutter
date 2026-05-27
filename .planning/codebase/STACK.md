# Technology Stack

**Analysis Date:** 2026-05-24

## Languages

**Primary:**
- Dart 3.11.0+ — all application code under `lib/`

**Secondary:**
- Swift — iOS native layer (`ios/Runner/AppDelegate.swift`, `ios/Runner/SceneDelegate.swift`)
- Kotlin/Java — Android native layer (`android/app/src/main/`)

## Runtime

**Environment:**
- Flutter 3.41.9 (stable channel) — cross-platform mobile framework

**Package Manager:**
- pub (Dart package manager)
- Lockfile: `pubspec.lock` present

## Frameworks

**Core:**
- Flutter SDK — UI framework targeting Android, iOS, web, Linux, macOS, Windows
- Material 3 — design system; dark mode only (`lib/core/theme/app_theme.dart`)

**State Management:**
- provider 6.1.2 (locked: 6.x) — ChangeNotifier pattern; all providers in `features/<name>/presentation/providers/`

**Dependency Injection:**
- Manual Service Locator singleton (`lib/core/di/service_locator.dart`) — no get_it or injectable

**Testing:**
- flutter_test (Flutter SDK bundled)

**Build/Dev:**
- build_runner 2.4.13 — code generation runner
- very_good_analysis 6.0.0 — lint ruleset (extends `package:very_good_analysis/analysis_options.yaml`)
- flutter_launcher_icons 0.14.4 — generates platform app icons from `assets/icon/icon.png`

## Key Dependencies

**Critical:**
- mapbox_maps_flutter 2.19.1 — primary map rendering; map SDK initialized at boot in `lib/main.dart` via `MapboxOptions.setAccessToken()`
- socket_io_client 2.0.3+1 (locked: 2.0.3+1) — WebSocket convoy coordination; connects to `/location` namespace on `AppConfig.webSocketUrl` (`lib/features/convoy/data/datasources/convoy_websocket_data_source.dart`)
- dio 5.7.0 — HTTP client; singleton `DioClient` with auth interceptor, retry interceptor, and logger (`lib/core/network/dio_client.dart`)
- geolocator 13.0.4 — device GPS streaming; used by `ConvoyProvider` for location publishing and by `TulinkMapScreen` for camera-follow
- flutter_secure_storage 9.2.2 — JWT token persistence via `TokenManager` (`lib/core/auth/token_manager.dart`)
- hive 2.2.3 + hive_flutter 1.1.0 — local NoSQL cache for auth user, journey data

**Infrastructure:**
- flutter_dotenv 6.0.0 — `.env` file loading at app boot; `MAPBOX_ACCESS_TOKEN` read via `AppConfig.mapboxAccessToken`
- pretty_dio_logger 1.4.0 — development request/response logging (disabled in production via `AppConfig.enableDetailedLogging`)
- logger 2.7.0 — structured logging utility (`lib/core/utils/logger.dart`)
- equatable 2.0.8 — value equality for domain entities
- json_annotation 4.9.0 + json_serializable 6.8.0 — JSON serialization code generation (`*.g.dart` files)
- hive_generator 2.0.1 — Hive type adapter code generation
- permission_handler 11.4.0 — runtime location permission requests (`lib/core/services/location_permission_service.dart`)
- battery_plus 6.2.3 — battery level included in convoy location update metadata (`lib/features/convoy/presentation/providers/convoy_provider.dart`)
- flutter_tts 4.2.5 — device TTS engine for turn-by-turn voice instructions (`lib/features/maps/presentation/services/voice_instruction_service.dart`)
- flutter_svg 2.2.4 — SVG asset rendering
- shimmer 3.0.0 — loading skeleton UI (`lib/core/widgets/shimmer_widgets.dart`)
- intl 0.19.0 — date/time formatting
- google_fonts 6.3.3 — Rajdhani (headings) and Inter (body) fonts loaded at runtime
- cupertino_icons 1.0.8 — iOS-style icons

## Configuration

**Environment:**
- `.env` file loaded at app boot via `flutter_dotenv` (file is an asset in `pubspec.yaml`)
- Required variable: `MAPBOX_ACCESS_TOKEN`
- Template: `.env.example`
- Environment tier selected via `--dart-define=FLUTTER_ENV=development|staging|production`; defaults to `development`

**Build:**
- `pubspec.yaml` — dependency manifest and Flutter asset/font config
- `analysis_options.yaml` — extends `very_good_analysis`; customizations section present but empty
- `devtools_options.yaml` — Flutter DevTools config
- `flutter_launcher_icons` section in `pubspec.yaml` — icon generation config
- Android: `android/app/src/main/AndroidManifest.xml` — location permission declarations
- iOS: `ios/Runner/Info.plist` — permission usage descriptions

## Platform Requirements

**Development:**
- Flutter 3.41.9+ (stable channel)
- Dart SDK ^3.11.0
- Android SDK (minSdkVersion 21 per launcher icons config)
- Xcode for iOS builds
- Mapbox account — `MAPBOX_ACCESS_TOKEN` required in `.env`

**Production:**
- API base URL: `https://api.dev.tulink.xyz` (development — production URL commented out in `lib/core/config/app_config.dart`)
- WebSocket base URL: `https://api.dev.tulink.xyz` (connects to `/location` namespace)

---

*Stack analysis: 2026-05-24*
