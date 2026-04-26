# Tu-Link Flutter — Real-Time Journey Coordination Implementation

## Project Context

You are working on the **TuLink Flutter app** — a real-time convoy coordination mobile app. The app uses **Clean Architecture** (presentation → domain → data → core) with **Provider** for state management, **Dio** for REST calls, **Mapbox** for map rendering, and **Hive** for local cache.

The backend is a NestJS API at `api.dev.tulink.xyz` (dev) / `api.tulink.xyz` (prod). It uses a **hybrid dual-database** approach — already implemented and deployed:
- **Firebase Realtime Database (RTDB)** — live ephemeral positions per journey member
- **Firestore** — persistent journey state, history, geospatial queries
- **Redis** — hot cache for latest positions (port 6380)

This prompt focuses on the **mobile-side implementation** of real-time journey coordination — i.e. letting all members of an active convoy see each other move live on the same map.

### Tech stack (mobile)
- Flutter 3.11+ / Dart 3.x
- Provider (ChangeNotifier) for state
- Dio for REST (`lib/core/network/dio_client.dart`)
- Mapbox Maps Flutter SDK (`mapbox_maps_flutter: ^2.19.1`) for rendering
- Firebase SDKs — Auth is already wired; **Realtime Database SDK needs to be added**
- Manual DI via `ServiceLocator` (`lib/core/di/service_locator.dart`)
- Dark theme (carbon black `#0D0D0D`, electric red `#E8002D`, Rajdhani/Bebas headings, Inter body)

---

## Problem Being Solved

Today the app can create journeys, search destinations, and render the map. What it **cannot** do yet is show the convoy moving in real time. Specifically:

1. When I start or join an active journey, I do not see other members' avatars on my map.
2. When I drive, my own position is not being streamed to the backend.
3. There is no subscription to the live RTDB feed, so the map does not update as convoy members move.

We need to implement the **full live coordination loop** for an active journey:

- **Publish:** Mobile client reads device GPS → `POST /locations` to the backend on a cadence → backend writes to RTDB + Firestore + Redis.
- **Subscribe:** Mobile client subscribes directly to RTDB at `journeys/{journeyId}/members` → receives every member's live position → updates Mapbox annotations on screen.
- **Render:** Each member appears as an avatar marker on the map with heading, speed, and a lag/arrival state.

---

## Backend Contract (already live — do not change)

### REST endpoint: publish a location update

```
POST /locations
Authorization: Bearer <firebase-id-token>
Content-Type: application/json

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

**Rate limit:** server enforces `60 updates/minute` per user per journey (`LOCATION_UPDATE_RATE_LIMIT=60`). The client should respect this — see "Publish cadence" below.

### REST endpoint: snapshot of latest positions (for cold start / fallback)

```
GET /locations/journeys/{journeyId}/latest
Authorization: Bearer <firebase-id-token>
```

Returns:
```json
{
  "locations": {
    "user_wesley": { /* LocationUpdate object */ },
    "user_claude":  { /* LocationUpdate object */ }
  },
  "destination": { "latitude": -1.2921, "longitude": 36.8219 },
  "destinationAddress": "JKIA, Nairobi"
}
```

### RTDB subscription path (client subscribes directly)

```
journeys/{journeyId}/members/{userId}
```

Shape of each member node written by the backend:

```json
{
  "lat": -1.2921,
  "lng": 36.8219,
  "accuracy": 10.5,
  "heading": 90.0,
  "speed": 15.5,
  "altitude": 1795.0,
  "timestamp": 1735171200000,
  "userId": "user_wesley",
  "sequenceNumber": 42,
  "priority": "HIGH",
  "metadata": {
    "batteryLevel": 75,
    "isMoving": true,
    "statusChange": null
  }
}
```

**Architectural note:** the app **does not subscribe via WebSocket or REST polling** for live positions. It subscribes directly to RTDB using the Firebase SDK. REST is used only for (a) publishing our own position and (b) cold-start snapshot fallback if RTDB is slow to connect.

---

## Scope of This Task

Build the full mobile-side live coordination feature, end to end, across all Clean Architecture layers. Deliver:

### 1. Dependencies — add to `pubspec.yaml`
- `firebase_database` (matching the existing Firebase core version)
- `geolocator` (for device GPS streaming) — if not already present
- `permission_handler` — if not already present

Run `flutter pub get` and regenerate code where needed.

### 2. New feature module: `features/convoy/`

Follow the existing feature-first Clean Architecture structure exactly as `features/auth/` and `features/journeys/` do. Create:

```
features/convoy/
├── domain/
│   ├── entities/
│   │   ├── member_position.dart        # immutable snapshot of one member's position
│   │   └── convoy_snapshot.dart        # map<userId, MemberPosition> + destination
│   ├── repositories/
│   │   └── convoy_repository.dart      # abstract interface
│   └── usecases/
│       ├── stream_convoy_positions.dart  # returns Stream<ConvoySnapshot>
│       ├── publish_my_position.dart      # sends one GPS update
│       └── fetch_latest_snapshot.dart    # cold-start REST fallback
│
├── data/
│   ├── models/
│   │   ├── member_position_model.dart  # fromJson/fromRtdb + toEntity
│   │   └── location_update_dto.dart    # outbound POST /locations payload
│   ├── datasources/
│   │   ├── convoy_rtdb_data_source.dart     # Firebase RTDB subscription
│   │   └── convoy_remote_data_source.dart   # POST /locations + GET latest
│   ├── services/
│   │   └── convoy_api_service.dart     # Dio-based REST client
│   └── repositories/
│       └── convoy_repository_impl.dart # coordinates RTDB + REST
│
└── presentation/
    ├── providers/
    │   └── convoy_provider.dart        # ChangeNotifier managing live state
    └── widgets/
        ├── member_avatar_marker.dart   # Mapbox point annotation widget
        ├── convoy_status_bar.dart      # top HUD: "IN PROGRESS", member count
        └── convoy_bottom_sheet.dart    # member list with status chips
```

### 3. Integration into existing map screen

- File to modify: `lib/features/maps/presentation/tulink_map_screen.dart`
- When the screen is opened with an active `journeyId`, wire the `ConvoyProvider` to start both **publish** (my GPS → backend) and **subscribe** (RTDB → UI state).
- Render each member from `ConvoyProvider.snapshot.members` as a Mapbox `PointAnnotation` with the avatar marker widget.
- Smoothly animate marker position changes (don't jump; interpolate over ~500ms).

### 4. Register in `ServiceLocator`

Add the new repository, data sources, API service, and provider to `lib/core/di/service_locator.dart` following the existing initialization order (infrastructure → API services → data sources → repositories → providers).

---

## Detailed Requirements

### Publish cadence (my GPS → backend)

- Use `Geolocator.getPositionStream` with `LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5)` — emit on 5m movement.
- **Throttle** published updates to **max 1 per second** regardless of how frequently the GPS stream emits — this keeps us well under the server's 60/min rate limit and leaves headroom for retries.
- If the user hasn't moved (`speed < 0.5 m/s`) for >15 seconds, back off to 1 update every 10 seconds (heartbeat mode).
- On publish failure, do **not** retry aggressively — log and continue. The next tick will overwrite anyway. RTDB authoritative state is what the rest of the convoy sees.
- Include `batteryLevel` in metadata using `battery_plus` if available; otherwise omit the field (do not hardcode).

### Subscribe (RTDB → UI)

- Initialize Firebase RTDB with the same Firebase app used for Auth. Region/URL should come from `AppConfig` (add `firebaseRtdbUrl` there). In dev, this is the default RTDB instance of the `tulink-dev` project.
- Auth: the mobile Firebase SDK will already be signed in (we use Firebase Auth for the app). RTDB rules should accept authenticated reads — do not pass any manual auth header.
- Subscribe to `journeys/{journeyId}/members` using `onValue`. On every snapshot, build a fresh `ConvoySnapshot` and push it to the provider.
- Keep a local map keyed by `userId`. Removed children (member leaves) should remove their marker.
- **Do not display my own avatar** as a convoy marker — my position is represented by Mapbox's built-in user location puck. (Filter out `currentUser.id` from the subscription result when rendering.)

### Cold start behavior

- On screen open, **immediately** call `GET /locations/journeys/{journeyId}/latest` via REST to populate the initial snapshot — do not wait for RTDB's first frame (which can take 1-3 seconds on a cold connection).
- Once RTDB's first snapshot arrives, it **supersedes** the REST response entirely. No merging logic.

### Error & lifecycle handling

- On network loss, show a subtle banner ("Reconnecting…") but keep the last-known positions on screen.
- On `AppLifecycleState.paused` (backgrounded), stop the GPS publish stream but keep the RTDB listener alive — iOS will suspend it anyway; we just want clean resource management.
- On journey end (provider receives journey-end event), cancel both the GPS publish stream and the RTDB subscription, and navigate to the summary screen.
- All errors funneled through the existing `Failure` types in `lib/core/errors/failure.dart`. Add a new `ConvoyFailure` subtype if none of the existing ones fit cleanly.

### State management (`ConvoyProvider`)

Expose at minimum:

```dart
class ConvoyProvider extends ChangeNotifier {
  ConvoySnapshot? get snapshot;                      // current members + destination
  bool get isPublishing;                             // am I streaming my GPS?
  bool get isSubscribed;                             // RTDB listener active?
  ConnectionState get connectionState;                // connecting / connected / reconnecting
  String? get errorMessage;

  Future<void> startCoordination(String journeyId);  // begin publish + subscribe
  Future<void> stopCoordination();                   // tear down both
}
```

The provider should **not** know about Mapbox or Dio directly — only about the repository interface.

### UI requirements (match existing design system)

- Avatar markers: 40×40 circular avatar with a 2px electric-red border ring, rotated to heading. If user has no avatar, use their initial on a brushed-steel (`#2A2A2A`) background.
- Stale positions (>30s since last update) render at 50% opacity with no border glow.
- Top status bar: `IN PROGRESS` label with a pulsing red dot, member count ("4 MEMBERS"), and ETA if available.
- Bottom sheet: list of members with name, speed (km/h), distance from destination, and a status chip (`MOVING` / `STOPPED` / `ARRIVED` / `LAG`).
- All typography: Rajdhani for numeric/stat values, Inter for names and body text. Uppercase labels for status states.
- All colors via `TulinkColors.dark` — do not introduce new color constants.

---

## Testing Requirements

Create tests matching the existing test structure in `test/`:

- **Unit tests** (`test/unit/features/convoy/`):
  - `MemberPositionModel.fromRtdb` — handles missing optional fields, clamps heading to 0-360, coerces numeric types.
  - `ConvoyRepositoryImpl` — RTDB stream emits correct `ConvoySnapshot`s; REST fallback used on cold start.
  - Throttle logic in publish service — 10 rapid GPS events → max 1 publish.
- **Provider tests** (`test/unit/features/convoy/providers/`):
  - `ConvoyProvider.startCoordination` transitions state correctly.
  - Stop tears down both streams.
- **Widget tests** (`test/widget/features/convoy/`):
  - `MemberAvatarMarker` renders heading rotation.
  - Stale state reduces opacity.

Mock the repository using the existing mockito pattern.

---

## Non-Goals for This Task (explicitly out of scope)

- Lag detection UI — the backend flags lagging members, but the full "Member Lag Alert Screen" overlay is its own separate task. For now just surface the `LAG` chip if the backend sends `statusChange: 'LAG'` in metadata.
- Arrival celebrations / haptics.
- Route polyline rendering between member and destination.
- Offline queue for publishes. If offline, drop the update.
- iOS background location permission beyond foreground-while-in-use. Background mode is a later task.

---

## Acceptance Criteria

Run through this checklist before considering the task complete:

1. On a physical device (iOS or Android), I can start a journey, and a second device signed in as a different user who joins that journey sees my avatar moving smoothly on their map within ~2 seconds of my device moving.
2. Both devices see each other — neither device shows its own avatar as a convoy marker (only the built-in user puck).
3. Killing the network on one device and restoring it 10s later: the other device's view of the first device pauses, then resumes, with no crash and no stuck ghost markers.
4. Ending the journey removes the RTDB listener (verify in Firebase console: `journeys/{id}/members` drains after cleanup) and navigates to summary.
5. No publishes exceed 1/sec even under a fast GPS stream (verify with a log counter or breakpoint).
6. `flutter analyze` passes with zero warnings.
7. All new tests pass and existing tests remain green.
8. `ServiceLocator` initializes cleanly with no missing dependencies.

---

## Constraints & Reminders

- **Do not** modify `features/location/` if it already exists for a different purpose — this convoy module is a new sibling feature focused on multi-user real-time coordination, distinct from single-user location services.
- **Do not** introduce WebSocket client code. The backend has a `location.gateway.ts` but the mobile strategy is RTDB-direct, not WebSocket.
- **Do not** add any new third-party package beyond `firebase_database`, `geolocator`, `permission_handler`, and `battery_plus` (if used). Keep the dependency tree lean.
- **Preserve** all existing patterns: `Failure`-based error returns, ChangeNotifier provider pattern, ServiceLocator DI, feature-first structure, entity/model split.
- **Ask before assuming** if anything about the existing `features/journeys/` provider or the `MapProvider` API would block clean integration — do not guess.

---

## Deliverables

1. All new files listed under the scope section, fully implemented.
2. Modified files: `pubspec.yaml`, `lib/core/config/app_config.dart` (add RTDB URL), `lib/core/di/service_locator.dart`, `lib/features/maps/presentation/tulink_map_screen.dart`.
3. Tests covering the new code.
4. A short `docs/CONVOY_COORDINATION.md` explaining the publish/subscribe architecture, cadence rules, and how to debug the RTDB listener.
5. A summary of any backend assumptions you had to make (e.g. RTDB rules, field names) so we can verify them against the deployed server.

Begin by reading `CLAUDE.md`, `lib/core/di/service_locator.dart`, `lib/features/journeys/presentation/providers/journey_provider.dart`, and `lib/features/maps/presentation/tulink_map_screen.dart` so your implementation matches the existing patterns exactly.
