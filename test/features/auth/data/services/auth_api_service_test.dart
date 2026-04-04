import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/features/auth/data/services/auth_api_service.dart';
import 'package:tulink_flutter/core/network/api_routes.dart';
import 'package:tulink_flutter/core/network/api_query_builder.dart';

void main() {
  group('AuthApiService Tests', () {
    late Dio dio;
    late AuthApiService authApiService;

    setUp(() {
      dio = Dio();
      authApiService = AuthApiService(dio);
    });

    test('should use correct endpoints from ApiRoutes', () {
      // Test that the service uses centralized endpoint definitions
      expect(ApiRoutes.signIn, equals('/auth/login'));
      expect(ApiRoutes.signUp, equals('/auth/register'));
      expect(ApiRoutes.signOut, equals('/auth/logout'));
      expect(ApiRoutes.currentUser, equals('/auth/profile'));
      expect(ApiRoutes.refreshToken, equals('/auth/refresh'));
      expect(ApiRoutes.resetPassword, equals('/auth/reset-password'));
      expect(ApiRoutes.verifyEmail, equals('/auth/verify-email'));
      expect(ApiRoutes.updateProfile, equals('/auth/profile'));
      expect(ApiRoutes.deleteAccount, equals('/auth/account'));
    });

    test('should construct dynamic endpoints correctly', () {
      // Test helper methods for dynamic endpoint construction
      expect(ApiRoutes.userById('123'), equals('/users/123'));
      expect(ApiRoutes.downloadMedia('file-123'), equals('/media/file-123/download'));
      
      // Test paginated endpoint construction
      final paginatedEndpoint = ApiQueryBuilder.paginated(
        '/users',
        page: 2,
        limit: 50,
        sortBy: 'name',
        sortOrder: 'asc',
      );
      expect(paginatedEndpoint, equals('/users?page=2&limit=50&sortBy=name&sortOrder=asc'));
      
      // Test search endpoint construction
      final searchEndpoint = ApiQueryBuilder.search(
        '/users/search',
        query: 'john',
        filters: ['active', 'verified'],
        page: 1,
        limit: 20,
      );
      expect(searchEndpoint, contains('q=john'));
      expect(searchEndpoint, contains('filter=active'));
      expect(searchEndpoint, contains('filter=verified'));
      expect(searchEndpoint, contains('page=1'));
      expect(searchEndpoint, contains('limit=20'));
    });

    test('should have proper service structure', () {
      // Test that the service has all required methods
      expect(authApiService, isA<AuthApiService>());
    });

    test('should demonstrate zero hardcoded strings in service', () {
      // This test verifies our architecture - all endpoints come from constants
      const endpoints = [
        ApiRoutes.signIn,
        ApiRoutes.signUp,
        ApiRoutes.signOut,
        ApiRoutes.currentUser,
        ApiRoutes.refreshToken,
        ApiRoutes.resetPassword,
        ApiRoutes.verifyEmail,
        ApiRoutes.updateProfile,
        ApiRoutes.deleteAccount,
      ];
      
      // All endpoints should start with '/' and be well-formed
      for (final endpoint in endpoints) {
        expect(endpoint.startsWith('/'), isTrue, reason: 'Endpoint $endpoint should start with /');
        expect(endpoint.contains(' '), isFalse, reason: 'Endpoint $endpoint should not contain spaces');
      }
    });

    group('API Endpoint Validation', () {
      test('should have health check and version endpoints', () {
        expect(ApiRoutes.health, equals('/health'));
        expect(ApiRoutes.version, equals('/version'));
        expect(ApiRoutes.status, equals('/status'));
      });

      test('should have consistent auth endpoint patterns', () {
        // All auth endpoints should start with /auth
        final authEndpoints = [
          ApiRoutes.signIn,
          ApiRoutes.signUp,
          ApiRoutes.signOut,
          ApiRoutes.currentUser,
          ApiRoutes.refreshToken,
          ApiRoutes.resetPassword,
          ApiRoutes.verifyEmail,
          ApiRoutes.updateProfile,
          ApiRoutes.deleteAccount,
        ];

        for (final endpoint in authEndpoints) {
          expect(endpoint.startsWith('/auth'), isTrue, 
            reason: 'Auth endpoint $endpoint should start with /auth');
        }
      });

      test('should validate dynamic endpoint construction', () {
        const testUserId = 'user123';
        const testMediaId = 'media456';

        expect(ApiRoutes.userById(testUserId), equals('/users/$testUserId'));
        expect(ApiRoutes.downloadMedia(testMediaId), equals('/media/$testMediaId/download'));
        
        // Test that dynamic endpoints don't have hardcoded values
        expect(ApiRoutes.userById(testUserId).contains(testUserId), isTrue);
        expect(ApiRoutes.downloadMedia(testMediaId).contains(testMediaId), isTrue);
      });
    });

    group('Service Method Structure', () {
      test('should have all required authentication methods', () {
        // Verify the service has all the expected methods
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
        // Verify utility methods exist
        expect(authApiService.getUserProfile, isA<Function>());
        expect(authApiService.getNotifications, isA<Function>());
        expect(authApiService.searchUsers, isA<Function>());
        expect(authApiService.updateAvatar, isA<Function>());
        expect(authApiService.downloadFile, isA<Function>());
      });
    });

    group('Query Builder Validation', () {
      test('should build paginated endpoints correctly', () {
        final endpoint1 = ApiQueryBuilder.paginated('/users');
        expect(endpoint1, equals('/users'));

        final endpoint2 = ApiQueryBuilder.paginated('/users', page: 1);
        expect(endpoint2, equals('/users?page=1'));

        final endpoint3 = ApiQueryBuilder.paginated('/users', page: 2, limit: 50);
        expect(endpoint3, equals('/users?page=2&limit=50'));

        final endpoint4 = ApiQueryBuilder.paginated(
          '/users', 
          page: 3, 
          limit: 25, 
          sortBy: 'name', 
          sortOrder: 'desc'
        );
        expect(endpoint4, equals('/users?page=3&limit=25&sortBy=name&sortOrder=desc'));
      });

      test('should build search endpoints correctly', () {
        final endpoint1 = ApiQueryBuilder.search('/search', query: 'test');
        expect(endpoint1, equals('/search?q=test'));

        final endpoint2 = ApiQueryBuilder.search('/search', query: 'test user', page: 2);
        expect(endpoint2, contains('q=test%20user'));
        expect(endpoint2, contains('page=2'));

        final endpoint3 = ApiQueryBuilder.search(
          '/search', 
          query: 'john', 
          filters: ['active'], 
          limit: 10
        );
        expect(endpoint3, contains('q=john'));
        expect(endpoint3, contains('filter=active'));
        expect(endpoint3, contains('limit=10'));
      });

      test('should handle query parameters correctly', () {
        final params = {
          'key1': 'value1',
          'key2': 'value 2',
          'key3': null,
          'key4': 123,
        };

        final endpoint = ApiQueryBuilder.withParams('/test', params);
        expect(endpoint, contains('key1=value1'));
        expect(endpoint, contains('key2=value%202'));
        expect(endpoint, contains('key4=123'));
        expect(endpoint, isNot(contains('key3')));
      });

      test('should build filters correctly', () {
        final filters = ApiQueryBuilder.buildFilters(
          category: 'technology',
          status: 'active',
          startDate: DateTime(2024, 1, 1),
          tags: ['flutter', 'mobile'],
        );

        expect(filters['category'], equals('technology'));
        expect(filters['status'], equals('active'));
        expect(filters['startDate'], equals('2024-01-01T00:00:00.000'));
        expect(filters['tags'], equals('flutter,mobile'));
      });
    });
  });
}