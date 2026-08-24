import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/core/network/api_routes.dart';
import 'package:tulink_flutter/core/network/dio_client.dart';

/// A 401 from a session-*establishing* endpoint is the server's verdict on the
/// credentials, not an expired session.
///
/// The shipped interceptor refreshed on any 401, including `POST /auth/login`.
/// Signing in with a wrong password therefore went: 401 → refresh a session that
/// does not exist → replay the login with a bogus `Authorization` header →
/// second 401 → clear tokens and fire `onAuthLost`. The server's real message
/// ("Login failed. Please check your credentials") never reached the user, and
/// when the refresh threw anything that was not a `TokenFailure` the callback
/// escaped without calling `handler`, so Dio never completed the request and the
/// Sign in button span forever.
void main() {
  group('session-establishing routes are exempt from refresh-on-401', () {
    test('every credential endpoint is exempt', () {
      for (final route in [
        ApiRoutes.signIn,
        ApiRoutes.signUp,
        ApiRoutes.socialSignIn,
        ApiRoutes.refreshToken,
        ApiRoutes.forgotPassword,
        ApiRoutes.resetPassword,
      ]) {
        expect(
          DioClient.debugIsSessionEstablishingRoute(route),
          isTrue,
          reason: '$route must not trigger a token refresh on 401',
        );
      }
    });

    test('refresh is exempt, or a failed refresh would trigger a refresh', () {
      expect(
        DioClient.debugIsSessionEstablishingRoute(ApiRoutes.refreshToken),
        isTrue,
      );
    });

    test('a path prefix from a configured base URL still matches', () {
      expect(
        DioClient.debugIsSessionEstablishingRoute('/api/v1${ApiRoutes.signIn}'),
        isTrue,
      );
      expect(
        DioClient.debugIsSessionEstablishingRoute(
          'http://127.0.0.1:3000${ApiRoutes.signIn}',
        ),
        isTrue,
      );
    });

    test('session-consuming routes are NOT exempt', () {
      // These carry a session, so a 401 really can mean "expired" and the
      // refresh-then-retry recovery must still run for them.
      for (final route in [
        ApiRoutes.currentUser,
        ApiRoutes.signOut,
        '/journeys',
        '/journeys/abc/invite',
        '/locations/journeys/abc/poll',
      ]) {
        expect(
          DioClient.debugIsSessionEstablishingRoute(route),
          isFalse,
          reason: '$route must keep its refresh-then-retry recovery',
        );
      }
    });

    test('a lookalike path is not exempted by accident', () {
      expect(
        DioClient.debugIsSessionEstablishingRoute('/auth/login-history'),
        isFalse,
      );
    });
  });

  group('the sign-in 401 reaches the caller intact', () {
    late Dio dio;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
      dio.interceptors.add(DioClient().debugAuthInterceptorForTest());
      dio.httpClientAdapter = _Rejecting401Adapter();
    });

    test('a wrong password fails fast with the server body', () async {
      // The regression: this used to hang forever, or surface a token error.
      final call = dio.post<Map<String, dynamic>>(
        ApiRoutes.signIn,
        data: {'email': 'someone@example.com', 'password': 'wrong'},
      );

      await expectLater(
        call.timeout(const Duration(seconds: 2)),
        throwsA(
          isA<DioException>()
              .having((e) => e.response?.statusCode, 'status', 401)
              .having(
                (e) => (e.response?.data as Map?)?['message'],
                'server message',
                'Login failed. Please check your credentials and try again',
              ),
        ),
      );
    });

    test('the login is attempted exactly once — no replay', () async {
      final adapter = _Rejecting401Adapter();
      dio.httpClientAdapter = adapter;

      await dio
          .post<Map<String, dynamic>>(ApiRoutes.signIn, data: {})
          .catchError(
            (Object _) => Response<Map<String, dynamic>>(
              requestOptions: RequestOptions(path: ApiRoutes.signIn),
            ),
          );

      expect(
        adapter.calls,
        1,
        reason: 'replaying the login with a bogus bearer token is the bug',
      );
    });
  });
}

/// Answers every request with the backend's real 401 login body.
class _Rejecting401Adapter implements HttpClientAdapter {
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    return ResponseBody.fromString(
      '{"success":false,"statusCode":401,'
      '"message":"Login failed. Please check your credentials and try again"}',
      401,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
