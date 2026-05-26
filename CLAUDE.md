<!-- GSD:project-start source:PROJECT.md -->
## Project

**Email Verification Flow**

A security gate that prevents unverified users from accessing TuLink after registration or login. When a user's `emailVerified` field is `false`, the app intercepts the auth flow and shows a dedicated screen prompting them to check their inbox. The screen auto-polls for verification in the background and lets users resend the verification link with a 60-second cooldown.

**Core Value:** Unverified users cannot reach the app — verified users flow through without friction.

### Constraints

- **Tech stack**: Dart / Flutter only — no new state management libraries
- **Theming**: Must use `TulinkColors` (dark theme — `carbonBlack`, `electricRed`, `silver`) and existing `AppTheme`
- **Toast pattern**: Must use `CarToastService.showSuccess/showError/showInfo` — no raw SnackBars
- **Architecture**: New code follows clean-arch layers; `sendEmailVerification` added to `AuthRepository` and implemented in data layer
<!-- GSD:project-end -->

<!-- GSD:stack-start source:codebase/STACK.md -->
## Technology Stack

## Languages
- Dart 3.11.0+ — all application code under `lib/`
- Swift — iOS native layer (`ios/Runner/AppDelegate.swift`, `ios/Runner/SceneDelegate.swift`)
- Kotlin/Java — Android native layer (`android/app/src/main/`)
## Runtime
- Flutter 3.41.9 (stable channel) — cross-platform mobile framework
- pub (Dart package manager)
- Lockfile: `pubspec.lock` present
## Frameworks
- Flutter SDK — UI framework targeting Android, iOS, web, Linux, macOS, Windows
- Material 3 — design system; dark mode only (`lib/core/theme/app_theme.dart`)
- provider 6.1.2 (locked: 6.x) — ChangeNotifier pattern; all providers in `features/<name>/presentation/providers/`
- Manual Service Locator singleton (`lib/core/di/service_locator.dart`) — no get_it or injectable
- flutter_test (Flutter SDK bundled)
- build_runner 2.4.13 — code generation runner
- very_good_analysis 6.0.0 — lint ruleset (extends `package:very_good_analysis/analysis_options.yaml`)
- flutter_launcher_icons 0.14.4 — generates platform app icons from `assets/icon/icon.png`
## Key Dependencies
- mapbox_maps_flutter 2.19.1 — primary map rendering; map SDK initialized at boot in `lib/main.dart` via `MapboxOptions.setAccessToken()`
- socket_io_client 2.0.3+1 (locked: 2.0.3+1) — WebSocket convoy coordination; connects to `/location` namespace on `AppConfig.webSocketUrl` (`lib/features/convoy/data/datasources/convoy_websocket_data_source.dart`)
- dio 5.7.0 — HTTP client; singleton `DioClient` with auth interceptor, retry interceptor, and logger (`lib/core/network/dio_client.dart`)
- geolocator 13.0.4 — device GPS streaming; used by `ConvoyProvider` for location publishing and by `TulinkMapScreen` for camera-follow
- flutter_secure_storage 9.2.2 — JWT token persistence via `TokenManager` (`lib/core/auth/token_manager.dart`)
- hive 2.2.3 + hive_flutter 1.1.0 — local NoSQL cache for auth user, journey data
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
- `.env` file loaded at app boot via `flutter_dotenv` (file is an asset in `pubspec.yaml`)
- Required variable: `MAPBOX_ACCESS_TOKEN`
- Template: `.env.example`
- Environment tier selected via `--dart-define=FLUTTER_ENV=development|staging|production`; defaults to `development`
- `pubspec.yaml` — dependency manifest and Flutter asset/font config
- `analysis_options.yaml` — extends `very_good_analysis`; customizations section present but empty
- `devtools_options.yaml` — Flutter DevTools config
- `flutter_launcher_icons` section in `pubspec.yaml` — icon generation config
- Android: `android/app/src/main/AndroidManifest.xml` — location permission declarations
- iOS: `ios/Runner/Info.plist` — permission usage descriptions
## Platform Requirements
- Flutter 3.41.9+ (stable channel)
- Dart SDK ^3.11.0
- Android SDK (minSdkVersion 21 per launcher icons config)
- Xcode for iOS builds
- Mapbox account — `MAPBOX_ACCESS_TOKEN` required in `.env`
- API base URL: `https://api.dev.tulink.xyz` (development — production URL commented out in `lib/core/config/app_config.dart`)
- WebSocket base URL: `https://api.dev.tulink.xyz` (connects to `/location` namespace)
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

## Language & Style
- **Language:** Dart (Flutter)
- **Lint ruleset:** `package:very_good_analysis/analysis_options.yaml` — strict linting enforced via `analysis_options.yaml`
- **Formatting:** Standard `dart format` (implicit via very_good_analysis)
## Naming Conventions
| Element | Convention | Example |
|---------|-----------|---------|
| Files | `snake_case.dart` | `auth_provider.dart` |
| Classes | `PascalCase` | `AuthProvider`, `ServerFailure` |
| Variables/params | `camelCase` | `_isLoading`, `tokenType` |
| Private fields | Leading `_` + camelCase | `_authRepository`, `_user` |
| Constants | `camelCase` | `AppConstants.appName` |
| Feature dirs | `snake_case` | `features/convoy/` |
## Architecture Patterns
- **Clean Architecture** with three layers: `data`, `domain`, `presentation`
- **Repository pattern** — domain defines abstract repos; data layer implements them
- **Use Case pattern** — `UseCase<Type, Params>` and `NoParamsUseCase<Type>` base classes in `lib/core/usecases/usecase.dart`
- **DI via GetIt** — service locator at `lib/core/di/service_locator.dart`
## Error Handling
- **Custom Result type** using Dart records (no external Either library):
- **Failure hierarchy** — all failures extend `Failure extends Equatable`:
- Failures are immutable with `copyWith()` on every subclass
- **Never throw** from use cases or repositories — return `Result<T>` or `BoolResult`
## State Management
- **`ChangeNotifier`** (flutter Provider pattern) for all feature providers
- Private state fields with public getters only:
- Helper methods `_setLoading(bool)`, `_setFailure(Failure?)` used consistently
- Providers injected via DI, registered in service locator
## Logging
- Custom logger at `lib/core/utils/logger.dart`
- Feature-specific logger: `lib/core/logging/auth_logger.dart`
- `print()` still used in provider methods (debug artifact — not cleaned up)
## Comments & Documentation
- Doc comments (`///`) on public APIs and abstract classes
- Inline comments for non-obvious logic
- No file-level `library` directive except in `result.dart` (marked `library result;`)
## Import Order (very_good_analysis enforced)
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

## System Overview
```text
```
## Component Responsibilities
| Component | Responsibility | File |
|-----------|----------------|------|
| `AppBootstrap` | Async startup orchestration, splash screen | `lib/main.dart` |
| `ServiceLocator` | Singleton DI container, dependency wiring | `lib/core/di/service_locator.dart` |
| `DioClient` | HTTP client singleton with auth/retry interceptors | `lib/core/network/dio_client.dart` |
| `ApiHandler` | Centralized Dio error normalization | `lib/core/network/api_handler.dart` |
| `TokenManager` | JWT storage, validation, preemptive refresh | `lib/core/auth/token_manager.dart` |
| `AppRouter` | Centralized named-route generation with type-safe args | `lib/core/navigation/app_router.dart` |
| `MainNavigationScreen` | Bottom tab shell (Home, History, Profile) | `lib/core/navigation/main_navigation_screen.dart` |
| `AuthProvider` | Authentication state, session lifecycle | `lib/features/auth/presentation/providers/auth_provider.dart` |
| `JourneyProvider` | Journey CRUD state, current/active journey tracking | `lib/features/journeys/presentation/providers/journey_provider.dart` |
| `ConvoyProvider` | Real-time position streaming, WebSocket lifecycle | `lib/features/convoy/presentation/providers/convoy_provider.dart` |
| `NavigationProvider` | Turn-by-turn GPS tracking, route progress | `lib/features/maps/presentation/providers/navigation_provider.dart` |
| `MapProvider` | Map state, place search, route fetching | `lib/features/maps/presentation/providers/map_provider.dart` |
## Pattern Overview
- Each feature is vertically sliced: `domain/` → `data/` → `presentation/`
- Dependency rule is strictly inward: presentation depends on domain; data implements domain; core supports all
- No external DI framework — a hand-rolled singleton `ServiceLocator` wires everything in `init()` order
- State management via `Provider` + `ChangeNotifier` registered globally in `main.dart`
- Results use Dart record types (`typedef Result<T> = ({T? data, Failure? failure})`) — no third-party Either
## Layers
- Purpose: UI widgets, state, and navigation; communicates downward via use cases
- Location: `lib/features/*/presentation/`
- Contains: `providers/` (ChangeNotifier), `screens/`/`pages/` (full-screen widgets), `widgets/` (feature-specific components)
- Depends on: Domain layer (use cases and entities)
- Used by: End user; `main.dart` as top of widget tree
- Purpose: Pure business logic, contracts, and core entities; no Flutter/platform imports
- Location: `lib/features/*/domain/`
- Contains: `entities/` (Equatable value objects), `repositories/` (abstract interfaces), `usecases/` (single-responsibility callable classes)
- Depends on: `lib/core/errors/failure.dart`, `lib/core/common/result.dart`, `lib/core/usecases/usecase.dart`
- Used by: Presentation (providers)
- Purpose: Infrastructure — API communication, local caching, model serialization
- Location: `lib/features/*/data/`
- Contains: `models/` (JSON + Hive DTOs that extend entities), `datasources/` (remote/local impls), `repositories/` (repository implementations), `services/` (Dio API service wrappers)
- Depends on: Domain interfaces, `DioClient`, Hive, `ApiHandler`
- Used by: ServiceLocator (wired at startup)
- Purpose: Cross-cutting shared infrastructure; used by all feature layers
- Location: `lib/core/`
- Contains: DI, network, auth, errors, navigation, theme, utils, validators, widgets
## Data Flow
### Primary REST Request Path
### Real-Time Convoy Coordination Path
### Auth Token Refresh Path
- All providers are singletons registered in `ServiceLocator` and exposed via `MultiProvider` in `MyApp`
- `Consumer<T>` or `context.watch<T>()` / `context.read<T>()` used in widgets
- `unawaited()` is used for background auth initialization so the splash screen can render immediately
## Key Abstractions
- Purpose: Type-safe success/failure return without third-party packages
- Examples: `lib/core/common/result.dart`, used in every use case and repository
- Pattern: `typedef Result<T> = ({T? data, Failure? failure})`; extension methods `isSuccess`, `isFailure`, `dataOrThrow`, `map`, `mapAsync`
- Purpose: Typed error objects replacing raw exceptions across all layers
- Examples: `lib/core/errors/failure.dart`
- Subtypes: `ServerFailure`, `NetworkFailure`, `AuthFailure`, `ValidationFailure`, `TokenFailure`, `CacheFailure`, `SearchFailure`, `ConvoyFailure`
- Purpose: Single-responsibility callable business operation
- Examples: `lib/core/usecases/usecase.dart`; concrete: `lib/features/journeys/domain/usecases/journey_usecases.dart`
- Pattern: Callable with `call()`, takes typed params, returns `Result<T>`
- Purpose: Inversion of control; domain defines contract, data layer implements it
- Examples: `lib/features/journeys/domain/repositories/journey_repository.dart` (interface) + `lib/features/journeys/data/repositories/journey_repository_impl.dart` (impl)
- Purpose: Models inherit entity fields, add JSON/Hive serialization; `toEntity()` converts down
- Examples: `UserModel extends UserEntity` (`lib/features/auth/data/models/user_model.dart`)
## Entry Points
- Location: `lib/main.dart`
- Triggers: `main()` calls `runApp(const AppBootstrap())`
- Responsibilities: Loads `.env`, inits Hive, calls `ServiceLocator().init()`, sets Mapbox token; shows splash while loading; swaps to `MyApp` on completion
- Location: `lib/main.dart`
- Triggers: Rendered after bootstrap completes
- Responsibilities: Mounts `MultiProvider` with all feature providers, configures Material dark theme, sets `AppRouter.generateRoute` as the route factory, starts at `HomePage.routeName`
- Location: `lib/main.dart`
- Triggers: Initial route `/home`
- Responsibilities: Watches `AuthProvider.isSignedIn`; shows `AuthScreen` or `MainNavigationScreen`
- Location: `lib/core/navigation/app_router.dart`
- Triggers: Every `Navigator.pushNamed` call
- Responsibilities: Switch on route name, extract type-safe arguments, return `MaterialPageRoute`; falls back to `UndefinedRouteScreen`
## Architectural Constraints
- **Threading:** Flutter single-threaded event loop; no isolates used. Async I/O via `async/await`; Socket.IO callbacks arrive on the main isolate.
- **Global state:** `ServiceLocator` is a module-level singleton (`lib/core/di/service_locator.dart`). All providers are singleton instances stored there. `DioClient` is also a singleton.
- **Circular imports:** No known circular chains. `core/` has no imports from `features/`.
- **WebSocket:** Only one active WebSocket connection at a time (convoy coordination). Managed by `ConvoyWebSocketDataSourceImpl` with a single `io.Socket?`.
- **Hive box lifecycle:** A single `auth_box` is opened at startup and closed on `ServiceLocator.dispose()`. Box is deleted and recreated if a type error is detected on open.
## Anti-Patterns
### Presentation-layer services in `maps/presentation/services/`
### Home-screen duplicate `journey_repository.dart`
## Error Handling
- Data sources throw `Failure` subtypes from `ApiHandler.performApiCall` catch blocks
- Repository implementations wrap try/catch around data source calls and return `(data: null, failure: theFailure)`
- Providers check `result.isSuccess` and set `_error` string for UI display via `notifyListeners()`
- `DioClient` uses `QueuedInterceptorsWrapper` to serialize concurrent token refresh attempts
## Cross-Cutting Concerns
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->
## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
