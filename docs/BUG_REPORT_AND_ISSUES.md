# TuLink Flutter App - Bug Report & Critical Issues

## Critical Issues (Priority 1 - Must Fix Immediately)

### 🚨 **CRITICAL-001: Authentication System Not Connected to Backend**

**Severity**: Critical  
**Impact**: Core app functionality broken  
**Location**: `lib/features/auth/presentation/providers/auth_provider.dart`

**Issue Description**:
The authentication system is currently using mock implementations. Users cannot actually register or log in to the application.

**Current Code**:
```dart
// AuthProvider.signIn() is calling repository but repository isn't hitting real API
final result = await _authRepository.signIn(email: email, password: password);
```

**Evidence**:
- Login always succeeds regardless of credentials
- No actual HTTP requests to backend API
- User data is not persisting between app sessions

**Root Cause**:
`AuthRepositoryImpl` is not properly integrated with `AuthApiService` to make actual HTTP calls to `https://api.dev.tulink.xyz`

**Fix Required**:
```dart
// In AuthRepositoryImpl
@override
Future<AuthResult> signIn({required String email, required String password}) async {
  try {
    final response = await _authApiService.login(LoginRequest(
      email: email,
      password: password,
    ));
    
    if (response.success && response.data != null) {
      final userModel = response.data!.user;
      await _localDataSource.cacheUser(userModel);
      return AuthResult(user: userModel.toEntity());
    } else {
      return AuthResult(failure: AuthFailure(message: response.message));
    }
  } catch (e) {
    return AuthResult(failure: NetworkFailure(message: 'Login failed'));
  }
}
```

---

### 🚨 **CRITICAL-002: No Real Location Tracking**

**Severity**: Critical  
**Impact**: Primary app feature non-functional  
**Location**: `lib/features/location/`

**Issue Description**:
The app displays static markers on the map but doesn't track actual user locations or provide real-time updates.

**Current Code**:
```dart
// In TulinkMapScreen - using hardcoded sample data
final sampleUsers = [
  {'name': 'John Doe', 'lat': -1.2921, 'lng': 36.8219, 'isMe': true},
  // ... more hardcoded users
];
```

**Evidence**:
- Map shows static sample markers
- No GPS permission requests
- No location services integration
- No real-time updates

**Root Cause**:
1. No GPS location services implemented
2. No WebSocket connection for real-time updates
3. Location repository not connected to actual hardware

**Fix Required**:
1. Add `geolocator` package for GPS access
2. Implement location permissions
3. Create WebSocket connection for real-time updates
4. Update map markers with live location data

---

### 🚨 **CRITICAL-003: Journey Creation Doesn't Persist**

**Severity**: Critical  
**Impact**: Core user flow broken  
**Location**: `lib/features/journeys/presentation/providers/journey_provider.dart`

**Issue Description**:
Created journeys are not saved to backend or local storage. Journey data is lost after app restart.

**Current Code**:
```dart
Future<bool> createJourney({...}) async {
  // This creates journey but doesn't save it anywhere persistent
  final journey = Journey(...);
  _currentJourney = journey;
  notifyListeners();
  return true; // Always returns success
}
```

**Evidence**:
- Journey creation form works but data disappears
- No API calls to backend journey creation endpoint
- No local persistence of journey data
- App restart loses all journey information

**Root Cause**:
JourneyProvider creates journey objects but doesn't call the repository to persist them via API or local storage.

**Fix Required**:
```dart
Future<bool> createJourney({...}) async {
  try {
    final createRequest = CreateJourneyRequest(
      name: name,
      destination: LatLng(latitude, longitude),
      destinationAddress: destinationAddress,
      lagThresholdMeters: lagThresholdMeters,
    );
    
    final journey = await _createJourneyUseCase(createRequest);
    _currentJourney = journey;
    _journeys.add(journey);
    notifyListeners();
    return true;
  } catch (e) {
    _error = e.toString();
    notifyListeners();
    return false;
  }
}
```

---

### 🚨 **CRITICAL-004: WebSocket Not Implemented**

**Severity**: Critical  
**Impact**: Real-time features impossible  
**Location**: `lib/core/network/`

**Issue Description**:
The app has no WebSocket implementation for real-time communication, making live location tracking impossible.

**Evidence**:
- No WebSocket client in the codebase
- Real-time features mentioned in docs but not implemented
- Map doesn't update with live participant locations

**Root Cause**:
WebSocket integration with backend (`wss://api.dev.tulink.xyz/location`) is completely missing.

**Fix Required**:
Create WebSocket service for real-time communication:
```dart
class WebSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  
  Future<void> connect(String journeyId) async {
    final token = await _getAuthToken();
    _channel = WebSocketChannel.connect(
      Uri.parse('wss://api.dev.tulink.xyz/location'),
      protocols: ['Bearer', token],
    );
    
    _subscription = _channel!.stream.listen(
      _handleMessage,
      onError: _handleError,
      onDone: _handleClose,
    );
    
    // Join journey room
    _channel!.sink.add(jsonEncode({
      'event': 'join-journey',
      'journeyId': journeyId,
    }));
  }
}
```

---

## High Priority Issues (Priority 2 - Fix Within Day 1)

### ⚠️ **HIGH-001: Missing Location Permissions**

**Severity**: High  
**Impact**: Location features will crash on first use  
**Location**: Platform-specific permission handling

**Issue Description**:
App doesn't request location permissions, which will cause crashes when trying to access GPS.

**Fix Required**:
1. Add permission handling in `AndroidManifest.xml` and `Info.plist`
2. Implement runtime permission requests
3. Handle permission denial gracefully

---

### ⚠️ **HIGH-002: No Error Handling for Network Failures**

**Severity**: High  
**Impact**: App crashes on network errors  
**Location**: `lib/core/network/dio_client.dart`

**Issue Description**:
Network errors are not properly caught and displayed to users.

**Current Code**:
```dart
// DioClient has basic setup but no comprehensive error handling
class DioClient {
  late Dio _dio;
  // Missing error interceptors for network failures
}
```

**Fix Required**:
Add comprehensive error interceptors and user-friendly error messages.

---

### ⚠️ **HIGH-003: Memory Leaks in Map Implementation**

**Severity**: High  
**Impact**: App performance degrades over time  
**Location**: `lib/features/maps/presentation/tulink_map_screen.dart`

**Issue Description**:
Map markers and controllers are not properly disposed, causing memory leaks.

**Fix Required**:
Implement proper cleanup in dispose methods for all map resources.

---

### ⚠️ **HIGH-004: Missing Push Notification Setup**

**Severity**: High  
**Impact**: Users won't receive journey notifications  
**Location**: Firebase configuration missing

**Issue Description**:
Firebase Cloud Messaging is not configured for the app.

**Fix Required**:
1. Add Firebase configuration files
2. Implement FCM service
3. Register for notifications
4. Handle notification routing

---

## Medium Priority Issues (Priority 3 - Fix Within Day 2)

### ⚠️ **MEDIUM-001: Incomplete Journey Invitation Flow**

**Severity**: Medium  
**Impact**: Social features non-functional  
**Location**: Journey management screens

**Issue Description**:
Users can't invite others to join journeys or accept invitations.

**Fix Required**:
Implement participant invitation UI and backend integration.

---

### ⚠️ **MEDIUM-002: Missing User Profile Screen**

**Severity**: Medium  
**Impact**: Users can't manage their account  
**Location**: Navigation missing profile route

**Issue Description**:
No user profile screen exists for account management.

**Fix Required**:
Create profile screen with user info display and edit capabilities.

---

### ⚠️ **MEDIUM-003: No Offline Capability**

**Severity**: Medium  
**Impact**: App unusable without internet  
**Location**: All API-dependent features

**Issue Description**:
App doesn't cache data for offline use.

**Fix Required**:
Implement local caching strategies for critical data.

---

### ⚠️ **MEDIUM-004: Performance Issues on Map Rendering**

**Severity**: Medium  
**Impact**: Poor user experience on lower-end devices  
**Location**: Map marker handling

**Issue Description**:
Map re-renders all markers on every location update instead of updating individual markers.

**Fix Required**:
Optimize marker updates to only modify changed markers.

---

## Low Priority Issues (Priority 4 - Post-MVP)

### ⚠️ **LOW-001: Missing Journey History**

**Severity**: Low  
**Impact**: Users lose track of past journeys  

**Fix Required**:
Add journey history screen and data persistence.

---

### ⚠️ **LOW-002: No Settings Screen**

**Severity**: Low  
**Impact**: Users can't customize app behavior  

**Fix Required**:
Create settings screen with user preferences.

---

### ⚠️ **LOW-003: Limited Error Messages**

**Severity**: Low  
**Impact**: Poor user experience during errors  

**Fix Required**:
Improve error message specificity and user guidance.

---

## Platform-Specific Issues

### **iOS Issues**

1. **iOS-001**: Missing location permission description in Info.plist
2. **iOS-002**: App icons missing for all required sizes
3. **iOS-003**: Launch screen needs TuLink branding

### **Android Issues**

1. **ANDROID-001**: Missing location permissions in AndroidManifest.xml
2. **ANDROID-002**: App icons missing for all densities
3. **ANDROID-003**: Splash screen needs implementation
4. **ANDROID-004**: Build configuration incomplete for release builds

---

## Build & Configuration Issues

### **BUILD-001: Missing Release Build Configuration**

**Severity**: High  
**Impact**: Cannot create production builds for store submission

**Current State**:
- No release build configuration
- Missing ProGuard rules
- No build optimization

**Fix Required**:
Configure Android release builds with proper optimization and signing.

---

### **BUILD-002: Missing Store Assets**

**Severity**: Medium  
**Impact**: Cannot submit to app stores

**Missing Assets**:
- App icons (all sizes for iOS and Android)
- Store screenshots
- App descriptions
- Privacy policy

---

### **BUILD-003: Environment Configuration Issues**

**Severity**: Medium  
**Impact**: API keys and endpoints not properly configured

**Issues**:
- `.env` file not properly loaded in production builds
- API keys hardcoded in some files
- Environment switching not working

---

## Security Issues

### **SECURITY-001: Insecure Token Storage**

**Severity**: High  
**Impact**: Authentication tokens could be compromised

**Issue**: Tokens are stored in regular shared preferences instead of secure storage.

---

### **SECURITY-002: API Keys in Source Code**

**Severity**: Medium  
**Impact**: API keys could be extracted from app

**Issue**: Some API keys are hardcoded in source files instead of environment configuration.

---

## Performance Issues

### **PERF-001: Inefficient State Management**

**Severity**: Medium  
**Impact**: Unnecessary UI rebuilds

**Issue**: Providers are notifying listeners too frequently, causing performance issues.

---

### **PERF-002: Large App Bundle Size**

**Severity**: Low  
**Impact**: Longer download times

**Issue**: Unused dependencies and resources increasing bundle size.

---

## Testing Issues

### **TEST-001: Minimal Test Coverage**

**Severity**: Medium  
**Impact**: High risk of regressions

**Current State**: Only basic widget test exists, no comprehensive testing.

---

### **TEST-002: No Integration Tests**

**Severity**: Medium  
**Impact**: End-to-end user flows not tested

**Missing**: Integration tests for critical user journeys.

---

## Recommended Fix Sequence

### **Day 1 Critical Path**:
1. Fix CRITICAL-001 (Authentication)
2. Fix CRITICAL-003 (Journey persistence)
3. Fix HIGH-001 (Location permissions)
4. Fix CRITICAL-002 (Location tracking basics)

### **Day 1 Secondary**:
5. Fix HIGH-002 (Error handling)
6. Fix CRITICAL-004 (WebSocket basics)
7. Fix BUILD-001 (Release builds)

### **Day 2 Critical Path**:
8. Complete CRITICAL-004 (WebSocket integration)
9. Fix HIGH-004 (Push notifications)
10. Fix BUILD-002 (Store assets)
11. Complete testing and deployment preparation

This prioritized bug fix sequence ensures the most critical user-facing issues are resolved first, followed by deployment blockers, and finally polish items.