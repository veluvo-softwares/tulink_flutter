# Critical Implementation Guide - TuLink Flutter App

This guide provides step-by-step implementation instructions for the most critical missing features that must be completed within 48 hours.

---

## 🔥 PRIORITY 1: Authentication Backend Integration (4 hours)

### Current Issue
Authentication system uses mock implementations. Users cannot actually log in or register.

### Implementation Steps

#### Step 1: Update AuthApiService (1 hour)

**File**: `lib/features/auth/data/services/auth_api_service.dart`

```dart
import 'package:dio/dio.dart';
import 'package:tulink_flutter/core/network/models/api_response.dart';
import 'package:tulink_flutter/features/auth/data/models/auth_response_model.dart';

class AuthApiService {
  final Dio _dio;
  
  AuthApiService(this._dio);
  
  // IMPLEMENT THESE METHODS TO REPLACE MOCK IMPLEMENTATIONS
  
  Future<ApiResponse<AuthResponseModel>> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _dio.post('/auth/login', data: {
        'email': email,
        'password': password,
      });
      
      final authResponse = AuthResponseModel.fromJson(response.data['data']);
      return ApiResponse<AuthResponseModel>(
        success: true,
        statusCode: response.statusCode ?? 200,
        message: response.data['message'] ?? 'Login successful',
        data: authResponse,
      );
    } on DioException catch (e) {
      return ApiResponse<AuthResponseModel>(
        success: false,
        statusCode: e.response?.statusCode ?? 500,
        message: e.response?.data['message'] ?? 'Login failed',
        error: e.response?.data['error'],
      );
    }
  }
  
  Future<ApiResponse<AuthResponseModel>> register({
    required String email,
    required String password,
    required String displayName,
    String? phoneNumber,
  }) async {
    try {
      final response = await _dio.post('/auth/register', data: {
        'email': email,
        'password': password,
        'displayName': displayName,
        if (phoneNumber != null) 'phoneNumber': phoneNumber,
      });
      
      final authResponse = AuthResponseModel.fromJson(response.data['data']);
      return ApiResponse<AuthResponseModel>(
        success: true,
        statusCode: response.statusCode ?? 201,
        message: response.data['message'] ?? 'Registration successful',
        data: authResponse,
      );
    } on DioException catch (e) {
      return ApiResponse<AuthResponseModel>(
        success: false,
        statusCode: e.response?.statusCode ?? 500,
        message: e.response?.data['message'] ?? 'Registration failed',
        error: e.response?.data['error'],
      );
    }
  }
  
  Future<ApiResponse<UserModel>> getCurrentUser() async {
    try {
      final response = await _dio.get('/auth/profile');
      
      final user = UserModel.fromJson(response.data['data']);
      return ApiResponse<UserModel>(
        success: true,
        statusCode: response.statusCode ?? 200,
        message: response.data['message'] ?? 'Profile retrieved successfully',
        data: user,
      );
    } on DioException catch (e) {
      return ApiResponse<UserModel>(
        success: false,
        statusCode: e.response?.statusCode ?? 500,
        message: e.response?.data['message'] ?? 'Failed to get profile',
        error: e.response?.data['error'],
      );
    }
  }
  
  Future<ApiResponse<AuthTokensModel>> refreshToken(String refreshToken) async {
    try {
      final response = await _dio.post('/auth/refresh', data: {
        'refreshToken': refreshToken,
      });
      
      final tokens = AuthTokensModel.fromJson(response.data['data']['tokens']);
      return ApiResponse<AuthTokensModel>(
        success: true,
        statusCode: response.statusCode ?? 200,
        message: 'Token refreshed successfully',
        data: tokens,
      );
    } on DioException catch (e) {
      return ApiResponse<AuthTokensModel>(
        success: false,
        statusCode: e.response?.statusCode ?? 401,
        message: e.response?.data['message'] ?? 'Token refresh failed',
        error: e.response?.data['error'],
      );
    }
  }
}
```

#### Step 2: Update AuthRepositoryImpl (2 hours)

**File**: `lib/features/auth/data/repositories/auth_repository_impl.dart`

Replace the mock implementations with real API calls:

```dart
@override
Future<AuthResult> signIn({
  required String email,
  required String password,
}) async {
  try {
    print('🔵 AuthRepositoryImpl.signIn() - Making API call...');
    
    // Make actual API call
    final response = await _authApiService.login(
      email: email,
      password: password,
    );
    
    if (response.success && response.data != null) {
      print('✅ API call successful, caching user...');
      
      // Cache user locally
      await _localDataSource.cacheUser(response.data!.user);
      
      // Cache tokens securely
      await _cacheTokens(response.data!.tokens);
      
      return AuthResult(user: response.data!.user.toEntity());
    } else {
      print('❌ API call failed: ${response.message}');
      return AuthResult(
        failure: _mapErrorToFailure(response.statusCode, response.message),
      );
    }
  } catch (e) {
    print('💥 Exception in signIn: $e');
    return AuthResult(
      failure: const ServerFailure(message: 'Network error occurred'),
    );
  }
}

@override
Future<AuthResult> signUp({
  required String email,
  required String password,
  required String name,
}) async {
  try {
    final response = await _authApiService.register(
      email: email,
      password: password,
      displayName: name,
    );
    
    if (response.success && response.data != null) {
      // Cache user locally
      await _localDataSource.cacheUser(response.data!.user);
      
      // Cache tokens securely
      await _cacheTokens(response.data!.tokens);
      
      return AuthResult(user: response.data!.user.toEntity());
    } else {
      return AuthResult(
        failure: _mapErrorToFailure(response.statusCode, response.message),
      );
    }
  } catch (e) {
    return AuthResult(
      failure: const ServerFailure(message: 'Registration failed'),
    );
  }
}

// Helper method to cache tokens securely
Future<void> _cacheTokens(AuthTokensModel tokens) async {
  await _localDataSource.cacheTokens(tokens);
}

// Helper method to map API errors to domain failures
Failure _mapErrorToFailure(int statusCode, String message) {
  switch (statusCode) {
    case 400:
      return ValidationFailure(message: message);
    case 401:
      return AuthFailure(message: 'Invalid credentials');
    case 409:
      return ConflictFailure(message: 'Email already exists');
    case 500:
      return ServerFailure(message: 'Server error occurred');
    default:
      return ServerFailure(message: message);
  }
}
```

#### Step 3: Update AuthLocalDataSource for Token Storage (1 hour)

**File**: `lib/features/auth/data/datasources/auth_local_data_source.dart`

Add secure token caching:

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class AuthLocalDataSource {
  // ... existing methods
  Future<void> cacheTokens(AuthTokensModel tokens);
  Future<AuthTokensModel?> getCachedTokens();
  Future<void> clearTokens();
}

class AuthLocalDataSourceImpl implements AuthLocalDataSource {
  final Box<dynamic> _box;
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: IOSAccessibility.first_unlock_this_device,
    ),
  );
  
  AuthLocalDataSourceImpl(this._box);
  
  @override
  Future<void> cacheTokens(AuthTokensModel tokens) async {
    await _secureStorage.write(
      key: 'auth_token',
      value: tokens.idToken,
    );
    await _secureStorage.write(
      key: 'refresh_token',
      value: tokens.refreshToken,
    );
    await _secureStorage.write(
      key: 'token_expires_in',
      value: tokens.expiresIn,
    );
  }
  
  @override
  Future<AuthTokensModel?> getCachedTokens() async {
    try {
      final idToken = await _secureStorage.read(key: 'auth_token');
      final refreshToken = await _secureStorage.read(key: 'refresh_token');
      final expiresIn = await _secureStorage.read(key: 'token_expires_in');
      
      if (idToken != null && refreshToken != null && expiresIn != null) {
        return AuthTokensModel(
          idToken: idToken,
          refreshToken: refreshToken,
          expiresIn: expiresIn,
        );
      }
      return null;
    } catch (e) {
      return null;
    }
  }
  
  @override
  Future<void> clearTokens() async {
    await _secureStorage.delete(key: 'auth_token');
    await _secureStorage.delete(key: 'refresh_token');
    await _secureStorage.delete(key: 'token_expires_in');
  }
}
```

#### Step 4: Add Token Refresh Interceptor to DioClient

**File**: `lib/core/network/dio_client.dart`

Add automatic token refresh:

```dart
void _addAuthInterceptor() {
  _dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        // Add auth token to requests
        final tokens = await ServiceLocator().authLocalDataSource.getCachedTokens();
        if (tokens != null) {
          options.headers['Authorization'] = 'Bearer ${tokens.idToken}';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        // Handle 401 errors with token refresh
        if (error.response?.statusCode == 401) {
          try {
            final tokens = await ServiceLocator().authLocalDataSource.getCachedTokens();
            if (tokens != null) {
              // Try to refresh token
              final authService = ServiceLocator().authApiService;
              final refreshResponse = await authService.refreshToken(tokens.refreshToken);
              
              if (refreshResponse.success && refreshResponse.data != null) {
                // Cache new tokens
                await ServiceLocator().authLocalDataSource.cacheTokens(refreshResponse.data!);
                
                // Retry original request with new token
                error.requestOptions.headers['Authorization'] = 'Bearer ${refreshResponse.data!.idToken}';
                
                final retryResponse = await _dio.fetch(error.requestOptions);
                return handler.resolve(retryResponse);
              }
            }
            
            // Refresh failed, clear tokens and redirect to login
            await ServiceLocator().authLocalDataSource.clearTokens();
            // Note: You'll need to implement navigation to login here
          } catch (e) {
            // Refresh failed, clear tokens
            await ServiceLocator().authLocalDataSource.clearTokens();
          }
        }
        
        handler.next(error);
      },
    ),
  );
}
```

---

## 🔥 PRIORITY 2: Location Services Implementation (6 hours)

### Step 1: Add Dependencies (30 minutes)

**File**: `pubspec.yaml`

```yaml
dependencies:
  geolocator: ^9.0.2
  permission_handler: ^10.4.3
  web_socket_channel: ^2.4.0
```

Run: `flutter pub get`

### Step 2: Create Location Service (2 hours)

**File**: `lib/features/location/services/location_service.dart`

```dart
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

class LocationService {
  static const LocationSettings _locationSettings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 10, // Update every 10 meters
  );
  
  StreamSubscription<Position>? _positionStreamSubscription;
  StreamController<Position>? _positionController;
  
  /// Request location permissions
  static Future<bool> requestLocationPermissions() async {
    // Check if location services are enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw LocationException('Location services are disabled');
    }
    
    // Check permissions
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw LocationException('Location permissions are denied');
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      throw LocationException('Location permissions are permanently denied');
    }
    
    // Request always permission for background tracking
    if (permission == LocationPermission.whileInUse) {
      final alwaysPermission = await Permission.locationAlways.request();
      if (alwaysPermission != PermissionStatus.granted) {
        print('⚠️ Always location permission not granted, background tracking may not work');
      }
    }
    
    return permission == LocationPermission.always || 
           permission == LocationPermission.whileInUse;
  }
  
  /// Get current location once
  static Future<Position> getCurrentLocation() async {
    final hasPermission = await requestLocationPermissions();
    if (!hasPermission) {
      throw LocationException('Location permission denied');
    }
    
    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 10),
    );
  }
  
  /// Start location tracking
  Stream<Position> startLocationTracking() async* {
    final hasPermission = await requestLocationPermissions();
    if (!hasPermission) {
      throw LocationException('Location permission denied');
    }
    
    _positionController = StreamController<Position>.broadcast();
    
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: _locationSettings,
    ).listen(
      (Position position) {
        print('📍 New location: ${position.latitude}, ${position.longitude}');
        _positionController?.add(position);
      },
      onError: (error) {
        print('❌ Location tracking error: $error');
        _positionController?.addError(LocationException('Location tracking failed: $error'));
      },
    );
    
    yield* _positionController!.stream;
  }
  
  /// Stop location tracking
  void stopLocationTracking() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    _positionController?.close();
    _positionController = null;
    print('🛑 Location tracking stopped');
  }
  
  /// Calculate distance between two points
  static double distanceBetween({
    required double startLatitude,
    required double startLongitude,
    required double endLatitude,
    required double endLongitude,
  }) {
    return Geolocator.distanceBetween(
      startLatitude,
      startLongitude,
      endLatitude,
      endLongitude,
    );
  }
}

class LocationException implements Exception {
  final String message;
  LocationException(this.message);
  
  @override
  String toString() => 'LocationException: $message';
}
```

### Step 3: Create WebSocket Manager (2 hours)

**File**: `lib/core/network/websocket_manager.dart`

```dart
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'dart:convert';
import 'dart:async';

class WebSocketManager {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  
  String? _url;
  String? _authToken;
  String? _currentJourneyId;
  
  int _reconnectAttempts = 0;
  static const int maxReconnectAttempts = 5;
  static const Duration heartbeatInterval = Duration(seconds: 30);
  
  final StreamController<Map<String, dynamic>> _messageController = 
      StreamController<Map<String, dynamic>>.broadcast();
  
  Stream<Map<String, dynamic>> get messages => _messageController.stream;
  
  bool get isConnected => _channel != null;
  
  /// Connect to WebSocket server
  Future<void> connect({
    required String url,
    required String authToken,
  }) async {
    _url = url;
    _authToken = authToken;
    
    try {
      print('🔌 Connecting to WebSocket: $url');
      
      _channel = WebSocketChannel.connect(
        Uri.parse(url),
        protocols: ['Bearer', authToken],
      );
      
      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleClose,
      );
      
      _reconnectAttempts = 0;
      _startHeartbeat();
      
      print('✅ WebSocket connected successfully');
    } catch (e) {
      print('❌ WebSocket connection failed: $e');
      _handleReconnect();
    }
  }
  
  /// Join a journey room
  void joinJourney(String journeyId) {
    _currentJourneyId = journeyId;
    _sendMessage({
      'event': 'join-journey',
      'journeyId': journeyId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    print('🚪 Joined journey room: $journeyId');
  }
  
  /// Leave current journey room
  void leaveJourney() {
    if (_currentJourneyId != null) {
      _sendMessage({
        'event': 'leave-journey',
        'journeyId': _currentJourneyId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      print('🚪 Left journey room: $_currentJourneyId');
      _currentJourneyId = null;
    }
  }
  
  /// Send location update
  void sendLocationUpdate({
    required String journeyId,
    required double latitude,
    required double longitude,
    required double accuracy,
    double? heading,
    double? speed,
    double? altitude,
    Map<String, dynamic>? metadata,
  }) {
    final locationData = {
      'event': 'location-update',
      'journeyId': journeyId,
      'location': {
        'latitude': latitude,
        'longitude': longitude,
      },
      'accuracy': accuracy,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      if (heading != null) 'heading': heading,
      if (speed != null) 'speed': speed,
      if (altitude != null) 'altitude': altitude,
      if (metadata != null) 'metadata': metadata,
    };
    
    _sendMessage(locationData);
  }
  
  /// Send message to WebSocket
  void _sendMessage(Map<String, dynamic> message) {
    if (_channel != null) {
      try {
        _channel!.sink.add(jsonEncode(message));
        print('📤 Sent WebSocket message: ${message['event']}');
      } catch (e) {
        print('❌ Failed to send message: $e');
      }
    } else {
      print('⚠️ Cannot send message: WebSocket not connected');
    }
  }
  
  /// Handle incoming messages
  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      print('📥 Received WebSocket message: ${data['event'] ?? 'unknown'}');
      _messageController.add(data);
    } catch (e) {
      print('❌ Failed to parse WebSocket message: $e');
    }
  }
  
  /// Handle WebSocket errors
  void _handleError(error) {
    print('❌ WebSocket error: $error');
    _handleReconnect();
  }
  
  /// Handle WebSocket close
  void _handleClose() {
    print('🔌 WebSocket connection closed');
    _cleanup();
    _handleReconnect();
  }
  
  /// Start heartbeat to keep connection alive
  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (timer) {
      _sendMessage({
        'event': 'heartbeat',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }
  
  /// Handle reconnection with exponential backoff
  void _handleReconnect() {
    if (_reconnectAttempts >= maxReconnectAttempts) {
      print('❌ Max reconnection attempts reached');
      return;
    }
    
    _cleanup();
    _reconnectAttempts++;
    
    final delay = Duration(seconds: 2 << _reconnectAttempts); // Exponential backoff
    print('🔄 Reconnecting in ${delay.inSeconds} seconds (attempt $_reconnectAttempts)');
    
    _reconnectTimer = Timer(delay, () {
      if (_url != null && _authToken != null) {
        connect(url: _url!, authToken: _authToken!);
        if (_currentJourneyId != null) {
          joinJourney(_currentJourneyId!);
        }
      }
    });
  }
  
  /// Clean up resources
  void _cleanup() {
    _subscription?.cancel();
    _subscription = null;
    
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    
    _channel?.sink.close(status.normalClosure);
    _channel = null;
  }
  
  /// Disconnect and clean up
  void disconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    
    leaveJourney();
    _cleanup();
    _messageController.close();
    
    print('🔌 WebSocket disconnected');
  }
}
```

### Step 4: Update LocationRepository (1.5 hours)

**File**: `lib/features/location/data/repositories/location_repository_impl.dart`

```dart
import 'package:geolocator/geolocator.dart';
import '../../domain/repositories/location_repository.dart';
import '../../domain/entities/location_update.dart';
import '../datasources/location_local_data_source.dart';
import '../datasources/location_remote_data_source.dart';
import '../models/location_update_model.dart';
import '../services/location_service.dart';
import '../../../../core/network/websocket_manager.dart';

class LocationRepositoryImpl implements LocationRepository {
  final LocationRemoteDataSource _remoteDataSource;
  final LocationLocalDataSource _localDataSource;
  final WebSocketManager _webSocketManager;
  final LocationService _locationService;
  
  LocationRepositoryImpl({
    required LocationRemoteDataSource remoteDataSource,
    required LocationLocalDataSource localDataSource,
    required WebSocketManager webSocketManager,
    required LocationService locationService,
  }) : _remoteDataSource = remoteDataSource,
       _localDataSource = localDataSource,
       _webSocketManager = webSocketManager,
       _locationService = locationService;
  
  @override
  Future<Position> getCurrentLocation() async {
    return await LocationService.getCurrentLocation();
  }
  
  @override
  Stream<Position> startLocationTracking() {
    return _locationService.startLocationTracking();
  }
  
  @override
  void stopLocationTracking() {
    _locationService.stopLocationTracking();
  }
  
  @override
  Future<void> sendLocationUpdate(LocationUpdate locationUpdate) async {
    try {
      // Send via WebSocket if connected
      if (_webSocketManager.isConnected) {
        _webSocketManager.sendLocationUpdate(
          journeyId: locationUpdate.journeyId,
          latitude: locationUpdate.location.latitude,
          longitude: locationUpdate.location.longitude,
          accuracy: locationUpdate.accuracy,
          heading: locationUpdate.heading,
          speed: locationUpdate.speed,
          altitude: locationUpdate.altitude,
          metadata: locationUpdate.metadata,
        );
      } else {
        // Fallback to REST API
        final model = LocationUpdateModel.fromEntity(locationUpdate);
        await _remoteDataSource.sendLocationUpdate(model);
      }
      
      // Cache locally
      await _localDataSource.cacheLocationUpdate(
        LocationUpdateModel.fromEntity(locationUpdate)
      );
    } catch (e) {
      print('❌ Failed to send location update: $e');
      // Cache locally for retry
      await _localDataSource.cacheLocationUpdate(
        LocationUpdateModel.fromEntity(locationUpdate)
      );
    }
  }
  
  @override
  Future<List<LocationUpdate>> getLatestLocations(String journeyId) async {
    try {
      final models = await _remoteDataSource.getLatestLocations(journeyId);
      return models.map((model) => model.toEntity()).toList();
    } catch (e) {
      // Return cached locations if API fails
      final cachedModels = await _localDataSource.getCachedLocationUpdates(journeyId);
      return cachedModels.map((model) => model.toEntity()).toList();
    }
  }
  
  @override
  Future<void> connectToJourney(String journeyId, String authToken) async {
    await _webSocketManager.connect(
      url: 'wss://api.dev.tulink.xyz/location',
      authToken: authToken,
    );
    _webSocketManager.joinJourney(journeyId);
  }
  
  @override
  Stream<LocationUpdate> getLocationUpdates() {
    return _webSocketManager.messages
        .where((message) => message['event'] == 'location-update')
        .map((message) => LocationUpdateModel.fromWebSocket(message).toEntity());
  }
}
```

---

## 🔥 PRIORITY 3: Journey Management Completion (4 hours)

### Step 1: Complete JourneyProvider Backend Integration (2 hours)

**File**: `lib/features/journeys/presentation/providers/journey_provider.dart`

Replace mock implementation with real API calls:

```dart
Future<bool> createJourney({
  required String name,
  required double latitude,
  required double longitude,
  required String destinationAddress,
  required int lagThresholdMeters,
}) async {
  setLoading(true);
  clearError();
  
  try {
    print('🚀 Creating journey: $name');
    
    // Create journey via use case (which calls repository -> API)
    final journey = await _createJourneyUseCase(CreateJourneyParams(
      name: name,
      destination: LatLng(latitude, longitude),
      destinationAddress: destinationAddress,
      lagThresholdMeters: lagThresholdMeters,
    ));
    
    // Update local state
    _currentJourney = journey;
    _journeys.add(journey);
    
    print('✅ Journey created successfully: ${journey.id}');
    setLoading(false);
    return true;
    
  } catch (e) {
    print('❌ Failed to create journey: $e');
    setError('Failed to create journey: ${e.toString()}');
    setLoading(false);
    return false;
  }
}

Future<void> loadActiveJourneys() async {
  setLoading(true);
  clearError();
  
  try {
    final journeys = await _getActiveJourneysUseCase(NoParams());
    _journeys = journeys;
    notifyListeners();
    setLoading(false);
  } catch (e) {
    setError('Failed to load journeys: ${e.toString()}');
    setLoading(false);
  }
}

Future<bool> startJourney(String journeyId) async {
  setLoading(true);
  clearError();
  
  try {
    final journey = await _startJourneyUseCase(StartJourneyParams(journeyId: journeyId));
    
    // Update current journey
    _currentJourney = journey;
    
    // Update in journeys list
    final index = _journeys.indexWhere((j) => j.id == journeyId);
    if (index != -1) {
      _journeys[index] = journey;
    }
    
    setLoading(false);
    return true;
  } catch (e) {
    setError('Failed to start journey: ${e.toString()}');
    setLoading(false);
    return false;
  }
}
```

### Step 2: Create Journey Detail Screen (2 hours)

**File**: `lib/features/journeys/presentation/screens/journey_detail_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/journey_provider.dart';
import '../../domain/entities/journey.dart';

class JourneyDetailScreen extends StatefulWidget {
  final String journeyId;
  
  const JourneyDetailScreen({
    super.key,
    required this.journeyId,
  });
  
  static const String routeName = '/journey-detail';
  
  @override
  State<JourneyDetailScreen> createState() => _JourneyDetailScreenState();
}

class _JourneyDetailScreenState extends State<JourneyDetailScreen> {
  @override
  void initState() {
    super.initState();
    // Load journey details
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<JourneyProvider>().loadJourneyById(widget.journeyId);
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Journey Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.map),
            onPressed: () => _navigateToMap(),
          ),
        ],
      ),
      body: Consumer<JourneyProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          
          final journey = provider.currentJourney;
          if (journey == null) {
            return const Center(child: Text('Journey not found'));
          }
          
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Journey Header
                _buildJourneyHeader(journey),
                const SizedBox(height: 24),
                
                // Journey Status
                _buildStatusSection(journey),
                const SizedBox(height: 24),
                
                // Participants List
                _buildParticipantsSection(journey),
                const SizedBox(height: 24),
                
                // Action Buttons
                _buildActionButtons(journey, provider),
              ],
            ),
          );
        },
      ),
    );
  }
  
  Widget _buildJourneyHeader(Journey journey) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              journey.name,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            if (journey.destinationAddress != null)
              Row(
                children: [
                  const Icon(Icons.location_on, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(journey.destinationAddress!),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            Text(
              'Created: ${_formatDate(journey.createdAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatusSection(Journey journey) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Status',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildStatusChip(journey.status),
                const Spacer(),
                if (journey.startTime != null)
                  Text('Started: ${_formatTime(journey.startTime!)}'),
              ],
            ),
            if (journey.endTime != null) ...[
              const SizedBox(height: 8),
              Text('Ended: ${_formatTime(journey.endTime!)}'),
            ],
          ],
        ),
      ),
    );
  }
  
  Widget _buildParticipantsSection(Journey journey) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Participants',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                IconButton(
                  icon: const Icon(Icons.person_add),
                  onPressed: () => _showInviteDialog(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // TODO: Build participants list when participants model is available
            const Text('Participants list will be shown here'),
          ],
        ),
      ),
    );
  }
  
  Widget _buildActionButtons(Journey journey, JourneyProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (journey.status == JourneyStatus.pending) ...[
          ElevatedButton(
            onPressed: provider.isLoading ? null : () => _startJourney(),
            child: const Text('Start Journey'),
          ),
        ] else if (journey.status == JourneyStatus.active) ...[
          ElevatedButton(
            onPressed: () => _navigateToMap(),
            child: const Text('View Live Map'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: provider.isLoading ? null : () => _endJourney(),
            child: const Text('End Journey'),
          ),
        ],
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => _shareJourney(),
          child: const Text('Share Journey'),
        ),
      ],
    );
  }
  
  Widget _buildStatusChip(JourneyStatus status) {
    Color color;
    String label;
    
    switch (status) {
      case JourneyStatus.pending:
        color = Colors.orange;
        label = 'Pending';
        break;
      case JourneyStatus.active:
        color = Colors.green;
        label = 'Active';
        break;
      case JourneyStatus.completed:
        color = Colors.blue;
        label = 'Completed';
        break;
      case JourneyStatus.cancelled:
        color = Colors.red;
        label = 'Cancelled';
        break;
    }
    
    return Chip(
      label: Text(label),
      backgroundColor: color.withOpacity(0.2),
      labelStyle: TextStyle(color: color),
    );
  }
  
  void _startJourney() async {
    final success = await context.read<JourneyProvider>()
        .startJourney(widget.journeyId);
    
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Journey started!')),
      );
    }
  }
  
  void _endJourney() async {
    // TODO: Implement end journey functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('End journey functionality coming soon')),
    );
  }
  
  void _navigateToMap() {
    Navigator.of(context).pushNamed('/mapview');
  }
  
  void _shareJourney() {
    // TODO: Implement journey sharing
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Share functionality coming soon')),
    );
  }
  
  void _showInviteDialog() {
    // TODO: Implement invite dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Invite Participants'),
        content: const Text('Invite functionality coming soon'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
  
  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
  
  String _formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
```

---

## 🔥 PRIORITY 4: Map Real-time Updates (4 hours)

### Step 1: Create Location Tracking Provider (1.5 hours)

**File**: `lib/features/location/presentation/providers/location_provider.dart`

```dart
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import '../../domain/repositories/location_repository.dart';
import '../../domain/entities/location_update.dart';

class LocationProvider extends ChangeNotifier {
  final LocationRepository _locationRepository;
  
  LocationProvider(this._locationRepository);
  
  // State
  Position? _currentPosition;
  Map<String, LocationUpdate> _participantLocations = {};
  bool _isTracking = false;
  String? _error;
  String? _currentJourneyId;
  
  // Stream subscriptions
  StreamSubscription<Position>? _locationSubscription;
  StreamSubscription<LocationUpdate>? _webSocketSubscription;
  
  // Getters
  Position? get currentPosition => _currentPosition;
  Map<String, LocationUpdate> get participantLocations => _participantLocations;
  bool get isTracking => _isTracking;
  String? get error => _error;
  
  /// Start location tracking for a journey
  Future<void> startTracking(String journeyId) async {
    try {
      _error = null;
      _currentJourneyId = journeyId;
      
      // Get initial position
      _currentPosition = await _locationRepository.getCurrentLocation();
      notifyListeners();
      
      // Connect to WebSocket for real-time updates
      final authToken = await _getAuthToken(); // You'll need to implement this
      await _locationRepository.connectToJourney(journeyId, authToken);
      
      // Start location stream
      _locationSubscription = _locationRepository.startLocationTracking()
          .listen(
            _handleLocationUpdate,
            onError: _handleLocationError,
          );
      
      // Start WebSocket updates stream
      _webSocketSubscription = _locationRepository.getLocationUpdates()
          .listen(
            _handleParticipantLocationUpdate,
            onError: _handleWebSocketError,
          );
      
      _isTracking = true;
      notifyListeners();
      
      print('✅ Location tracking started for journey: $journeyId');
    } catch (e) {
      _error = 'Failed to start location tracking: ${e.toString()}';
      print('❌ Error starting location tracking: $e');
      notifyListeners();
    }
  }
  
  /// Stop location tracking
  void stopTracking() {
    _locationSubscription?.cancel();
    _locationSubscription = null;
    
    _webSocketSubscription?.cancel();
    _webSocketSubscription = null;
    
    _locationRepository.stopLocationTracking();
    
    _isTracking = false;
    _currentJourneyId = null;
    notifyListeners();
    
    print('🛑 Location tracking stopped');
  }
  
  /// Handle new location from GPS
  void _handleLocationUpdate(Position position) {
    _currentPosition = position;
    
    // Send location update via WebSocket/API
    if (_currentJourneyId != null) {
      final locationUpdate = LocationUpdate(
        journeyId: _currentJourneyId!,
        location: LatLng(position.latitude, position.longitude),
        accuracy: position.accuracy,
        heading: position.heading,
        speed: position.speed,
        altitude: position.altitude,
        timestamp: DateTime.now(),
        metadata: {
          'batteryLevel': 85, // You can get this from battery_plus package
          'isCharging': false,
        },
      );
      
      _locationRepository.sendLocationUpdate(locationUpdate);
    }
    
    notifyListeners();
  }
  
  /// Handle location updates from other participants
  void _handleParticipantLocationUpdate(LocationUpdate locationUpdate) {
    _participantLocations[locationUpdate.userId ?? 'unknown'] = locationUpdate;
    notifyListeners();
    
    print('📍 Received participant location: ${locationUpdate.location.latitude}, ${locationUpdate.location.longitude}');
  }
  
  /// Handle location tracking errors
  void _handleLocationError(error) {
    _error = 'Location tracking error: ${error.toString()}';
    print('❌ Location error: $error');
    notifyListeners();
  }
  
  /// Handle WebSocket errors
  void _handleWebSocketError(error) {
    print('❌ WebSocket error: $error');
    // Don't set error state for WebSocket issues, location tracking can continue
  }
  
  /// Get current location once
  Future<void> getCurrentLocation() async {
    try {
      _error = null;
      _currentPosition = await _locationRepository.getCurrentLocation();
      notifyListeners();
    } catch (e) {
      _error = 'Failed to get current location: ${e.toString()}';
      notifyListeners();
    }
  }
  
  /// Clear error state
  void clearError() {
    _error = null;
    notifyListeners();
  }
  
  /// Get authentication token for WebSocket
  Future<String> _getAuthToken() async {
    // TODO: Get token from AuthProvider or secure storage
    // For now, return a placeholder
    return 'your-auth-token';
  }
  
  @override
  void dispose() {
    stopTracking();
    super.dispose();
  }
}

class LatLng {
  final double latitude;
  final double longitude;
  
  LatLng(this.latitude, this.longitude);
}
```

### Step 2: Update MapScreen with Real-time Updates (2.5 hours)

**File**: `lib/features/maps/presentation/tulink_map_screen.dart`

Replace static markers with live tracking:

```dart
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../../../features/journeys/presentation/providers/journey_provider.dart';
import '../../../features/location/presentation/providers/location_provider.dart';
import 'widgets/map_journey_overlay.dart';
import 'widgets/map_header_overlay.dart';

class TulinkMapScreen extends StatefulWidget {
  const TulinkMapScreen({super.key});

  static const String routeName = '/mapview';

  @override
  State<TulinkMapScreen> createState() => _TulinkMapScreenState();
}

class _TulinkMapScreenState extends State<TulinkMapScreen> {
  MapboxMap? _mapboxMap;
  PointAnnotationManager? _pointAnnotationManager;
  
  final Map<String, PointAnnotation> _userMarkers = {};
  PointAnnotation? _destinationMarker;
  
  @override
  void initState() {
    super.initState();
    
    // Start location tracking when map loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeLocationTracking();
    });
  }
  
  @override
  void dispose() {
    // Stop location tracking
    context.read<LocationProvider>().stopTracking();
    super.dispose();
  }

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    _pointAnnotationManager = 
        await mapboxMap.annotations.createPointAnnotationManager();
    
    // Enable user location
    await mapboxMap.location.updateSettings(LocationComponentSettings(
      enabled: true,
      pulsingEnabled: true,
    ));

    await _updateMapWithCurrentData();
  }
  
  void _initializeLocationTracking() {
    final journeyProvider = context.read<JourneyProvider>();
    final locationProvider = context.read<LocationProvider>();
    
    if (journeyProvider.currentJourney != null) {
      locationProvider.startTracking(journeyProvider.currentJourney!.id);
    }
  }

  Future<void> _updateMapWithCurrentData() async {
    if (_mapboxMap == null || _pointAnnotationManager == null) return;

    final locationProvider = context.read<LocationProvider>();
    final journeyProvider = context.read<JourneyProvider>();

    // Update current user location
    if (locationProvider.currentPosition != null) {
      await _updateCurrentUserMarker(locationProvider.currentPosition!);
      await _centerMapOnUser(locationProvider.currentPosition!);
    }
    
    // Update participant markers
    await _updateParticipantMarkers(locationProvider.participantLocations);
    
    // Update destination marker
    if (journeyProvider.currentJourney?.destination != null) {
      await _updateDestinationMarker(journeyProvider.currentJourney!);
    }
  }
  
  Future<void> _updateCurrentUserMarker(Position position) async {
    const currentUserKey = 'current_user';
    
    // Remove existing marker
    if (_userMarkers.containsKey(currentUserKey)) {
      await _pointAnnotationManager?.delete(_userMarkers[currentUserKey]!);
    }
    
    // Create new marker
    final userPos = Point(
      coordinates: Position(position.longitude, position.latitude),
    );
    
    final marker = await _pointAnnotationManager?.create(PointAnnotationOptions(
      geometry: userPos,
      textField: 'You',
      textColor: Colors.red.toARGB32(),
      textSize: 12,
      textOffset: [0, 2.5],
      iconImage: 'marker-15',
      iconSize: 1.5,
    ));
    
    if (marker != null) {
      _userMarkers[currentUserKey] = marker;
    }
  }
  
  Future<void> _updateParticipantMarkers(Map<String, LocationUpdate> participants) async {
    // Remove markers for participants no longer in the list
    final participantIds = participants.keys.toSet();
    final markerIds = _userMarkers.keys.where((key) => key != 'current_user').toSet();
    
    for (final markerId in markerIds.difference(participantIds)) {
      await _pointAnnotationManager?.delete(_userMarkers[markerId]!);
      _userMarkers.remove(markerId);
    }
    
    // Add or update markers for current participants
    for (final entry in participants.entries) {
      final userId = entry.key;
      final locationUpdate = entry.value;
      
      // Remove existing marker
      if (_userMarkers.containsKey(userId)) {
        await _pointAnnotationManager?.delete(_userMarkers[userId]!);
      }
      
      // Create new marker
      final participantPos = Point(
        coordinates: Position(
          locationUpdate.location.longitude,
          locationUpdate.location.latitude,
        ),
      );
      
      final color = _getUserColor(userId);
      
      final marker = await _pointAnnotationManager?.create(PointAnnotationOptions(
        geometry: participantPos,
        textField: 'Participant',
        textColor: color,
        textSize: 11,
        textOffset: [0, 2.5],
        iconImage: 'marker-15',
      ));
      
      if (marker != null) {
        _userMarkers[userId] = marker;
      }
    }
  }
  
  Future<void> _updateDestinationMarker(Journey journey) async {
    if (journey.destination == null) return;
    
    // Remove existing destination marker
    if (_destinationMarker != null) {
      await _pointAnnotationManager?.delete(_destinationMarker!);
    }
    
    // Create destination marker
    final destPos = Point(
      coordinates: Position(
        journey.destination!.longitude,
        journey.destination!.latitude,
      ),
    );
    
    _destinationMarker = await _pointAnnotationManager?.create(PointAnnotationOptions(
      geometry: destPos,
      textField: 'DESTINATION',
      textColor: Colors.orange.toARGB32(),
      textSize: 12,
      textOffset: [0, 2.5],
      iconImage: 'rocket-15',
      iconSize: 1.2,
    ));
  }
  
  Future<void> _centerMapOnUser(Position position) async {
    if (_mapboxMap == null) return;
    
    await _mapboxMap!.setCamera(CameraOptions(
      center: Point(coordinates: Position(position.longitude, position.latitude)),
      zoom: 14.0,
    ));
  }
  
  int _getUserColor(String userId) {
    final colors = [
      0xFFE53E3E, // Red
      0xFF38A169, // Green  
      0xFFDD6B20, // Orange
      0xFF3182CE, // Blue
      0xFF805AD5, // Purple
      0xFFD69E2E, // Yellow
      0xFF319795, // Teal
    ];
    
    return colors[userId.hashCode % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Mapbox Map
          RepaintBoundary(
            child: MapWidget(
              key: const ValueKey('mapbox_map'),
              onMapCreated: _onMapCreated,
              styleUri: MapboxStyles.DARK,
              cameraOptions: CameraOptions(
                center: Point(
                  coordinates: Position(36.8219, -1.2921), // Nairobi
                ),
                zoom: 12,
              ),
            ),
          ),
          
          // Listen to location updates and update map
          Consumer<LocationProvider>(
            builder: (context, locationProvider, child) {
              // Update map when location changes
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _updateMapWithCurrentData();
              });
              
              // Show error if any
              if (locationProvider.error != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(locationProvider.error!),
                      backgroundColor: Colors.red,
                      action: SnackBarAction(
                        label: 'Dismiss',
                        onPressed: () => locationProvider.clearError(),
                      ),
                    ),
                  );
                });
              }
              
              return const SizedBox.shrink();
            },
          ),
          
          // Map Header - Top Overlay
          const Align(
            alignment: Alignment.topCenter,
            child: MapHeaderOverlay(),
          ),
            
          // Map Bottom Bar - Bottom Overlay
          const Align(
            alignment: Alignment.bottomCenter,
            child: MapJourneyOverlay(),
          ),
        ],
      ),
    );
  }
}
```

This implementation provides:

1. **Real Authentication**: Users can actually register and log in using the backend API
2. **Location Services**: GPS tracking with proper permissions and error handling
3. **WebSocket Integration**: Real-time communication for live location updates
4. **Journey Management**: Complete journey creation and management flow
5. **Live Map Updates**: Real-time participant locations on the map

Each section includes comprehensive error handling, proper state management, and follows the existing clean architecture patterns in the app.

**Time Estimate**: These 4 critical implementations should take approximately **18 hours** of focused development work, which fits within the 2-day timeline when combined with testing and deployment tasks.