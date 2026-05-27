# Codebase Structure

**Analysis Date:** 2026-05-24

## Directory Layout

```
tulink_flutter/
├── lib/                          # All Dart source code
│   ├── main.dart                 # App bootstrap and root widget
│   ├── core/                     # Shared infrastructure (no feature logic)
│   │   ├── auth/                 # JWT token management
│   │   ├── common/               # Shared types (Result<T>)
│   │   ├── config/               # AppConfig, environment flags
│   │   ├── constants/            # App-wide constants, storage keys
│   │   ├── di/                   # ServiceLocator (singleton DI)
│   │   ├── errors/               # Failure type hierarchy
│   │   ├── logging/              # Auth logger
│   │   ├── navigation/           # AppRouter, MainNavigationScreen, helpers
│   │   │   └── widgets/          # AppNavbar bottom tab bar
│   │   ├── network/              # DioClient, ApiHandler, ApiEndpoints
│   │   │   └── models/           # ApiResponse model + generated code
│   │   ├── services/             # Cross-cutting services (location perms, toasts)
│   │   ├── theme/                # AppTheme, TulinkColors, ThemeProvider
│   │   ├── usecases/             # UseCase base classes
│   │   ├── utils/                # Logger, JourneyStatsCalculator, UserPinUtils
│   │   ├── validators/           # Auth form validators
│   │   └── widgets/              # Reusable UI widgets (CarToast, Shimmer)
│   └── features/                 # Feature modules (each self-contained)
│       ├── analytics/            # Journey history and stats
│       ├── auth/                 # Authentication / user management
│       ├── convoy/               # Real-time convoy coordination (WebSocket)
│       ├── home/                 # Home dashboard
│       ├── invites/              # Journey invitation flow
│       ├── journeys/             # Journey CRUD and management
│       ├── location/             # Device location domain types
│       ├── maps/                 # Mapbox map, place search, routing, navigation
│       ├── notifications/        # Push notification handling
│       └── profile/              # User profile screen
├── test/                         # Test files
│   ├── core/                     # Core layer unit tests
│   ├── features/                 # Feature-level tests
│   │   ├── auth/                 # Auth service & integration tests
│   │   └── convoy/               # Convoy provider tests
│   ├── unit/                     # Additional unit tests
│   └── widget_test.dart          # Default widget smoke test
├── assets/
│   ├── icon/                     # App launcher icons
│   └── icons/                    # In-app SVG/PNG icons
├── android/                      # Android platform project
├── ios/                          # iOS platform project
├── docs/                         # Project documentation (architecture, API)
├── scripts/                      # Utility shell scripts
├── skills/                       # AI codebase context documents
│   └── tulink-codebase-skill.md  # Comprehensive AI context guide
├── pubspec.yaml                  # Dependencies manifest
├── pubspec.lock                  # Locked dependency versions
└── analysis_options.yaml         # Dart lint rules
```

## Feature Module Internal Structure

Every feature follows the same three-layer layout:

```
features/<feature_name>/
├── domain/                       # Business logic (no Flutter/platform imports)
│   ├── entities/                 # Equatable value objects (pure Dart)
│   ├── repositories/             # Abstract repository interfaces
│   └── usecases/                 # Callable single-responsibility use cases
├── data/                         # Infrastructure
│   ├── models/                   # JSON/Hive DTOs (extend domain entities)
│   ├── datasources/              # Remote (Dio) and local (Hive) impls
│   ├── repositories/             # Concrete repository implementations
│   └── services/                 # Feature-specific API service wrappers
└── presentation/                 # UI
    ├── providers/                 # ChangeNotifier state classes
    ├── screens/ or pages/         # Full-screen stateful/stateless widgets
    └── widgets/                  # Feature-scoped reusable widgets
```

## Directory Purposes

**`lib/core/auth/`:**
- Purpose: JWT lifecycle — storage in Flutter Secure Storage, expiry parsing, refresh
- Key files: `lib/core/auth/token_manager.dart`

**`lib/core/di/`:**
- Purpose: Manual dependency injection; initializes and wires all singletons in the correct order
- Key files: `lib/core/di/service_locator.dart`

**`lib/core/errors/`:**
- Purpose: Typed failure hierarchy (`Failure`, `ServerFailure`, `NetworkFailure`, etc.)
- Key files: `lib/core/errors/failure.dart`

**`lib/core/network/`:**
- Purpose: HTTP client, interceptors, centralized error handling, API endpoint constants
- Key files: `lib/core/network/dio_client.dart`, `lib/core/network/api_handler.dart`, `lib/core/network/api_endpoints.dart`, `lib/core/network/api_routes.dart`

**`lib/core/navigation/`:**
- Purpose: Named route factory, shell navigation screen, navigation helpers
- Key files: `lib/core/navigation/app_router.dart`, `lib/core/navigation/main_navigation_screen.dart`, `lib/core/navigation/navigation_helper.dart`

**`lib/core/common/`:**
- Purpose: Shared type definitions used across all features
- Key files: `lib/core/common/result.dart` (`Result<T>` and `BoolResult` typedefs)

**`lib/features/convoy/`:**
- Purpose: Real-time group position sharing via Socket.IO WebSocket; convoy map overlays
- Key files: `lib/features/convoy/data/datasources/convoy_websocket_data_source.dart`, `lib/features/convoy/presentation/providers/convoy_provider.dart`

**`lib/features/maps/presentation/services/`:**
- Purpose: Navigation sub-services (maneuver tracking, off-route detection, voice, map matching) — note these are placed in the presentation layer, not domain
- Key files: `lib/features/maps/presentation/services/maneuver_tracker_service.dart`, `lib/features/maps/presentation/services/voice_instruction_service.dart`, `lib/features/maps/presentation/services/off_route_detection_service.dart`

## Key File Locations

**Entry Points:**
- `lib/main.dart`: `AppBootstrap` (startup), `MyApp` (root widget), `HomePage` (auth gate)

**Dependency Wiring:**
- `lib/core/di/service_locator.dart`: All singleton creation and initialization order

**Routing:**
- `lib/core/navigation/app_router.dart`: Route switch statement + `Routes` constants

**Network Client:**
- `lib/core/network/dio_client.dart`: Singleton Dio with interceptor stack

**Error Types:**
- `lib/core/errors/failure.dart`: All `Failure` subclasses

**Result Type:**
- `lib/core/common/result.dart`: `Result<T>` typedef and extension methods

**Theme:**
- `lib/core/theme/app_theme.dart`: Material theme configuration
- `lib/core/theme/tulink_colors.dart`: Color palette (accessed via `Theme.of(context).tulinkColors`)

**API Endpoint Constants:**
- `lib/core/network/api_endpoints.dart` and `lib/core/network/api_routes.dart`

**Main Map Screen:**
- `lib/features/maps/presentation/tulink_map_screen.dart`: 1,542-line core map widget (Mapbox + convoy overlay + navigation)

**Journey Preview (largest journey screen):**
- `lib/features/journeys/presentation/pages/journey_preview_screen.dart`: 1,261 lines

## Naming Conventions

**Files:**
- Dart files: `snake_case.dart`
- Generated files: `snake_case.g.dart` (build_runner output — JSON/Hive adapters)
- Test files: `snake_case_test.dart`

**Directories:**
- All lowercase `snake_case`

**Classes:**
- Widgets and providers: `PascalCase` (e.g., `JourneyProvider`, `TulinkMapScreen`)
- Abstract repository interfaces: `abstract class AuthRepository` (no `I` prefix)
- Concrete implementations: `AuthRepositoryImpl`, `AuthRemoteDataSourceImpl`
- Entities: `PascalCase` matching the domain concept (e.g., `Journey`, `UserEntity`)
- Models: `PascalCase` + `Model` suffix (e.g., `JourneyModel`, `UserModel`)
- Use cases: `PascalCase` verb-noun (e.g., `CreateJourney`, `GetActiveJourneys`, `StartJourney`)
- Failure types: `PascalCase` + `Failure` suffix (e.g., `NetworkFailure`, `ConvoyFailure`)

**Route Names:**
- Defined as `static const String routeName` on each screen class
- Format: lowercase with leading slash (e.g., `/mapview`, `/dashboard`, `/main`)
- Collected in `abstract class Routes` in `lib/core/navigation/app_router.dart`

## Where to Add New Code

**New Feature (full vertical slice):**
- Domain entities: `lib/features/<feature>/domain/entities/<entity_name>.dart`
- Repository interface: `lib/features/<feature>/domain/repositories/<feature>_repository.dart`
- Use cases: `lib/features/<feature>/domain/usecases/<feature>_usecases.dart`
- Data model: `lib/features/<feature>/data/models/<entity_name>_model.dart`
- Remote data source: `lib/features/<feature>/data/datasources/<feature>_remote_data_source.dart`
- Repository impl: `lib/features/<feature>/data/repositories/<feature>_repository_impl.dart`
- API service: `lib/features/<feature>/data/services/<feature>_api_service.dart`
- Provider: `lib/features/<feature>/presentation/providers/<feature>_provider.dart`
- Screens: `lib/features/<feature>/presentation/screens/<screen_name>_screen.dart`
- Register everything in: `lib/core/di/service_locator.dart` (follow init order: service → data source → repository → use cases → provider)
- Expose provider in: `lib/main.dart` inside `MultiProvider`
- Add route in: `lib/core/navigation/app_router.dart`

**New Screen for Existing Feature:**
- Implementation: `lib/features/<feature>/presentation/screens/<screen_name>_screen.dart` or `pages/<screen_name>_screen.dart`
- Route constant: add `static const String routeName` on the widget class; add a case to `AppRouter.generateRoute`

**New Use Case for Existing Feature:**
- Add a new callable class to `lib/features/<feature>/domain/usecases/<feature>_usecases.dart`
- Add the method to the repository interface and implement it

**Shared Utility:**
- Stateless pure functions: `lib/core/utils/<utility_name>.dart`
- Shared widgets: `lib/core/widgets/<widget_name>.dart`
- Shared service: `lib/core/services/<service_name>.dart`

**New Failure Type:**
- Add a new `class XyzFailure extends Failure` to `lib/core/errors/failure.dart`

**Tests:**
- Unit tests (use cases, repositories): `test/features/<feature>/` or `test/unit/features/<feature>/`
- Integration tests: `test/features/<feature>/integration/`
- Core tests: `test/core/<area>/`

## Special Directories

**`lib/core/network/models/`:**
- Purpose: Generic API response envelope models
- Generated: Partially (`.g.dart` files)
- Committed: Yes (including `.g.dart`)

**`lib/features/*/data/models/*.g.dart`:**
- Purpose: Generated JSON serialization and Hive type adapter code
- Generated: Yes, via `flutter pub run build_runner build`
- Committed: Yes

**`skills/`:**
- Purpose: AI context documentation for codebase understanding
- Generated: No
- Committed: Yes

**`.planning/`:**
- Purpose: GSD planning and codebase analysis documents
- Generated: By AI tooling
- Committed: Yes (convention)

**`docs/`:**
- Purpose: Human-facing architecture docs, API format docs, implementation plans
- Key files: `docs/clean-architecture-patterns.md`, `docs/api-response-format-documentation.md`

---

*Structure analysis: 2026-05-24*
