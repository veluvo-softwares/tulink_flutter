# TuLink Flutter - Claude AI Codebase Understanding Skill

## Overview

**TuLink** is a Flutter application for group journey coordination and tracking. This document serves as a comprehensive guide for AI tools like Claude to understand the full structure, patterns, and implementation details of the TuLink Flutter codebase.

---

## 🏗️ Architecture Overview

### Clean Architecture Implementation
The application follows **Clean Architecture** principles with clear layer separation:

```
┌─────────────────────────────────────┐
│           Presentation              │ ← UI, State Management (Provider)
│  (Screens, Widgets, Providers)      │
├─────────────────────────────────────┤
│             Domain                  │ ← Business Logic  
│   (Entities, Repositories, Use Cases)│
├─────────────────────────────────────┤
│              Data                   │ ← Infrastructure
│ (Models, API, Cache, Data Sources)  │
├─────────────────────────────────────┤
│             Core                    │ ← Shared Infrastructure
│  (Network, DI, Navigation, Theme)   │
└─────────────────────────────────────┘
```

### Technology Stack
- **Framework**: Flutter 3.11.0+
- **State Management**: Provider pattern with ChangeNotifier
- **Dependency Injection**: Manual DI using Service Locator pattern
- **Local Storage**: Hive (NoSQL) + Flutter Secure Storage
- **Network**: Dio with custom interceptors
- **Maps**: Mapbox integration
- **Design**: Material 3 with custom dark theme
- **Architecture**: Clean Architecture with feature-first organization

---

## 📁 Directory Structure

### Root Level
```
tulink_flutter/
├── lib/                          # Main source code
├── android/                      # Android platform code
├── ios/                          # iOS platform code  
├── web/                          # Web platform code
├── assets/                       # Static assets (icons)
├── docs/                         # Project documentation
├── test/                         # Test files
├── pubspec.yaml                  # Dependencies
├── .env                          # Environment variables
└── CLAUDE.md                     # Development guidelines
```

### Core Application Structure (lib/)
```
lib/
├── main.dart                     # Application entry point
├── core/                         # Shared infrastructure
│   ├── auth/                     # Authentication utilities
│   ├── common/                   # Common utilities
│   ├── config/                   # App configuration
│   ├── constants/                # App constants
│   ├── di/                       # Dependency injection
│   ├── errors/                   # Error handling
│   ├── logging/                  # Logging utilities
│   ├── navigation/               # Navigation & routing
│   ├── network/                  # HTTP client & API
│   ├── services/                 # Core services
│   ├── theme/                    # UI theming
│   ├── usecases/                 # Base use case classes
│   ├── utils/                    # Utility functions
│   ├── validators/               # Input validation
│   └── widgets/                  # Reusable widgets
│
└── features/                     # Feature modules
    ├── analytics/                # User analytics & journey history
    ├── auth/                     # Authentication & user management
    ├── home/                     # Home dashboard
    ├── journeys/                 # Journey creation & management
    ├── location/                 # Location services
    ├── maps/                     # Map display & interaction
    ├── notifications/            # Push notifications
    └── profile/                  # User profile management
```

### Feature Module Structure (Example: auth/)
```
features/auth/
├── domain/                       # Business logic layer
│   ├── entities/                 # Pure business objects
│   ├── repositories/             # Repository interfaces
│   └── usecases/                 # Business use cases
├── data/                         # Infrastructure layer
│   ├── models/                   # Data transfer objects
│   ├── datasources/              # API & cache sources
│   ├── repositories/             # Repository implementations
│   └── services/                 # External API services
└── presentation/                 # UI layer
    ├── providers/                # State management
    ├── screens/                  # Full screen widgets
    ├── pages/                    # Page components
    └── widgets/                  # Feature-specific widgets
```

---

## 🎯 Key Features & Modules

### 1. Authentication Module (`features/auth/`)
**Purpose**: User registration, login, profile management

**Key Components**:
- **Entity**: `UserEntity` - Pure business object for user data
- **Provider**: `AuthProvider` - Manages authentication state
- **Repository**: `AuthRepositoryImpl` - Coordinates data sources
- **Services**: `AuthApiService` - Handles API communication
- **Storage**: Hive local storage + secure token storage

**Key Files**:
- `lib/features/auth/presentation/providers/auth_provider.dart` - State management
- `lib/features/auth/domain/entities/user_entity.dart` - User business object
- `lib/features/auth/data/repositories/auth_repository_impl.dart` - Data coordination
- `lib/core/auth/token_manager.dart` - JWT token management

### 2. Journey Module (`features/journeys/`)
**Purpose**: Group journey creation, management, and coordination

**Key Components**:
- **Entity**: `Journey` - Core journey business object with participants
- **Provider**: `JourneyProvider` - Journey state management
- **Use Cases**: CRUD operations for journeys
- **Search**: Mapbox integration for location search

**Key Files**:
- `lib/features/journeys/domain/entities/journey.dart` - Journey domain model
- `lib/features/journeys/presentation/providers/journey_provider.dart` - State management
- `lib/features/journeys/presentation/pages/create_journey_screen.dart` - Journey creation UI

### 3. Maps Module (`features/maps/`)
**Purpose**: Map display, location search, and route visualization

**Key Components**:
- **Integration**: Mapbox Maps Flutter SDK
- **Search**: Place search with Google Places API
- **Provider**: `MapProvider` - Map state management
- **Widgets**: Custom map overlays and controls

**Key Files**:
- `lib/features/maps/presentation/tulink_map_screen.dart` - Main map interface
- `lib/features/maps/presentation/providers/map_provider.dart` - Map state management
- `lib/features/maps/data/datasources/place_search_remote_data_source.dart` - Place search API

### 4. Analytics Module (`features/analytics/`)
**Purpose**: Journey history, statistics, and user analytics

**Key Components**:
- **History**: Journey history tracking
- **Metrics**: User journey analytics
- **Provider**: `AnalyticsProvider` - Analytics state management

### 5. Core Infrastructure (`core/`)
**Purpose**: Shared services and utilities across all features

**Key Components**:
- **Network**: `DioClient` with auth interceptors and retry logic
- **DI**: `ServiceLocator` for manual dependency injection
- **Theme**: Custom dark theme with Rajdhani typography
- **Navigation**: Centralized app routing with type safety
- **Error Handling**: Comprehensive failure types and handling

---

## 🔧 Core Services & Architecture Patterns

### 1. Dependency Injection - Service Locator Pattern
**File**: `lib/core/di/service_locator.dart`

**Implementation**: Manual dependency injection using singleton pattern
```dart
class ServiceLocator {
  static final ServiceLocator _instance = ServiceLocator._internal();
  factory ServiceLocator() => _instance;
  
  // Dependencies are initialized in order:
  // 1. Infrastructure (Dio, Hive)
  // 2. API Services
  // 3. Data Sources  
  // 4. Repositories
  // 5. Providers
}
```

**Dependency Flow**:
- Presentation → Domain (Providers depend on Repository interfaces)
- Data → Domain (Repository implementations depend on interfaces)
- Infrastructure → All layers (Core services support all layers)

### 2. State Management - Provider Pattern
**Implementation**: ChangeNotifier with Consumer widgets

**Pattern**:
```dart
class FeatureProvider extends ChangeNotifier {
  // Private state
  bool _isLoading = false;
  FeatureEntity? _data;
  Failure? _error;
  
  // Public getters
  bool get isLoading => _isLoading;
  FeatureEntity? get data => _data;
  String get errorMessage => _error?.message ?? '';
  
  // Actions that notify listeners
  Future<bool> performAction() async {
    _setLoading(true);
    // Business logic via repository
    _setLoading(false);
    return success;
  }
}
```

### 3. Network Layer - Enhanced Dio Client
**File**: `lib/core/network/dio_client.dart`

**Features**:
- **Authentication Interceptor**: Automatic token injection and refresh
- **Retry Interceptor**: Exponential backoff for failed requests
- **Logging Interceptor**: Development request/response logging
- **Token Management**: JWT expiry detection and preemptive refresh

**Token Refresh Flow**:
1. Check if token expires soon (< 5 minutes)
2. Attempt preemptive refresh with refresh token
3. On 401 errors, attempt token refresh and retry request
4. On refresh failure, clear tokens and require re-authentication

### 4. Error Handling System
**File**: `lib/core/errors/failure.dart`

**Failure Types**:
- `AuthFailure` - Authentication/authorization errors
- `NetworkFailure` - Connectivity and network errors
- `ServerFailure` - API and backend errors
- `ValidationFailure` - Input validation errors
- `TokenFailure` - JWT token-related errors
- `CacheFailure` - Local storage errors

**Usage Pattern**:
```dart
Future<({Entity? data, Failure? failure})> operation() async {
  try {
    final result = await dataSource.fetch();
    return (data: result.toEntity(), failure: null);
  } on CustomException catch (e) {
    return (data: null, failure: NetworkFailure.fromException(e));
  }
}
```

---

## 🎨 UI & Design System

### Theme Architecture
**File**: `lib/core/theme/app_theme.dart`

**Design Principles**:
- **Dark Mode Only**: TuLink uses exclusively dark theme
- **Motorsports Inspired**: Racing-inspired color scheme and typography
- **Material 3**: Modern Material Design components

**Typography**:
- **Primary Font**: Rajdhani (racing-inspired, Google Fonts)
- **Fallback Font**: Inter (clean, readable)
- **Font Weights**: Light (300), Regular (400), Medium (500), Semi-Bold (600), Bold (700)

**Color Palette**:
```dart
static const TulinkColors colors = TulinkColors.dark;
// Electric Red: #E8002D (CTAs, highlights)
// Carbon Black: #0D0D0D (backgrounds) 
// Brushed Steel: #2A2A2A (cards, inputs)
// Silver: #C8C8C8 (secondary text)
// White: #FFFFFF (primary text)
```

### Navigation System
**File**: `lib/core/navigation/app_router.dart`

**Implementation**: Centralized routing with type-safe argument handling
```dart
class AppRouter {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case CreateJourneyScreen.routeName:
        return _createRoute(const CreateJourneyScreen(), settings);
      // Route validation and error handling for undefined routes
    }
  }
}
```

**Navigation Structure**:
- **HomePage**: Entry point with authentication check
- **MainNavigationScreen**: Bottom navigation with 4 tabs
- **Feature Screens**: Individual feature interfaces
- **Error Handling**: `UndefinedRouteScreen` for invalid routes

---

## 🏛️ Data Layer Architecture

### Repository Pattern Implementation
**Structure**: Interface in domain, implementation in data layer

**Example - Auth Repository**:
```dart
// Domain interface
abstract class AuthRepository {
  Future<({UserEntity? user, Failure? failure})> signIn({
    required String email,
    required String password,
  });
}

// Data implementation  
class AuthRepositoryImpl implements AuthRepository {
  // Coordinates remote and local data sources
  // Implements caching and error handling logic
}
```

### Data Sources Pattern
**Remote Data Sources**: API communication
**Local Data Sources**: Cache and offline storage

**Example**:
```dart
// Remote - handles API calls
class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final AuthApiService _authApiService;
  
  Future<({UserModel user, String token})> signIn() async {
    final response = await _authApiService.signIn();
    return AuthResponseModel.fromJson(response);
  }
}

// Local - handles caching
class AuthLocalDataSourceImpl implements AuthLocalDataSource {
  final Box<dynamic> _authBox;
  
  Future<UserModel?> getCachedUser() async {
    return _authBox.get('user');
  }
}
```

### Model-Entity Pattern
**Entities**: Pure business objects in domain layer
**Models**: Data transfer objects in data layer with serialization

**Example**:
```dart
// Domain Entity (pure business logic)
class UserEntity extends Equatable {
  final String id;
  final String email;
  final String name;
  
  // Business logic methods
  bool get hasCompleteProfile => name.isNotEmpty;
}

// Data Model (serialization, storage)
@JsonSerializable()
@HiveType(typeId: 0)
class UserModel extends UserEntity {
  UserModel({required super.id, required super.email, required super.name});
  
  factory UserModel.fromJson(Map<String, dynamic> json) => _$UserModelFromJson(json);
  Map<String, dynamic> toJson() => _$UserModelToJson(this);
  
  UserEntity toEntity() => UserEntity(id: id, email: email, name: name);
}
```

---

## 🔐 Authentication & Security

### JWT Token Management
**File**: `lib/core/auth/token_manager.dart`

**Features**:
- **Automatic Expiry Detection**: Parse JWT payload for expiry time
- **Preemptive Refresh**: Refresh tokens before expiration
- **Secure Storage**: Flutter Secure Storage for token persistence
- **Concurrent Safety**: Handle multiple token operations safely

**Security Measures**:
- Tokens stored in secure platform storage
- Automatic token validation and cleanup
- Refresh token rotation
- Session invalidation on security events

### API Security
**Implementation**: 
- Bearer token authentication
- Automatic token refresh on 401 errors
- Request retry with new tokens
- Token expiry buffer (5 minutes before expiry)

---

## 📱 Platform & Environment Configuration

### Environment Management
**File**: `lib/core/config/app_config.dart`

**Environments**:
- **Development**: Local development with detailed logging
- **Staging**: Pre-production testing environment
- **Production**: Live production environment

**Configuration**:
```dart
class AppConfig {
  static bool get isDevelopment => _environment == 'development';
  static String get baseUrl => isDevelopment 
    ? 'https://api.dev.tulink.xyz'
    : 'https://api.tulink.com';
  static bool get enableDetailedLogging => !isProduction;
}
```

### Dependencies
**Key Dependencies**:
- **provider: ^6.1.2** - State management
- **dio: ^5.7.0** - HTTP client
- **hive: ^2.2.3** - Local NoSQL database
- **flutter_secure_storage: ^9.2.2** - Secure token storage
- **mapbox_maps_flutter: ^2.19.1** - Map integration
- **google_fonts: ^6.2.1** - Typography
- **equatable: ^2.0.5** - Value equality
- **json_annotation: ^4.9.0** - JSON serialization

---

## 🧪 Testing Strategy

### Test Structure
```
test/
├── unit/                         # Unit tests for business logic
├── integration/                  # Integration tests for data flow  
├── widget/                       # Widget tests for UI components
└── mocks/                        # Mock implementations
```

### Testing Patterns
**Repository Tests**: Mock data sources, test business logic
**Provider Tests**: Mock repositories, test state management
**Widget Tests**: Test UI behavior and user interactions
**Integration Tests**: Test full feature flows

---

## 🚀 Development Workflows

### Code Generation
**Commands**:
```bash
flutter packages pub run build_runner build --delete-conflicting-outputs
```

**Generated Code**:
- JSON serialization (`*.g.dart`)
- Hive type adapters (`*.g.dart`)

### Development Commands
```bash
flutter run                      # Run development build
flutter test                     # Run all tests
flutter analyze                  # Static analysis
flutter build apk                # Android build
flutter build ios                # iOS build
```

### Code Quality
- **Linting**: `very_good_analysis` package
- **Formatting**: `dart format`
- **Analysis**: `flutter analyze` with custom rules

---

## 🔍 Key Implementation Patterns

### 1. Feature-First Organization
- Each feature is self-contained with its own layers
- Shared code lives in `core/`
- Clear boundaries between features

### 2. Dependency Inversion
- High-level modules don't depend on low-level modules
- Both depend on abstractions (interfaces)
- Dependencies point inward toward business logic

### 3. Single Responsibility
- Each class has one reason to change
- Clear separation of concerns across layers
- Focused, testable components

### 4. Provider State Management
- Reactive UI updates with ChangeNotifier
- Clear state management with computed getters
- Action methods that coordinate with domain layer

### 5. Failure-Based Error Handling
- Type-safe error handling with custom failure types
- Graceful error recovery and user messaging
- Comprehensive error context for debugging

---

## 📝 Documentation Files

### Project Documentation (docs/)
- **`IMPLEMENTATION_PLAN.md`** - Completed implementation roadmap
- **`clean-architecture-patterns.md`** - Detailed architecture guide
- **`CRITICAL_IMPLEMENTATION_GUIDE.md`** - Critical implementation details
- **`FLUTTER_APP_ANALYSIS_AND_2DAY_PLAN.md`** - Project analysis and planning
- **`api-response-format-documentation.md`** - API contract documentation

### Development Guidelines
- **`CLAUDE.md`** - Full stack development guidelines and patterns
- **`README.md`** - Basic project information
- **`.env.example`** - Environment variables template

---

## 🎯 AI Assistant Usage Guidelines

### When Analyzing This Codebase:

1. **Start with Architecture**: Always understand the Clean Architecture layers before making changes
2. **Follow Patterns**: Use existing patterns for new features (Repository, Provider, Model-Entity)
3. **Respect Boundaries**: Don't violate dependency rules (e.g., domain depending on data)
4. **Consider State**: Understand how Provider manages state before modifying UI
5. **Check Dependencies**: Verify service locator setup when adding new dependencies
6. **Test Coverage**: Maintain test coverage when adding features
7. **Error Handling**: Use appropriate Failure types for different error scenarios
8. **Security**: Ensure token management and secure storage practices are maintained

### When Making Changes:

1. **Read `CLAUDE.md`** for full development guidelines
2. **Check `clean-architecture-patterns.md`** for implementation patterns  
3. **Follow existing code style** and naming conventions
4. **Update dependencies** in `ServiceLocator` when adding new features
5. **Test thoroughly** across all layers
6. **Maintain documentation** when adding significant features

### Common Tasks:

- **Adding New Feature**: Follow feature module structure, implement all layers
- **API Integration**: Use existing DioClient patterns and error handling
- **UI Changes**: Follow TuLink dark theme and Material 3 patterns
- **State Management**: Use Provider pattern with ChangeNotifier
- **Navigation**: Update `AppRouter` with type-safe routing
- **Testing**: Create tests for all layers (unit, integration, widget)

---

This documentation provides a complete understanding of the TuLink Flutter codebase architecture, patterns, and implementation details. Use it as a reference for understanding the codebase structure and making informed development decisions.