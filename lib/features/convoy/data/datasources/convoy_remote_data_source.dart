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
      await _apiService.publishLocation(locationUpdate);
      return true;
    } on DioException catch (e) {
      // Convert DioException to appropriate failure
      if (e.response?.statusCode == 429) {
        throw ConvoyFailure.rateLimitExceeded;
      } else if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
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
  Future<ConvoySnapshot> fetchLatestSnapshot(String journeyId) async {
    try {
      final responseData = await _apiService.fetchLatestPositions(journeyId);
      
      // Parse the response according to API contract
      final snapshotDto = ConvoySnapshotDto.fromJson(responseData);
      
      // Convert location data to member positions
      final memberPositions = <String, MemberPosition>{};
      
      for (final entry in snapshotDto.locations.entries) {
        try {
          final locationData = entry.value as Map<String, dynamic>;
          final position = MemberPositionModel.fromJson({
            'userId': entry.key,
            ...locationData,
          });
          memberPositions[entry.key] = position.toEntity();
        } catch (e) {
          // Skip invalid position data and continue
          print('⚠️ Failed to parse position for user ${entry.key}: $e');
        }
      }

      // Create destination if available
      final destination = snapshotDto.destination != null
          ? ConvoyDestination(
              latitude: snapshotDto.destination!.latitude,
              longitude: snapshotDto.destination!.longitude,
            )
          : const ConvoyDestination(latitude: 0.0, longitude: 0.0); // Default if missing

      return ConvoySnapshot(
        journeyId: journeyId,
        members: memberPositions,
        destination: destination,
        destinationAddress: snapshotDto.destinationAddress ?? 'Unknown destination',
        timestamp: DateTime.now(),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw ConvoyFailure.journeyNotActive;
      } else if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
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
        details: 'An unexpected error occurred while fetching convoy positions: $e',
        timestamp: DateTime.now(),
      );
    }
  }
}