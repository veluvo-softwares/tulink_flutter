import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:tulink_flutter/core/errors/failure.dart';
import 'package:tulink_flutter/features/journeys/data/datasources/journey_remote_data_source.dart';
import 'package:tulink_flutter/features/journeys/data/repositories/journey_repository_impl.dart';

@GenerateMocks([JourneyRemoteDataSource])
import 'journey_repository_impl_test.mocks.dart';

void main() {
  late JourneyRepositoryImpl repo;
  late MockJourneyRemoteDataSource remote;

  setUp(() {
    remote = MockJourneyRemoteDataSource();
    repo = JourneyRepositoryImpl(remoteDataSource: remote);
  });

  DioException dioWith(int status, Object body) {
    final req = RequestOptions(path: '/journeys/j-new/start');
    return DioException(
      requestOptions: req,
      response: Response<dynamic>(
        requestOptions: req,
        statusCode: status,
        data: body,
      ),
      type: DioExceptionType.badResponse,
    );
  }

  group('startJourney — backend single-active enforcement (BE-FIX-3)', () {
    test('maps a 409 ALREADY_IN_ACTIVE_JOURNEY to a typed failure that carries '
        'activeJourneyId', () async {
      when(remote.startJourney('j-new')).thenThrow(
        dioWith(409, {
          'message': 'You already have an active journey',
          'error': {
            'code': 'ALREADY_IN_ACTIVE_JOURNEY',
            'activeJourneyId': 'j-active-123',
          },
        }),
      );

      final result = await repo.startJourney('j-new');

      expect(result.failure, isA<AlreadyInActiveJourneyFailure>());
      expect(
        (result.failure as AlreadyInActiveJourneyFailure).activeJourneyId,
        'j-active-123',
      );
    });

    test('a 409 without the typed error envelope stays a generic ServerFailure',
        () async {
      when(remote.startJourney('j-new')).thenThrow(
        dioWith(409, {'message': 'Conflict. Resource already exists.'}),
      );

      final result = await repo.startJourney('j-new');

      expect(result.failure, isA<ServerFailure>());
      expect(result.failure, isNot(isA<AlreadyInActiveJourneyFailure>()));
    });

    test('an unrelated upstream error is not misread as an active-journey '
        'conflict', () async {
      when(remote.startJourney('j-new')).thenThrow(
        dioWith(502, {
          'message': 'Bad gateway',
          'error': {'code': 'UPSTREAM_PLACES_ERROR'},
        }),
      );

      final result = await repo.startJourney('j-new');

      expect(result.failure, isNot(isA<AlreadyInActiveJourneyFailure>()));
    });
  });
}
