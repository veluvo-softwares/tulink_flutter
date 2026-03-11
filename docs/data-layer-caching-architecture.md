# Data Layer Caching Architecture

## Overview

This document explains our architectural decision to implement caching at the **Data Layer** using **UserModel + Hive** instead of caching domain entities directly. This approach maintains clean architecture principles while providing efficient local storage.

## Architecture Decision

### Chosen Approach: Data Layer Caching
```
┌─────────────────┐
│ Presentation    │ ← UserEntity (Pure)
├─────────────────┤
│ Domain          │ ← UserEntity (Pure) 
├─────────────────┤
│ Data            │ ← UserModel (Hive + JSON)
└─────────────────┘
```

### Alternative Rejected: Domain Layer Caching
```
┌─────────────────┐
│ Presentation    │ ← UserEntity (Hive annotated)
├─────────────────┤ 
│ Domain          │ ← UserEntity (Hive annotated) ❌
├─────────────────┤
│ Data            │ ← UserModel (JSON only)
└─────────────────┘
```

## Rationale

### ✅ Why Data Layer Caching is Better

#### 1. **Clean Architecture Compliance**
- **Dependency Rule**: Domain layer has zero external dependencies
- **Infrastructure Isolation**: Storage technology (Hive) isolated to data layer
- **Framework Independence**: Domain entities remain pure Dart objects

#### 2. **Separation of Concerns**
```dart
// Domain Layer - Pure business logic
class UserEntity {
  final String id;
  final String email;
  // No Hive annotations, no external dependencies
}

// Data Layer - Infrastructure concerns
@HiveType(typeId: 0)
class UserModel extends UserEntity {
  @HiveField(0) final String id;
  @HiveField(1) final String email;
  // Handles both JSON serialization AND Hive storage
}
```

#### 3. **Testability**
- Domain layer tests require no Hive setup
- Repository tests can mock storage without affecting domain
- Clean unit tests for business logic

#### 4. **Flexibility & Future-Proofing**
- Can switch from Hive → SQLite → SharedPreferences without touching domain
- Different storage strategies per platform
- Easy to add encryption or compression at data layer

### ❌ Why Domain Layer Caching is Problematic

#### 1. **Violates Clean Architecture**
```dart
// This would pollute the domain layer ❌
@HiveType(typeId: 0)  // Infrastructure concern leaking into domain
class UserEntity {
  @HiveField(0) final String id;  // Storage detail in business logic
}
```

#### 2. **Tight Coupling**
- Domain entities become coupled to Hive framework
- Harder to change storage technology
- Domain layer tests require Hive setup

#### 3. **Mixed Responsibilities**
- Business logic mixed with storage concerns
- Harder to reason about and maintain

## Implementation Pattern

### Data Flow
```
Remote API → UserModel (JSON) → Cache (Hive) → UserEntity (Domain)
                    ↑                              ↓
                Cache Hit ← UserModel (Hive) ←──────┘
```

### Repository Implementation
```dart
@override
Future<UserEntity> getCurrentUser() async {
  // 1. Check cache first (Data Layer concern)
  final cachedModel = await localDataSource.getCachedUser(); // UserModel
  if (cachedModel != null) {
    return cachedModel.toEntity(); // Convert to pure domain object
  }
  
  // 2. Fallback to remote API (Data Layer concern)
  final remoteModel = await remoteDataSource.getCurrentUser(); // UserModel
  
  // 3. Cache for future use (Data Layer concern)
  await localDataSource.cacheUser(remoteModel); // Store UserModel
  
  // 4. Return pure domain object
  return remoteModel.toEntity(); // UserEntity
}
```

### Conversion Methods
```dart
class UserModel extends UserEntity {
  // Convert data model to domain entity
  UserEntity toEntity() => UserEntity(
    id: id,
    email: email,
    name: name,
    phoneNumber: phoneNumber,
    // ... all fields
  );
  
  // Convert domain entity to data model  
  factory UserModel.fromEntity(UserEntity entity) => UserModel(
    id: entity.id,
    email: entity.email,
    // ... all fields
  );
}
```

## Benefits in Practice

### 1. **Clean Testing**
```dart
// Domain tests - no Hive setup needed
test('should return user entity', () {
  final entity = UserEntity(id: '1', email: 'test@example.com');
  // Pure unit test
});

// Repository tests - mock the data layer
test('should cache user after remote fetch', () async {
  when(mockLocalDataSource.getCachedUser()).thenReturn(null);
  when(mockRemoteDataSource.getCurrentUser()).thenReturn(userModel);
  
  final result = await repository.getCurrentUser();
  
  verify(mockLocalDataSource.cacheUser(userModel));
  expect(result, equals(expectedEntity));
});
```

### 2. **Easy Storage Migration**
```dart
// Tomorrow: Switch from Hive to SQLite
class UserModelSqlAdapter {
  static const String tableName = 'users';
  
  Map<String, dynamic> toSql(UserModel model) => {
    'id': model.id,
    'email': model.email,
    // Same UserModel, different storage
  };
}
```

### 3. **Platform-Specific Storage**
```dart
// Different storage per platform
if (Platform.isWeb) {
  // Use SharedPreferences for web
} else {
  // Use Hive for mobile
}
// Domain layer unchanged
```

## Current Implementation

### UserModel (Data Layer)
```dart
@JsonSerializable()
@HiveType(typeId: 0)
class UserModel extends UserEntity {
  @HiveField(0) final String id;
  @HiveField(1) final String email;
  @HiveField(2) final String name;
  @HiveField(3) final String? phoneNumber;
  @HiveField(4) final String? profilePicture;
  @HiveField(5) final bool isEmailVerified;
  @HiveField(6) final DateTime createdAt;
  @HiveField(7) final DateTime? updatedAt;
  
  // Handles JSON from API
  factory UserModel.fromJson(Map<String, dynamic> json) => ...;
  
  // Converts to pure domain object
  UserEntity toEntity() => UserEntity(...);
}
```

### UserEntity (Domain Layer)
```dart
class UserEntity extends Equatable {
  const UserEntity({
    required this.id,
    required this.email,
    required this.name,
    this.phoneNumber,
    // ... pure domain object, no annotations
  });
  
  // Pure business logic methods
  bool get hasCompleteProfile => 
    name.isNotEmpty && phoneNumber != null;
}
```

## Conclusion

By keeping caching concerns in the data layer:

1. **Domain stays pure** - focused on business logic
2. **Data layer handles infrastructure** - JSON parsing, caching, API calls
3. **Repository orchestrates** - cache strategy, fallbacks, conversions
4. **Clean separation** - easy to test, modify, and extend

This approach scales well and maintains clean architecture principles as the application grows.