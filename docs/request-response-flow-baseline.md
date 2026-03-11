# Request-Response Flow Baseline Documentation

## Overview

This document establishes the **standard baseline** for how data flows through our Flutter application architecture during authentication operations. This pattern should be followed consistently across all API requests and responses in the application.

## Architecture Layers

```
┌─────────────────────────────────────────────────────────────┐
│                     PRESENTATION LAYER                     │
│  ┌─────────────────┐    ┌──────────────────────────────┐    │
│  │   UI (Screens)  │ ←→ │      AuthProvider            │    │
│  │   - AuthScreen  │    │   - State Management         │    │
│  │   - User Input  │    │   - Error Handling           │    │
│  └─────────────────┘    │   - Loading States           │    │
│                         └──────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                                    ↕
┌─────────────────────────────────────────────────────────────┐
│                      DOMAIN LAYER                          │
│  ┌──────────────────────────────────────────────────────┐    │
│  │               AuthRepository                         │    │
│  │   - Business Logic Contracts                        │    │
│  │   - UserEntity (Pure Business Objects)              │    │
│  │   - Success/Failure Return Types                    │    │
│  └──────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                                    ↕
┌─────────────────────────────────────────────────────────────┐
│                       DATA LAYER                           │
│  ┌──────────────────┐  ┌─────────────────┐  ┌─────────────┐  │
│  │AuthRepositoryImpl│  │AuthRemoteDataSrc│  │AuthApiService│  │
│  │- Orchestration   │→ │- API Integration│→ │- HTTP Calls │  │
│  │- Caching Logic   │  │- Response Parsing│  │- Endpoints  │  │
│  │- Token Storage   │  │- UserModel DTOs │  │- Raw JSON   │  │
│  └──────────────────┘  └─────────────────┘  └─────────────┘  │
└─────────────────────────────────────────────────────────────┘
                                    ↕
┌─────────────────────────────────────────────────────────────┐
│                   INFRASTRUCTURE LAYER                     │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐  │
│  │   ApiHandler    │  │    DioClient    │  │   Storage   │  │
│  │- Standardized   │→ │- HTTP Client    │→ │- Hive Cache │  │
│  │  Response       │  │- Interceptors   │  │- Secure     │  │
│  │- Error Mapping  │  │- Token Mgmt     │  │  Storage    │  │
│  └─────────────────┘  └─────────────────┘  └─────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Standard Request-Response Flow

### 📱 Outgoing Request Flow (UI → API)

#### Step 1: Presentation Layer
**File:** `auth_provider.dart`
```dart
Future<bool> signIn({required String email, required String password}) async {
  _setLoading(true);        // Set UI loading state
  _clearFailure();          // Clear previous errors
  
  final result = await _authRepository.signIn(email: email, password: password);
  
  // Handle domain result and update UI state
  if (result.failure == null) {
    _user = result.user;    // Store UserEntity
    _isSignedIn = true;     // Update sign-in state
    return true;
  } else {
    _setFailure(result.failure);
    return false;
  }
}
```

#### Step 2: Domain Layer
**File:** `auth_repository.dart` (Interface)
```dart
Future<({UserEntity? user, String? token, Failure? failure})> signIn({
  required String email,
  required String password,
});
```

#### Step 3: Data Layer Implementation
**File:** `auth_repository_impl.dart`
```dart
Future<({UserEntity? user, String? token, Failure? failure})> signIn(...) async {
  try {
    // 1. Call remote data source
    final result = await remoteDataSource.signIn(email: email, password: password);
    
    // 2. Cache data locally
    await localDataSource.cacheUser(result.user);
    await localDataSource.cacheToken(result.token);
    await dioClient.saveAuthToken(result.token);
    
    // 3. Handle refresh token
    if (result.refreshToken != null) {
      await dioClient.saveRefreshToken(result.refreshToken!);
    }
    
    // 4. Convert to domain entity and return
    return (user: result.user.toEntity(), token: result.token, failure: null);
  } on Failure catch (failure) {
    return (user: null, token: null, failure: failure);
  }
}
```

#### Step 4: Remote Data Source
**File:** `auth_remote_data_source.dart`
```dart
Future<({UserModel user, String token, String? refreshToken})> signIn(...) async {
  // 1. Make API call
  final responseData = await _authApiService.signIn({
    'email': email,
    'password': password,
  });
  
  // 2. Parse response data
  final dataObject = responseData['data'] as Map<String, dynamic>;
  final authResponse = AuthResponseModel.fromJson(dataObject);
  
  // 3. Return structured data
  return (
    user: authResponse.user,
    token: authResponse.tokens.idToken,
    refreshToken: authResponse.tokens.refreshToken,
  );
}
```

#### Step 5: API Service
**File:** `auth_api_service.dart`
```dart
Future<Map<String, dynamic>> signIn(Map<String, dynamic> credentials) {
  return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
    () => _dio.post<Map<String, dynamic>>(
      ApiRoutes.signIn,  // "/auth/signin"
      data: credentials,
    ),
    (data) => data,
  );
}
```

#### Step 6: Infrastructure Layer
**File:** `api_handler.dart`
```dart
static Future<T> performStandardApiCall<T>(
  Future<Response<Map<String, dynamic>>> Function() apiCall,
  T Function(Map<String, dynamic> data) parser,
) async {
  final response = await apiCall();
  
  // Parse standardized wrapper response
  final apiResponse = ApiResponse<Map<String, dynamic>>.fromJson(
    response.data!,
    (json) => json! as Map<String, dynamic>,
  );
  
  if (apiResponse.success && apiResponse.data != null) {
    return parser(apiResponse.data!);
  } else {
    throw _handleStandardApiError(apiResponse);
  }
}
```

### 📡 Incoming Response Flow (API → UI)

#### Step 1: API Response Structure
```json
{
  "success": true,
  "statusCode": 200,
  "message": "User signed in successfully",
  "data": {
    "user": {
      "uid": "firebase_uid_123",
      "email": "user@example.com",
      "displayName": "John Doe",
      "phoneNumber": "+1234567890",
      "emailVerified": true,
      "createdAt": "2024-01-15T10:30:00Z",
      "updatedAt": "2024-01-20T14:45:00Z"
    },
    "tokens": {
      "idToken": "eyJhbGciOiJSUzI1NiIs...",
      "refreshToken": "AMf-vBwD8eSpuC21eICm...",
      "expiresIn": 3600
    }
  }
}
```

#### Step 2: Data Transformation Pipeline

| **Layer** | **Input Type** | **Output Type** | **Transformation** |
|-----------|----------------|-----------------|-------------------|
| **ApiHandler** | Raw JSON | `Map<String, dynamic>` | Extract `data` from wrapper |
| **AuthApiService** | `Map<String, dynamic>` | `Map<String, dynamic>` | Pass-through parser |
| **AuthRemoteDataSource** | `Map<String, dynamic>` | `AuthResponseModel` | JSON → DTO parsing |
| **AuthRepositoryImpl** | `UserModel + tokens` | `UserEntity + token` | Model → Entity conversion |
| **AuthProvider** | `UserEntity + token` | UI State | State management |

### 🔐 Token Storage Strategy

#### Storage Locations
| **Token Type** | **Primary Storage** | **Secondary Storage** | **Purpose** |
|----------------|-------------------|-------------------|-------------|
| **ID Token** | Secure Storage (DioClient) | Hive Cache | API authentication |
| **Refresh Token** | Secure Storage (DioClient) | None | Token renewal |
| **User Data** | Hive Cache | Memory (AuthProvider) | Local persistence |

#### Storage Flow
```dart
// In AuthRepositoryImpl.signIn()
await localDataSource.cacheUser(result.user);        // UserModel → Hive
await localDataSource.cacheToken(result.token);      // ID Token → Hive  
await dioClient.saveAuthToken(result.token);         // ID Token → Secure Storage
await dioClient.saveRefreshToken(result.refreshToken!); // Refresh Token → Secure Storage
```

## Error Handling Strategy

### Error Flow Pattern
```
API Error → AuthFailure → Repository Result → Provider State → UI Display
```

### Error Types by Layer
- **Infrastructure:** Network, HTTP, JSON parsing errors
- **Data Layer:** Cache failures, API failures (converted to domain failures)
- **Domain Layer:** Business logic failures (AuthFailure, ValidationFailure)
- **Presentation:** UI state failures, form validation errors

### Standardized Error Response
```json
{
  "success": false,
  "statusCode": 401,
  "message": "Invalid credentials",
  "data": null,
  "error": {
    "code": "INVALID_CREDENTIALS",
    "details": "The provided email and password combination is incorrect"
  }
}
```

## Key Principles

### 1. **Separation of Concerns**
- **UI Layer:** User interaction, state display
- **Domain Layer:** Business rules, entity definitions
- **Data Layer:** External data handling, caching
- **Infrastructure:** HTTP, storage, external services

### 2. **Data Flow Direction**
- **Inward Dependency:** Outer layers depend on inner layers
- **Domain Independence:** Core business logic has no external dependencies
- **Interface Contracts:** Layers communicate through well-defined interfaces

### 3. **Error Handling**
- **No Exceptions in UI:** Repository returns success/failure records
- **Typed Failures:** Specific failure types for different error categories
- **Graceful Degradation:** Local cache fallbacks when API fails

### 4. **Token Management**
- **Secure Storage:** Sensitive tokens stored securely
- **Cache Strategy:** Performance optimization with local cache
- **Automatic Refresh:** Silent token renewal in background

## Usage Guidelines

### For New Features
1. **Follow the same layer pattern** for all API interactions
2. **Use the established error handling** with typed failures
3. **Implement proper caching** at the repository level
4. **Use domain entities** in presentation layer, data models in data layer
5. **Maintain the request/response transformation pipeline**

### For Testing
1. **Mock at layer boundaries** (Repository interface, RemoteDataSource interface)
2. **Test each layer independently** with appropriate test doubles
3. **Verify error handling** at each layer
4. **Test data transformations** between layers

This baseline ensures **consistency**, **maintainability**, and **scalability** across all features in the TuLink Flutter application.