import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/core/errors/failure.dart';
import 'package:tulink_flutter/features/convoy/data/datasources/convoy_remote_data_source.dart';
import 'package:tulink_flutter/features/convoy/data/services/convoy_api_service.dart';

void main() {
  const journeyId = 'journey-1';

  test(
    'resume recovery prefers the authoritative live journey snapshot',
    () async {
      final api = _FakeConvoyApiService(
        live: {
          'journey': {
            'destination': {'latitude': -1.25, 'longitude': 36.8},
            'destinationAddress': 'Nairobi',
          },
          'members': [
            {
              'userId': 'leader-1',
              'location': {
                'location': {'latitude': -1.2, 'longitude': 36.7},
                'timestamp': 1720000000000,
                'sequenceNumber': 12,
              },
            },
            {'userId': 'waiting-1', 'location': null},
          ],
        },
      );
      final source = ConvoyRemoteDataSourceImpl(api);

      final snapshot = await source.fetchLatestSnapshot(journeyId);

      expect(api.liveCalls, 1);
      expect(api.legacyCalls, 0);
      expect(snapshot.members.keys, ['leader-1']);
      expect(snapshot.members['leader-1']!.latitude, -1.2);
      expect(snapshot.destination.latitude, -1.25);
      expect(snapshot.destinationAddress, 'Nairobi');
    },
  );

  test('older servers fall back to the locations snapshot endpoint', () async {
    final api = _FakeConvoyApiService(
      liveError: DioException(
        requestOptions: RequestOptions(path: '/journeys/$journeyId/live'),
        response: Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: '/journeys/$journeyId/live'),
          statusCode: 404,
          data: {
            'statusCode': 404,
            'message': 'Cannot GET /journeys/$journeyId/live',
            'error': 'Not Found',
          },
        ),
        type: DioExceptionType.badResponse,
      ),
      legacy: {
        'participants': {
          'follower-1': {
            'userId': 'follower-1',
            'location': {'latitude': -1.3, 'longitude': 36.9},
            'timestamp': 1720000001000,
          },
        },
        'destination': {'latitude': -1.25, 'longitude': 36.8},
        'destinationAddress': 'Nairobi',
      },
    );
    final source = ConvoyRemoteDataSourceImpl(api);

    final snapshot = await source.fetchLatestSnapshot(journeyId);

    expect(api.liveCalls, 1);
    expect(api.legacyCalls, 1);
    expect(snapshot.members.keys, ['follower-1']);
  });

  test('a missing journey does not fall back to legacy locations', () async {
    final request = RequestOptions(path: '/journeys/$journeyId/live');
    final api = _FakeConvoyApiService(
      liveError: DioException(
        requestOptions: request,
        response: Response<Map<String, dynamic>>(
          requestOptions: request,
          statusCode: 404,
          data: {
            'statusCode': 404,
            'message': 'Journey not found',
            'error': 'Not Found',
          },
        ),
        type: DioExceptionType.badResponse,
      ),
    );
    final source = ConvoyRemoteDataSourceImpl(api);

    await expectLater(
      source.fetchLatestSnapshot(journeyId),
      throwsA(same(ConvoyFailure.journeyNotActive)),
    );
    expect(api.legacyCalls, 0);
  });
}

class _FakeConvoyApiService extends ConvoyApiService {
  _FakeConvoyApiService({
    this.live = const {},
    this.legacy = const {},
    this.liveError,
  }) : super(Dio());

  final Map<String, dynamic> live;
  final Map<String, dynamic> legacy;
  final Object? liveError;
  int liveCalls = 0;
  int legacyCalls = 0;

  @override
  Future<Map<String, dynamic>> fetchLiveJourneySnapshot(
    String journeyId,
  ) async {
    liveCalls += 1;
    final error = liveError;
    if (error != null) throw error;
    return live;
  }

  @override
  Future<Map<String, dynamic>> fetchLatestPositions(String journeyId) async {
    legacyCalls += 1;
    return legacy;
  }
}
