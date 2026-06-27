import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:tulink_flutter/core/errors/failure.dart';
import 'package:tulink_flutter/features/journeys/data/datasources/journey_exceptions.dart';
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

  group('startJourney — translate data exceptions to domain failures', () {
    test('maps AlreadyInActiveJourneyException (BE-FIX-3) to a domain failure '
        'carrying activeJourneyId', () async {
      // The data source owns wire-envelope parsing and raises a typed data
      // exception; the repository only translates it into a domain Failure.
      when(remote.startJourney('j-new')).thenThrow(
        const AlreadyInActiveJourneyException(activeJourneyId: 'j-active-123'),
      );

      final result = await repo.startJourney('j-new');

      expect(result.failure, isA<AlreadyInActiveJourneyFailure>());
      expect(
        (result.failure as AlreadyInActiveJourneyFailure).activeJourneyId,
        'j-active-123',
      );
    });

    test('maps a generic DioException to a ServerFailure (not a conflict)',
        () async {
      final req = RequestOptions(path: '/journeys/j-new/start');
      when(remote.startJourney('j-new')).thenThrow(
        DioException(
          requestOptions: req,
          response: Response<dynamic>(
            requestOptions: req,
            statusCode: 500,
            data: {'message': 'Internal error'},
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      final result = await repo.startJourney('j-new');

      expect(result.failure, isA<ServerFailure>());
      expect(result.failure, isNot(isA<AlreadyInActiveJourneyFailure>()));
    });
  });
}
