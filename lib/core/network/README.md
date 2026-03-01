# ApiHandler Usage Guide

The `ApiHandler` is a centralized utility for handling all API calls with consistent error handling. It eliminates code duplication and provides a clean, type-safe way to interact with APIs.

## Basic Usage

### Simple API Call
```dart
// GET request with response parsing
final user = await ApiHandler.performApiCall<UserModel>(
  () => _dio.get('/users/123'),
  (data) => UserModel.fromJson(data),
);
```

### Multiple Results from Single Endpoint
```dart
// POST request returning multiple fields
final result = await ApiHandler.performApiCallWithMultipleResults<
    ({UserModel user, String token})>(
  () => _dio.post('/auth/signin', data: credentials),
  (data) => (
    user: UserModel.fromJson(data['user']),
    token: data['token'] as String,
  ),
);

final user = result.user;
final token = result.token;
```

### Void API Calls
```dart
// DELETE or other calls that don't return data
await ApiHandler.performVoidApiCall(
  () => _dio.delete('/users/123'),
);
```

### List Responses
```dart
// GET request returning a list
final users = await ApiHandler.performListApiCall<UserModel>(
  () => _dio.get('/users'),
  (item) => UserModel.fromJson(item),
);
```

### Paginated Responses
```dart
// GET request with pagination info
final result = await ApiHandler.performPaginatedApiCall<UserModel>(
  () => _dio.get('/users?page=1&limit=20'),
  (item) => UserModel.fromJson(item),
);

print('Users: ${result.data}');
print('Total: ${result.total}');
print('Has more: ${result.hasMore}');
```

## Error Handling

All methods automatically handle these error types:

- **Connection Timeout** → `NetworkFailure.timeout`
- **No Internet** → `NetworkFailure.noInternet` 
- **Server Errors** → `ServerFailure.fromStatusCode(statusCode)`
- **Unknown Errors** → `NetworkFailure.unknown`

## Example Remote Data Source

```dart
class UserRemoteDataSourceImpl implements UserRemoteDataSource {
  UserRemoteDataSourceImpl(this._dioClient);
  
  final DioClient _dioClient;

  @override
  Future<UserModel> getUser(String id) async {
    return ApiHandler.performApiCall<UserModel>(
      () => _dioClient.dio.get('/users/$id'),
      (data) => UserModel.fromJson(data['user']),
    );
  }

  @override
  Future<List<UserModel>> getUsers() async {
    return ApiHandler.performListApiCall<UserModel>(
      () => _dioClient.dio.get('/users'),
      (item) => UserModel.fromJson(item),
    );
  }

  @override
  Future<UserModel> createUser(CreateUserRequest request) async {
    return ApiHandler.performApiCall<UserModel>(
      () => _dioClient.dio.post('/users', data: request.toJson()),
      (data) => UserModel.fromJson(data['user']),
    );
  }

  @override
  Future<void> deleteUser(String id) async {
    await ApiHandler.performVoidApiCall(
      () => _dioClient.dio.delete('/users/$id'),
    );
  }
}
```

## Benefits

1. **DRY Principle**: No repeated error handling code
2. **Type Safety**: Generic methods ensure type correctness
3. **Consistency**: All API calls behave the same way
4. **Maintainability**: Error handling logic in one place
5. **Testability**: Easy to mock and test individual API calls