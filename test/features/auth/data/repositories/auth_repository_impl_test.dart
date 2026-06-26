import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:tulink_flutter/core/network/dio_client.dart';
import 'package:tulink_flutter/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:tulink_flutter/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:tulink_flutter/features/auth/data/repositories/auth_repository_impl.dart';

@GenerateMocks([AuthRemoteDataSource, AuthLocalDataSource, DioClient])
import 'auth_repository_impl_test.mocks.dart';

void main() {
  late AuthRepositoryImpl repository;
  late MockAuthRemoteDataSource remote;
  late MockAuthLocalDataSource local;
  late MockDioClient dio;

  setUp(() {
    remote = MockAuthRemoteDataSource();
    local = MockAuthLocalDataSource();
    dio = MockDioClient();
    repository = AuthRepositoryImpl(
      remoteDataSource: remote,
      localDataSource: local,
      dioClient: dio,
    );
  });

  group('isSignedIn — iOS resume recovery', () {
    test('not signed in when no user is cached', () async {
      when(local.isUserCached()).thenAnswer((_) async => false);

      expect(await repository.isSignedIn(), isFalse);
      verifyNever(dio.getAuthToken());
    });

    test('signed in with a valid access token (no refresh needed)', () async {
      when(local.isUserCached()).thenAnswer((_) async => true);
      when(dio.getAuthToken()).thenAnswer((_) async => 'valid-id-token');

      expect(await repository.isSignedIn(), isTrue);
      verifyNever(dio.tryRefreshToken());
    });

    test(
        'recovers via refresh when the access token is expired but a refresh '
        'token exists (the core iOS-resume fix)', () async {
      when(local.isUserCached()).thenAnswer((_) async => true);
      // Expired/cleared ID token surfaces as null from getAuthToken().
      when(dio.getAuthToken()).thenAnswer((_) async => null);
      when(dio.hasRefreshToken()).thenAnswer((_) async => true);
      when(dio.tryRefreshToken()).thenAnswer((_) async => 'fresh-id-token');

      expect(await repository.isSignedIn(), isTrue);
      verify(dio.tryRefreshToken()).called(1);
    });

    test('signs out when the access token is expired and refresh fails',
        () async {
      when(local.isUserCached()).thenAnswer((_) async => true);
      when(dio.getAuthToken()).thenAnswer((_) async => null);
      when(dio.hasRefreshToken()).thenAnswer((_) async => true);
      // tryRefreshToken returns null on a genuine refresh failure (TokenManager
      // has already cleared tokens + fired onAuthLost).
      when(dio.tryRefreshToken()).thenAnswer((_) async => null);

      expect(await repository.isSignedIn(), isFalse);
    });

    test('signs out when there is no refresh token to recover from', () async {
      when(local.isUserCached()).thenAnswer((_) async => true);
      when(dio.getAuthToken()).thenAnswer((_) async => null);
      when(dio.hasRefreshToken()).thenAnswer((_) async => false);

      expect(await repository.isSignedIn(), isFalse);
      verifyNever(dio.tryRefreshToken());
    });
  });
}
