# API Response Format Documentation

## Overview

This document defines the standardized API response format used throughout the TuLink Flutter application. All API endpoints follow consistent response structures to ensure predictable error handling and data parsing across the application.

## Response Structure

### Base Response Format

All API responses follow a standardized structure with the following fields:

```json
{
  "success": boolean,
  "statusCode": number,
  "message": string,
  "data": object | null,
  "error": object | null
}
```

#### Field Definitions

- **`success`**: Boolean indicating if the request was successful
- **`statusCode`**: HTTP status code (200, 400, 401, 500, etc.)
- **`message`**: Human-readable message describing the operation result
- **`data`**: Response payload (present on successful requests)
- **`error`**: Error details (present on failed requests)

## Success Responses

### Structure
```json
{
  "success": true,
  "statusCode": 200,
  "message": "Operation completed successfully",
  "data": {
    // Actual response data
  },
  "error": null
}
```

### Authentication Success Example

#### Sign In Success
```json
{
  "success": true,
  "statusCode": 200,
  "message": "User signed in successfully",
  "data": {
    "user": {
      "id": "firebase_uid_123",
      "email": "user@example.com",
      "name": "John Doe",
      "phoneNumber": "+1234567890",
      "profilePicture": "https://example.com/avatar.jpg",
      "isEmailVerified": true,
      "createdAt": "2024-01-15T10:30:00Z",
      "updatedAt": "2024-01-20T14:45:00Z"
    },
    "tokens": {
      "idToken": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
      "refreshToken": "AOEOulbqd3v4IJHYFhUILKF8xHYoLkT...",
      "expiresIn": "3600"
    }
  },
  "error": null
}
```

#### Sign Up Success
```json
{
  "success": true,
  "statusCode": 201,
  "message": "User account created successfully",
  "data": {
    "user": {
      "id": "firebase_uid_456",
      "email": "newuser@example.com",
      "name": "Jane Smith",
      "phoneNumber": null,
      "profilePicture": null,
      "isEmailVerified": false,
      "createdAt": "2024-01-22T09:15:00Z",
      "updatedAt": null
    },
    "tokens": {
      "idToken": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
      "refreshToken": "AOEOulbqd3v4IJHYFhUILKF8xHYoLkT...",
      "expiresIn": "3600"
    }
  },
  "error": null
}
```

#### Get Current User Success
```json
{
  "success": true,
  "statusCode": 200,
  "message": "User data retrieved successfully",
  "data": {
    "id": "firebase_uid_123",
    "email": "user@example.com",
    "name": "John Doe",
    "phoneNumber": "+1234567890",
    "profilePicture": "https://example.com/avatar.jpg",
    "isEmailVerified": true,
    "createdAt": "2024-01-15T10:30:00Z",
    "updatedAt": "2024-01-20T14:45:00Z"
  },
  "error": null
}
```

#### Void Operation Success
```json
{
  "success": true,
  "statusCode": 200,
  "message": "User signed out successfully",
  "data": null,
  "error": null
}
```

## Error Responses

### Structure
```json
{
  "success": false,
  "statusCode": 4xx | 5xx,
  "message": "Error description",
  "data": null,
  "error": {
    "code": "ERROR_CODE_TYPE",
    "details": "Detailed error information"
  }
}
```

### Authentication Error Examples

#### Invalid Credentials (401)
```json
{
  "success": false,
  "statusCode": 401,
  "message": "Invalid email or password",
  "data": null,
  "error": {
    "code": "INVALID_CREDENTIALS",
    "details": "The provided email and password combination is incorrect"
  }
}
```

#### Account Already Exists (409)
```json
{
  "success": false,
  "statusCode": 409,
  "message": "User with this email already exists",
  "data": null,
  "error": {
    "code": "EMAIL_ALREADY_IN_USE",
    "details": "An account with the email address user@example.com already exists"
  }
}
```

#### Validation Error (400)
```json
{
  "success": false,
  "statusCode": 400,
  "message": "Invalid request data",
  "data": null,
  "error": {
    "code": "VALIDATION_ERROR",
    "details": "Email field is required and must be a valid email address"
  }
}
```

#### Server Error (500)
```json
{
  "success": false,
  "statusCode": 500,
  "message": "Internal server error",
  "data": null,
  "error": {
    "code": "INTERNAL_SERVER_ERROR",
    "details": "An unexpected error occurred while processing your request"
  }
}
```

#### Token Expired (401)
```json
{
  "success": false,
  "statusCode": 401,
  "message": "Authentication token has expired",
  "data": null,
  "error": {
    "code": "TOKEN_EXPIRED",
    "details": "The authentication token has expired and needs to be refreshed"
  }
}
```

## Implementation Details

### Response Parsing

The application uses typed response models to parse API responses:

```dart
// Generic response wrapper
@JsonSerializable(genericArgumentFactories: true)
class ApiResponse<T> {
  const ApiResponse({
    required this.success,
    required this.statusCode,
    required this.message,
    this.data,
    this.error,
  });

  final bool success;
  final int statusCode;
  final String message;
  final T? data;
  final ApiError? error;
}

// Error structure
@JsonSerializable()
class ApiError {
  const ApiError({
    required this.code,
    required this.details,
  });

  final String code;
  final String details;
}
```

### Authentication Response Models

```dart
// Complete authentication response
@JsonSerializable()
class AuthResponseModel {
  const AuthResponseModel({
    required this.user,
    required this.tokens,
  });

  final UserModel user;
  final AuthTokensModel tokens;
}

// Token information
@JsonSerializable()
class AuthTokensModel {
  const AuthTokensModel({
    required this.idToken,
    required this.refreshToken,
    required this.expiresIn,
  });

  final String idToken;
  final String refreshToken;
  final String expiresIn;
}
```

## Error Code Reference

### Authentication Error Codes

| Code | Status | Description |
|------|---------|-------------|
| `INVALID_CREDENTIALS` | 401 | Email/password combination is incorrect |
| `EMAIL_ALREADY_IN_USE` | 409 | Email address is already registered |
| `TOKEN_EXPIRED` | 401 | Authentication token has expired |
| `TOKEN_INVALID` | 401 | Authentication token is malformed or invalid |
| `USER_NOT_FOUND` | 404 | User account does not exist |
| `EMAIL_NOT_VERIFIED` | 403 | Email address has not been verified |
| `ACCOUNT_DISABLED` | 403 | User account has been disabled |
| `TOO_MANY_REQUESTS` | 429 | Rate limit exceeded |

### Validation Error Codes

| Code | Status | Description |
|------|---------|-------------|
| `VALIDATION_ERROR` | 400 | Request data fails validation |
| `MISSING_REQUIRED_FIELD` | 400 | Required field is missing |
| `INVALID_EMAIL_FORMAT` | 400 | Email format is invalid |
| `WEAK_PASSWORD` | 400 | Password does not meet requirements |
| `INVALID_PHONE_NUMBER` | 400 | Phone number format is invalid |

### Server Error Codes

| Code | Status | Description |
|------|---------|-------------|
| `INTERNAL_SERVER_ERROR` | 500 | Unexpected server error |
| `SERVICE_UNAVAILABLE` | 503 | Service is temporarily unavailable |
| `DATABASE_ERROR` | 500 | Database operation failed |
| `NETWORK_ERROR` | 503 | Network connectivity issue |

## Usage in Data Sources

### Remote Data Source Implementation

```dart
@override
Future<({UserModel user, String token, String? refreshToken})> signIn({
  required String email,
  required String password,
}) async {
  // API call returns standardized response
  final responseData = await _authApiService.signIn({
    'email': email,
    'password': password,
  });

  // Parse using our response model
  final authResponse = AuthResponseModel.fromJson(responseData);
  
  // Extract relevant data
  return (
    user: authResponse.user,
    token: authResponse.tokens.idToken,
    refreshToken: authResponse.tokens.refreshToken,
  );
}
```

### Error Handling

```dart
// ApiHandler automatically maps status codes to appropriate Failure types
try {
  final response = await performStandardApiCall<AuthResponseModel>(
    request: () => _dio.post('/auth/signin', data: requestData),
    parser: AuthResponseModel.fromJson,
  );
  return response.data!;
} on AuthFailure catch (e) {
  // Handle authentication-specific errors
  throw AuthFailure.fromApiError(e);
} on ValidationFailure catch (e) {
  // Handle validation errors
  throw ValidationFailure.fromApiError(e);
}
```

## Benefits

### 1. **Consistency**
- All endpoints follow the same response structure
- Predictable error handling across the app
- Standardized status codes and messages

### 2. **Type Safety**
- Generic response types ensure compile-time validation
- Structured error information prevents runtime crashes
- Clear data contracts between layers

### 3. **Maintainability**
- Single source of truth for response format
- Easy to modify response structure globally
- Clear documentation for API consumers

### 4. **Debugging**
- Structured error codes simplify issue identification
- Consistent error messages improve user experience
- Detailed error information aids in troubleshooting

This standardized format ensures reliable data exchange between the Flutter application and backend services while maintaining clean architecture principles.