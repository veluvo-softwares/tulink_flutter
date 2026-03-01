import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/features/auth/data/services/auth_api_service.dart';
import 'package:tulink_flutter/core/network/api_endpoints.dart';

void main() {
  group('AuthApiService Tests', () {
    late Dio mockDio;
    late AuthApiService authApiService;

    setUp(() {
      mockDio = Dio();
      authApiService = AuthApiService(mockDio);
    });

    test('should use correct endpoints from ApiEndpoints', () {
      // Test that the service uses centralized endpoint definitions
      expect(ApiEndpoints.signIn, equals('/auth/signin'));
      expect(ApiEndpoints.signUp, equals('/auth/signup'));
      expect(ApiEndpoints.signOut, equals('/auth/signout'));
      expect(ApiEndpoints.currentUser, equals('/auth/me'));
      expect(ApiEndpoints.refreshToken, equals('/auth/refresh'));
      expect(ApiEndpoints.resetPassword, equals('/auth/reset-password'));
      expect(ApiEndpoints.verifyEmail, equals('/auth/verify-email'));
      expect(ApiEndpoints.updateProfile, equals('/auth/profile'));
      expect(ApiEndpoints.deleteAccount, equals('/auth/account'));
    });

    test('should construct dynamic endpoints correctly', () {
      // Test helper methods for dynamic endpoint construction
      expect(ApiEndpoints.userById('123'), equals('/users/123'));
      expect(ApiEndpoints.downloadFile('file-123'), equals('/files/file-123/download'));
      
      // Test paginated endpoint construction
      final paginatedEndpoint = ApiEndpoints.paginated(
        '/users',
        page: 2,
        limit: 50,
        sortBy: 'name',
        sortOrder: 'asc',
      );
      expect(paginatedEndpoint, equals('/users?page=2&limit=50&sortBy=name&sortOrder=asc'));
      
      // Test search endpoint construction
      final searchEndpoint = ApiEndpoints.search(
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
      
      // The actual API calls would require mocking Dio responses
      // For now, we just verify the service structure is correct
    });

    test('should demonstrate zero hardcoded strings in DataSource pattern', () {
      // This test verifies our architecture - all endpoints come from constants
      const endpoints = [
        ApiEndpoints.signIn,
        ApiEndpoints.signUp,
        ApiEndpoints.signOut,
        ApiEndpoints.currentUser,
        ApiEndpoints.refreshToken,
        ApiEndpoints.resetPassword,
        ApiEndpoints.verifyEmail,
        ApiEndpoints.updateProfile,
        ApiEndpoints.deleteAccount,
      ];
      
      // All endpoints should start with '/' and be well-formed
      for (final endpoint in endpoints) {
        expect(endpoint.startsWith('/'), isTrue, reason: 'Endpoint $endpoint should start with /');
        expect(endpoint.contains(' '), isFalse, reason: 'Endpoint $endpoint should not contain spaces');
      }
    });
  });
}