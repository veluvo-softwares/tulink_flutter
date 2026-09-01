# TuLink Flutter

TuLink is a mobile app for coordinated group driving. It lets users create journeys, invite participants, and track everyone's position in real time during an active convoy — all on top of a Mapbox-powered map with turn-by-turn voice navigation.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Setup](#setup)
- [Environment & Configuration](#environment--configuration)
- [Running the App](#running-the-app)
- [Project Structure](#project-structure)
- [Architecture](#architecture)
- [Clean Architecture Layers](#clean-architecture-layers)
- [State Management](#state-management)
- [Dependency Injection](#dependency-injection)
- [Navigation](#navigation)
- [Networking](#networking)
- [Error Handling](#error-handling)
- [Authentication Flow](#authentication-flow)
- [Real-Time Convoy Coordination](#real-time-convoy-coordination)
- [Theming](#theming)
- [Testing](#testing)
- [CI Pipeline](#ci-pipeline)
- [Adding a New Feature](#adding-a-new-feature)

---

## Prerequisites

| Tool | Version |
|------|---------|
| Flutter | 3.41.9 (stable channel) |
| Dart SDK | ^3.11.0 |
| Xcode | Latest stable (iOS builds) |
| Android SDK | minSdkVersion 21 |
| CocoaPods | Latest stable |

---

## Setup

```bash
# 1. Clone the repo
git clone <repo-url>
cd tulink_flutter

# 2. Copy the environment template
cp .env.example .env
# Edit .env and fill in your MAPBOX_ACCESS_TOKEN

# 3. Add Firebase config files (download from Firebase console)
#    — Android: android/app/google-services.json
#    — iOS:     ios/Runner/GoogleService-Info.plist
#    Both files are gitignored; you must obtain them from a team member
#    or the Firebase console.

# 4. Install dependencies
flutter pub get

# 5. iOS only — install CocoaPods
cd ios && pod install && cd ..

# 6. Run
flutter run
```

---

## Environment & Configuration

Configuration is split across two mechanisms:

### `.env` file

Loaded at runtime by `flutter_dotenv`. Required before the app boots.

```
MAPBOX_ACCESS_TOKEN=pk.eyJ1Ij...
```

The `.env` file is listed as a Flutter asset in `pubspec.yaml` so it's bundled with the app. Never commit real tokens — the file is gitignored.

### Dart define

The active tier is selected at build time:

```bash
flutter run --dart-define=FLUTTER_ENV=development   # default
flutter run --dart-define=FLUTTER_ENV=staging
flutter run --dart-define=FLUTTER_ENV=production
```

`AppConfig` (`lib/core/config/app_config.dart`) reads `FLUTTER_ENV` and exposes per-tier values: API base URL, WebSocket URL, feature flags, and logging switches.

| Flag | development | staging | production |
|------|-------------|---------|------------|
| `enableDetailedLogging` | true | true | false |
| `enableCrashReporting` | false | false | true |
| `enableAnalytics` | false | true | true |

---

## Running the App

```bash
# Debug on connected device
flutter run

# Debug with explicit environment
flutter run --dart-define=FLUTTER_ENV=development

# Release build (Android)
flutter build apk --release

# Release build (iOS — requires signing)
flutter build ipa

# Run tests
flutter test

# Static analysis
flutter analyze lib/ --no-fatal-infos --no-fatal-warnings
```

---

## Project Structure

```
lib/
├── main.dart                     # Entry point, bootstrap, MyApp, HomePage
├── core/                         # Cross-cutting infrastructure
│   ├── auth/                     # TokenManager (JWT storage & refresh)
│   ├── common/                   # Result<T> / BoolResult type definitions
│   ├── config/                   # AppConfig (env, URLs, feature flags)
│   ├── constants/                # AppConstants, StorageKeys
│   ├── di/                       # ServiceLocator (manual DI container)
│   ├── errors/                   # Failure hierarchy
│   ├── logging/                  # AuthLogger and structured logger
│   ├── navigation/               # AppRouter, MainNavigationScreen, helpers
│   ├── network/                  # DioClient, ApiHandler, ApiEndpoints
│   ├── services/                 # CarToastService, LocationPermissionService
│   ├── theme/                    # AppTheme, TulinkColors, ThemeProvider
│   ├── usecases/                 # UseCase<T, P> and NoParamsUseCase<T> bases
│   ├── utils/                    # Logger, JourneyStatsCalculator, UserPinUtils
│   ├── validators/               # AuthValidators
│   └── widgets/                  # CarToast, ShimmerWidgets, StatusIndicator
│
└── features/                     # Vertical feature slices
    ├── analytics/                # Journey history & stats
    ├── auth/                     # Sign-in, sign-up, email verification
    ├── convoy/                   # Real-time position streaming
    ├── home/                     # Dashboard
    ├── invites/                  # Journey invitations
    ├── journeys/                 # Journey CRUD & lifecycle
    ├── maps/                     # Mapbox map, routing, navigation
    └── profile/                  # User profile screen
```

Each feature is a self-contained vertical slice with its own `domain/`, `data/`, and `presentation/` directories. Nothing inside a feature imports from another feature — shared contracts go through `core/`.

---

## Architecture

TuLink follows **Clean Architecture** with three layers per feature. Dependencies flow strictly inward:

```
Presentation  ──►  Domain  ◄──  Data
                     ▲
                   Core
```

- Presentation depends on Domain (via use cases and entities).
- Data implements Domain interfaces.
- Core has no imports from features.
- No feature imports from another feature.

### Data flow — REST request

```
Widget
  └─► Provider.method()
        └─► UseCase.call(params)           // domain
              └─► Repository.method()     // domain interface
                    └─► RepositoryImpl    // data
                          └─► DataSource.method()
                                └─► ApiHandler.performApiCall()
                                      └─► DioClient.dio.get/post/...
```

### Data flow — real-time convoy

```
ConvoyProvider
  └─► StreamConvoyPositions.call(journeyId)
        └─► ConvoyRepositoryImpl.streamConvoyPositions()
              └─► ConvoyWebSocketDataSourceImpl (Socket.IO)
                    └─► /location namespace on WebSocket URL
```

### Boot sequence

```
main()
  └─► Firebase.initializeApp()
  └─► AppBootstrap (StatefulWidget)
        └─► dotenv.load()
        └─► Hive.initFlutter()
        └─► ServiceLocator().init()        // wires all dependencies
        └─► MapboxOptions.setAccessToken()
        └─► MyApp
              └─► MultiProvider (all feature providers)
              └─► MaterialApp → initialRoute: /home
                    └─► HomePage
                          └─► watches AuthProvider
                                ├─► isSignedIn=false  → AuthScreen
                                ├─► isEmailVerified=false → VerifyEmailScreen
                                └─► verified → MainNavigationScreen
```

---

## Clean Architecture Layers

### Domain layer (`features/<name>/domain/`)

Pure Dart. No Flutter imports. No network or storage dependencies.

- **Entities** — immutable value objects extending `Equatable`.
- **Repository interfaces** — abstract contracts the data layer must fulfil.
- **Use cases** — single-responsibility callable classes.

```dart
// Use case base classes (lib/core/usecases/usecase.dart)
abstract class UseCase<Type, Params> {
  Future<Result<Type>> call(Params params);
}

abstract class NoParamsUseCase<Type> {
  Future<Result<Type>> call();
}
```

Concrete example (`features/journeys/domain/usecases/journey_usecases.dart`):

```dart
class CreateJourney extends UseCase<Journey, CreateJourneyParams> {
  CreateJourney(this._repository);
  final JourneyRepository _repository;

  @override
  Future<Result<Journey>> call(CreateJourneyParams params) =>
      _repository.createJourney(params);
}
```

### Data layer (`features/<name>/data/`)

Implements domain contracts. Allowed to import Dio, Hive, and platform packages.

- **Models** — extend entities; add `fromJson`, `toJson`, and Hive adapters. Provide `toEntity()` to strip serialization concerns before handing data upward.
- **Data sources** — `Remote` (API) and `Local` (cache). Throw `Failure` subtypes, never raw exceptions.
- **Repository implementations** — wrap data source calls in try/catch and return `Result<T>`.

### Presentation layer (`features/<name>/presentation/`)

Flutter widgets and `ChangeNotifier` providers.

- **Providers** — hold `_isLoading`, `_failure`, and domain state. Expose read-only getters. Call use cases and call `notifyListeners()`.
- **Screens / Pages** — full-screen widgets. Navigate via `Navigator.pushNamed`.
- **Widgets** — feature-specific reusable components.

---

## State Management

Provider (`^6.1.2`) with `ChangeNotifier`. All providers are singletons wired by `ServiceLocator` and mounted with `MultiProvider` in `MyApp`.

**Provider pattern used in every feature:**

```dart
class ExampleProvider extends ChangeNotifier {
  bool _isLoading = false;
  Failure? _failure;
  SomeEntity? _data;

  bool get isLoading => _isLoading;
  Failure? get failure => _failure;
  SomeEntity? get data => _data;

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  Future<void> doSomething() async {
    _setLoading(true);
    _failure = null;
    final result = await _someUseCase.call(params);
    if (result.isSuccess) {
      _data = result.data;
    } else {
      _failure = result.failure;
    }
    _setLoading(false);
  }
}
```

Consuming in widgets:

```dart
context.watch<ExampleProvider>().isLoading   // rebuilds on change
context.read<ExampleProvider>().doSomething() // one-shot call, no rebuild
```

---

## Dependency Injection

`ServiceLocator` (`lib/core/di/service_locator.dart`) is a hand-rolled singleton. No `get_it` or `injectable`.

`ServiceLocator().init()` is called once in `AppBootstrap._bootstrap()`. It wires the full dependency graph in order:

1. Hive box
2. `DioClient`
3. API services
4. Data sources
5. Repositories
6. Use cases
7. Providers

Access a dependency anywhere via the singleton:

```dart
ServiceLocator().authProvider
ServiceLocator().journeyProvider
```

In practice, providers are accessed through the widget tree via `context.read<T>()` / `context.watch<T>()`, not directly from `ServiceLocator`.

---

## Navigation

Centralized named routing via `AppRouter.generateRoute` (`lib/core/navigation/app_router.dart`).

```dart
// Navigate
Navigator.pushNamed(context, CreateJourneyScreen.routeName);

// Navigate with arguments
Navigator.pushNamed(
  context,
  JourneyPreviewScreen.routeName,
  arguments: journeyId,
);
```

Every screen defines its own `static const String routeName`. `AppRouter` extracts and validates arguments with safe fallbacks to `UndefinedRouteScreen`.

Route constants are also available via the `Routes` class:

```dart
Routes.home       // '/home'
Routes.main       // '/main'
Routes.map        // '/map'
Routes.auth       // '/auth'
Routes.verifyEmail
```

---

## Networking

### DioClient (`lib/core/network/dio_client.dart`)

Singleton. Configured with:

- Base URL from `AppConfig.baseUrl`
- 30-second connect / receive / send timeouts
- `QueuedInterceptorsWrapper` auth interceptor — attaches `Bearer` token; handles 401 by refreshing once, then retrying. Uses a `Completer` guard so parallel 401s don't race to refresh.
- Retry interceptor — up to `AppConfig.maxRetryAttempts` retries on transient network errors.
- `PrettyDioLogger` — request/response logging in non-production builds.

### ApiHandler (`lib/core/network/api_handler.dart`)

Static utility consumed by all remote data sources. Wraps every Dio call:

```dart
final user = await ApiHandler.performApiCall(
  () => _dio.get('/users/me'),
  (data) => UserModel.fromJson(data),
);
```

Normalizes `DioException` into typed `Failure` subclasses. Data sources never catch `DioException` directly.

### API endpoints

All paths are defined in `lib/core/network/api_endpoints.dart` and `api_routes.dart`. Never hardcode URLs in data sources.

---

## Error Handling

The entire codebase uses a custom `Result<T>` record type — no third-party Either:

```dart
typedef Result<T> = ({T? data, Failure? failure});
typedef BoolResult = ({bool success, Failure? failure});
```

**Never throw from use cases or repositories.** Return a `Result` instead.

### Failure hierarchy

| Type | When to use |
|------|-------------|
| `ServerFailure` | HTTP 4xx / 5xx responses |
| `NetworkFailure` | No internet, timeout, connection error |
| `AuthFailure` | Invalid credentials, expired token, suspended account |
| `TokenFailure` | Token missing, corrupted, or expired in secure storage |
| `ValidationFailure` | Field validation errors |
| `CacheFailure` | Hive read/write failures |
| `SearchFailure` | Place search errors |
| `ConvoyFailure` | WebSocket / real-time position errors |

**Checking results in a provider:**

```dart
final result = await _useCase.call(params);
if (result.isSuccess) {
  _data = result.data;
} else {
  _failure = result.failure;
}
```

### Toasts

Never use raw `SnackBar`. Use `CarToastService`:

```dart
CarToastService.showSuccess('Journey started');
CarToastService.showError('Could not connect');
CarToastService.showInfo('Waiting for members...');
```

---

## Authentication Flow

```
AuthScreen
  └─► AuthProvider.signIn(email, password)
        └─► SignInUseCase → AuthRepositoryImpl → AuthRemoteDataSource
              ├─► success → TokenManager.saveAuthToken() + saveRefreshToken()
              │             AuthProvider.isSignedIn = true
              │             → if emailVerified → MainNavigationScreen
              │             → if !emailVerified → VerifyEmailScreen
              └─► failure → AuthProvider._failure set → UI shows error toast
```

**Email verification gate** (`VerifyEmailScreen`): polling provider (`EmailVerificationProvider`) checks `emailVerified` on the user object every few seconds. Once verified, `HomePage` rebuilds and routes to `MainNavigationScreen`. Users can resend the verification email with a 60-second cooldown.

**Token lifecycle** (handled transparently by `DioClient`):
1. `TokenManager.getValidAuthToken()` is called on every request.
2. If the access token is within `AppConfig.tokenExpiryBufferMinutes` of expiry, it is preemptively refreshed.
3. On a 401, the interceptor calls `TokenManager.refreshAuthToken()`.
4. If the refresh token is also expired, `TokenManager.onAuthLost` fires and `AuthProvider` signs the user out.

---

## Real-Time Convoy Coordination

Uses **Socket.IO** (`socket_io_client`) connecting to the `/location` namespace on `AppConfig.webSocketUrl`.

```
ConvoyProvider
  ├─► PublishMyPosition — emits GPS position + battery level on each location update
  ├─► StreamConvoyPositions — listens for member position events, updates map markers
  └─► FetchLatestSnapshot — REST fallback to bootstrap initial member positions
```

Only one WebSocket connection is active at a time. It is opened when a journey becomes active and closed when the journey ends or the user leaves the screen.

The `ConvoyFailure.stopPolling` case is a silent terminal state — the server signals the journey is over; the provider stops publishing without showing an error.

---

## Theming

TuLink is **dark mode only**. Light mode is never shown.

Colors are defined as a `ThemeExtension` (`TulinkColors`) and accessed via:

```dart
final colors = Theme.of(context).tulinkColors;
colors.electricRed   // #E8002D — primary accent, CTAs
colors.carbonBlack   // #0D0D0D — background
colors.brushedSteel  // #2A2A2A — container surfaces
colors.cardDark      // #1E1E1E — card backgrounds
colors.silver        // #C8C8C8 — secondary text
colors.white         // #FFFFFF — primary text
colors.tulinkBlue    // #0066FF — racing blue accent
```

Typography uses **Rajdhani** (headings) and **Inter** (body) loaded from Google Fonts at runtime. Both are configured in `AppTheme` (`lib/core/theme/app_theme.dart`).

Do not use hardcoded `Color(...)` values in widgets. Always pull from `TulinkColors`.

---

## Testing

Tests live in `test/`, mirroring `lib/`:

```
test/
├── core/
│   ├── errors/
│   └── network/
├── features/
│   ├── auth/
│   ├── convoy/
│   └── journeys/
├── unit/
└── widget_test.dart
```

```bash
# Run all tests
flutter test

# Run with coverage
flutter test --coverage
```

Use `mockito` for mocking. Provider tests mock use case dependencies directly. No mocking of the database — data source tests hit real implementations where possible.

---

## CI Pipeline

GitHub Actions (`.github/workflows/ci.yml`) runs on every push and PR to `main`.

| Job | Runner | Steps |
|-----|--------|-------|
| Android | ubuntu-latest | inject Firebase config → create `.env` → `flutter test` → `flutter analyze` → `flutter build apk --debug` |
| iOS | macos-latest | inject Firebase config → create `.env` → `flutter test` → `pod install` → `flutter build ios --no-codesign` |

**Secrets required in GitHub repository settings:**

| Secret | Description |
|--------|-------------|
| `MAPBOX_ACCESS_TOKEN` | Mapbox public token |
| `GOOGLE_SERVICES_JSON` | Base64-encoded `google-services.json` |
| `GOOGLE_SERVICE_INFO_PLIST` | Base64-encoded `GoogleService-Info.plist` |

CI skips forked PRs because they cannot access repository secrets.

### iOS App Store production uploads

`.github/workflows/production.yml` is the production-only iOS pipeline. It
runs only from the `prod` branch, uses the protected `production` GitHub
environment, builds the version declared in `pubspec.yaml`, and uploads the
signed IPA to App Store Connect. It intentionally does **not** submit the app
for review or release it to customers; selecting the build, checking the store
metadata and pressing **Submit for Review** remain explicit human approvals.

Before the first run:

1. create and protect the `prod` branch, requiring a PR from `main`;
2. configure a required reviewer on the `production` GitHub environment;
3. copy the iOS signing and App Store Connect secrets already used by the
   TestFlight workflow into that environment; and
4. set the repository variable `IOS_PRODUCTION_ENABLED` to `true`.

The required production secrets are `APP_STORE_CONNECT_API_KEY`,
`APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_API_ISSUER_ID`,
`IOS_CERT_P12`, `IOS_CERT_PASSWORD`, `IOS_KEYCHAIN_PASSWORD`,
`IOS_PROVISIONING_PROFILE`, `IOS_WIDGET_PROVISIONING_PROFILE`,
`GOOGLE_SERVICE_INFO_PLIST`, `MAPBOX_ACCESS_TOKEN`, and
`GOOGLE_SERVER_CLIENT_ID`.

To ship, open a PR from `main` to `prod`. Merging it creates and uploads a new
App Store build. After Apple processes the upload, select that build on the
matching App Store version page and complete the submission in App Store
Connect.

---

## Adding a New Feature

Follow this checklist to keep every feature consistent with the existing patterns.

**1. Create the directory structure**

```
lib/features/<name>/
  domain/
    entities/
    repositories/          # abstract interface
    usecases/
  data/
    datasources/           # remote + local impls
    models/                # extend entities, add fromJson/toJson
    repositories/          # implement domain interface
    services/              # Dio API service wrapper (optional)
  presentation/
    providers/             # ChangeNotifier
    screens/ or pages/
    widgets/
```

**2. Domain layer first**

- Define the entity (extends `Equatable`).
- Define the repository interface (abstract class).
- Write use cases (extend `UseCase<T, Params>` or `NoParamsUseCase<T>`).

**3. Data layer**

- Create the model (extends entity, adds serialization).
- Implement the data source (remote throws `Failure` on error; never throws raw exceptions).
- Implement the repository (wraps data source in try/catch, returns `Result<T>`).

**4. Presentation layer**

- Create a `ChangeNotifier` provider with `_isLoading`, `_failure`, and state fields.
- Use `_setLoading(bool)` and `_setFailure(Failure?)` helpers.
- Register the provider in `ServiceLocator.init()`.
- Expose it via `MultiProvider` in `MyApp` (`main.dart`).

**5. Navigation**

- Add a `static const String routeName` to the screen class.
- Add a case in `AppRouter.generateRoute`.

**6. Tests**

- Unit test each use case with a mocked repository.
- Unit test the provider with mocked use cases.
