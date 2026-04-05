# Unified API Pattern Documentation

## Overview

This document describes the standardized API pattern implemented across the TuLink Flutter application's domain layers. The pattern ensures consistency, maintainability, and clean separation of concerns across all API integrations.

## Architecture Components

### 1. ApiRoutes - Centralized Route Definitions

**Purpose**: Single source of truth for all API endpoint paths

**Location**: `lib/core/network/api_routes.dart`

**Pattern**:
- Static constants for fixed endpoints
- Static methods with parameters for dynamic endpoints
- Zero hardcoded strings in service or data source files

**Example**:
```dart
class ApiRoutes {
  // Static endpoints
  static const String journeys = '/journeys';
  static const String invitations = '/invitations';
  
  // Dynamic endpoints
  static String journeyById(String id) => '/journeys/$id';
  static String journeyInvitations(String id) => '/journeys/$id/invitations';
}
```

### 2. ApiService - Retrofit-Style Service Layer

**Purpose**: Clean method signatures that delegate to ApiHandler for standardized HTTP operations

**Pattern**:
- Constructor takes Dio instance
- Each method returns `Future<Map<String, dynamic>>` for data or `Future<void>` for operations
- Uses `ApiHandler.performStandardApiCall` for consistent error handling and response formatting
- Uses `ApiHandler.performStandardVoidApiCall` for delete/void operations

**Example**:
```dart
class JourneyApiService {
  JourneyApiService(this._dio);
  
  final Dio _dio;

  Future<Map<String, dynamic>> getJourneyById(String journeyId) {
    return ApiHandler.performStandardApiCall<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(
        ApiRoutes.journeyById(journeyId),
      ),
      (data) => data,
    );
  }
}
```

### 3. RemoteDataSource - Pure Data Mapping Layer

**Purpose**: Execute API calls through services and map responses to domain entities

**Pattern**:
- Constructor takes ApiService dependency
- Zero business logic - pure mapping responsibility
- Delegates all HTTP operations to ApiService
- Maps API responses to domain entities using private helper methods
- No hardcoded endpoints or manual error handling

**Example**:
```dart
class JourneyRemoteDataSourceImpl implements JourneyRemoteDataSource {
  JourneyRemoteDataSourceImpl(this._journeyApiService);
  
  final JourneyApiService _journeyApiService;

  @override
  Future<JourneyModel> getJourneyById(String journeyId) async {
    final responseData = await _journeyApiService.getJourneyById(journeyId);
    final journeyData = responseData['data'] as Map<String, dynamic>;
    return JourneyModel.fromJson(journeyData);
  }
}
```

## Implementation Guidelines

### Do's ✅

1. **Centralize Routes**: All endpoints must be defined in ApiRoutes
2. **Use ApiHandler**: All HTTP calls must go through ApiHandler for consistency
3. **Single Responsibility**: Each layer has one clear purpose
4. **Package Imports**: Use `package:tulink_flutter/...` imports for internal files
5. **Standardized Responses**: Expect `{data: {...}}` format from API
6. **Error Delegation**: Let ApiHandler manage all error scenarios

### Don'ts ❌

1. **No Hardcoded URLs**: Never put endpoint strings directly in services or data sources
2. **No Manual Error Handling**: Don't catch/handle HTTP errors manually
3. **No Business Logic**: Keep data sources focused on pure mapping
4. **No Direct Dio Usage**: Always go through ApiService layer
5. **No Mixed Responsibilities**: Don't mix mapping logic with HTTP logic

## File Structure

```
lib/
├── core/
│   └── network/
│       ├── api_routes.dart          // Centralized routes
│       ├── api_handler.dart         // HTTP wrapper
│       └── api_query_builder.dart   // Query utilities
├── features/
│   └── [feature]/
│       └── data/
│           ├── services/
│           │   └── [feature]_api_service.dart      // HTTP service
│           └── datasources/
│               └── [feature]_remote_data_source.dart // Mapping layer
```

## Migration Checklist

When updating existing implementations:

- [ ] Move all endpoint strings to ApiRoutes
- [ ] Create ApiService using ApiHandler pattern
- [ ] Update RemoteDataSource to use ApiService
- [ ] Remove hardcoded endpoints from data sources
- [ ] Remove manual error handling
- [ ] Add proper package imports
- [ ] Test compilation with `flutter analyze`

## Testing

Run analysis to ensure pattern compliance:

```bash
flutter analyze lib/features/[feature]/data/ --suppress-analytics
```

Common issues to fix:
- Package import violations
- Line length limits
- Missing newlines at file endings
- Directive ordering

## Benefits

1. **Consistency**: Uniform approach across all features
2. **Maintainability**: Single place to update endpoints
3. **Testability**: Clear separation enables better unit testing
4. **Error Handling**: Centralized error management through ApiHandler
5. **Type Safety**: Standardized response formats
6. **Scalability**: Easy to add new endpoints and services

## Phase 1 & 2 Integration

This pattern has been successfully applied to:

- **Authentication**: Reference implementation (already compliant)
- **Journeys**: Refactored in this migration
- **Invitations**: Created new implementation following pattern

All domain layers now follow the unified API pattern for consistent, maintainable code.