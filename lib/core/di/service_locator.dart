import 'package:hive/hive.dart';
import 'package:tulink_flutter/features/analytics/data/services/analytics_api_service.dart';
import 'package:tulink_flutter/features/analytics/data/datasources/analytics_remote_data_source.dart';
import 'package:tulink_flutter/features/analytics/data/repositories/analytics_repository_impl.dart';
import 'package:tulink_flutter/features/analytics/domain/repositories/analytics_repository.dart';
import 'package:tulink_flutter/features/analytics/domain/usecases/analytics_usecases.dart';
import 'package:tulink_flutter/features/analytics/presentation/providers/analytics_provider.dart';
import 'package:tulink_flutter/features/convoy/data/services/convoy_api_service.dart';
import 'package:tulink_flutter/features/convoy/data/datasources/convoy_remote_data_source.dart';
import 'package:tulink_flutter/features/convoy/data/datasources/convoy_websocket_data_source.dart';
import 'package:tulink_flutter/features/convoy/data/repositories/convoy_repository_impl.dart';
import 'package:tulink_flutter/features/convoy/domain/repositories/convoy_repository.dart';
import 'package:tulink_flutter/features/convoy/domain/usecases/stream_convoy_positions.dart';
import 'package:tulink_flutter/features/convoy/domain/usecases/publish_my_position.dart';
import 'package:tulink_flutter/features/convoy/domain/usecases/fetch_latest_snapshot.dart';
import 'package:tulink_flutter/features/convoy/presentation/providers/convoy_provider.dart';
import 'package:tulink_flutter/features/navigation/data/services/mapbox_directions_service.dart';
import 'package:tulink_flutter/features/navigation/data/repositories/navigation_repository_impl.dart';
import 'package:tulink_flutter/features/navigation/domain/repositories/navigation_repository.dart';

import '../../features/auth/data/datasources/auth_local_data_source.dart';
import '../../features/auth/data/datasources/auth_remote_data_source.dart';
import '../../features/auth/data/repositories/auth_repository_impl.dart';
import '../../features/auth/data/services/auth_api_service.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/journeys/data/datasources/journey_remote_data_source.dart';
import '../../features/journeys/data/datasources/mapbox_search_datasource.dart';
import '../../features/journeys/data/repositories/journey_repository_impl.dart';
import '../../features/journeys/domain/repositories/journey_repository.dart';
import '../../features/journeys/domain/usecases/journey_usecases.dart';
import '../../features/journeys/presentation/providers/journey_provider.dart';
import '../../features/maps/data/datasources/map_local_data_source.dart';
import '../../features/maps/data/datasources/place_search_remote_data_source.dart';
import '../../features/maps/data/repositories/map_repository_impl.dart';
import '../../features/maps/domain/repositories/map_repository.dart';
import '../../features/maps/domain/usecases/search_places_usecase.dart';
import '../../features/maps/presentation/providers/map_provider.dart';
import '../constants/app_constants.dart';
import '../config/app_config.dart';
import '../network/dio_client.dart';
import '../theme/theme_provider.dart';
import '../auth/token_manager.dart';

/// Service locator for dependency injection
/// Manages the creation and lifecycle of dependencies
class ServiceLocator {
  ServiceLocator._internal();
  static final ServiceLocator _instance = ServiceLocator._internal();
  factory ServiceLocator() => _instance;

  // Private fields for singleton instances
  late DioClient _dioClient;
  late Box<dynamic> _authBox;
  late AuthApiService _authApiService;
  late AuthLocalDataSource _authLocalDataSource;
  late AuthRemoteDataSource _authRemoteDataSource;
  late AuthRepository _authRepository;
  late AuthProvider _authProvider;
  late ThemeProvider _themeProvider;

  // Map Feature
  late MapLocalDataSource _mapLocalDataSource;
  late PlaceSearchRemoteDataSource _placeSearchRemoteDataSource;
  late MapRepository _mapRepository;
  late SearchPlacesUseCase _searchPlacesUseCase;
  late MapProvider _mapProvider;

  // Journey Feature
  late JourneyRemoteDataSource _journeyRemoteDataSource;
  late MapboxSearchDataSource _mapboxSearchDataSource;
  late JourneyRepository _journeyRepository;
  late JourneyProvider _journeyProvider;


  // Analytics Feature
  late AnalyticsApiService _analyticsApiService;
  late AnalyticsRemoteDataSource _analyticsRemoteDataSource;
  late AnalyticsRepository _analyticsRepository;
  late GetJourneyHistoryUseCase _getJourneyHistoryUseCase;
  late GetJourneyAnalyticsUseCase _getJourneyAnalyticsUseCase;
  late AnalyticsProvider _analyticsProvider;

  // Convoy Feature
  late ConvoyApiService _convoyApiService;
  late ConvoyRemoteDataSource _convoyRemoteDataSource;
  late ConvoyWebSocketDataSource _convoyWebSocketDataSource;
  late ConvoyRepository _convoyRepository;
  late StreamConvoyPositions _streamConvoyPositions;
  late PublishMyPosition _publishMyPosition;
  late FetchLatestSnapshot _fetchLatestSnapshot;
  late ConvoyProvider _convoyProvider;

  // Navigation Feature
  late MapboxDirectionsService _mapboxDirectionsService;
  late NavigationRepository _navigationRepository;

  // Getters for accessing dependencies
  DioClient get dioClient => _dioClient;
  Box<dynamic> get authBox => _authBox;
  AuthApiService get authApiService => _authApiService;
  AuthLocalDataSource get authLocalDataSource => _authLocalDataSource;
  AuthRemoteDataSource get authRemoteDataSource => _authRemoteDataSource;
  AuthRepository get authRepository => _authRepository;
  AuthProvider get authProvider => _authProvider;
  ThemeProvider get themeProvider => _themeProvider;
  
  // Map Feature Getters
  MapProvider get mapProvider => _mapProvider;

  // Journey Feature Getters
  JourneyProvider get journeyProvider => _journeyProvider;


  // Analytics Feature Getters
  AnalyticsProvider get analyticsProvider => _analyticsProvider;

  // Convoy Feature Getters
  ConvoyProvider get convoyProvider => _convoyProvider;

  // Navigation Feature Getters
  NavigationRepository get navigationRepository => _navigationRepository;

  /// Initialize all dependencies
  /// Call this once in main.dart before runApp
  Future<void> init() async {
    // Initialize Hive boxes with error recovery
    try {
      _authBox = await Hive.openBox(AppConstants.authBoxName);
    } catch (e) {
      // If there's a type error (likely due to model structure changes),
      // delete the box and recreate it
      print('⚠️ Hive box error detected: $e');
      print('🧹 Clearing auth_box and recreating...');
      await Hive.deleteBoxFromDisk(AppConstants.authBoxName);
      _authBox = await Hive.openBox(AppConstants.authBoxName);
      print('✅ Auth box recreated successfully');
    }

    // Initialize network client
    _dioClient = DioClient();
    _dioClient.initialize();

    // Initialize API services
    _authApiService = AuthApiService(_dioClient.dio);
    _analyticsApiService = AnalyticsApiService(_dioClient.dio);
    _convoyApiService = ConvoyApiService(_dioClient.dio);
    _mapboxDirectionsService = MapboxDirectionsService(
      dio: _dioClient.dio,
      accessToken: AppConfig.mapboxAccessToken,
    );

    // Initialize data sources
    _authLocalDataSource = AuthLocalDataSourceImpl(_authBox);
    _authRemoteDataSource = AuthRemoteDataSourceImpl(_authApiService);
    _mapLocalDataSource = MapLocalDataSourceImpl();
    _placeSearchRemoteDataSource = PlaceSearchRemoteDataSourceImpl(dio: _dioClient.dio);
    _journeyRemoteDataSource = JourneyRemoteDataSourceImpl(dio: _dioClient.dio);
    _mapboxSearchDataSource = MapboxSearchDataSource(dio: _dioClient.dio);
    _analyticsRemoteDataSource = AnalyticsRemoteDataSourceImpl(_analyticsApiService);
    _convoyRemoteDataSource = ConvoyRemoteDataSourceImpl(_convoyApiService);
    _convoyWebSocketDataSource = ConvoyWebSocketDataSourceImpl();
   

    // Initialize repositories
    _authRepository = AuthRepositoryImpl(
      remoteDataSource: _authRemoteDataSource,
      localDataSource: _authLocalDataSource,
      dioClient: _dioClient,
    );
    _mapRepository = MapRepositoryImpl(
      localDataSource: _mapLocalDataSource,
      placeSearchRemoteDataSource: _placeSearchRemoteDataSource,
    );
    _journeyRepository = JourneyRepositoryImpl(remoteDataSource: _journeyRemoteDataSource);
    _analyticsRepository = AnalyticsRepositoryImpl(remoteDataSource: _analyticsRemoteDataSource);
    _convoyRepository = ConvoyRepositoryImpl(
      remoteDataSource: _convoyRemoteDataSource,
      webSocketDataSource: _convoyWebSocketDataSource,
      tokenManager: TokenManager(),
    );
    _navigationRepository = NavigationRepositoryImpl(_mapboxDirectionsService);

    // Initialize use cases
    _searchPlacesUseCase = SearchPlacesUseCase(repository: _mapRepository);
    _getJourneyHistoryUseCase = GetJourneyHistoryUseCase(_analyticsRepository);
    _getJourneyAnalyticsUseCase = GetJourneyAnalyticsUseCase(_analyticsRepository);
    _streamConvoyPositions = StreamConvoyPositions(_convoyRepository);
    _publishMyPosition = PublishMyPosition(_convoyRepository);
    _fetchLatestSnapshot = FetchLatestSnapshot(_convoyRepository);

    // Initialize providers
    _authProvider = AuthProvider(_authRepository);
    _themeProvider = ThemeProvider();
    _mapProvider = MapProvider(_mapRepository, _searchPlacesUseCase);
    _journeyProvider = JourneyProvider(
      createJourneyUseCase: CreateJourney(_journeyRepository),
      getJourneyByIdUseCase: GetJourneyById(_journeyRepository),
      getActiveJourneysUseCase: GetActiveJourneys(_journeyRepository),
      startJourneyUseCase: StartJourney(_journeyRepository),
      updateJourneyUseCase: UpdateJourney(_journeyRepository),
      mapboxSearchDataSource: _mapboxSearchDataSource, 
      endJourneyUseCase: EndJourney(_journeyRepository),
      navigationRepository: _navigationRepository,
    );
    _analyticsProvider = AnalyticsProvider(
      _getJourneyHistoryUseCase,
      _getJourneyAnalyticsUseCase,
    );
    _convoyProvider = ConvoyProvider(
      streamConvoyPositions: _streamConvoyPositions,
      publishMyPosition: _publishMyPosition,
      fetchLatestSnapshot: _fetchLatestSnapshot,
      repository: _convoyRepository,
    );

    // Initialize auth provider
    await _authProvider.initialize();
  }

  /// Dispose resources when app is closing
  Future<void> dispose() async {
    await _authBox.close();
  }
}