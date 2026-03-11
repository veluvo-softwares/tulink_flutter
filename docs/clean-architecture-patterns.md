# Clean Architecture Patterns in TuLink Flutter

## Overview

This document outlines the Clean Architecture implementation patterns used in TuLink Flutter, focusing on proper layer separation, dependency flow, and architectural decisions that maintain scalability and testability.

## Architecture Layers

### Visual Architecture
```
┌─────────────────────────────────────┐
│           Presentation              │ ← UI, State Management
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

### Directory Structure
```
lib/
├── core/                     # Shared infrastructure
│   ├── di/                   # Dependency Injection
│   ├── errors/               # Error handling
│   ├── network/              # HTTP client & API handling
│   ├── navigation/           # App routing
│   └── theme/                # UI theming
│
├── features/                 # Feature-first organization
│   └── auth/                 # Authentication feature
│       ├── domain/           # Business logic layer
│       │   ├── entities/     # Pure business objects
│       │   ├── repositories/ # Repository interfaces
│       │   └── usecases/     # Business use cases
│       ├── data/             # Infrastructure layer  
│       │   ├── models/       # Data transfer objects
│       │   ├── datasources/  # API & Cache sources
│       │   ├── repositories/ # Repository implementations
│       │   └── services/     # API services
│       └── presentation/     # UI layer
│           ├── providers/    # State management
│           ├── screens/      # UI screens
│           └── widgets/      # Reusable widgets
│
└── main.dart                 # App entry point
```

## Layer Responsibilities

### 1. Domain Layer (Business Logic)

#### Entities
**Purpose**: Pure business objects representing core concepts
**Dependencies**: None (pure Dart)

```dart
// ✅ Good - Pure business logic
class UserEntity extends Equatable {
  const UserEntity({
    required this.id,
    required this.email,
    required this.name,
    this.phoneNumber,
    this.isEmailVerified = false,
  });
  
  // Business logic methods
  bool get hasCompleteProfile => 
    name.isNotEmpty && phoneNumber != null;
    
  bool get needsEmailVerification => !isEmailVerified;
}
```

#### Repository Interfaces
**Purpose**: Define contracts for data operations
**Dependencies**: Only domain entities

```dart
// ✅ Good - Abstract interface
abstract class AuthRepository {
  Future<({UserEntity? user, String? token, Failure? failure})> signIn({
    required String email,
    required String password,
  });
  
  Future<bool> isSignedIn();
}
```

#### Use Cases (Future Implementation)
**Purpose**: Encapsulate specific business operations
**Dependencies**: Repository interfaces, entities

```dart
// Example use case pattern
class SignInUseCase extends UseCase<UserEntity, SignInParams> {
  const SignInUseCase(this._authRepository);
  
  final AuthRepository _authRepository;
  
  @override
  Future<({UserEntity? data, Failure? failure})> call(SignInParams params) async {
    final result = await _authRepository.signIn(
      email: params.email,
      password: params.password,
    );
    
    if (result.failure != null) {
      return (data: null, failure: result.failure);
    }
    
    return (data: result.user, failure: null);
  }
}
```

### 2. Data Layer (Infrastructure)

#### Models
**Purpose**: Handle external data format conversion
**Dependencies**: Domain entities, JSON/Hive frameworks

```dart
// ✅ Good - Handles external concerns
@JsonSerializable()
@HiveType(typeId: 0)
class UserModel extends UserEntity {
  UserModel({
    required super.id,
    required super.email,
    required super.name,
    super.phoneNumber,
    super.isEmailVerified,
    required this.createdAt,
  });
  
  @HiveField(6) final DateTime createdAt;
  
  // JSON conversion (API integration)
  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
    id: json['uid'] as String,           // Maps Firebase field names
    email: json['email'] as String,
    name: json['displayName'] as String,
    phoneNumber: json['phoneNumber'] as String?,
    isEmailVerified: json['emailVerified'] as bool? ?? false,
    createdAt: DateTime.now(),
  );
  
  // Domain conversion
  UserEntity toEntity() => UserEntity(
    id: id,
    email: email,
    name: name,
    phoneNumber: phoneNumber,
    isEmailVerified: isEmailVerified,
  );
}
```

#### Data Sources
**Purpose**: Handle specific data operations
**Dependencies**: Models, external APIs/storage

```dart
// Remote data source - API integration
class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  AuthRemoteDataSourceImpl(this._authApiService);
  
  final AuthApiService _authApiService;
  
  @override
  Future<({UserModel user, String token, String? refreshToken})> signIn({
    required String email,
    required String password,
  }) async {
    final responseData = await _authApiService.signIn({
      'email': email,
      'password': password,
    });
    
    final authResponse = AuthResponseModel.fromJson(responseData);
    
    return (
      user: authResponse.user,
      token: authResponse.tokens.idToken,
      refreshToken: authResponse.tokens.refreshToken,
    );
  }
}

// Local data source - Cache integration  
class AuthLocalDataSourceImpl implements AuthLocalDataSource {
  AuthLocalDataSourceImpl(this._authBox);
  
  final Box<dynamic> _authBox;
  
  @override
  Future<UserModel?> getCachedUser() async {
    try {
      final userData = _authBox.get(_userKey);
      return userData is UserModel ? userData : null;
    } catch (e) {
      throw CacheFailure.read;
    }
  }
}
```

#### Repository Implementation
**Purpose**: Orchestrate data sources and implement business rules
**Dependencies**: Data sources, domain interfaces

```dart
class AuthRepositoryImpl implements AuthRepository {
  const AuthRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
    required this.dioClient,
  });
  
  @override
  Future<({UserEntity? user, String? token, Failure? failure})> signIn({
    required String email,
    required String password,
  }) async {
    try {
      // 1. API call
      final result = await remoteDataSource.signIn(
        email: email,
        password: password,
      );
      
      // 2. Cache data
      await localDataSource.cacheUser(result.user);
      await localDataSource.cacheToken(result.token);
      await dioClient.saveAuthToken(result.token);
      
      // 3. Return domain object
      return (
        user: result.user.toEntity(),  // Convert to domain
        token: result.token,
        failure: null,
      );
    } on Failure catch (failure) {
      return (user: null, token: null, failure: failure);
    }
  }
}
```

### 3. Presentation Layer (UI)

#### Providers (State Management)
**Purpose**: Manage UI state and coordinate with domain layer
**Dependencies**: Domain repositories, UI framework

```dart
class AuthProvider extends ChangeNotifier {
  AuthProvider(this._authRepository);
  
  final AuthRepository _authRepository;
  
  // State
  UserEntity? _user;
  bool _isLoading = false;
  Failure? _failure;
  
  // Getters (computed state)
  UserEntity? get user => _user;
  bool get isLoading => _isLoading;
  bool get hasError => _failure != null;
  String get errorMessage => _failure?.message ?? '';
  
  // Actions
  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    _setLoading(true);
    _clearFailure();
    
    final result = await _authRepository.signIn(
      email: email,
      password: password,
    );
    
    if (result.failure == null) {
      _user = result.user;
      _setLoading(false);
      return true;
    } else {
      _setFailure(result.failure);
      _setLoading(false);
      return false;
    }
  }
}
```

#### Screens
**Purpose**: Define UI structure and handle user interactions
**Dependencies**: Providers, widgets

```dart
class AuthScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          if (authProvider.isLoading) {
            return const CircularProgressIndicator();
          }
          
          return AuthForm(
            onSignIn: (email, password) async {
              final success = await authProvider.signIn(
                email: email,
                password: password,
              );
              
              if (success) {
                Navigator.of(context).pushReplacementNamed('/home');
              }
            },
            errorMessage: authProvider.errorMessage,
          );
        },
      ),
    );
  }
}
```

## Dependency Flow

### The Dependency Rule
**"Source code dependencies can only point inwards"**

```
┌─────────────────┐
│  Presentation   │ ─depends on─┐
├─────────────────┤              │
│     Domain      │ ←────────────┘
├─────────────────┤              │ 
│      Data       │ ─depends on─┘
└─────────────────┘
```

### Dependency Injection
**Pattern**: Manual DI using Service Locator

```dart
class ServiceLocator {
  // Singleton pattern
  static final ServiceLocator _instance = ServiceLocator._internal();
  factory ServiceLocator() => _instance;
  
  Future<void> init() async {
    // 1. Infrastructure
    _dioClient = DioClient();
    _authBox = await Hive.openBox(AppConstants.authBoxName);
    
    // 2. Services 
    _authApiService = AuthApiService(_dioClient.dio);
    
    // 3. Data sources
    _authLocalDataSource = AuthLocalDataSourceImpl(_authBox);
    _authRemoteDataSource = AuthRemoteDataSourceImpl(_authApiService);
    
    // 4. Repositories (Domain ← Data)
    _authRepository = AuthRepositoryImpl(
      remoteDataSource: _authRemoteDataSource,
      localDataSource: _authLocalDataSource,
      dioClient: _dioClient,
    );
    
    // 5. Providers (Presentation ← Domain)
    _authProvider = AuthProvider(_authRepository);
    _themeProvider = ThemeProvider();
    
    await _authProvider.initialize();
  }
}
```

## Key Patterns

### 1. Repository Pattern
**Purpose**: Abstract data access logic
**Implementation**: Interface in domain, implementation in data

```dart
// Domain layer - interface
abstract class AuthRepository {
  Future<({UserEntity? user, Failure? failure})> getCurrentUser();
}

// Data layer - implementation  
class AuthRepositoryImpl implements AuthRepository {
  // Coordinates multiple data sources
  @override
  Future<({UserEntity? user, Failure? failure})> getCurrentUser() async {
    // Check cache first, fallback to remote
  }
}
```

### 2. Model-Entity Pattern
**Purpose**: Separate external data format from business logic

```dart
// Data Model - handles external concerns
@JsonSerializable()
@HiveType(typeId: 0)  
class UserModel extends UserEntity {
  // JSON serialization, Hive storage, API field mapping
}

// Domain Entity - pure business logic
class UserEntity {
  // Business rules, validation, computed properties
  bool get hasCompleteProfile => name.isNotEmpty && phoneNumber != null;
}
```

### 3. Provider Pattern (State Management)
**Purpose**: Reactive state management with clear separation

```dart
// Provider handles state + business operations
class AuthProvider extends ChangeNotifier {
  // Delegates business logic to repositories
  Future<bool> signIn() async {
    final result = await _authRepository.signIn();
    // Handle state updates
  }
}

// UI consumes state reactively
Consumer<AuthProvider>(
  builder: (context, authProvider, child) {
    return authProvider.isLoading 
      ? LoadingWidget()
      : ContentWidget();
  },
)
```

### 4. Failure Handling Pattern
**Purpose**: Type-safe error handling across layers

```dart
// Domain layer - typed failures
abstract class Failure {
  const Failure({required this.message});
  final String message;
}

class AuthFailure extends Failure {
  const AuthFailure.invalidCredentials() : 
    super(message: 'Invalid email or password');
}

// Repository returns success/failure
Future<({UserEntity? user, Failure? failure})> signIn();

// UI handles specific failures
if (result.failure is AuthFailure) {
  showSnackBar('Authentication failed');
}
```

## Testing Strategy

### Unit Tests by Layer

#### Domain Tests
```dart
group('UserEntity', () {
  test('should identify complete profile', () {
    final user = UserEntity(
      id: '1',
      email: 'test@example.com',
      name: 'John Doe',
      phoneNumber: '+1234567890',
    );
    
    expect(user.hasCompleteProfile, isTrue);
  });
});
```

#### Repository Tests  
```dart
group('AuthRepositoryImpl', () {
  test('should return cached user when available', () async {
    when(mockLocalDataSource.getCachedUser())
        .thenAnswer((_) async => testUserModel);
    
    final result = await repository.getCurrentUser();
    
    expect(result.user, equals(testUserModel.toEntity()));
    expect(result.failure, isNull);
    verifyNever(mockRemoteDataSource.getCurrentUser());
  });
});
```

#### Provider Tests
```dart
group('AuthProvider', () {
  test('should set loading state during sign in', () async {
    when(mockAuthRepository.signIn(any))
        .thenAnswer((_) async => (user: testUser, failure: null));
    
    final future = authProvider.signIn(email: 'test@example.com', password: 'password');
    
    expect(authProvider.isLoading, isTrue);
    await future;
    expect(authProvider.isLoading, isFalse);
  });
});
```

## Benefits of This Architecture

### 1. **Testability**
- Each layer can be tested in isolation
- Easy to mock dependencies
- Fast unit tests (no external dependencies in domain)

### 2. **Maintainability**  
- Clear separation of concerns
- Easy to locate and modify specific functionality
- Consistent patterns across features

### 3. **Scalability**
- New features follow established patterns
- Easy to add new data sources or UI components
- Framework-independent business logic

### 4. **Team Development**
- Different developers can work on different layers
- Clear interfaces between layers
- Consistent code organization

This architecture ensures that TuLink Flutter remains maintainable, testable, and scalable as it grows.