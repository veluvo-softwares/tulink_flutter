import 'package:dio/dio.dart';
import 'package:tulink_flutter/features/convoy/domain/entities/member_position.dart';

import '../models/location_update_dto.dart';
import '../models/member_position_model.dart';
import '../services/convoy_api_service.dart';
import '../../domain/entities/convoy_snapshot.dart';
import '../../../../core/errors/failure.dart';

/// Abstract interface for convoy remote data operations
abstract class ConvoyRemoteDataSource {
  /// Publish location update via REST API
  Future<bool> publishLocation(LocationUpdateDto locationUpdate);
  Future<Map<String, dynamic>> backfillLocations({
    required String journeyId,
    required String batchId,
    required List<Map<String, dynamic>> points,
  });

  /// Fetch latest convoy snapshot via REST API
  Future<ConvoySnapshot> fetchLatestSnapshot(String journeyId);
}

/// Implementation of convoy remote data source using REST API
class ConvoyRemoteDataSourceImpl implements ConvoyRemoteDataSource {
  ConvoyRemoteDataSourceImpl(this._apiService);

  final ConvoyApiService _apiService;

  @override
  Future<bool> publishLocation(LocationUpdateDto locationUpdate) async {
    try {
      final response = await _apiService.publishLocation(locationUpdate);
      final inner = response['data'];
      if (inner is Map && inner.containsKey('success')) {
        return inner['success'] == true;
      }
      return response['success'] == true;
    } on DioException catch (e) {
      // Convert DioException to appropriate failure
      if (e.response?.statusCode == 429) {
        throw ConvoyFailure.rateLimitExceeded;
      } else if (e.response?.statusCode == 401 ||
          e.response?.statusCode == 403) {
        throw ConvoyFailure.notJourneyMember;
      } else if (e.response?.statusCode == 404) {
        throw ConvoyFailure.journeyNotActive;
      } else if (e.response?.statusCode == 400) {
        final body = e.response?.data;
        if (body is Map) {
          if (body['stopPolling'] == true) {
            throw ConvoyFailure.stopPolling;
          }
          final message = body['message']?.toString() ?? '';
          if (message.toLowerCase().contains('not active')) {
            throw ConvoyFailure.journeyNotActive;
          }
        }
        throw ConvoyFailure.publishLocationFailed;
      } else if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw NetworkFailure.connectionError;
      } else {
        throw ConvoyFailure.publishLocationFailed;
      }
    } catch (e) {
      if (e is Failure) rethrow;
      throw ConvoyFailure.publishLocationFailed;
    }
  }

  @override
  Future<Map<String, dynamic>> backfillLocations({
    required String journeyId,
    required String batchId,
    required List<Map<String, dynamic>> points,
  }) => _apiService.backfillLocations(
    journeyId: journeyId,
    batchId: batchId,
    points: points,
  );

  @override
  Future<ConvoySnapshot> fetchLatestSnapshot(String journeyId) async {
    try {
      Map<String, dynamic> responseData;
      try {
        final liveSnapshot = await _apiService.fetchLiveJourneySnapshot(
          journeyId,
        );
        responseData = _normalizeLiveSnapshot(liveSnapshot);
      } on DioException catch (error) {
        // Allows the mobile release to be deployed before every environment
        // has the new recovery endpoint. Once available, /live is always the
        // authoritative source for roster, locations, route, and cursor.
        if (!_isUnsupportedLiveSnapshotEndpoint(error)) rethrow;
        responseData = await _apiService.fetchLatestPositions(journeyId);
      }

      // Parse the response according to API contract
      final snapshotDto = ConvoySnapshotDto.fromJson(responseData);

      // Convert location data to member positions
      final memberPositions = <String, MemberPosition>{};

      for (final entry in snapshotDto.locations.entries) {
        try {
          final locationData = entry.value as Map<String, dynamic>;

          // Backend embeds coordinates under a nested 'location' object.
          // Fall back to flat keys for any future schema that flattens them.
          final nested = (locationData['location'] as Map?)
              ?.cast<String, dynamic>();
          final lat = nested != null
              ? (nested['latitude'] as num?)?.toDouble()
              : (locationData['latitude'] as num?)?.toDouble();
          final lng = nested != null
              ? (nested['longitude'] as num?)?.toDouble()
              : (locationData['longitude'] as num?)?.toDouble();

          if (lat == null || lng == null) continue;

          // Prefer an explicit userId in the payload (added in a future backend
          // pass); fall back to the map key which is currently participantId.
          final userId = locationData['userId'] as String? ?? entry.key;

          final position = MemberPositionModel.fromJson({
            'userId': userId,
            'latitude': lat,
            'longitude': lng,
            'timestamp': locationData['timestamp'],
            'accuracy': locationData['accuracy'],
            'heading': locationData['heading'],
            'speed': locationData['speed'],
            'altitude': locationData['altitude'],
            'sequenceNumber': locationData['sequenceNumber'],
            'priority': locationData['priority'],
          });
          memberPositions[userId] = position.toEntity();
        } catch (e) {
          print('⚠️ Failed to parse position for user ${entry.key}: $e');
        }
      }

      // Create destination if available
      final destination = snapshotDto.destination != null
          ? ConvoyDestination(
              latitude: snapshotDto.destination!.latitude,
              longitude: snapshotDto.destination!.longitude,
            )
          : const ConvoyDestination(
              latitude: 0.0,
              longitude: 0.0,
            ); // Default if missing

      return ConvoySnapshot(
        journeyId: journeyId,
        members: memberPositions,
        destination: destination,
        destinationAddress:
            snapshotDto.destinationAddress ?? 'Unknown destination',
        timestamp: DateTime.now(),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw ConvoyFailure.journeyNotActive;
      } else if (e.response?.statusCode == 401 ||
          e.response?.statusCode == 403) {
        throw ConvoyFailure.notJourneyMember;
      } else if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw NetworkFailure.connectionError;
      } else {
        throw ServerFailure.fromStatusCode(e.response?.statusCode ?? 500);
      }
    } catch (e) {
      if (e is Failure) rethrow;
      throw ServerFailure(
        message: 'Failed to fetch convoy snapshot',
        details:
            'An unexpected error occurred while fetching convoy positions: $e',
        timestamp: DateTime.now(),
      );
    }
  }

  bool _isUnsupportedLiveSnapshotEndpoint(DioException error) {
    if (error.response?.statusCode != 404) return false;
    final body = error.response?.data;
    if (body is! Map) return false;
    final message = body['message']?.toString() ?? '';
    // Nest reports an unregistered route as "Cannot GET /.../live". A real
    // journey lookup returns "Journey not found" and must remain terminal.
    return message.startsWith('Cannot GET ') && message.contains('/live');
  }

  Map<String, dynamic> _normalizeLiveSnapshot(Map<String, dynamic> snapshot) {
    final journey = snapshot['journey'];
    final journeyData = journey is Map
        ? journey.map((key, value) => MapEntry(key.toString(), value))
        : const <String, dynamic>{};
    final participants = <String, dynamic>{};
    final members = snapshot['members'];

    if (members is List) {
      for (final rawMember in members) {
        if (rawMember is! Map) continue;
        final member = rawMember.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        final userId = member['userId']?.toString();
        final rawLocation = member['location'];
        if (userId == null || rawLocation is! Map) continue;
        final location = rawLocation.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        participants[userId] = <String, dynamic>{...location, 'userId': userId};
      }
    }

    return <String, dynamic>{
      'participants': participants,
      'destination': journeyData['destination'],
      'destinationAddress':
          journeyData['destinationAddress'] ?? journeyData['destinationName'],
      'generatedAt': snapshot['generatedAt'],
    };
  }
}
