import 'package:hive/hive.dart';

import '../../features/auth/data/datasources/auth_local_data_source.dart';
import '../../features/auth/data/datasources/auth_remote_data_source.dart';
import '../../features/auth/data/repositories/auth_repository_impl.dart';
import '../../features/auth/data/services/auth_api_service.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/maps/data/datasources/map_local_data_source.dart';
import '../../features/maps/data/repositories/map_repository_impl.dart';
import '../../features/maps/domain/repositories/map_repository.dart';
import '../../features/maps/presentation/providers/map_provider.dart';
import '../constants/app_constants.dart';
import '../network/dio_client.dart';
import '../theme/theme_provider.dart';

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
  late MapRepository _mapRepository;
  late MapProvider _mapProvider;

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

    // Initialize data sources
    _authLocalDataSource = AuthLocalDataSourceImpl(_authBox);
    _authRemoteDataSource = AuthRemoteDataSourceImpl(_authApiService);
    _mapLocalDataSource = MapLocalDataSourceImpl();

    // Initialize repositories
    _authRepository = AuthRepositoryImpl(
      remoteDataSource: _authRemoteDataSource,
      localDataSource: _authLocalDataSource,
      dioClient: _dioClient,
    );
    _mapRepository = MapRepositoryImpl(localDataSource: _mapLocalDataSource);

    // Initialize providers
    _authProvider = AuthProvider(_authRepository);
    _themeProvider = ThemeProvider();
    _mapProvider = MapProvider(_mapRepository);

    // Initialize auth provider
    await _authProvider.initialize();
  }

  /// Dispose resources when app is closing
  Future<void> dispose() async {
    await _authBox.close();
  }
}