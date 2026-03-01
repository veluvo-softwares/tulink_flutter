import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/core/errors/failure.dart';
import 'package:tulink_flutter/core/network/api_handler.dart';

void main() {
  group('ApiHandler Tests', () {
    test('should handle successful API response', () async {
      // Mock a successful response
      final mockResponse = Response<Map<String, dynamic>>(
        data: {'message': 'success', 'data': {'id': '1', 'name': 'Test'}},
        statusCode: 200,
        requestOptions: RequestOptions(path: '/test'),
      );

      // Test parsing with parser function
      final result = await ApiHandler.performApiCall<String>(
        () => Future.value(mockResponse),
        (data) => data['message'] as String,
      );

      expect(result, equals('success'));
    });

    test('should handle API response with multiple results', () async {
      // Mock a successful response with multiple fields
      final mockResponse = Response<Map<String, dynamic>>(
        data: {
          'user': {'id': '1', 'name': 'John'},
          'token': 'abc123',
        },
        statusCode: 200,
        requestOptions: RequestOptions(path: '/auth/signin'),
      );

      final result = await ApiHandler.performApiCallWithMultipleResults<
          ({String userId, String userName, String token})>(
        () => Future.value(mockResponse),
        (data) => (
          userId: data['user']['id'] as String,
          userName: data['user']['name'] as String,
          token: data['token'] as String,
        ),
      );

      expect(result.userId, equals('1'));
      expect(result.userName, equals('John'));
      expect(result.token, equals('abc123'));
    });

    test('should handle void API calls', () async {
      final mockResponse = Response<void>(
        data: null,
        statusCode: 204,
        requestOptions: RequestOptions(path: '/delete'),
      );

      // Should complete without throwing
      await expectLater(
        ApiHandler.performVoidApiCall(
          () => Future.value(mockResponse),
        ),
        completes,
      );
    });

    test('should throw ServerFailure for bad status codes', () async {
      final mockResponse = Response<Map<String, dynamic>>(
        data: {'error': 'Not found'},
        statusCode: 404,
        requestOptions: RequestOptions(path: '/test'),
      );

      await expectLater(
        ApiHandler.performApiCall(
          () => Future.value(mockResponse),
        ),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('should handle list responses', () async {
      final mockResponse = Response<List<dynamic>>(
        data: [
          {'id': '1', 'name': 'John'},
          {'id': '2', 'name': 'Jane'},
        ],
        statusCode: 200,
        requestOptions: RequestOptions(path: '/users'),
      );

      final result = await ApiHandler.performListApiCall<
          ({String id, String name})>(
        () => Future.value(mockResponse),
        (item) => (
          id: item['id'] as String,
          name: item['name'] as String,
        ),
      );

      expect(result.length, equals(2));
      expect(result[0].id, equals('1'));
      expect(result[0].name, equals('John'));
      expect(result[1].id, equals('2'));
      expect(result[1].name, equals('Jane'));
    });

    test('should handle paginated responses', () async {
      final mockResponse = Response<Map<String, dynamic>>(
        data: {
          'data': [
            {'id': '1', 'name': 'John'},
          ],
          'total': 10,
          'hasMore': true,
        },
        statusCode: 200,
        requestOptions: RequestOptions(path: '/users'),
      );

      final result = await ApiHandler.performPaginatedApiCall<
          ({String id, String name})>(
        () => Future.value(mockResponse),
        (item) => (
          id: item['id'] as String,
          name: item['name'] as String,
        ),
      );

      expect(result.data.length, equals(1));
      expect(result.total, equals(10));
      expect(result.hasMore, equals(true));
      expect(result.data[0].id, equals('1'));
    });
  });
}