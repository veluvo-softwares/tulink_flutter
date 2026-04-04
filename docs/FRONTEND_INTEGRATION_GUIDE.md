# TuLink Frontend Integration Guide

## Table of Contents
1. [API Documentation](#api-documentation)
2. [Data Models (TypeScript & Dart)](#data-models)
3. [Screen-to-API Mapping](#screen-to-api-mapping)
4. [State Management Guide](#state-management-guide)
5. [Error Handling Patterns](#error-handling-patterns)
6. [Performance Optimization](#performance-optimization)
7. [Security Best Practices](#security-best-practices)
8. [Testing Strategy](#testing-strategy)
9. [Environment Configuration](#environment-configuration)
10. [Code Templates & Examples](#code-templates--examples)

---

## 1. API Documentation

### Base Configuration
- **Development**: `https://api.dev.tulink.xyz`
- **WebSocket**: `ws://localhost:3000/location` (dev) / `wss://api.tulink.com/location` (prod)

### Authentication
All protected endpoints require a Bearer token:
```
Authorization: Bearer <firebase-id-token>
```

### Response Format
**Success Response:**
```json
{
  "success": true,
  "statusCode": 200,
  "message": "Operation completed successfully",
  "data": { ... }
}
```

**Error Response:**
```json
{
  "success": false,
  "statusCode": 400,
  "message": "Validation failed",
  "error": {
    "code": "VALIDATION_ERROR",
    "details": [ ... ]
  }
}
```

---

### Auth Service

#### POST /auth/register
**Purpose**: Register a new user account

**Request:**
```typescript
POST /auth/register
Content-Type: application/json

{
  "email": "user@example.com",          // Required, valid email
  "password": "securepass123",          // Required, minimum 6 characters
  "displayName": "John Doe",            // Required
  "phoneNumber": "+254712345678"        // Optional, E.164 format
}
```

**Success Response (201):**
```json
{
  "success": true,
  "statusCode": 201,
  "message": "User registered successfully",
  "data": {
    "user": {
      "id": "firebase-uid-123",
      "email": "user@example.com",
      "displayName": "John Doe",
      "phoneNumber": "+254712345678",
      "createdAt": "2026-03-26T10:30:00.000Z",
      "updatedAt": "2026-03-26T10:30:00.000Z"
    },
    "tokens": {
      "idToken": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
      "refreshToken": "AMf-vBwQKOWxZBZKYfIuUgKcpCQqj...",
      "expiresIn": "3600"
    }
  }
}
```

**Error Responses:**
- **400**: Phone number format invalid
- **409**: Email or phone already in use

#### POST /auth/login
**Purpose**: Authenticate existing user

**Request:**
```typescript
POST /auth/login
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "securepass123"
}
```

**Success Response (200):**
```json
{
  "success": true,
  "statusCode": 200,
  "data": {
    "user": { ... },
    "tokens": {
      "idToken": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
      "refreshToken": "AMf-vBwQKOWxZBZKYfIuUgKcpCQqj...",
      "expiresIn": "3600"
    }
  }
}
```

#### POST /auth/refresh
**Purpose**: Refresh expired ID token

**Request:**
```typescript
POST /auth/refresh
Content-Type: application/json

{
  "refreshToken": "AMf-vBwQKOWxZBZKYfIuUgKcpCQqj..."
}
```

#### GET /auth/profile
**Purpose**: Get current user profile
**Authentication**: Required

**Success Response (200):**
```json
{
  "success": true,
  "data": {
    "id": "firebase-uid-123",
    "email": "user@example.com",
    "displayName": "John Doe",
    "phoneNumber": "+254712345678",
    "createdAt": "2026-03-26T10:30:00.000Z",
    "updatedAt": "2026-03-26T10:30:00.000Z"
  }
}
```

#### PUT /auth/profile
**Purpose**: Update user profile
**Authentication**: Required

---

### Journey Service

#### POST /journeys
**Purpose**: Create a new journey
**Authentication**: Required

**Request:**
```typescript
POST /journeys
Authorization: Bearer <token>
Content-Type: application/json

{
  "name": "Weekend Road Trip",
  "destination": {
    "latitude": -1.2921,
    "longitude": 36.8219
  },
  "destinationAddress": "Nairobi KICC, Kenya",
  "lagThresholdMeters": 2000  // Optional, default: 1000m
}
```

**Success Response (201):**
```json
{
  "success": true,
  "statusCode": 201,
  "data": {
    "id": "journey-uuid-123",
    "name": "Weekend Road Trip",
    "leaderId": "firebase-uid-123",
    "status": "PENDING",
    "destination": {
      "latitude": -1.2921,
      "longitude": 36.8219
    },
    "destinationAddress": "Nairobi KICC, Kenya",
    "lagThresholdMeters": 2000,
    "createdAt": "2026-03-26T10:30:00.000Z",
    "updatedAt": "2026-03-26T10:30:00.000Z",
    "metadata": {
      "totalDistance": null,
      "estimatedDuration": null
    }
  }
}
```

#### GET /journeys/active
**Purpose**: Get user's active journeys
**Authentication**: Required

#### GET /journeys/:id
**Purpose**: Get journey details with participants
**Authentication**: Required (must be participant)

#### POST /journeys/:id/start
**Purpose**: Start journey (leader only)
**Authentication**: Required

#### POST /journeys/:id/end
**Purpose**: End journey (leader only)
**Authentication**: Required

#### POST /journeys/:id/invite
**Purpose**: Invite user to journey
**Authentication**: Required (leader only)

**Request:**
```typescript
POST /journeys/:id/invite
{
  "invitedUserId": "firebase-uid-456"
}
```

#### POST /journeys/:id/accept
**Purpose**: Accept journey invitation
**Authentication**: Required

#### POST /journeys/:id/decline
**Purpose**: Decline journey invitation
**Authentication**: Required

#### POST /journeys/:id/leave
**Purpose**: Leave journey (non-leaders only)
**Authentication**: Required

---

### Location Service

#### WebSocket Connection
**Namespace**: `/location`
**URL**: `ws://localhost:3000/location`

**Authentication:**
```javascript
const socket = io('http://localhost:3000/location', {
  auth: {
    token: 'your-firebase-id-token'
  }
});
```

**Events:**

**Client → Server:**
- `join-journey`: Join journey room
- `leave-journey`: Leave journey room
- `location-update`: Send location update
- `acknowledge`: Acknowledge received message
- `request-resync`: Request missing updates
- `heartbeat`: Keep connection alive

**Server → Client:**
- `connection-status`: Connection status updates
- `joined-journey`: Confirmation of joining journey
- `location-update`: Location update from participant
- `lag-alert`: Participant lagging behind
- `arrival-detected`: Participant reached destination
- `participant-joined`: New participant joined
- `participant-left`: Participant left journey

**Location Update Example:**
```typescript
// Client sends
socket.emit('location-update', {
  journeyId: 'journey-123',
  location: {
    latitude: -1.2921,
    longitude: 36.8219
  },
  accuracy: 10.5,
  heading: 45.0,
  speed: 25.5,
  altitude: 1661.2,
  metadata: {
    batteryLevel: 85,
    isCharging: false
  }
});

// Server broadcasts to journey participants
socket.on('location-update', (data) => {
  console.log('Location update:', data);
  // {
  //   userId: 'firebase-uid-123',
  //   participantId: 'firebase-uid-123',
  //   location: { latitude: -1.2921, longitude: 36.8219 },
  //   accuracy: 10.5,
  //   heading: 45.0,
  //   speed: 25.5,
  //   timestamp: 1711442200000,
  //   sequenceNumber: 12345,
  //   priority: 'NORMAL'
  // }
});
```

#### REST Fallback Endpoints

#### POST /locations
**Purpose**: REST fallback for location updates
**Authentication**: Required

**Request:**
```typescript
POST /locations
{
  "journeyId": "journey-123",
  "location": {
    "latitude": -1.2921,
    "longitude": 36.8219
  },
  "accuracy": 10.5,
  "heading": 45.0,
  "speed": 25.5,
  "altitude": 1661.2
}
```

#### GET /locations/journeys/:journeyId/latest
**Purpose**: Get latest locations for all participants
**Authentication**: Required

---

### Maps Service

#### GET /maps/search
**Purpose**: Search places using Google Places API
**Authentication**: Required

**Request:**
```typescript
GET /maps/search?query=KICC&lat=-1.2921&lng=36.8219
```

**Success Response:**
```json
{
  "success": true,
  "data": {
    "results": [
      {
        "place_id": "ChIJX6Y8KpAZLBgR...",
        "name": "Kenyatta International Conference Centre",
        "formatted_address": "Harambee Avenue, Nairobi, Kenya",
        "location": {
          "lat": -1.2921,
          "lng": 36.8219
        },
        "types": ["establishment", "point_of_interest"]
      }
    ]
  }
}
```

#### GET /maps/reverse
**Purpose**: Reverse geocode coordinates to address
**Authentication**: Required

**Request:**
```typescript
GET /maps/reverse?lat=-1.2921&lng=36.8219
```

---

### Notification Service

#### POST /notifications/fcm-token
**Purpose**: Register FCM token for push notifications
**Authentication**: Required

**Request:**
```typescript
POST /notifications/fcm-token
{
  "fcmToken": "dXNFc3NGTG1jeFE6QPA91bEhGdlK...",
  "platform": "android",
  "deviceId": "device-unique-id"
}
```

#### GET /notifications
**Purpose**: Get user notifications
**Authentication**: Required

#### GET /notifications/unread-count
**Purpose**: Get unread notification count
**Authentication**: Required

#### PUT /notifications/:id/read
**Purpose**: Mark notification as read
**Authentication**: Required

---

## 2. Data Models

### TypeScript Interfaces

```typescript
// User Model
interface User {
  id: string;
  email: string;
  displayName: string;
  phoneNumber?: string;
  createdAt: string; // ISO 8601
  updatedAt: string; // ISO 8601
}

// Journey Model
interface Journey {
  id: string;
  name: string;
  leaderId: string;
  status: JourneyStatus;
  startTime?: string; // ISO 8601
  endTime?: string; // ISO 8601
  destination?: GeoPoint;
  destinationAddress?: string;
  lagThresholdMeters: number;
  createdAt: string; // ISO 8601
  updatedAt: string; // ISO 8601
  metadata: {
    totalDistance?: number;
    estimatedDuration?: number;
  };
}

// Journey Status Enum
type JourneyStatus = 'PENDING' | 'ACTIVE' | 'COMPLETED' | 'CANCELLED';

// Participant Model
interface Participant {
  id: string;
  journeyId: string;
  userId: string;
  status: ParticipantStatus;
  isLeader: boolean;
  invitedAt: string; // ISO 8601
  joinedAt?: string; // ISO 8601
  connectionStatus?: ConnectionStatus;
}

type ParticipantStatus = 'INVITED' | 'ACCEPTED' | 'DECLINED' | 'ACTIVE' | 'LEFT';
type ConnectionStatus = 'CONNECTED' | 'DISCONNECTED';

// Location Model
interface LocationUpdate {
  journeyId: string;
  location: GeoPoint;
  accuracy: number;
  heading?: number;
  speed?: number;
  altitude?: number;
  metadata?: {
    batteryLevel?: number;
    isCharging?: boolean;
    signalStrength?: number;
  };
}

// GeoPoint Model
interface GeoPoint {
  latitude: number;
  longitude: number;
}

// Notification Model
interface Notification {
  id: string;
  userId: string;
  type: NotificationType;
  title: string;
  body: string;
  data?: Record<string, any>;
  isRead: boolean;
  createdAt: string; // ISO 8601
}

type NotificationType = 
  | 'JOURNEY_INVITATION' 
  | 'JOURNEY_STARTED' 
  | 'JOURNEY_ENDED' 
  | 'LAG_ALERT' 
  | 'ARRIVAL_DETECTED';

// API Response Wrapper
interface ApiResponse<T = any> {
  success: boolean;
  statusCode: number;
  message: string;
  data?: T;
  error?: {
    code: string;
    details?: any;
  };
}

// Authentication Response
interface AuthResponse {
  user: User;
  tokens: {
    idToken: string;
    refreshToken: string;
    expiresIn: string;
  };
}
```

### Dart Models

```dart
// User Model
class User {
  final String id;
  final String email;
  final String displayName;
  final String? phoneNumber;
  final DateTime createdAt;
  final DateTime updatedAt;

  User({
    required this.id,
    required this.email,
    required this.displayName,
    this.phoneNumber,
    required this.createdAt,
    required this.updatedAt,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'],
    email: json['email'],
    displayName: json['displayName'],
    phoneNumber: json['phoneNumber'],
    createdAt: DateTime.parse(json['createdAt']),
    updatedAt: DateTime.parse(json['updatedAt']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'displayName': displayName,
    'phoneNumber': phoneNumber,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}

// Journey Model
class Journey {
  final String id;
  final String name;
  final String leaderId;
  final JourneyStatus status;
  final DateTime? startTime;
  final DateTime? endTime;
  final GeoPoint? destination;
  final String? destinationAddress;
  final int lagThresholdMeters;
  final DateTime createdAt;
  final DateTime updatedAt;
  final JourneyMetadata metadata;

  Journey({
    required this.id,
    required this.name,
    required this.leaderId,
    required this.status,
    this.startTime,
    this.endTime,
    this.destination,
    this.destinationAddress,
    required this.lagThresholdMeters,
    required this.createdAt,
    required this.updatedAt,
    required this.metadata,
  });

  factory Journey.fromJson(Map<String, dynamic> json) => Journey(
    id: json['id'],
    name: json['name'],
    leaderId: json['leaderId'],
    status: JourneyStatus.values.byName(json['status']),
    startTime: json['startTime'] != null ? DateTime.parse(json['startTime']) : null,
    endTime: json['endTime'] != null ? DateTime.parse(json['endTime']) : null,
    destination: json['destination'] != null 
        ? GeoPoint.fromJson(json['destination']) 
        : null,
    destinationAddress: json['destinationAddress'],
    lagThresholdMeters: json['lagThresholdMeters'],
    createdAt: DateTime.parse(json['createdAt']),
    updatedAt: DateTime.parse(json['updatedAt']),
    metadata: JourneyMetadata.fromJson(json['metadata']),
  );
}

enum JourneyStatus { pending, active, completed, cancelled }

// GeoPoint Model
class GeoPoint {
  final double latitude;
  final double longitude;

  GeoPoint({required this.latitude, required this.longitude});

  factory GeoPoint.fromJson(Map<String, dynamic> json) => GeoPoint(
    latitude: json['latitude'].toDouble(),
    longitude: json['longitude'].toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
  };
}

// Location Update Model
class LocationUpdate {
  final String journeyId;
  final GeoPoint location;
  final double accuracy;
  final double? heading;
  final double? speed;
  final double? altitude;
  final Map<String, dynamic>? metadata;

  LocationUpdate({
    required this.journeyId,
    required this.location,
    required this.accuracy,
    this.heading,
    this.speed,
    this.altitude,
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
    'journeyId': journeyId,
    'location': location.toJson(),
    'accuracy': accuracy,
    'heading': heading,
    'speed': speed,
    'altitude': altitude,
    'metadata': metadata,
  };
}

// API Response Wrapper
class ApiResponse<T> {
  final bool success;
  final int statusCode;
  final String message;
  final T? data;
  final ApiError? error;

  ApiResponse({
    required this.success,
    required this.statusCode,
    required this.message,
    this.data,
    this.error,
  });

  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic) fromJsonT,
  ) => ApiResponse<T>(
    success: json['success'],
    statusCode: json['statusCode'],
    message: json['message'],
    data: json['data'] != null ? fromJsonT(json['data']) : null,
    error: json['error'] != null ? ApiError.fromJson(json['error']) : null,
  );
}

class ApiError {
  final String code;
  final dynamic details;

  ApiError({required this.code, this.details});

  factory ApiError.fromJson(Map<String, dynamic> json) => ApiError(
    code: json['code'],
    details: json['details'],
  );
}
```

---

## 3. Screen-to-API Mapping

### Screen 1: Splash/Onboarding
**Design**: TuLink logo, tagline "Stay in Formation", "Get Started" CTA

**Backend Integration:**
- No API calls required
- Check for stored authentication tokens
- Navigate to appropriate screen based on auth status

**Implementation:**
```typescript
// Check authentication on app launch
const checkAuthStatus = async () => {
  const token = await SecureStorage.getItem('auth_token');
  const refreshToken = await SecureStorage.getItem('refresh_token');
  
  if (token && refreshToken) {
    try {
      // Verify token validity
      const response = await api.get('/auth/profile');
      navigateToHome();
    } catch (error) {
      if (error.status === 401) {
        // Try to refresh token
        await refreshAuthToken();
      } else {
        navigateToSignIn();
      }
    }
  } else {
    navigateToSignIn();
  }
};
```

### Screen 2: Sign Up
**Design**: Email, password, display name fields, phone number (optional)

**Backend Integration:**
```typescript
// Registration Flow
const handleRegister = async (formData: RegisterForm) => {
  try {
    setLoading(true);
    
    const response = await api.post('/auth/register', {
      email: formData.email,
      password: formData.password,
      displayName: formData.displayName,
      phoneNumber: formData.phoneNumber // Optional, E.164 format
    });
    
    // Store tokens securely
    await SecureStorage.setItem('auth_token', response.data.tokens.idToken);
    await SecureStorage.setItem('refresh_token', response.data.tokens.refreshToken);
    
    // Update global auth state
    authContext.setUser(response.data.user);
    authContext.setIsAuthenticated(true);
    
    navigateToHome();
  } catch (error) {
    if (error.status === 409) {
      showError('Email already exists. Please sign in instead.');
    } else if (error.status === 400) {
      showError('Please check your phone number format.');
    } else {
      showError('Registration failed. Please try again.');
    }
  } finally {
    setLoading(false);
  }
};

// Form validation
const validateForm = (data: RegisterForm) => {
  const errors: string[] = [];
  
  if (!isValidEmail(data.email)) {
    errors.push('Please enter a valid email address');
  }
  
  if (data.password.length < 6) {
    errors.push('Password must be at least 6 characters');
  }
  
  if (data.phoneNumber && !isValidE164(data.phoneNumber)) {
    errors.push('Phone number must be in international format (+254...)');
  }
  
  return errors;
};
```

### Screen 3: Sign In
**Design**: Email, password fields, "Sign In" CTA, forgot password link

**Backend Integration:**
```typescript
const handleLogin = async (credentials: LoginCredentials) => {
  try {
    setLoading(true);
    
    const response = await api.post('/auth/login', credentials);
    
    // Store tokens
    await SecureStorage.setItem('auth_token', response.data.tokens.idToken);
    await SecureStorage.setItem('refresh_token', response.data.tokens.refreshToken);
    
    // Update auth state
    authContext.setUser(response.data.user);
    authContext.setIsAuthenticated(true);
    
    navigateToHome();
  } catch (error) {
    if (error.status === 401) {
      showError('Invalid email or password');
    } else {
      showError('Login failed. Please try again.');
    }
  } finally {
    setLoading(false);
  }
};
```

### Screen 4: Home/Dashboard
**Design**: "Start Journey", "Join Journey" buttons, recent journeys list

**Backend Integration:**
```typescript
// Load dashboard data
const loadDashboardData = async () => {
  try {
    const [activeJourneys, invitations] = await Promise.all([
      api.get('/journeys/active'),
      api.get('/journeys/invitations')
    ]);
    
    setActiveJourneys(activeJourneys.data);
    setPendingInvitations(invitations.data);
  } catch (error) {
    console.error('Failed to load dashboard:', error);
  }
};

// Start new journey
const startNewJourney = () => {
  navigateToCreateJourney();
};

// Join journey by invitation
const joinByInvitation = (invitation: JourneyInvitation) => {
  navigateToJourneyDetail(invitation.journeyId);
};
```

### Screen 5: Create Journey
**Design**: Journey name, destination search, lag threshold slider

**Backend Integration:**
```typescript
// Search destinations
const searchDestinations = async (query: string) => {
  if (query.length < 3) return [];
  
  try {
    const currentLocation = await getCurrentLocation();
    const response = await api.get('/maps/search', {
      params: {
        query,
        lat: currentLocation.latitude,
        lng: currentLocation.longitude
      }
    });
    
    return response.data.results;
  } catch (error) {
    console.error('Search failed:', error);
    return [];
  }
};

// Create journey
const handleCreateJourney = async (journeyData: CreateJourneyForm) => {
  try {
    setLoading(true);
    
    const response = await api.post('/journeys', {
      name: journeyData.name,
      destination: journeyData.selectedDestination,
      destinationAddress: journeyData.destinationAddress,
      lagThresholdMeters: journeyData.lagThreshold * 1000 // Convert km to meters
    });
    
    const journey = response.data;
    
    // Navigate to journey detail
    navigateToJourneyDetail(journey.id);
  } catch (error) {
    showError('Failed to create journey');
  } finally {
    setLoading(false);
  }
};
```

### Screen 6: Active Journey/Live Map
**Design**: Full-screen map, participant markers, bottom sheet with journey info

**Backend Integration:**
```typescript
// Real-time tracking setup
const initializeJourneyTracking = async (journeyId: string) => {
  // 1. Connect to WebSocket
  const socket = io('/location', {
    auth: { token: await getAuthToken() }
  });
  
  // 2. Join journey room
  socket.emit('join-journey', { journeyId });
  
  // 3. Set up location tracking
  const watchId = navigator.geolocation.watchPosition(
    (position) => {
      const locationUpdate = {
        journeyId,
        location: {
          latitude: position.coords.latitude,
          longitude: position.coords.longitude
        },
        accuracy: position.coords.accuracy,
        heading: position.coords.heading,
        speed: position.coords.speed,
        altitude: position.coords.altitude
      };
      
      // Send via WebSocket (preferred) or REST fallback
      if (socket.connected) {
        socket.emit('location-update', locationUpdate);
      } else {
        api.post('/locations', locationUpdate);
      }
    },
    (error) => console.error('Location error:', error),
    {
      enableHighAccuracy: true,
      timeout: 10000,
      maximumAge: 5000
    }
  );
  
  // 4. Listen for participant updates
  socket.on('location-update', (data) => {
    updateParticipantMarker(data);
    checkForLagAlerts(data);
  });
  
  socket.on('lag-alert', (alert) => {
    showLagAlert(alert);
  });
  
  socket.on('arrival-detected', (data) => {
    showArrivalNotification(data);
  });
  
  // Cleanup on unmount
  return () => {
    navigator.geolocation.clearWatch(watchId);
    socket.disconnect();
  };
};

// Journey control actions
const startJourney = async (journeyId: string) => {
  try {
    await api.post(`/journeys/${journeyId}/start`);
    showSuccess('Journey started!');
  } catch (error) {
    showError('Failed to start journey');
  }
};

const endJourney = async (journeyId: string) => {
  try {
    await api.post(`/journeys/${journeyId}/end`);
    navigateToJourneySummary(journeyId);
  } catch (error) {
    showError('Failed to end journey');
  }
};
```

### Screen 7: Journey Invitations
**Design**: List of pending invitations with accept/decline actions

**Backend Integration:**
```typescript
// Load invitations
const loadInvitations = async () => {
  try {
    const response = await api.get('/journeys/invitations');
    setInvitations(response.data);
  } catch (error) {
    console.error('Failed to load invitations');
  }
};

// Accept invitation
const acceptInvitation = async (journeyId: string) => {
  try {
    await api.post(`/journeys/${journeyId}/accept`);
    showSuccess('Invitation accepted!');
    navigateToJourneyDetail(journeyId);
  } catch (error) {
    showError('Failed to accept invitation');
  }
};

// Decline invitation
const declineInvitation = async (journeyId: string) => {
  try {
    await api.post(`/journeys/${journeyId}/decline`);
    showSuccess('Invitation declined');
    removeInvitationFromList(journeyId);
  } catch (error) {
    showError('Failed to decline invitation');
  }
};
```

### Screen 8: Notifications
**Design**: List of journey notifications, unread count badge

**Backend Integration:**
```typescript
// Load notifications
const loadNotifications = async () => {
  try {
    const [notifications, unreadCount] = await Promise.all([
      api.get('/notifications?limit=50'),
      api.get('/notifications/unread-count')
    ]);
    
    setNotifications(notifications.data);
    setUnreadCount(unreadCount.data.count);
  } catch (error) {
    console.error('Failed to load notifications');
  }
};

// Mark as read
const markAsRead = async (notificationId: string) => {
  try {
    await api.put(`/notifications/${notificationId}/read`);
    updateNotificationReadStatus(notificationId);
  } catch (error) {
    console.error('Failed to mark as read');
  }
};

// Register FCM token for push notifications
const registerForNotifications = async () => {
  try {
    const permission = await requestNotificationPermission();
    if (permission === 'granted') {
      const token = await getMessagingToken();
      const deviceId = await getDeviceId();
      
      await api.post('/notifications/fcm-token', {
        fcmToken: token,
        platform: Platform.OS,
        deviceId
      });
    }
  } catch (error) {
    console.error('Failed to register for notifications');
  }
};
```

### Screen 9: Profile
**Design**: User avatar, stats, settings list

**Backend Integration:**
```typescript
// Load profile
const loadProfile = async () => {
  try {
    const response = await api.get('/auth/profile');
    setUser(response.data);
  } catch (error) {
    console.error('Failed to load profile');
  }
};

// Update profile
const updateProfile = async (profileData: UpdateProfileForm) => {
  try {
    const response = await api.put('/auth/profile', profileData);
    setUser(response.data);
    showSuccess('Profile updated successfully');
  } catch (error) {
    showError('Failed to update profile');
  }
};

// Logout
const handleLogout = async () => {
  try {
    await api.post('/auth/logout');
    await SecureStorage.removeItem('auth_token');
    await SecureStorage.removeItem('refresh_token');
    
    authContext.setUser(null);
    authContext.setIsAuthenticated(false);
    
    navigateToSignIn();
  } catch (error) {
    // Force logout even if API call fails
    await SecureStorage.clear();
    authContext.logout();
    navigateToSignIn();
  }
};
```

---

## 4. State Management Guide

### Flutter BLoC Pattern

```dart
// Authentication BLoC
abstract class AuthEvent {}
class AuthLoginRequested extends AuthEvent {
  final String email;
  final String password;
  AuthLoginRequested(this.email, this.password);
}
class AuthLogoutRequested extends AuthEvent {}
class AuthRegisterRequested extends AuthEvent {
  final RegisterDto registerDto;
  AuthRegisterRequested(this.registerDto);
}

abstract class AuthState {}
class AuthInitial extends AuthState {}
class AuthLoading extends AuthState {}
class AuthAuthenticated extends AuthState {
  final User user;
  AuthAuthenticated(this.user);
}
class AuthUnauthenticated extends AuthState {}
class AuthError extends AuthState {
  final String message;
  AuthError(this.message);
}

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthService _authService;

  AuthBloc(this._authService) : super(AuthInitial()) {
    on<AuthLoginRequested>(_onLoginRequested);
    on<AuthLogoutRequested>(_onLogoutRequested);
    on<AuthRegisterRequested>(_onRegisterRequested);
  }

  Future<void> _onLoginRequested(
    AuthLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final authResponse = await _authService.login(event.email, event.password);
      emit(AuthAuthenticated(authResponse.user));
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }
}

// Journey BLoC
abstract class JourneyEvent {}
class JourneyLoadRequested extends JourneyEvent {}
class JourneyCreateRequested extends JourneyEvent {
  final CreateJourneyDto createJourneyDto;
  JourneyCreateRequested(this.createJourneyDto);
}

abstract class JourneyState {}
class JourneyInitial extends JourneyState {}
class JourneyLoading extends JourneyState {}
class JourneyLoaded extends JourneyState {
  final List<Journey> activeJourneys;
  final List<Journey> invitations;
  JourneyLoaded(this.activeJourneys, this.invitations);
}
class JourneyCreated extends JourneyState {
  final Journey journey;
  JourneyCreated(this.journey);
}
class JourneyError extends JourneyState {
  final String message;
  JourneyError(this.message);
}

// Location Tracking BLoC
abstract class LocationEvent {}
class LocationTrackingStarted extends LocationEvent {
  final String journeyId;
  LocationTrackingStarted(this.journeyId);
}
class LocationUpdateReceived extends LocationEvent {
  final LocationUpdate locationUpdate;
  LocationUpdateReceived(this.locationUpdate);
}

abstract class LocationState {}
class LocationInitial extends LocationState {}
class LocationTracking extends LocationState {
  final Map<String, LocationUpdate> participantLocations;
  final bool isConnected;
  LocationTracking(this.participantLocations, this.isConnected);
}
```

### React Native Context + Hooks

```typescript
// Auth Context
interface AuthContextType {
  user: User | null;
  isAuthenticated: boolean;
  isLoading: boolean;
  login: (email: string, password: string) => Promise<void>;
  register: (data: RegisterDto) => Promise<void>;
  logout: () => Promise<void>;
  refreshToken: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | null>(null);

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [user, setUser] = useState<User | null>(null);
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [isLoading, setIsLoading] = useState(true);

  const login = async (email: string, password: string) => {
    try {
      setIsLoading(true);
      const response = await authService.login(email, password);
      setUser(response.user);
      setIsAuthenticated(true);
      await storeTokens(response.tokens);
    } catch (error) {
      throw error;
    } finally {
      setIsLoading(false);
    }
  };

  const logout = async () => {
    try {
      await authService.logout();
    } finally {
      setUser(null);
      setIsAuthenticated(false);
      await clearTokens();
    }
  };

  return (
    <AuthContext.Provider value={{
      user,
      isAuthenticated,
      isLoading,
      login,
      logout,
      register,
      refreshToken
    }}>
      {children}
    </AuthContext.Provider>
  );
};

// Journey Context
interface JourneyContextType {
  activeJourneys: Journey[];
  invitations: Journey[];
  isLoading: boolean;
  createJourney: (data: CreateJourneyDto) => Promise<Journey>;
  acceptInvitation: (journeyId: string) => Promise<void>;
  declineInvitation: (journeyId: string) => Promise<void>;
}

// Location Tracking Hook
const useLocationTracking = (journeyId: string) => {
  const [socket, setSocket] = useState<Socket | null>(null);
  const [participants, setParticipants] = useState<Map<string, LocationUpdate>>(new Map());
  const [isConnected, setIsConnected] = useState(false);

  useEffect(() => {
    const initSocket = async () => {
      const token = await getAuthToken();
      const newSocket = io('/location', {
        auth: { token }
      });

      newSocket.on('connect', () => {
        setIsConnected(true);
        newSocket.emit('join-journey', { journeyId });
      });

      newSocket.on('location-update', (data) => {
        setParticipants(prev => new Map(prev.set(data.userId, data)));
      });

      setSocket(newSocket);
    };

    initSocket();

    return () => {
      socket?.disconnect();
    };
  }, [journeyId]);

  const sendLocationUpdate = useCallback((locationData: LocationUpdate) => {
    if (socket?.connected) {
      socket.emit('location-update', locationData);
    }
  }, [socket]);

  return { participants, isConnected, sendLocationUpdate };
};
```

---

## 5. Error Handling Patterns

### Error Classification

```typescript
// Error Types
class ApiError extends Error {
  constructor(
    public statusCode: number,
    public code: string,
    message: string,
    public details?: any
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

class NetworkError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'NetworkError';
  }
}

class ValidationError extends Error {
  constructor(
    public field: string,
    message: string
  ) {
    super(message);
    this.name = 'ValidationError';
  }
}

// Error Handler
class ErrorHandler {
  static handle(error: any): string {
    if (error instanceof NetworkError) {
      return 'No internet connection. Please check your network.';
    }
    
    if (error instanceof ApiError) {
      switch (error.statusCode) {
        case 400:
          return error.message || 'Invalid request. Please check your input.';
        case 401:
          return 'Session expired. Please sign in again.';
        case 403:
          return 'You don\'t have permission for this action.';
        case 404:
          return 'Resource not found.';
        case 409:
          return 'This item already exists.';
        case 429:
          return 'Too many requests. Please try again later.';
        case 500:
          return 'Server error. Our team has been notified.';
        default:
          return 'Something went wrong. Please try again.';
      }
    }
    
    return 'An unexpected error occurred.';
  }
}

// Retry Logic
const retryWithExponentialBackoff = async <T>(
  fn: () => Promise<T>,
  maxRetries: number = 3,
  baseDelay: number = 1000
): Promise<T> => {
  let lastError: Error;
  
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error as Error;
      
      if (attempt === maxRetries) {
        throw lastError;
      }
      
      // Don't retry client errors (4xx)
      if (error instanceof ApiError && error.statusCode >= 400 && error.statusCode < 500) {
        throw error;
      }
      
      const delay = baseDelay * Math.pow(2, attempt);
      await new Promise(resolve => setTimeout(resolve, delay));
    }
  }
  
  throw lastError!;
};
```

### Flutter Error Handling

```dart
// Error Classes
class ApiException implements Exception {
  final int statusCode;
  final String code;
  final String message;
  final dynamic details;

  ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
    this.details,
  });
}

class NetworkException implements Exception {
  final String message;
  NetworkException(this.message);
}

// Error Handler Service
class ErrorHandlerService {
  static String getErrorMessage(dynamic error) {
    if (error is NetworkException) {
      return 'No internet connection. Please check your network.';
    }
    
    if (error is ApiException) {
      switch (error.statusCode) {
        case 400:
          return error.message.isNotEmpty ? error.message : 'Invalid request';
        case 401:
          return 'Session expired. Please sign in again.';
        case 403:
          return 'You don\'t have permission for this action.';
        case 404:
          return 'Resource not found.';
        case 409:
          return 'This item already exists.';
        case 429:
          return 'Too many requests. Please try again later.';
        case 500:
          return 'Server error. Our team has been notified.';
        default:
          return 'Something went wrong. Please try again.';
      }
    }
    
    return 'An unexpected error occurred.';
  }
}

// BLoC Error Handling
class JourneyBloc extends Bloc<JourneyEvent, JourneyState> {
  @override
  Stream<JourneyState> mapEventToState(JourneyEvent event) async* {
    if (event is CreateJourneyEvent) {
      yield JourneyLoading();
      try {
        final journey = await journeyService.createJourney(event.dto);
        yield JourneyCreated(journey);
      } on ApiException catch (e) {
        if (e.statusCode == 401) {
          yield JourneyAuthError();
        } else {
          yield JourneyError(ErrorHandlerService.getErrorMessage(e));
        }
      } on NetworkException {
        yield JourneyNetworkError();
      } catch (e) {
        yield JourneyError('An unexpected error occurred');
      }
    }
  }
}
```

---

## 6. Performance Optimization

### API Call Optimization

```typescript
// Request Debouncing
import { debounce } from 'lodash';

const debouncedSearch = debounce(async (query: string) => {
  try {
    const results = await api.get('/maps/search', { params: { query } });
    setSearchResults(results.data.results);
  } catch (error) {
    console.error('Search failed:', error);
  }
}, 300);

// Request Caching
class ApiCache {
  private cache = new Map<string, { data: any; timestamp: number; ttl: number }>();

  set(key: string, data: any, ttl: number = 300000) { // 5 minutes default
    this.cache.set(key, { data, timestamp: Date.now(), ttl });
  }

  get(key: string): any | null {
    const cached = this.cache.get(key);
    if (!cached) return null;

    if (Date.now() - cached.timestamp > cached.ttl) {
      this.cache.delete(key);
      return null;
    }

    return cached.data;
  }

  clear() {
    this.cache.clear();
  }
}

const apiCache = new ApiCache();

// Cached API wrapper
const cachedGet = async (url: string, ttl?: number): Promise<any> => {
  const cached = apiCache.get(url);
  if (cached) return cached;

  const response = await api.get(url);
  apiCache.set(url, response.data, ttl);
  return response.data;
};

// Pagination for Lists
const useInfiniteScroll = (loadMore: () => Promise<void>) => {
  const [isLoading, setIsLoading] = useState(false);

  const handleScroll = useCallback(
    debounce(async (event: any) => {
      const { scrollTop, scrollHeight, clientHeight } = event.target;
      const isNearBottom = scrollTop + clientHeight >= scrollHeight - 100;

      if (isNearBottom && !isLoading) {
        setIsLoading(true);
        await loadMore();
        setIsLoading(false);
      }
    }, 200),
    [isLoading, loadMore]
  );

  return { handleScroll, isLoading };
};
```

### Real-time Optimization

```typescript
// Location Update Throttling
const useThrottledLocationUpdates = (journeyId: string) => {
  const lastUpdateTime = useRef(0);
  const THROTTLE_INTERVAL = 10000; // 10 seconds

  const sendLocationUpdate = useCallback((location: LocationUpdate) => {
    const now = Date.now();
    if (now - lastUpdateTime.current >= THROTTLE_INTERVAL) {
      socket.emit('location-update', { ...location, journeyId });
      lastUpdateTime.current = now;
    }
  }, [journeyId]);

  return sendLocationUpdate;
};

// WebSocket Connection Management
class SocketManager {
  private socket: Socket | null = null;
  private reconnectAttempts = 0;
  private maxReconnectAttempts = 5;

  connect(journeyId: string): Promise<Socket> {
    return new Promise((resolve, reject) => {
      this.socket = io('/location', {
        auth: { token: getAuthToken() },
        transports: ['websocket'],
        timeout: 5000
      });

      this.socket.on('connect', () => {
        this.reconnectAttempts = 0;
        this.socket!.emit('join-journey', { journeyId });
        resolve(this.socket!);
      });

      this.socket.on('disconnect', () => {
        this.handleReconnect(journeyId);
      });

      this.socket.on('connect_error', (error) => {
        reject(error);
      });
    });
  }

  private handleReconnect(journeyId: string) {
    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      console.error('Max reconnection attempts reached');
      return;
    }

    const delay = Math.pow(2, this.reconnectAttempts) * 1000; // Exponential backoff
    this.reconnectAttempts++;

    setTimeout(() => {
      this.connect(journeyId);
    }, delay);
  }

  disconnect() {
    if (this.socket) {
      this.socket.disconnect();
      this.socket = null;
    }
  }
}
```

### Flutter Performance

```dart
// Location Service Optimization
class LocationService {
  Timer? _locationTimer;
  Position? _lastKnownPosition;
  final int _updateIntervalMs = 10000;

  void startLocationTracking(String journeyId) {
    _locationTimer = Timer.periodic(
      Duration(milliseconds: _updateIntervalMs),
      (_) => _sendLocationUpdate(journeyId),
    );
  }

  Future<void> _sendLocationUpdate(String journeyId) async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 5),
      );

      // Only send if position has changed significantly
      if (_hasPositionChanged(position)) {
        final locationUpdate = LocationUpdate(
          journeyId: journeyId,
          location: GeoPoint(
            latitude: position.latitude,
            longitude: position.longitude,
          ),
          accuracy: position.accuracy,
          heading: position.heading,
          speed: position.speed,
          altitude: position.altitude,
        );

        await _locationRepository.sendLocationUpdate(locationUpdate);
        _lastKnownPosition = position;
      }
    } catch (e) {
      print('Failed to get location: $e');
    }
  }

  bool _hasPositionChanged(Position newPosition) {
    if (_lastKnownPosition == null) return true;

    final distance = Geolocator.distanceBetween(
      _lastKnownPosition!.latitude,
      _lastKnownPosition!.longitude,
      newPosition.latitude,
      newPosition.longitude,
    );

    return distance > 10; // Only update if moved more than 10 meters
  }

  void stopLocationTracking() {
    _locationTimer?.cancel();
    _locationTimer = null;
  }
}

// Efficient Map Updates
class MapController extends ChangeNotifier {
  final Map<String, Marker> _markers = {};
  GoogleMapController? _mapController;

  void updateParticipantLocation(String userId, LocationUpdate location) {
    final marker = Marker(
      markerId: MarkerId(userId),
      position: LatLng(location.location.latitude, location.location.longitude),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
    );

    _markers[userId] = marker;
    notifyListeners();
  }

  Set<Marker> get markers => _markers.values.toSet();
}
```

---

## 7. Security Best Practices

### Token Management

```typescript
// Secure Token Storage (React Native)
import { Keychain } from 'react-native-keychain';

class SecureStorage {
  static async setItem(key: string, value: string): Promise<void> {
    await Keychain.setInternetCredentials(key, key, value);
  }

  static async getItem(key: string): Promise<string | null> {
    try {
      const credentials = await Keychain.getInternetCredentials(key);
      if (credentials) {
        return credentials.password;
      }
      return null;
    } catch (error) {
      return null;
    }
  }

  static async removeItem(key: string): Promise<void> {
    await Keychain.resetInternetCredentials(key);
  }

  static async clear(): Promise<void> {
    const credentials = await Keychain.getAllInternetCredentials();
    for (const cred of credentials) {
      await Keychain.resetInternetCredentials(cred.server);
    }
  }
}

// Token Refresh Interceptor
axios.interceptors.response.use(
  (response) => response,
  async (error) => {
    if (error.response?.status === 401) {
      try {
        const refreshToken = await SecureStorage.getItem('refresh_token');
        if (refreshToken) {
          const response = await api.post('/auth/refresh', { refreshToken });
          await SecureStorage.setItem('auth_token', response.data.idToken);
          
          // Retry original request
          error.config.headers.Authorization = `Bearer ${response.data.idToken}`;
          return axios.request(error.config);
        }
      } catch (refreshError) {
        // Refresh failed, redirect to login
        await SecureStorage.clear();
        NavigationService.navigate('SignIn');
      }
    }
    return Promise.reject(error);
  }
);
```

### Flutter Security

```dart
// Secure Storage (Flutter)
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: IOSAccessibility.first_unlock_this_device,
    ),
  );

  static Future<void> setToken(String key, String token) async {
    await _storage.write(key: key, value: token);
  }

  static Future<String?> getToken(String key) async {
    return await _storage.read(key: key);
  }

  static Future<void> deleteToken(String key) async {
    await _storage.delete(key: key);
  }

  static Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}

// Network Security (Certificate Pinning)
class HttpService {
  static Dio createDio() {
    final dio = Dio();
    
    // Certificate pinning for production
    if (kReleaseMode) {
      (dio.httpClientAdapter as IOHttpClientAdapter).onHttpClientCreate = (client) {
        client.badCertificateCallback = (cert, host, port) {
          // Implement certificate validation
          return _validateCertificate(cert, host);
        };
        return client;
      };
    }

    // Request interceptor for auth
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await SecureStorageService.getToken('auth_token');
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401) {
            // Handle token refresh
            final refreshed = await _refreshToken();
            if (refreshed) {
              // Retry request
              return handler.resolve(await dio.fetch(error.requestOptions));
            }
          }
          handler.next(error);
        },
      ),
    );

    return dio;
  }
}
```

### Input Validation & Sanitization

```typescript
// Input Validation
import validator from 'validator';

class ValidationService {
  static validateEmail(email: string): boolean {
    return validator.isEmail(email);
  }

  static validatePhoneNumber(phone: string): boolean {
    return validator.isMobilePhone(phone, 'any', { strictMode: true });
  }

  static sanitizeString(input: string): string {
    return validator.escape(input.trim());
  }

  static validatePassword(password: string): { isValid: boolean; message?: string } {
    if (password.length < 6) {
      return { isValid: false, message: 'Password must be at least 6 characters' };
    }
    
    if (!/(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/.test(password)) {
      return { 
        isValid: false, 
        message: 'Password must contain uppercase, lowercase, and number' 
      };
    }
    
    return { isValid: true };
  }

  static validateCoordinates(lat: number, lng: number): boolean {
    return (
      typeof lat === 'number' && 
      typeof lng === 'number' &&
      lat >= -90 && lat <= 90 &&
      lng >= -180 && lng <= 180
    );
  }
}

// XSS Prevention
const sanitizeInput = (input: string): string => {
  return input
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#x27;')
    .replace(/\//g, '&#x2F;');
};
```

---

## 8. Testing Strategy

### Unit Tests

```typescript
// React Native Testing (Jest)
import { render, fireEvent, waitFor } from '@testing-library/react-native';
import { AuthService } from '../services/AuthService';
import { LoginScreen } from '../screens/LoginScreen';

// Mock API
jest.mock('../services/AuthService');
const mockAuthService = AuthService as jest.Mocked<typeof AuthService>;

describe('LoginScreen', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  test('should login successfully with valid credentials', async () => {
    const mockUser = { id: '1', email: 'test@example.com' };
    mockAuthService.login.mockResolvedValue({
      user: mockUser,
      tokens: { idToken: 'token', refreshToken: 'refresh', expiresIn: '3600' }
    });

    const { getByTestId } = render(<LoginScreen />);
    
    fireEvent.changeText(getByTestId('email-input'), 'test@example.com');
    fireEvent.changeText(getByTestId('password-input'), 'password123');
    fireEvent.press(getByTestId('login-button'));

    await waitFor(() => {
      expect(mockAuthService.login).toHaveBeenCalledWith('test@example.com', 'password123');
    });
  });

  test('should show error message for invalid credentials', async () => {
    mockAuthService.login.mockRejectedValue(new Error('Invalid credentials'));

    const { getByTestId, getByText } = render(<LoginScreen />);
    
    fireEvent.changeText(getByTestId('email-input'), 'test@example.com');
    fireEvent.changeText(getByTestId('password-input'), 'wrongpassword');
    fireEvent.press(getByTestId('login-button'));

    await waitFor(() => {
      expect(getByText('Invalid credentials')).toBeTruthy();
    });
  });
});

// Service Testing
describe('AuthService', () => {
  const authService = new AuthService(mockApiClient);

  test('should register user successfully', async () => {
    const registerData = {
      email: 'test@example.com',
      password: 'password123',
      displayName: 'Test User'
    };

    mockApiClient.post.mockResolvedValue({
      data: {
        user: { id: '1', ...registerData },
        tokens: { idToken: 'token', refreshToken: 'refresh' }
      }
    });

    const result = await authService.register(registerData);

    expect(mockApiClient.post).toHaveBeenCalledWith('/auth/register', registerData);
    expect(result.user.email).toBe(registerData.email);
  });
});
```

### Flutter Testing

```dart
// Widget Testing
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:bloc_test/bloc_test.dart';

// Mock Services
class MockAuthService extends Mock implements AuthService {}
class MockJourneyService extends Mock implements JourneyService {}

void main() {
  group('LoginScreen Widget Tests', () {
    late MockAuthService mockAuthService;

    setUp(() {
      mockAuthService = MockAuthService();
    });

    testWidgets('should show login form', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: LoginScreen(authService: mockAuthService),
      ));

      expect(find.byKey(Key('email_field')), findsOneWidget);
      expect(find.byKey(Key('password_field')), findsOneWidget);
      expect(find.byKey(Key('login_button')), findsOneWidget);
    });

    testWidgets('should call login when button pressed', (WidgetTester tester) async {
      when(mockAuthService.login(any, any)).thenAnswer(
        (_) async => AuthResponse(user: User(id: '1', email: 'test@example.com')),
      );

      await tester.pumpWidget(MaterialApp(
        home: LoginScreen(authService: mockAuthService),
      ));

      await tester.enterText(find.byKey(Key('email_field')), 'test@example.com');
      await tester.enterText(find.byKey(Key('password_field')), 'password');
      await tester.tap(find.byKey(Key('login_button')));
      await tester.pump();

      verify(mockAuthService.login('test@example.com', 'password')).called(1);
    });
  });

  // BLoC Testing
  group('AuthBloc Tests', () {
    late MockAuthService mockAuthService;
    late AuthBloc authBloc;

    setUp(() {
      mockAuthService = MockAuthService();
      authBloc = AuthBloc(mockAuthService);
    });

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthAuthenticated] when login succeeds',
      build: () {
        when(mockAuthService.login(any, any)).thenAnswer(
          (_) async => AuthResponse(user: User(id: '1', email: 'test@example.com')),
        );
        return authBloc;
      },
      act: (bloc) => bloc.add(AuthLoginRequested('test@example.com', 'password')),
      expect: () => [
        AuthLoading(),
        AuthAuthenticated(User(id: '1', email: 'test@example.com')),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthError] when login fails',
      build: () {
        when(mockAuthService.login(any, any)).thenThrow(Exception('Login failed'));
        return authBloc;
      },
      act: (bloc) => bloc.add(AuthLoginRequested('test@example.com', 'password')),
      expect: () => [
        AuthLoading(),
        AuthError('Exception: Login failed'),
      ],
    );
  });
}

// Integration Testing
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('App Integration Tests', () {
    testWidgets('complete user journey: register -> create journey -> invite', (WidgetTester tester) async {
      await tester.pumpWidget(MyApp());

      // Register new user
      await tester.tap(find.byKey(Key('register_tab')));
      await tester.pump();
      
      await tester.enterText(find.byKey(Key('email_field')), 'test@example.com');
      await tester.enterText(find.byKey(Key('password_field')), 'password123');
      await tester.enterText(find.byKey(Key('name_field')), 'Test User');
      
      await tester.tap(find.byKey(Key('register_button')));
      await tester.pumpAndSettle();

      // Should navigate to home screen
      expect(find.byKey(Key('home_screen')), findsOneWidget);

      // Create new journey
      await tester.tap(find.byKey(Key('create_journey_button')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(Key('journey_name_field')), 'Test Journey');
      await tester.tap(find.byKey(Key('create_button')));
      await tester.pumpAndSettle();

      // Should navigate to journey detail screen
      expect(find.byKey(Key('journey_detail_screen')), findsOneWidget);
      expect(find.text('Test Journey'), findsOneWidget);
    });
  });
}
```

### E2E Testing

```typescript
// Detox E2E Testing (React Native)
describe('TuLink App E2E', () => {
  beforeAll(async () => {
    await device.launchApp();
  });

  beforeEach(async () => {
    await device.reloadReactNative();
  });

  it('should complete full user journey', async () => {
    // Register new user
    await element(by.id('register_tab')).tap();
    await element(by.id('email_input')).typeText('e2e@example.com');
    await element(by.id('password_input')).typeText('password123');
    await element(by.id('name_input')).typeText('E2E User');
    await element(by.id('register_button')).tap();

    // Should navigate to home
    await waitFor(element(by.id('home_screen')))
      .toBeVisible()
      .withTimeout(5000);

    // Create journey
    await element(by.id('create_journey_button')).tap();
    await element(by.id('journey_name_input')).typeText('E2E Test Journey');
    await element(by.id('destination_input')).typeText('KICC Nairobi');
    
    // Wait for search results and select first one
    await waitFor(element(by.id('destination_result_0')))
      .toBeVisible()
      .withTimeout(3000);
    await element(by.id('destination_result_0')).tap();
    
    await element(by.id('create_journey_submit')).tap();

    // Should navigate to journey detail
    await waitFor(element(by.id('journey_detail_screen')))
      .toBeVisible()
      .withTimeout(5000);

    await expect(element(by.text('E2E Test Journey'))).toBeVisible();
  });

  it('should handle offline scenarios', async () => {
    // Simulate offline state
    await device.setURLBlacklist(['*']);
    
    await element(by.id('create_journey_button')).tap();
    await element(by.id('journey_name_input')).typeText('Offline Journey');
    await element(by.id('create_journey_submit')).tap();

    // Should show offline message
    await expect(element(by.text('No internet connection'))).toBeVisible();

    // Re-enable network
    await device.setURLBlacklist([]);
    
    // Retry should work
    await element(by.id('retry_button')).tap();
    await waitFor(element(by.id('journey_detail_screen')))
      .toBeVisible()
      .withTimeout(5000);
  });
});
```

---

## 9. Environment Configuration

### Configuration Setup

```typescript
// config/environments.ts
interface Environment {
  name: string;
  apiBaseUrl: string;
  wsUrl: string;
  googleMapsApiKey: string;
  firebaseConfig: any;
  enableLogging: boolean;
  enableCrashlytics: boolean;
}

export const environments: Record<string, Environment> = {
  development: {
    name: 'development',
    apiBaseUrl: 'http://localhost:3000',
    wsUrl: 'ws://localhost:3000',
    googleMapsApiKey: 'AIzaSyDEVELOPMENT_KEY',
    firebaseConfig: {
      apiKey: "dev-api-key",
      authDomain: "tulink-dev.firebaseapp.com",
      projectId: "tulink-dev",
      storageBucket: "tulink-dev.appspot.com",
      messagingSenderId: "123456789",
      appId: "1:123456789:web:dev"
    },
    enableLogging: true,
    enableCrashlytics: false,
  },
  staging: {
    name: 'staging',
    apiBaseUrl: 'https://staging-api.tulink.com',
    wsUrl: 'wss://staging-api.tulink.com',
    googleMapsApiKey: 'AIzaSySTAGING_KEY',
    firebaseConfig: {
      apiKey: "staging-api-key",
      authDomain: "tulink-staging.firebaseapp.com",
      projectId: "tulink-staging",
      storageBucket: "tulink-staging.appspot.com",
      messagingSenderId: "987654321",
      appId: "1:987654321:web:staging"
    },
    enableLogging: true,
    enableCrashlytics: true,
  },
  production: {
    name: 'production',
    apiBaseUrl: 'https://api.tulink.com',
    wsUrl: 'wss://api.tulink.com',
    googleMapsApiKey: 'AIzaSyPRODUCTION_KEY',
    firebaseConfig: {
      apiKey: "prod-api-key",
      authDomain: "tulink-prod.firebaseapp.com",
      projectId: "tulink-prod",
      storageBucket: "tulink-prod.appspot.com",
      messagingSenderId: "555666777",
      appId: "1:555666777:web:prod"
    },
    enableLogging: false,
    enableCrashlytics: true,
  },
};

// Get current environment
export const getCurrentEnvironment = (): Environment => {
  const envName = process.env.NODE_ENV || __DEV__ ? 'development' : 'production';
  return environments[envName];
};

// Config service
export class ConfigService {
  private static config = getCurrentEnvironment();

  static get apiBaseUrl(): string {
    return this.config.apiBaseUrl;
  }

  static get wsUrl(): string {
    return this.config.wsUrl;
  }

  static get googleMapsApiKey(): string {
    return this.config.googleMapsApiKey;
  }

  static get firebaseConfig(): any {
    return this.config.firebaseConfig;
  }

  static get enableLogging(): boolean {
    return this.config.enableLogging;
  }
}
```

### Flutter Configuration

```dart
// config/environments.dart
abstract class Environment {
  static const String dev = 'DEV';
  static const String staging = 'STAGING';
  static const String prod = 'PROD';
}

class AppConfig {
  final String environment;
  final String apiBaseUrl;
  final String wsUrl;
  final String googleMapsApiKey;
  final Map<String, dynamic> firebaseConfig;
  final bool enableLogging;
  final bool enableCrashlytics;

  AppConfig({
    required this.environment,
    required this.apiBaseUrl,
    required this.wsUrl,
    required this.googleMapsApiKey,
    required this.firebaseConfig,
    required this.enableLogging,
    required this.enableCrashlytics,
  });

  static AppConfig get instance {
    return _getConfig();
  }

  static AppConfig _getConfig() {
    switch (const String.fromEnvironment('ENVIRONMENT', defaultValue: Environment.dev)) {
      case Environment.staging:
        return AppConfig(
          environment: Environment.staging,
          apiBaseUrl: 'https://staging-api.tulink.com',
          wsUrl: 'wss://staging-api.tulink.com',
          googleMapsApiKey: 'AIzaSySTAGING_KEY',
          firebaseConfig: {
            'apiKey': 'staging-api-key',
            'authDomain': 'tulink-staging.firebaseapp.com',
            'projectId': 'tulink-staging',
            'storageBucket': 'tulink-staging.appspot.com',
            'messagingSenderId': '987654321',
            'appId': '1:987654321:android:staging',
          },
          enableLogging: true,
          enableCrashlytics: true,
        );
      case Environment.prod:
        return AppConfig(
          environment: Environment.prod,
          apiBaseUrl: 'https://api.tulink.com',
          wsUrl: 'wss://api.tulink.com',
          googleMapsApiKey: 'AIzaSyPRODUCTION_KEY',
          firebaseConfig: {
            'apiKey': 'prod-api-key',
            'authDomain': 'tulink-prod.firebaseapp.com',
            'projectId': 'tulink-prod',
            'storageBucket': 'tulink-prod.appspot.com',
            'messagingSenderId': '555666777',
            'appId': '1:555666777:android:prod',
          },
          enableLogging: false,
          enableCrashlytics: true,
        );
      default:
        return AppConfig(
          environment: Environment.dev,
          apiBaseUrl: 'http://10.0.2.2:3000', // Android emulator
          wsUrl: 'ws://10.0.2.2:3000',
          googleMapsApiKey: 'AIzaSyDEVELOPMENT_KEY',
          firebaseConfig: {
            'apiKey': 'dev-api-key',
            'authDomain': 'tulink-dev.firebaseapp.com',
            'projectId': 'tulink-dev',
            'storageBucket': 'tulink-dev.appspot.com',
            'messagingSenderId': '123456789',
            'appId': '1:123456789:android:dev',
          },
          enableLogging: true,
          enableCrashlytics: false,
        );
    }
  }
}

// Build commands:
// flutter run --dart-define=ENVIRONMENT=DEV
// flutter run --dart-define=ENVIRONMENT=STAGING  
// flutter build apk --dart-define=ENVIRONMENT=PROD
```

---

## 10. Code Templates & Examples

### React Native API Service

```typescript
// services/ApiService.ts
import axios, { AxiosInstance, AxiosResponse } from 'axios';
import { ConfigService } from '../config/ConfigService';
import { SecureStorage } from '../utils/SecureStorage';
import { ErrorHandler } from '../utils/ErrorHandler';

export class ApiService {
  private client: AxiosInstance;

  constructor() {
    this.client = axios.create({
      baseURL: ConfigService.apiBaseUrl,
      timeout: 10000,
      headers: {
        'Content-Type': 'application/json',
      },
    });

    this.setupInterceptors();
  }

  private setupInterceptors() {
    // Request interceptor
    this.client.interceptors.request.use(
      async (config) => {
        const token = await SecureStorage.getItem('auth_token');
        if (token) {
          config.headers.Authorization = `Bearer ${token}`;
        }
        return config;
      },
      (error) => Promise.reject(error)
    );

    // Response interceptor
    this.client.interceptors.response.use(
      (response) => response,
      async (error) => {
        if (error.response?.status === 401) {
          try {
            await this.refreshToken();
            // Retry original request
            const token = await SecureStorage.getItem('auth_token');
            error.config.headers.Authorization = `Bearer ${token}`;
            return this.client.request(error.config);
          } catch (refreshError) {
            await this.handleAuthFailure();
            return Promise.reject(refreshError);
          }
        }
        return Promise.reject(ErrorHandler.transformError(error));
      }
    );
  }

  private async refreshToken(): Promise<void> {
    const refreshToken = await SecureStorage.getItem('refresh_token');
    if (!refreshToken) throw new Error('No refresh token');

    const response = await axios.post(`${ConfigService.apiBaseUrl}/auth/refresh`, {
      refreshToken,
    });

    await SecureStorage.setItem('auth_token', response.data.idToken);
  }

  private async handleAuthFailure(): Promise<void> {
    await SecureStorage.clear();
    // Navigate to login screen
    // NavigationService.navigate('SignIn');
  }

  // Auth endpoints
  async register(data: RegisterDto): Promise<AuthResponse> {
    const response = await this.client.post<ApiResponse<AuthResponse>>('/auth/register', data);
    return response.data.data!;
  }

  async login(email: string, password: string): Promise<AuthResponse> {
    const response = await this.client.post<ApiResponse<AuthResponse>>('/auth/login', {
      email,
      password,
    });
    return response.data.data!;
  }

  async getProfile(): Promise<User> {
    const response = await this.client.get<ApiResponse<User>>('/auth/profile');
    return response.data.data!;
  }

  // Journey endpoints
  async createJourney(data: CreateJourneyDto): Promise<Journey> {
    const response = await this.client.post<ApiResponse<Journey>>('/journeys', data);
    return response.data.data!;
  }

  async getActiveJourneys(): Promise<Journey[]> {
    const response = await this.client.get<ApiResponse<Journey[]>>('/journeys/active');
    return response.data.data!;
  }

  async startJourney(journeyId: string): Promise<Journey> {
    const response = await this.client.post<ApiResponse<Journey>>(`/journeys/${journeyId}/start`);
    return response.data.data!;
  }

  // Location endpoints
  async sendLocationUpdate(data: LocationUpdate): Promise<void> {
    await this.client.post('/locations', data);
  }

  async getLatestLocations(journeyId: string): Promise<LocationUpdate[]> {
    const response = await this.client.get<ApiResponse<LocationUpdate[]>>(
      `/locations/journeys/${journeyId}/latest`
    );
    return response.data.data!;
  }
}

export const apiService = new ApiService();
```

### Flutter Repository Pattern

```dart
// repositories/auth_repository.dart
import 'package:dio/dio.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../utils/exceptions.dart';

class AuthRepository {
  final ApiService _apiService;

  AuthRepository(this._apiService);

  Future<AuthResponse> register(RegisterDto registerDto) async {
    try {
      final response = await _apiService.post('/auth/register', registerDto.toJson());
      return AuthResponse.fromJson(response.data['data']);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<AuthResponse> login(String email, String password) async {
    try {
      final response = await _apiService.post('/auth/login', {
        'email': email,
        'password': password,
      });
      return AuthResponse.fromJson(response.data['data']);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<User> getProfile() async {
    try {
      final response = await _apiService.get('/auth/profile');
      return User.fromJson(response.data['data']);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> logout() async {
    try {
      await _apiService.post('/auth/logout');
    } on DioException catch (e) {
      // Continue logout even if API call fails
      print('Logout API call failed: $e');
    }
  }

  AppException _handleError(DioException error) {
    switch (error.response?.statusCode) {
      case 400:
        return ValidationException(error.response?.data['message'] ?? 'Validation failed');
      case 401:
        return UnauthorizedException('Invalid credentials');
      case 409:
        return ConflictException('User already exists');
      case 500:
        return ServerException('Server error');
      default:
        return NetworkException('Network error occurred');
    }
  }
}
```

### WebSocket Service

```typescript
// services/SocketService.ts
import io, { Socket } from 'socket.io-client';
import { ConfigService } from '../config/ConfigService';
import { SecureStorage } from '../utils/SecureStorage';

export class SocketService {
  private socket: Socket | null = null;
  private reconnectAttempts = 0;
  private maxReconnectAttempts = 5;
  private reconnectDelay = 1000;
  
  async connect(): Promise<Socket> {
    const token = await SecureStorage.getItem('auth_token');
    if (!token) {
      throw new Error('No authentication token');
    }

    return new Promise((resolve, reject) => {
      this.socket = io(`${ConfigService.wsUrl}/location`, {
        auth: { token },
        transports: ['websocket'],
        timeout: 5000,
      });

      this.socket.on('connect', () => {
        console.log('WebSocket connected');
        this.reconnectAttempts = 0;
        resolve(this.socket!);
      });

      this.socket.on('disconnect', () => {
        console.log('WebSocket disconnected');
        this.handleReconnect();
      });

      this.socket.on('connect_error', (error) => {
        console.error('WebSocket connection error:', error);
        reject(error);
      });

      this.socket.on('error', (error) => {
        console.error('WebSocket error:', error);
      });
    });
  }

  async joinJourney(journeyId: string): Promise<void> {
    if (!this.socket?.connected) {
      throw new Error('Socket not connected');
    }

    return new Promise((resolve, reject) => {
      this.socket!.emit('join-journey', { journeyId });
      
      this.socket!.once('joined-journey', (data) => {
        console.log('Joined journey:', data);
        resolve();
      });

      this.socket!.once('error', (error) => {
        reject(new Error(error.message));
      });
    });
  }

  sendLocationUpdate(locationUpdate: LocationUpdate): void {
    if (this.socket?.connected) {
      this.socket.emit('location-update', locationUpdate);
    } else {
      console.warn('Cannot send location update: socket not connected');
      // Fallback to REST API
      // apiService.sendLocationUpdate(locationUpdate);
    }
  }

  onLocationUpdate(callback: (data: any) => void): void {
    this.socket?.on('location-update', callback);
  }

  onLagAlert(callback: (alert: any) => void): void {
    this.socket?.on('lag-alert', callback);
  }

  onArrivalDetected(callback: (data: any) => void): void {
    this.socket?.on('arrival-detected', callback);
  }

  private handleReconnect(): void {
    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      console.error('Max reconnection attempts reached');
      return;
    }

    const delay = this.reconnectDelay * Math.pow(2, this.reconnectAttempts);
    this.reconnectAttempts++;

    setTimeout(() => {
      console.log(`Attempting to reconnect (${this.reconnectAttempts}/${this.maxReconnectAttempts})`);
      this.connect().catch(console.error);
    }, delay);
  }

  disconnect(): void {
    if (this.socket) {
      this.socket.disconnect();
      this.socket = null;
    }
  }
}

export const socketService = new SocketService();
```

### Location Tracking Hook

```typescript
// hooks/useLocationTracking.ts
import { useEffect, useRef, useCallback } from 'react';
import { Platform } from 'react-native';
import Geolocation from '@react-native-community/geolocation';
import { socketService } from '../services/SocketService';

interface LocationTrackingOptions {
  journeyId: string;
  updateInterval?: number;
  accuracy?: 'high' | 'balanced' | 'low';
}

export const useLocationTracking = ({
  journeyId,
  updateInterval = 10000,
  accuracy = 'high'
}: LocationTrackingOptions) => {
  const watchId = useRef<number | null>(null);
  const lastUpdateTime = useRef(0);

  const getAccuracyOption = () => {
    switch (accuracy) {
      case 'high':
        return { enableHighAccuracy: true, timeout: 15000, maximumAge: 5000 };
      case 'balanced':
        return { enableHighAccuracy: false, timeout: 10000, maximumAge: 10000 };
      case 'low':
        return { enableHighAccuracy: false, timeout: 5000, maximumAge: 30000 };
      default:
        return { enableHighAccuracy: true, timeout: 15000, maximumAge: 5000 };
    }
  };

  const sendLocationUpdate = useCallback((position: GeolocationPosition) => {
    const now = Date.now();
    if (now - lastUpdateTime.current < updateInterval) {
      return; // Throttle updates
    }

    const locationUpdate: LocationUpdate = {
      journeyId,
      location: {
        latitude: position.coords.latitude,
        longitude: position.coords.longitude,
      },
      accuracy: position.coords.accuracy,
      heading: position.coords.heading || undefined,
      speed: position.coords.speed || undefined,
      altitude: position.coords.altitude || undefined,
      metadata: {
        timestamp: position.timestamp,
        platform: Platform.OS,
      },
    };

    socketService.sendLocationUpdate(locationUpdate);
    lastUpdateTime.current = now;
  }, [journeyId, updateInterval]);

  const startTracking = useCallback(() => {
    if (watchId.current !== null) {
      return; // Already tracking
    }

    const options = getAccuracyOption();

    watchId.current = Geolocation.watchPosition(
      sendLocationUpdate,
      (error) => {
        console.error('Location tracking error:', error);
      },
      options
    );
  }, [sendLocationUpdate]);

  const stopTracking = useCallback(() => {
    if (watchId.current !== null) {
      Geolocation.clearWatch(watchId.current);
      watchId.current = null;
    }
  }, []);

  useEffect(() => {
    startTracking();
    return stopTracking;
  }, [startTracking, stopTracking]);

  return {
    startTracking,
    stopTracking,
    isTracking: watchId.current !== null,
  };
};
```

---

<function_calls>
<invoke name="TodoWrite">
<parameter name="todos">[{"content": "Explore codebase structure and identify all microservices", "status": "completed", "activeForm": "Exploring codebase structure and identifying microservices"}, {"content": "Analyze API Gateway and extract all routes", "status": "completed", "activeForm": "Analyzing API Gateway and extracting routes"}, {"content": "Document Auth Service endpoints and authentication flow", "status": "completed", "activeForm": "Documenting Auth Service endpoints and authentication flow"}, {"content": "Document Journey Service endpoints and data models", "status": "completed", "activeForm": "Documenting Journey Service endpoints and data models"}, {"content": "Document Location Service and real-time tracking", "status": "completed", "activeForm": "Documenting Location Service and real-time tracking"}, {"content": "Document Maps Service and Google Maps integration", "status": "completed", "activeForm": "Documenting Maps Service and Google Maps integration"}, {"content": "Document Notification Service and FCM setup", "status": "completed", "activeForm": "Documenting Notification Service and FCM setup"}, {"content": "Extract data models and create TypeScript/Dart interfaces", "status": "completed", "activeForm": "Extracting data models and creating TypeScript/Dart interfaces"}, {"content": "Create screen-to-API mapping for all 13 screens", "status": "completed", "activeForm": "Creating screen-to-API mapping for all 13 screens"}, {"content": "Generate Frontend Integration Guide document", "status": "completed", "activeForm": "Generating Frontend Integration Guide document"}]