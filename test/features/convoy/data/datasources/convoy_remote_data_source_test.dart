import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
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
        response: Response<void>(
          requestOptions: RequestOptions(path: '/journeys/$journeyId/live'),
          statusCode: 404,
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
