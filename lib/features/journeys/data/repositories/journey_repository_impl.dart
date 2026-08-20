import 'package:dio/dio.dart';
import 'package:tulink_flutter/core/common/result.dart';
import 'package:tulink_flutter/core/errors/failure.dart';
import 'package:tulink_flutter/features/journeys/data/datasources/journey_exceptions.dart';
import 'package:tulink_flutter/features/journeys/domain/entities/journey.dart';
import 'package:tulink_flutter/features/journeys/domain/repositories/journey_repository.dart';
import 'package:tulink_flutter/features/journeys/data/datasources/journey_remote_data_source.dart';
import 'package:tulink_flutter/features/journeys/data/models/journey_model.dart';
import 'package:tulink_flutter/core/services/connectivity_service.dart';
import 'package:tulink_flutter/core/services/offline_storage_service.dart';

class JourneyRepositoryImpl implements JourneyRepository {
  final JourneyRemoteDataSource remoteDataSource;
  final OfflineStorageService? offlineStorage;
  final ConnectivityService? connectivityService;
  final Future<String?> Function()? currentUserId;

  JourneyRepositoryImpl({
    required this.remoteDataSource,
    this.offlineStorage,
    this.connectivityService,
    this.currentUserId,
  });

  @override
  Future<Result<Journey>> createJourney({
    required String name,
    required double latitude,
    required double longitude,
    String? destinationName,
    required String destinationAddress,
    required int lagThresholdMeters,
    DateTime? scheduledFor,
    bool autoStart = false,
  }) async {
    try {
      final journey = await remoteDataSource.createJourney(
        name: name,
        latitude: latitude,
        longitude: longitude,
        destinationName: destinationName,
        destinationAddress: destinationAddress,
        lagThresholdMeters: lagThresholdMeters,
        scheduledFor: scheduledFor,
        autoStart: autoStart,
      );
      return (data: journey, failure: null);
    } on DioException catch (e) {
      return (
        data: null,
        failure: ServerFailure(
          message:
              e.response?.data?['message']?.toString() ??
              'Failed to create journey',
        ),
      );
    } catch (e) {
      return (data: null, failure: ServerFailure(message: e.toString()));
    }
  }

  @override
  Future<Result<Journey>> getJourneyById(String journeyId) async {
    if (connectivityService?.isOnline.value == false) {
      return _cachedJourneyResult(journeyId);
    }
    try {
      final journey = await remoteDataSource.getJourneyById(journeyId);
      await _cacheJourney(journey);
      return (data: journey, failure: null);
    } on DioException catch (e) {
      if (_isNetworkFailure(e)) {
        final cached = await _cachedJourneyResult(journeyId);
        if (cached.data != null) return cached;
      }
      return (
        data: null,
        failure: ServerFailure(
          message:
              e.response?.data?['message']?.toString() ??
              'Failed to get journey details',
        ),
      );
    } catch (e) {
      return (data: null, failure: ServerFailure(message: e.toString()));
    }
  }

  /// Active journeys already on disk, for painting before the network answers.
  ///
  /// Failures flatten to an empty list: the caller wants something to show,
  /// and "nothing cached" and "cache unreadable" lead to the same screen.
  @override
  Future<List<Journey>> getCachedActiveJourneys() async {
    final cached = await _cachedActiveJourneysResult();
    return cached.data ?? const [];
  }

  @override
  Future<Result<List<Journey>>> getActiveJourneys() async {
    if (connectivityService?.isOnline.value == false) {
      return _cachedActiveJourneysResult();
    }
    try {
      final journeys = await remoteDataSource.getActiveJourneys();
      for (final journey in journeys) {
        await _cacheJourney(journey);
      }
      return (data: journeys, failure: null);
    } on DioException catch (e) {
      if (_isNetworkFailure(e)) {
        final cached = await _cachedActiveJourneysResult();
        if (cached.data?.isNotEmpty == true) return cached;
      }
      return (
        data: null,
        failure: ServerFailure(
          message:
              e.response?.data?['message']?.toString() ??
              'Failed to get active journeys',
        ),
      );
    } catch (e) {
      return (data: null, failure: ServerFailure(message: e.toString()));
    }
  }

  @override
  Future<Result<Journey>> joinJourneyByCode(String inviteCode) async {
    try {
      final journey = await remoteDataSource.joinJourneyByCode(inviteCode);
      return (data: journey, failure: null);
    } on DioException catch (e) {
      return (
        data: null,
        failure: ServerFailure(
          message:
              (e.response?.data is Map<String, dynamic>
                  ? (e.response?.data as Map<String, dynamic>)['message']
                        ?.toString()
                  : null) ??
              'Failed to join journey',
        ),
      );
    } catch (e) {
      return (data: null, failure: ServerFailure(message: e.toString()));
    }
  }

  @override
  Future<Result<Journey>> startJourney(String journeyId) async {
    try {
      final journey = await remoteDataSource.startJourney(journeyId);
      await _cacheJourney(journey);
      return (data: journey, failure: null);
    } on AlreadyInActiveJourneyException catch (e) {
      // Single-active-journey enforcement (BE-FIX-3): the data source already
      // parsed the 409 envelope; translate it to a domain Failure that carries
      // activeJourneyId so the UI can offer an end-it-and-start-this switch.
      return (
        data: null,
        failure: AlreadyInActiveJourneyFailure(
          activeJourneyId: e.activeJourneyId,
          message: e.message ?? 'You already have an active journey.',
        ),
      );
    } on DioException catch (e) {
      return (
        data: null,
        failure: ServerFailure(
          message:
              e.response?.data?['message']?.toString() ??
              'Failed to start journey',
        ),
      );
    } catch (e) {
      return (data: null, failure: ServerFailure(message: e.toString()));
    }
  }

  @override
  Future<Result<Journey>> updateJourney(
    String journeyId,
    Map<String, dynamic> updateData,
  ) async {
    try {
      final journey = await remoteDataSource.updateJourney(
        journeyId,
        updateData,
      );
      await _cacheJourney(journey);
      return (data: journey, failure: null);
    } on DioException catch (e) {
      return (
        data: null,
        failure: ServerFailure(
          message:
              e.response?.data?['message']?.toString() ??
              'Failed to update journey',
        ),
      );
    } catch (e) {
      return (data: null, failure: ServerFailure(message: e.toString()));
    }
  }

  @override
  Future<Result<Journey>> endJourney(String journeyId) async {
    try {
      final journey = await remoteDataSource.endJourney(journeyId);
      await _deleteCachedJourney(journeyId);
      return (data: journey, failure: null);
    } on DioException catch (e) {
      return (
        data: null,
        failure: ServerFailure(
          message:
              e.response?.data?['message']?.toString() ??
              'Failed to start journey',
        ),
      );
    } catch (e) {
      return (data: null, failure: ServerFailure(message: e.toString()));
    }
  }

  @override
  Future<Result<bool>> cancelJourney(String journeyId) async {
    try {
      await remoteDataSource.cancelJourney(journeyId);
      await _deleteCachedJourney(journeyId);
      return (data: true, failure: null);
    } on DioException catch (e) {
      return (
        data: null,
        failure: ServerFailure(
          message:
              e.response?.data?['message']?.toString() ??
              'Failed to cancel journey',
        ),
      );
    } catch (e) {
      return (data: null, failure: ServerFailure(message: e.toString()));
    }
  }

  @override
  Future<Result<bool>> leaveJourney(String journeyId) async {
    try {
      await remoteDataSource.leaveJourney(journeyId);
      await _deleteCachedJourney(journeyId);
      return (data: true, failure: null);
    } on DioException catch (e) {
      return (
        data: null,
        failure: ServerFailure(
          message:
              e.response?.data?['message']?.toString() ??
              'Failed to leave journey',
        ),
      );
    } catch (e) {
      return (data: null, failure: ServerFailure(message: e.toString()));
    }
  }

  bool _isNetworkFailure(DioException error) =>
      error.type == DioExceptionType.connectionError ||
      error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.receiveTimeout ||
      error.type == DioExceptionType.sendTimeout;

  Future<void> _cacheJourney(Journey journey) async {
    if (journey.status != JourneyStatus.ACTIVE) return;
    final storage = offlineStorage;
    final resolveUserId = currentUserId;
    if (storage == null || resolveUserId == null) return;
    final userId = await resolveUserId();
    if (userId == null || userId.isEmpty) return;
    final model = journey is JourneyModel
        ? journey
        : JourneyModel(
            id: journey.id,
            inviteCode: journey.inviteCode,
            name: journey.name,
            leaderId: journey.leaderId,
            status: journey.status,
            destination: journey.destination,
            destinationName: journey.destinationName,
            destinationAddress: journey.destinationAddress,
            lagThresholdMeters: journey.lagThresholdMeters,
            createdAt: journey.createdAt,
            updatedAt: journey.updatedAt,
            startTime: journey.startTime,
            participants: journey.participants,
            startedAt: journey.startedAt,
            completedAt: journey.completedAt,
            scheduledFor: journey.scheduledFor,
            autoStart: journey.autoStart,
          );
    await storage.mergeSession(userId, journey.id, {'journey': model.toJson()});
  }

  Future<Result<Journey>> _cachedJourneyResult(String journeyId) async {
    final storage = offlineStorage;
    final resolveUserId = currentUserId;
    final userId = resolveUserId == null ? null : await resolveUserId();
    if (storage != null && userId != null) {
      final session = storage.loadSession(userId, journeyId);
      final json = OfflineStorageService.readMap(session?['journey']);
      if (json != null) {
        try {
          return (data: JourneyModel.fromJson(json), failure: null);
        } catch (error) {
          print('⚠️ Discarding corrupt offline journey: $error');
        }
      }
    }
    return (
      data: null,
      failure: const NetworkFailure(
        message: 'Journey is not available offline',
      ),
    );
  }

  Future<Result<List<Journey>>> _cachedActiveJourneysResult() async {
    final storage = offlineStorage;
    final resolveUserId = currentUserId;
    final userId = resolveUserId == null ? null : await resolveUserId();
    if (storage == null || userId == null) {
      return (
        data: null,
        failure: const NetworkFailure(message: 'No offline user session'),
      );
    }
    final journeys = <Journey>[];
    for (final session in storage.loadUserSessions(userId)) {
      final json = OfflineStorageService.readMap(session['journey']);
      if (json == null) continue;
      try {
        final journey = JourneyModel.fromJson(json);
        if (journey.status == JourneyStatus.ACTIVE) journeys.add(journey);
      } catch (error) {
        print('⚠️ Skipping corrupt offline journey: $error');
      }
    }
    return (data: journeys, failure: null);
  }

  Future<void> _deleteCachedJourney(String journeyId) async {
    final storage = offlineStorage;
    final resolveUserId = currentUserId;
    if (storage == null || resolveUserId == null) return;
    final userId = await resolveUserId();
    if (userId != null) {
      await storage.deleteSession(userId, journeyId);
      // The stored route goes with it. This runs on the three terminal
      // transitions — end, cancel, leave — after which the journey can never
      // be navigated again, so its polyline is the largest thing on disk with
      // nothing left to do. Without this they accumulate for the life of the
      // install.
      await storage.deleteRoute(userId, journeyId);
    }
  }
}
