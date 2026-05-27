<!-- refreshed: 2026-05-24 -->
# Architecture

**Analysis Date:** 2026-05-24

## System Overview

```text
┌──────────────────────────────────────────────────────────────────┐
│                     Presentation Layer                            │
│  Providers (ChangeNotifier) + Screens + Widgets                  │
│  `lib/features/*/presentation/`  `lib/core/navigation/`          │
└──────────┬───────────────────────────────────────────────────────┘
           │ depends on (via use cases)
           ▼
┌──────────────────────────────────────────────────────────────────┐
│                       Domain Layer                                │
│  Entities · Repository Interfaces · Use Cases                    │
│  `lib/features/*/domain/`  `lib/core/usecases/usecase.dart`      │
└──────────┬───────────────────────────────────────────────────────┘
           │ implements
           ▼
┌──────────────────────────────────────────────────────────────────┐
│                        Data Layer                                 │
│  Models · Data Sources (Remote/Local) · Repository Impls         │
│  `lib/features/*/data/`                                          │
└──────────┬──────────────────────────┬───────────────────────────┘
           │                          │
           ▼                          ▼
┌───────────────────┐      ┌─────────────────────────────────────┐
│  REST API (Dio)   │      │  WebSocket (Socket.IO)              │
│  `DioClient`      │      │  `ConvoyWebSocketDataSourceImpl`    │
│  `ApiHandler`     │      │  `lib/features/convoy/data/`        │
└───────────────────┘      └─────────────────────────────────────┘
           │                          │
           ▼                          ▼
┌──────────────────────────────────────────────────────────────────┐
│  Core Infrastructure (shared across all features)                │
│  DI · Network · Auth · Theme · Navigation · Errors               │
│  `lib/core/`                                                     │
└──────────────────────────────────────────────────────────────────┘
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

**Overall:** Feature-first Clean Architecture

**Key Characteristics:**
- Each feature is vertically sliced: `domain/` → `data/` → `presentation/`
- Dependency rule is strictly inward: presentation depends on domain; data implements domain; core supports all
- No external DI framework — a hand-rolled singleton `ServiceLocator` wires everything in `init()` order
- State management via `Provider` + `ChangeNotifier` registered globally in `main.dart`
- Results use Dart record types (`typedef Result<T> = ({T? data, Failure? failure})`) — no third-party Either

## Layers

**Presentation Layer:**
- Purpose: UI widgets, state, and navigation; communicates downward via use cases
- Location: `lib/features/*/presentation/`
- Contains: `providers/` (ChangeNotifier), `screens/`/`pages/` (full-screen widgets), `widgets/` (feature-specific components)
- Depends on: Domain layer (use cases and entities)
- Used by: End user; `main.dart` as top of widget tree

**Domain Layer:**
- Purpose: Pure business logic, contracts, and core entities; no Flutter/platform imports
- Location: `lib/features/*/domain/`
- Contains: `entities/` (Equatable value objects), `repositories/` (abstract interfaces), `usecases/` (single-responsibility callable classes)
- Depends on: `lib/core/errors/failure.dart`, `lib/core/common/result.dart`, `lib/core/usecases/usecase.dart`
- Used by: Presentation (providers)

**Data Layer:**
- Purpose: Infrastructure — API communication, local caching, model serialization
- Location: `lib/features/*/data/`
- Contains: `models/` (JSON + Hive DTOs that extend entities), `datasources/` (remote/local impls), `repositories/` (repository implementations), `services/` (Dio API service wrappers)
- Depends on: Domain interfaces, `DioClient`, Hive, `ApiHandler`
- Used by: ServiceLocator (wired at startup)

**Core Layer:**
- Purpose: Cross-cutting shared infrastructure; used by all feature layers
- Location: `lib/core/`
- Contains: DI, network, auth, errors, navigation, theme, utils, validators, widgets

## Data Flow

### Primary REST Request Path

1. User action triggers method on Provider (`JourneyProvider.createJourney`) (`lib/features/journeys/presentation/providers/journey_provider.dart`)
2. Provider calls a Use Case (`CreateJourney.call(...)`) (`lib/features/journeys/domain/usecases/journey_usecases.dart`)
3. Use Case delegates to Repository interface (`JourneyRepository.createJourney`) (`lib/features/journeys/domain/repositories/journey_repository.dart`)
4. Repository implementation calls Remote Data Source (`JourneyRemoteDataSourceImpl`) (`lib/features/journeys/data/repositories/journey_repository_impl.dart`)
5. Data source sends HTTP request via `DioClient.dio` through auth/retry interceptors (`lib/core/network/dio_client.dart`)
6. Response is deserialized into a Model (`JourneyModel`) and mapped to a domain `Journey` entity
7. Repository wraps result as `Result<Journey>` and returns up the chain
8. Provider stores data or error, calls `notifyListeners()`, widget rebuilds

### Real-Time Convoy Coordination Path

1. `TulinkMapScreen` starts journey → `ConvoyProvider.startCoordination(journeyId)` (`lib/features/convoy/presentation/providers/convoy_provider.dart`)
2. `ConvoyProvider` calls `StreamConvoyPositions` use case (`lib/features/convoy/domain/usecases/stream_convoy_positions.dart`)
3. `ConvoyRepositoryImpl` connects `ConvoyWebSocketDataSourceImpl` (Socket.IO) (`lib/features/convoy/data/datasources/convoy_websocket_data_source.dart`)
4. WebSocket broadcasts position updates as `Stream<ConvoySnapshot>` to `ConvoyProvider`
5. `NavigationProvider` subscribes to device GPS stream via Geolocator and publishes position updates back through `PublishMyPosition` use case
6. Map widgets react to convoy snapshot and route progress via `Consumer<ConvoyProvider>` / `Consumer<NavigationProvider>`

### Auth Token Refresh Path

1. `DioClient._createAuthInterceptor()` (queued) checks token via `TokenManager.getValidAuthToken()` before each request
2. On `TokenFailure.accessTokenExpired` → calls `TokenManager.refreshAuthToken()`
3. On 401 response with `TOKEN_EXPIRED` code → retries request with fresh token
4. On refresh failure → clears all tokens and fires `TokenManager.onAuthLost` callback → user is signed out

**State Management:**
- All providers are singletons registered in `ServiceLocator` and exposed via `MultiProvider` in `MyApp`
- `Consumer<T>` or `context.watch<T>()` / `context.read<T>()` used in widgets
- `unawaited()` is used for background auth initialization so the splash screen can render immediately

## Key Abstractions

**`Result<T>` (Dart record typedef):**
- Purpose: Type-safe success/failure return without third-party packages
- Examples: `lib/core/common/result.dart`, used in every use case and repository
- Pattern: `typedef Result<T> = ({T? data, Failure? failure})`; extension methods `isSuccess`, `isFailure`, `dataOrThrow`, `map`, `mapAsync`

**`Failure` hierarchy:**
- Purpose: Typed error objects replacing raw exceptions across all layers
- Examples: `lib/core/errors/failure.dart`
- Subtypes: `ServerFailure`, `NetworkFailure`, `AuthFailure`, `ValidationFailure`, `TokenFailure`, `CacheFailure`, `SearchFailure`, `ConvoyFailure`

**`UseCase<Type, Params>` base:**
- Purpose: Single-responsibility callable business operation
- Examples: `lib/core/usecases/usecase.dart`; concrete: `lib/features/journeys/domain/usecases/journey_usecases.dart`
- Pattern: Callable with `call()`, takes typed params, returns `Result<T>`

**Repository interface + implementation split:**
- Purpose: Inversion of control; domain defines contract, data layer implements it
- Examples: `lib/features/journeys/domain/repositories/journey_repository.dart` (interface) + `lib/features/journeys/data/repositories/journey_repository_impl.dart` (impl)

**Model extends Entity:**
- Purpose: Models inherit entity fields, add JSON/Hive serialization; `toEntity()` converts down
- Examples: `UserModel extends UserEntity` (`lib/features/auth/data/models/user_model.dart`)

## Entry Points

**`AppBootstrap` (startup):**
- Location: `lib/main.dart`
- Triggers: `main()` calls `runApp(const AppBootstrap())`
- Responsibilities: Loads `.env`, inits Hive, calls `ServiceLocator().init()`, sets Mapbox token; shows splash while loading; swaps to `MyApp` on completion

**`MyApp` (app root):**
- Location: `lib/main.dart`
- Triggers: Rendered after bootstrap completes
- Responsibilities: Mounts `MultiProvider` with all feature providers, configures Material dark theme, sets `AppRouter.generateRoute` as the route factory, starts at `HomePage.routeName`

**`HomePage` (auth gate):**
- Location: `lib/main.dart`
- Triggers: Initial route `/home`
- Responsibilities: Watches `AuthProvider.isSignedIn`; shows `AuthScreen` or `MainNavigationScreen`

**`AppRouter.generateRoute` (navigation):**
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

**What happens:** `ManeuverTrackerService`, `VoiceInstructionService`, `OffRouteDetectionService`, `MapMatchingService` live under `presentation/services/` inside the maps feature.
**Why it's wrong:** These are business/domain services (route matching, voice synthesis) housed in the UI layer, violating Clean Architecture layer placement.
**Do this instead:** Move them to `lib/features/maps/domain/services/` or `lib/features/maps/data/services/` and depend on them via interfaces.

### Home-screen duplicate `journey_repository.dart`

**What happens:** `lib/features/home/domain/repositories/journey_repository.dart` mirrors the one in `lib/features/journeys/domain/repositories/journey_repository.dart`.
**Why it's wrong:** Duplicate contracts create drift risk when the canonical journey repository evolves.
**Do this instead:** The `home` feature should import the journey repository interface from `features/journeys/domain/repositories/`.

## Error Handling

**Strategy:** All public operations return `Result<T>` records. Exceptions are caught at the data layer boundary and converted to typed `Failure` subclasses. Providers surface `Failure.message` as `String? error` state.

**Patterns:**
- Data sources throw `Failure` subtypes from `ApiHandler.performApiCall` catch blocks
- Repository implementations wrap try/catch around data source calls and return `(data: null, failure: theFailure)`
- Providers check `result.isSuccess` and set `_error` string for UI display via `notifyListeners()`
- `DioClient` uses `QueuedInterceptorsWrapper` to serialize concurrent token refresh attempts

## Cross-Cutting Concerns

**Logging:** `lib/core/utils/logger.dart` for general logging; `lib/core/logging/auth_logger.dart` for auth-specific events; `PrettyDioLogger` interceptor for HTTP (disabled in production via `AppConfig.enableDetailedLogging`)
**Validation:** `lib/core/validators/auth_validators.dart` for form field validation
**Authentication:** `TokenManager` (`lib/core/auth/token_manager.dart`) handles all JWT operations; `DioClient` interceptors handle automatic injection and refresh transparently

---

*Architecture analysis: 2026-05-24*
