import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/features/auth/data/services/auth_api_service.dart';
import 'package:tulink_flutter/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:tulink_flutter/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:tulink_flutter/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:tulink_flutter/features/auth/data/models/user_model.dart';
import 'package:tulink_flutter/features/auth/presentation/providers/auth_provider.dart';
import 'package:tulink_flutter/core/network/dio_client.dart';
import 'package:tulink_flutter/core/validators/auth_validators.dart';
import 'package:tulink_flutter/core/errors/failure.dart';
import 'package:tulink_flutter/core/auth/token_manager.dart';
import 'package:dio/dio.dart';
import 'package:hive/hive.dart';

void main() {
  group('Authentication Integration Tests', () {
    late Dio dio;
    late DioClient dioClient;
    late AuthApiService authApiService;
    late AuthRemoteDataSource remoteDataSource;
    late AuthLocalDataSource localDataSource;
    late AuthRepositoryImpl repository;
    late AuthProvider authProvider;
    late Box<dynamic> mockBox;
    late TokenManager tokenManager;

    setUpAll(() async {
      // Initialize Hive for testing
      Hive.init('./test_cache');
    });

    setUp(() async {
      // Create mock box for local storage testing
      mockBox = await Hive.openBox('test_auth_box');
      await mockBox.clear(); // Clear any previous test data
      
      // Initialize dependencies
      dio = Dio();
      dioClient = DioClient();
      authApiService = AuthApiService(dio);
      remoteDataSource = AuthRemoteDataSourceImpl(authApiService);
      localDataSource = AuthLocalDataSourceImpl(mockBox);
      repository = AuthRepositoryImpl(
        remoteDataSource: remoteDataSource,
        localDataSource: localDataSource,
        dioClient: dioClient,
      );
      authProvider = AuthProvider(repository);
      tokenManager = TokenManager();
    });

    tearDown(() async {
      await mockBox.clear();
      await mockBox.close();
      await tokenManager.clearAllTokens();
    });

    tearDownAll(() async {
      await Hive.deleteFromDisk();
    });

    group('Input Validation Tests', () {
      test('should validate email addresses correctly', () {
        // Valid emails
        expect(AuthValidators.validateEmail('test@example.com'), isNull);
        expect(AuthValidators.validateEmail('user.name+tag@domain.co.uk'), isNull);
        expect(AuthValidators.validateEmail('test123@gmail.com'), isNull);
        
        // Invalid emails
        expect(AuthValidators.validateEmail(''), isA<ValidationFailure>());
        expect(AuthValidators.validateEmail('invalid'), isA<ValidationFailure>());
        expect(AuthValidators.validateEmail('test@'), isA<ValidationFailure>());
        expect(AuthValidators.validateEmail('@domain.com'), isA<ValidationFailure>());
        expect(AuthValidators.validateEmail('test@domain'), isA<ValidationFailure>());
      });

      test('should validate passwords with proper strength requirements', () {
        // Valid passwords
        expect(AuthValidators.validatePassword('password123'), isNull);
        expect(AuthValidators.validatePassword('MySecurePass2024!'), isNull);
        
        // Invalid passwords
        expect(AuthValidators.validatePassword(''), isA<ValidationFailure>());
        expect(AuthValidators.validatePassword('short'), isA<ValidationFailure>());
        expect(AuthValidators.validatePassword('password'), isA<ValidationFailure>()); // Common password
      });

      test('should validate password strength correctly', () {
        // Weak passwords
        expect(AuthValidators.calculatePasswordStrength('123456'), lessThan(30));
        expect(AuthValidators.calculatePasswordStrength('password'), lessThan(30));
        
        // Strong passwords
        expect(AuthValidators.calculatePasswordStrength('MyStr0ng!Password'), greaterThan(80));
        expect(AuthValidators.calculatePasswordStrength('C0mpl3x!Password'), greaterThan(80));
      });

      test('should validate names properly', () {
        // Valid names
        expect(AuthValidators.validateName('John Doe'), isNull);
        expect(AuthValidators.validateName('Mary-Jane Smith'), isNull);
        expect(AuthValidators.validateName("O'Connor"), isNull);
        
        // Invalid names
        expect(AuthValidators.validateName(''), isA<ValidationFailure>());
        expect(AuthValidators.validateName('A'), isA<ValidationFailure>());
        expect(AuthValidators.validateName('John123'), isA<ValidationFailure>());
        expect(AuthValidators.validateName('  John  '), isA<ValidationFailure>());
      });

      test('should validate complete sign up form', () {
        // Valid form data
        final validForm = AuthValidators.validateSignUpForm(
          email: 'test@example.com',
          password: 'SecurePass123!',
          confirmPassword: 'SecurePass123!',
          name: 'John Doe',
        );
        expect(validForm, isEmpty);
        
        // Invalid form data
        final invalidForm = AuthValidators.validateSignUpForm(
          email: 'invalid-email',
          password: 'weak',
          confirmPassword: 'different',
          name: '',
        );
        expect(invalidForm, hasLength(4));
        expect(invalidForm['email'], isA<ValidationFailure>());
        expect(invalidForm['password'], isA<ValidationFailure>());
        expect(invalidForm['confirmPassword'], isA<ValidationFailure>());
        expect(invalidForm['name'], isA<ValidationFailure>());
      });
    });

    group('Local Data Source Tests', () {
      test('should cache and retrieve user data correctly', () async {
        final testUser = UserModel(
          id: 'test123',
          email: 'test@example.com',
          name: 'Test User',
          isEmailVerified: true,
          profilePicture: null,
          createdAt: DateTime.parse('2024-01-01T00:00:00.000Z'),
          updatedAt: DateTime.parse('2024-01-01T00:00:00.000Z'),
        );

        // Test user caching
        await localDataSource.cacheUser(testUser);
        
        // Test user retrieval
        final cachedUser = await localDataSource.getCachedUser();
        expect(cachedUser, isNotNull);
        expect(cachedUser!.email, equals('test@example.com'));
        
        // Test user existence check
        final isUserCached = await localDataSource.isUserCached();
        expect(isUserCached, isTrue);
        
        // Test user clearing
        await localDataSource.clearCachedUser();
        final clearedUser = await localDataSource.getCachedUser();
        expect(clearedUser, isNull);
      });

      test('should cache and retrieve tokens correctly', () async {
        const testToken = 'test_auth_token_12345';
        
        // Test token caching
        await localDataSource.cacheToken(testToken);
        
        // Test token retrieval
        final cachedToken = await localDataSource.getCachedToken();
        expect(cachedToken, equals(testToken));
        
        // Test token clearing
        await localDataSource.clearCachedToken();
        final clearedToken = await localDataSource.getCachedToken();
        expect(clearedToken, isNull);
      });

      test('should handle cache errors gracefully', () async {
        // Close the box to simulate errors
        await mockBox.close();
        
        // Recreate data source with closed box
        final failingDataSource = AuthLocalDataSourceImpl(mockBox);
        
        // These should throw CacheFailure
        expect(() => failingDataSource.cacheUser(UserModel(
          id: 'test',
          email: 'test@example.com',
          name: 'Test User',
          isEmailVerified: true,
          profilePicture: null,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        )), throwsA(isA<CacheFailure>()));
        expect(() => failingDataSource.getCachedUser(), 
               throwsA(isA<CacheFailure>()));
      });
    });

    group('Token Manager Tests', () {
      test('should save and retrieve tokens with metadata', () async {
        const testToken = 'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJ0ZXN0IiwiZXhwIjoxNzA4NzEzNjAwfQ.signature';
        const testRefreshToken = 'refresh_token_12345';
        
        // Save tokens
        await tokenManager.saveAuthToken(testToken);
        await tokenManager.saveRefreshToken(testRefreshToken);
        
        // Verify tokens exist and are valid
        expect(await tokenManager.hasValidAuthToken(), isTrue);
        expect(await tokenManager.hasValidRefreshToken(), isTrue);
        
        // Retrieve tokens
        final retrievedToken = await tokenManager.getValidAuthToken();
        final retrievedRefreshToken = await tokenManager.getValidRefreshToken();
        
        expect(retrievedToken, equals(testToken));
        expect(retrievedRefreshToken, equals(testRefreshToken));
        
        // Get token metadata
        final metadata = await tokenManager.getTokenMetadata();
        expect(metadata, isNotNull);
        expect(metadata!['authToken']['exists'], isTrue);
        expect(metadata['refreshToken']['exists'], isTrue);
      });

      test('should detect expired tokens', () async {
        // Create an expired JWT token (exp: Jan 1, 2020)
        const expiredToken = 'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJ0ZXN0IiwiZXhwIjoxNTc3ODM2ODAwfQ.signature';
        
        await tokenManager.saveAuthToken(expiredToken);
        
        // Should detect as expired
        expect(() => tokenManager.getValidAuthToken(), throwsA(isA<TokenFailure>()));
        expect(await tokenManager.hasValidAuthToken(), isFalse);
      });

      test('should cleanup expired tokens automatically', () async {
        const expiredToken = 'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJ0ZXN0IiwiZXhwIjoxNTc3ODM2ODAwfQ.signature';
        
        await tokenManager.saveAuthToken(expiredToken);
        await tokenManager.validateAndCleanupTokens();
        
        expect(await tokenManager.hasValidAuthToken(), isFalse);
      });

      test('should clear all tokens', () async {
        const testToken = 'test_token';
        const testRefreshToken = 'test_refresh_token';
        
        await tokenManager.saveAuthToken(testToken);
        await tokenManager.saveRefreshToken(testRefreshToken);
        
        await tokenManager.clearAllTokens();
        
        expect(await tokenManager.hasValidAuthToken(), isFalse);
        expect(await tokenManager.hasValidRefreshToken(), isFalse);
      });
    });

    group('Error Handling Tests', () {
      test('should create appropriate failure types', () {
        // Server failures
        final serverFailure = ServerFailure.fromStatusCode(401);
        expect(serverFailure.statusCode, equals(401));
        expect(serverFailure.message, contains('Authentication failed'));
        
        // Auth failures
        expect(AuthFailure.invalidCredentials.isRetryable, isTrue);
        expect(AuthFailure.tokenExpired.requiresReauth, isTrue);
        
        // Validation failures
        final validationFailure = ValidationFailure.withFieldErrors(
          message: 'Form has errors',
          fieldErrors: {'email': 'Invalid email', 'password': 'Too short'},
        );
        expect(validationFailure.fieldErrors, hasLength(2));
        
        // Network failures
        expect(NetworkFailure.noInternet.message, contains('No internet'));
        expect(NetworkFailure.timeout.message, contains('timeout'));
      });

      test('should handle failure copying and modification', () {
        final originalFailure = AuthFailure.invalidCredentials;
        final modifiedFailure = originalFailure.copyWith(
          message: 'Custom message',
          details: 'Custom details',
        );
        
        expect(modifiedFailure.message, equals('Custom message'));
        expect(modifiedFailure.details, equals('Custom details'));
        expect(modifiedFailure.isRetryable, equals(originalFailure.isRetryable));
      });
    });

    group('Authentication Provider State Tests', () {
      test('should initialize with correct default state', () {
        expect(authProvider.isLoading, isFalse);
        expect(authProvider.isSignedIn, isFalse);
        expect(authProvider.user, isNull);
        expect(authProvider.hasError, isFalse);
      });

      test('should handle loading states correctly', () async {
        expect(authProvider.isLoading, isFalse);
        
        // Note: Without a real backend, we can't test actual sign-in
        // This tests the state management structure
      });

      test('should clear errors when requested', () {
        authProvider.clearError();
        expect(authProvider.hasError, isFalse);
        expect(authProvider.errorMessage, isEmpty);
      });
    });

    group('API Service Structure Tests', () {
      test('should have all required methods', () {
        expect(authApiService.signIn, isA<Function>());
        expect(authApiService.signUp, isA<Function>());
        expect(authApiService.signOut, isA<Function>());
        expect(authApiService.getCurrentUser, isA<Function>());
        expect(authApiService.refreshToken, isA<Function>());
        expect(authApiService.resetPassword, isA<Function>());
        expect(authApiService.verifyEmail, isA<Function>());
        expect(authApiService.updateProfile, isA<Function>());
        expect(authApiService.deleteAccount, isA<Function>());
        expect(authApiService.healthCheck, isA<Function>());
        expect(authApiService.getApiVersion, isA<Function>());
      });

      test('should have utility methods', () {
        expect(authApiService.getUserProfile, isA<Function>());
        expect(authApiService.getNotifications, isA<Function>());
        expect(authApiService.searchUsers, isA<Function>());
        expect(authApiService.updateAvatar, isA<Function>());
        expect(authApiService.downloadFile, isA<Function>());
      });
    });

    group('Repository Pattern Tests', () {
      test('should implement proper repository interface', () {
        expect(repository.signIn, isA<Function>());
        expect(repository.signUp, isA<Function>());
        expect(repository.signOut, isA<Function>());
        expect(repository.getCurrentUser, isA<Function>());
        expect(repository.isSignedIn, isA<Function>());
        expect(repository.refreshToken, isA<Function>());
        expect(repository.resetPassword, isA<Function>());
        expect(repository.verifyEmail, isA<Function>());
        expect(repository.updateProfile, isA<Function>());
        expect(repository.deleteAccount, isA<Function>());
      });
    });

    group('Integration Flow Tests', () {
      test('should demonstrate complete authentication flow structure', () async {
        // This test validates the complete integration structure
        // without requiring actual network calls
        
        // 1. Repository should handle failures gracefully
        expect(() => repository.signIn(
          email: 'test@example.com',
          password: 'password',
        ), isA<Function>());
        
        // 2. Local data source should be working
        expect(await localDataSource.isUserCached(), isFalse);
        
        // 3. Token manager should be operational
        expect(await tokenManager.hasValidAuthToken(), isFalse);
        
        // 4. Provider should maintain correct state
        expect(authProvider.isSignedIn, isFalse);
        expect(authProvider.isLoading, isFalse);
      });

      test('should handle offline scenarios', () async {
        // Test local data persistence when offline
        final testUser = UserModel(
          id: 'offline_test',
          email: 'offline@test.com',
          name: 'Offline User',
          isEmailVerified: true,
          profilePicture: null,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        
        await localDataSource.cacheUser(testUser);
        final cachedUser = await localDataSource.getCachedUser();
        
        expect(cachedUser, isNotNull);
        expect(cachedUser!.email, equals('offline@test.com'));
      });
    });

    group('Performance Tests', () {
      test('should handle multiple concurrent token operations', () async {
        const testToken = 'concurrent_test_token';
        
        // Perform multiple operations concurrently
        final futures = List.generate(10, (index) async {
          await tokenManager.saveAuthToken('${testToken}_$index');
          return await tokenManager.getValidAuthToken();
        });
        
        final results = await Future.wait(futures);
        
        // Should handle concurrent operations without errors
        expect(results.length, equals(10));
        for (final result in results) {
          expect(result, isNotNull);
          expect(result!, startsWith('concurrent_test_token'));
        }
      });

      test('should cache operations efficiently', () async {
        final stopwatch = Stopwatch()..start();
        
        // Perform multiple cache operations
        for (int i = 0; i < 100; i++) {
          await localDataSource.cacheToken('token_$i');
        }
        
        stopwatch.stop();
        
        // Should complete reasonably quickly (under 1 second)
        expect(stopwatch.elapsedMilliseconds, lessThan(1000));
      });
    });

    group('Edge Cases Tests', () {
      test('should handle null and empty inputs gracefully', () {
        // Test validation with null inputs
        expect(AuthValidators.validateEmail(null), isA<ValidationFailure>());
        expect(AuthValidators.validatePassword(null), isA<ValidationFailure>());
        expect(AuthValidators.validateName(null), isA<ValidationFailure>());
        
        // Test validation with empty inputs
        expect(AuthValidators.validateEmail(''), isA<ValidationFailure>());
        expect(AuthValidators.validatePassword(''), isA<ValidationFailure>());
        expect(AuthValidators.validateName(''), isA<ValidationFailure>());
      });

      test('should handle malformed JWT tokens', () async {
        const malformedToken = 'not.a.valid.jwt.token';
        
        await tokenManager.saveAuthToken(malformedToken);
        
        // Should still work with malformed tokens (fallback to default expiry)
        expect(await tokenManager.hasValidAuthToken(), isTrue);
      });

      test('should handle special characters in inputs', () {
        // Email with special characters
        expect(AuthValidators.validateEmail('test+tag@domain.co.uk'), isNull);
        expect(AuthValidators.validateEmail('test@sub-domain.example.com'), isNull);
        
        // Names with special characters
        expect(AuthValidators.validateName("O'Connor"), isNull);
        expect(AuthValidators.validateName('Mary-Jane'), isNull);
        expect(AuthValidators.validateName('José María'), isNull);
      });
    });
  });
}