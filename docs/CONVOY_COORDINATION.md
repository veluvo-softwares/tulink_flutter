# TuLink Convoy Coordination - Real-Time Implementation

## Overview

The TuLink convoy coordination feature enables real-time tracking and coordination of multiple journey participants through a backend-mediated architecture. This implementation follows Clean Architecture principles and integrates with the existing TuLink journey management system.

---

## Architecture

### Backend-Mediated Real-Time Updates

The convoy coordination uses a **backend-mediated architecture** with WebSocket connections for real-time communication:

```
Mobile App → REST API (Publish) + WebSocket (Real-time) ← Backend
     ↓                                        ↓
  Publish GPS                         Live Position Updates
```

**Why Backend-Mediated?**
- **Security & Validation**: Authentication, authorization, and journey membership validation
- **Smart Processing**: Rate limiting, priority calculation, lag detection, arrival detection
- **Multi-Database Coordination**: WebSocket (live), Firestore (history), Redis (cache)
- **Convoy Intelligence**: Leader tracking, movement analysis, battery-aware throttling

---

## Data Flow

### Publishing Location Updates

1. **GPS Stream**: `Geolocator.getPositionStream()` with 5m distance filter
2. **Throttling**: Max 1 update per second (respects 60/min server limit)
3. **Heartbeat Mode**: 10-second intervals when stationary for 15+ seconds
4. **API Call**: `POST /locations` with location data and metadata
5. **Backend Processing**: Server validates, processes, and writes to RTDB/Firestore/Redis

### Receiving Real-Time Updates

1. **WebSocket Connection**: Socket.IO connection to `/location` namespace
2. **Journey Subscription**: Join journey room via `join-journey` event
3. **Real-Time Updates**: Receive `location-update` and `latest-locations` events
4. **Cold Start**: Initial REST API call for immediate data availability
5. **Connection Management**: Automatic reconnection with exponential backoff and REST polling fallback

---

## API Contracts

### Publishing Endpoint

**POST /locations**
```json
{
  "journeyId": "journey_abc123",
  "location": {
    "latitude": -1.2921,
    "longitude": 36.8219
  },
  "timestamp": 1735171200000,
  "accuracy": 10.5,
  "altitude": 1795.0,
  "heading": 90.0,
  "speed": 15.5,
  "metadata": {
    "batteryLevel": 75,
    "isMoving": true
  }
}
```

**Rate Limit**: 60 updates/minute per user per journey

### Cold Start Endpoint

**GET /locations/journeys/{journeyId}/latest**
```json
{
  "locations": {
    "user_wesley": { /* LocationUpdate object */ },
    "user_claude": { /* LocationUpdate object */ }
  },
  "destination": { "latitude": -1.2921, "longitude": 36.8219 },
  "destinationAddress": "JKIA, Nairobi"
}
```

### WebSocket Events

**Connection**: `wss://api.dev.tulink.xyz/location`

**1. Join Journey**
```javascript
socket.emit('join-journey', { journeyId: 'journey_abc123' });
```

**2. Receive Location Updates**
```javascript
socket.on('location-update', {
  "userId": "user_wesley",
  "location": {
    "latitude": -1.2921,
    "longitude": 36.8219
  },
  "timestamp": 1735171200000,
  "accuracy": 10.5,
  "heading": 90.0,
  "speed": 15.5,
  "altitude": 1795.0,
  "sequenceNumber": 42,
  "priority": "HIGH",
  "metadata": {
    "batteryLevel": 75,
    "isMoving": true
  }
});
```

**3. Publish Location (via WebSocket)**
```javascript
socket.emit('location-update', {
  "journeyId": "journey_abc123",
  "location": {
    "latitude": -1.2921,
    "longitude": 36.8219
  },
  "timestamp": 1735171200000,
  "accuracy": 10.5,
  "altitude": 1795.0,
  "heading": 90.0,
  "speed": 15.5,
  "metadata": {
    "batteryLevel": 75,
    "isMoving": true
  }
});
```

**4. Connection Events**
- `connection-status`: Connection state updates
- `joined-journey`: Successful journey join confirmation
- `participant-joined`: New member joins convoy
- `participant-left`: Member leaves convoy
- `lag-alert`: Member lagging detection
- `arrival-detected`: Member reaches destination

---

## Implementation Details

### Publish Cadence Rules

```dart
// GPS stream configuration
const locationSettings = LocationSettings(
  accuracy: LocationAccuracy.high,
  distanceFilter: 5, // Emit on 5m movement
);

// Throttling logic
if (timeSinceLastPublish < 1000ms) return; // Max 1/second

// Heartbeat mode (stationary)
if (!isMoving && timeSinceMovement > 15s) {
  // Switch to 10-second heartbeat mode
  publishEvery(10.seconds);
}
```

### Connection State Management

```dart
enum ConvoyConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}
```

### Error Handling

- **Network Loss**: Keep last-known positions on screen, activate REST polling fallback
- **WebSocket Disconnect**: Automatic reconnection with exponential backoff (1s, 2s, 4s, 8s, 15s, 30s)
- **Publish Failures**: Fallback from WebSocket to REST API automatically
- **Rate Limiting**: Graceful throttling with user feedback
- **Connection States**: `disconnected`, `connecting`, `connected`, `reconnecting`, `error`

---

## UI Components

### ConvoyStatusBar
- **Location**: Top overlay during active journeys
- **Features**: Pulsing status indicator, member count, connection state
- **States**: IN PROGRESS, MEMBERS LAGGING, ALL ARRIVED, CONNECTING

### ConvoyBottomSheet  
- **Trigger**: Tap convoy status bar
- **Content**: Member list with status chips, speed, battery, last update
- **Stats**: Total members, active count, moving count, convoy status

### MemberAvatarMarker
- **Rendering**: Map markers for convoy members (excludes current user)
- **Visual States**: 
  - Active: Electric red border with glow
  - Stale (30s+): 50% opacity, no glow  
  - Low battery: Orange border
  - Lagging: Orange-red highlight

---

## Member Status Logic

```dart
String get memberStatus {
  if (hasArrived) return 'ARRIVED';
  if (isLagging) return 'LAG';
  if (isStale) return 'OFFLINE';  // 30+ seconds
  if (isMoving && speed > 0.5) return 'MOVING';
  return 'STOPPED';
}
```

### Status Indicators
- **MOVING**: Green - Member is actively moving (speed > 0.5 m/s)
- **STOPPED**: Gray - Member is stationary but connected
- **LAG**: Orange - Backend flagged member as lagging behind convoy
- **ARRIVED**: Blue - Member reached destination
- **OFFLINE**: Gray - No updates for 30+ seconds

---

## Testing Strategy

### Unit Tests
- **MemberPositionModel**: JSON parsing, heading normalization, missing fields
- **ConvoyWebSocketDataSource**: WebSocket event handling, connection management, error scenarios
- **ConvoyRepository**: WebSocket + REST fallback coordination, connection state management
- **Throttling Logic**: GPS event throttling, heartbeat mode transitions

### Widget Tests  
- **MemberAvatarMarker**: Heading rotation, status colors, stale state opacity
- **ConvoyStatusBar**: Status text updates, connection indicators, member counts

### Integration Tests
- **End-to-End Flow**: GPS → Backend → WebSocket → UI updates
- **Network Scenarios**: Connection loss, reconnection, WebSocket-to-REST fallback handling
- **Hybrid Architecture**: WebSocket real-time + REST polling coordination

---

## Debugging Guide

### Common Issues

**1. WebSocket Connection Fails**
```dart
// Check WebSocket configuration
print('WebSocket URL: ${AppConfig.webSocketUrl}');

// Verify auth state and token
final authProvider = context.read<AuthProvider>();
final token = await authProvider.getAuthToken();
print('User signed in: ${authProvider.isSignedIn}');
print('Auth token available: ${token != null}');
```

**2. GPS Not Publishing**
```dart
// Check permissions
final locationStatus = await Permission.location.status;
print('Location permission: $locationStatus');

// Check service enabled
final serviceEnabled = await Geolocator.isLocationServiceEnabled();
print('Location service enabled: $serviceEnabled');
```

**3. Rate Limiting Issues**
```dart
// Monitor publish frequency
print('Last publish: ${_lastPublishTime}');
print('Time since last: ${DateTime.now().difference(_lastPublishTime!)}');
```

**4. Markers Not Updating**
```dart
// Check convoy snapshot
final snapshot = convoyProvider.snapshot;
print('Convoy members: ${snapshot?.members.length}');
print('Member positions: ${snapshot?.membersList}');
```

### WebSocket Debugging

1. **Monitor Connection**: Check WebSocket connection state in developer tools
2. **Event Tracking**: Log WebSocket events in browser/app console
3. **Network Tab**: Verify WebSocket handshake and messages in browser DevTools
4. **Backend Logs**: Check server logs for WebSocket connection errors

**WebSocket Connection Monitoring**
```dart
// Monitor connection state changes
convoyProvider.connectionStateStream.listen((state) {
  print('WebSocket state: $state');
});

// Check current connection
print('WebSocket connected: ${convoyProvider.isConnected}');
```

### Network Debugging

```bash
# Monitor API calls
curl -X POST https://api.dev.tulink.xyz/locations \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"journeyId":"test","location":{"latitude":-1.2921,"longitude":36.8219},"timestamp":1735171200000}'

# Test WebSocket connection
wscat -c "wss://api.dev.tulink.xyz/location?token=$FIREBASE_TOKEN"

# Send test events
{"type": "join-journey", "data": {"journeyId": "test"}}
{"type": "location-update", "data": {"journeyId": "test", "location": {"latitude": -1.2921, "longitude": 36.8219}, "timestamp": 1735171200000}}
```

---

## Performance Considerations

### Battery Optimization
- **Heartbeat Mode**: Reduces GPS usage when stationary
- **Battery Monitoring**: Include battery level in metadata
- **Background Handling**: Respect app lifecycle states

### Network Efficiency
- **Throttling**: Max 1 update/second prevents spam
- **Smart Intervals**: Longer intervals when stationary
- **Compression**: Minimal JSON payload structure

### Memory Management
- **Stream Cleanup**: Properly dispose RTDB subscriptions
- **Marker Recycling**: Reuse map annotations where possible
- **State Management**: Clean up convoy state on navigation

---

## Backend Integration Notes

The convoy coordination relies on backend services that provide:

1. **Location Processing Service** (`location.service.ts`):
   - Rate limiting and validation
   - Priority calculation based on movement/battery
   - Multi-database coordination

2. **Lag Detection Service** (`lag-detection.service.ts`):
   - Identifies members falling behind convoy
   - Triggers `statusChange: 'LAG'` notifications

3. **Arrival Detection Service** (`arrival-detection.service.ts`):
   - Detects when members reach destination
   - Triggers `statusChange: 'ARRIVED'` notifications

4. **Priority Service** (`priority.service.ts`):
   - Calculates update priority (HIGH/MEDIUM/LOW)
   - Optimizes RTDB update frequency

### Backend Assumptions
- Server enforces 60 updates/minute rate limit
- RTDB rules allow authenticated reads
- Firebase Auth tokens are properly configured
- Backend handles token validation and user authorization

---

## Future Enhancements

### Potential Improvements
1. **Offline Support**: Queue location updates during network loss
2. **Route Visualization**: Show polyline between members and destination
3. **Voice Notifications**: Audio alerts for convoy status changes
4. **Advanced Analytics**: Journey completion metrics and insights
5. **Background Location**: Continue tracking when app is backgrounded

### Scalability Considerations
- **Large Convoys**: Optimize for 50+ member groups with WebSocket room management
- **Global Deployment**: Regional WebSocket servers with load balancing
- **Advanced Caching**: Redis-based position caching and session management
- **REST Fallback**: Graceful degradation to polling when WebSocket unavailable
- **Connection Pooling**: Efficient WebSocket connection management for concurrent users

---

This implementation provides a robust foundation for real-time convoy coordination while maintaining the benefits of backend-mediated architecture for security, validation, and intelligent processing.