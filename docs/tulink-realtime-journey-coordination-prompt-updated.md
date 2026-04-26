# Tu-Link Flutter — Real-Time Journey Coordination Implementation

## Project Context

You are working on the **TuLink Flutter app** — a real-time convoy coordination mobile app. The app uses **Clean Architecture** (presentation → domain → data → core) with **Provider** for state management, **Dio** for REST calls, **Mapbox** for map rendering, and **Hive** for local cache.

The backend is a NestJS API at `api.dev.tulink.xyz` (dev) / `api.tulink.xyz` (prod). It is the **single source of truth** for convoy state and provides:
- A REST endpoint to publish my own position (`POST /locations`)
- A REST endpoint for snapshot reads (`GET /locations/journeys/{id}/latest`)
- A WebSocket gateway for live fan-out of position updates (`location.gateway.ts`)

This prompt focuses on the **mobile-side implementation** of real-time journey coordination — i.e. letting all members of an active convoy see each other move live on the same map.

### Tech stack (mobile)
- Flutter 3.11+ / Dart 3.x
- Provider (ChangeNotifier) for state
- Dio for REST (`lib/core/network/dio_client.dart`)
- Mapbox Maps Flutter SDK (`mapbox_maps_flutter: ^2.19.1`) for rendering
- Firebase Auth (already wired) — used for the bearer token on REST and the WS handshake
- Manual DI via `ServiceLocator` (`lib/core/di/service_locator.dart`)
- Dark theme (carbon black `#0D0D0D`, electric red `#E8002D`, Rajdhani/Bebas headings, Inter body)

---

## Architectural Constraint — Backend-Mediated Only

**The mobile app must never connect to Firebase Realtime Database, Firestore, or Redis directly.** All convoy coordination flows through the backend. The backend handles RTDB, Firestore, and Redis writes server-side; it owns rate limiting, priority calculation, sequence numbering, lag detection, arrival detection, and authorization.

Mobile responsibilities are limited to:
1. **Publish:** Stream device GPS to `POST /locations`.
2. **Subscribe:** Connect to the backend WebSocket gateway and listen for live position updates broadcast by the server.
3. **Cold-start fallback:** On screen open and on WS disconnect, fetch a snapshot via `GET /locations/journeys/{id}/latest` to seed the UI immediately.
4. **Render:** Update Mapbox annotations as new positions arrive.

Do not import `firebase_database`. Do not subscribe to any Firebase RTDB path directly. Do not bypass the backend "for performance."

---

## Problem Being Solved

Today the app can create journeys, search destinations, and render the map. What it **cannot** do yet is show the convoy moving in real time. Specifically:

1. When I start or join an active journey, I do not see other members' avatars on my map.
2. When I drive, my own position is not being streamed to the backend.
3. There is no WebSocket subscription to the backend's live broadcast, so the map never updates as convoy members move.

We need to implement the **full live coordination loop**:
- **Publish** my GPS to `POST /locations` on a sane cadence.
- **Subscribe** to the backend WebSocket gateway for live position broadcasts.
- **Fallback** to REST polling if the WebSocket disconnects, so the map stays alive.
- **Render** each member as an animated avatar marker with heading, speed, and stale-state opacity.

---

## Backend Contract

### REST: publish a location update

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

**Server-enforced rate limit:** 60 updates/minute per user per journey. The client must throttle to stay well under this — see "Publish cadence" below.

### REST: snapshot of latest positions (cold start + fallback)

```
GET /locations/journeys/{journeyId}/latest
Authorization: Bearer <firebase-id-token>
```

Returns:
```json
{
  "locations": {
    "user_wesley": { /* MemberPosition */ },
    "user_claude":  { /* MemberPosition */ }
  },
  "destination": { "latitude": -1.2921, "longitude": 36.8219 },
  "destinationAddress": "JKIA, Nairobi"
}
```

### WebSocket: live position broadcast

The backend WebSocket gateway is in `src/modules/location/location.gateway.ts` on the server. **Before implementing anything WS-related, the implementer must obtain the exact contract** — event names, namespace, auth handshake, and payload shape — from one of these sources, in order of preference:

1. The deployed gateway file (Wesley can paste it or share the path).
2. Existing backend integration tests / docs in `docs/api-response-format-documentation.md`.
3. A direct check by connecting and logging the first few events.

**Assume Socket.IO v4** (NestJS's default WebSocket adapter is `@nestjs/platform-socket.io`). Use the `socket_io_client` Dart package. If the gateway turns out to be a raw WebSocket (`@WebSocketGateway` with `transports: ['websocket']` only), swap to `web_socket_channel`.

**Assumed event contract** — verify against the actual gateway and adjust:

| Direction | Event name | Payload |
|---|---|---|
| Client → Server | `subscribe:journey` | `{ journeyId: string }` |
| Server → Client | `location:update` | One `MemberPosition` |
| Server → Client | `member:joined` | `{ userId, name }` |
| Server → Client | `member:left` | `{ userId }` |
| Server → Client | `journey:ended` | `{ journeyId, reason }` |
| Client → Server | `unsubscribe:journey` | `{ journeyId: string }` |

**Auth:** pass the Firebase ID token as either an `auth` payload during connection or an `Authorization` header — whichever the gateway expects. NestJS Socket.IO gateways usually accept `auth: { token: '...' }` in `io.connect(url, { auth: ... })`.

**Connection URL:** `${AppConfig.baseUrl}` with the gateway's namespace appended if any (commonly `/locations` or `/convoy`).

### Shape of a MemberPosition (consistent across REST and WS)

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

`metadata.statusChange` may be one of `null`, `"LAG"`, `"ARRIVED"`, `"REJOINED"` — surface these in the UI as status chips but do not implement full lag/arrival overlays in this task.

---

## Scope of This Task

Build the full mobile-side live coordination feature, end to end, across all Clean Architecture layers.

### 1. Dependencies — add to `pubspec.yaml`
- `socket_io_client: ^2.x` (assumed; confirm against gateway)
- `geolocator: ^10.x` (if not already present)
- `permission_handler: ^11.x` (if not already present)
- `battery_plus: ^5.x` (optional; for batteryLevel metadata)

Run `flutter pub get` and regenerate code (`build_runner`) where needed.

### 2. New feature module: `features/convoy/`

Follow the existing feature-first Clean Architecture structure exactly as `features/auth/` and `features/journeys/` do:

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
│       └── fetch_latest_snapshot.dart    # REST snapshot (cold start + fallback)
│
├── data/
│   ├── models/
│   │   ├── member_position_model.dart  # fromJson + toEntity (used by both WS and REST)
│   │   └── location_update_dto.dart    # outbound POST /locations payload
│   ├── datasources/
│   │   ├── convoy_websocket_data_source.dart  # Socket.IO connection + event handling
│   │   └── convoy_remote_data_source.dart     # POST /locations + GET latest
│   ├── services/
│   │   └── convoy_api_service.dart     # Dio-based REST client
│   └── repositories/
│       └── convoy_repository_impl.dart # coordinates WS + REST fallback
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
- When the screen is opened with an active `journeyId`, wire the `ConvoyProvider` to start both **publish** (my GPS → backend) and **subscribe** (WS → UI state, with REST fallback).
- Render each member from `ConvoyProvider.snapshot.members` as a Mapbox `PointAnnotation` with the avatar marker widget.
- Smoothly animate marker position changes — interpolate over ~500ms; do not jump.

### 4. Register in `ServiceLocator`

Add the new repository, data sources, API service, WebSocket data source, and provider to `lib/core/di/service_locator.dart`, following the existing initialization order (infrastructure → API services → data sources → repositories → providers).

---

## Detailed Requirements

### Publish cadence (my GPS → `POST /locations`)

- Use `Geolocator.getPositionStream` with `LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5)` — emit on 5m movement.
- **Throttle** published updates to **max 1 per second** regardless of how frequently the GPS stream emits — keeps us well under the server's 60/min and leaves headroom.
- If the user hasn't moved (`speed < 0.5 m/s`) for >15 seconds, back off to 1 update every 10 seconds (heartbeat mode).
- On publish failure, do **not** retry aggressively — log, increment a counter, and continue. The next tick will overwrite anyway.
- Include `batteryLevel` if `battery_plus` is available; otherwise omit (do not hardcode).

### Subscribe via WebSocket (primary live channel)

- On `startCoordination(journeyId)`, connect to the gateway with the Firebase ID token in the auth payload.
- Emit `subscribe:journey` (or whatever the gateway expects) with `{ journeyId }`.
- Listen for `location:update` events. Each payload is one `MemberPosition`. Merge it into the in-memory snapshot keyed by `userId`.
- Listen for `member:left` and remove that user from the snapshot.
- Listen for `journey:ended` and tear down both publish and subscribe streams.
- On receiving an updated `MemberPosition` for myself (current user), **ignore it for rendering** — my position is the Mapbox user puck, not a convoy marker. (But still update internal state if needed for stats.)
- Heartbeat / ping handling: rely on Socket.IO defaults unless the gateway specifies otherwise.

### REST fallback (when WS is unavailable)

- On screen open, call `GET /locations/journeys/{id}/latest` **immediately** to seed the UI — do not wait for WS handshake (cold connect can take 1-3s).
- Once the WS delivers its first `location:update`, the WS becomes the source of truth.
- If WS disconnects (network drop, server restart), enter **polling fallback mode**: call `GET /locations/journeys/{id}/latest` every **3 seconds** until WS reconnects.
- Cap reconnect attempts: exponential backoff starting at 1s, doubling up to 30s max. Continue polling fallback throughout.
- When WS reconnects successfully, stop the polling timer and resume real-time stream.
- Surface connection state to the UI via `ConvoyProvider.connectionState` (`connecting | live | reconnecting | offline`).

### Lifecycle handling

- On `AppLifecycleState.paused` (backgrounded): stop the GPS publish stream; **disconnect** the WS to free resources. iOS will suspend it anyway.
- On `AppLifecycleState.resumed`: reconnect WS, restart GPS publish, and immediately fetch a REST snapshot to repaint quickly.
- On journey end (provider receives `journey:ended` event): cancel both streams, navigate to summary screen.
- All errors funneled through the existing `Failure` types in `lib/core/errors/failure.dart`. Add a `ConvoyFailure` subtype if none of the existing ones fit cleanly.

### State management (`ConvoyProvider`)

```dart
class ConvoyProvider extends ChangeNotifier {
  ConvoySnapshot? get snapshot;                     // current members + destination
  bool get isPublishing;                            // am I streaming my GPS?
  ConvoyConnectionState get connectionState;        // connecting | live | reconnecting | offline
  String? get errorMessage;

  Future<void> startCoordination(String journeyId); // begin publish + subscribe
  Future<void> stopCoordination();                  // tear down both
}
```

The provider must **not** know about Mapbox, Dio, or Socket.IO directly — only the repository interface.

### UI requirements (match existing design system)

- **Avatar markers:** 40×40 circular avatar, 2px electric-red border ring, rotated to heading. If user has no avatar, use their initial on a brushed-steel `#2A2A2A` background.
- **Stale positions** (>30s since last update): render at 50% opacity with no border glow.
- **Top status bar:** `IN PROGRESS` label with a pulsing red dot, member count ("4 MEMBERS"), and ETA if available.
- **Bottom sheet:** list of members with name, speed (km/h), distance from destination, and a status chip (`MOVING` / `STOPPED` / `ARRIVED` / `LAG`).
- **Connection state indicator:** subtle banner near the top — `LIVE` (red dot, no banner), `RECONNECTING` (amber, "Reconnecting…"), `OFFLINE` (silver, "Showing last known positions").
- All typography: Rajdhani for numeric/stat values, Inter for names and body text. Uppercase labels for status states.
- All colors via `TulinkColors.dark` — do not introduce new color constants.

---

## Testing Requirements

Create tests matching the existing test structure in `test/`:

- **Unit tests** (`test/unit/features/convoy/`):
  - `MemberPositionModel.fromJson` — handles missing optional fields, clamps heading 0-360, coerces numerics.
  - `ConvoyRepositoryImpl` — WS stream emits correct snapshots; REST fallback kicks in on WS disconnect; WS reconnect cancels polling.
  - Throttle logic in publish — 10 rapid GPS events → max 1 publish.
- **Provider tests:**
  - `startCoordination` transitions `connectionState` correctly through `connecting → live`.
  - `stopCoordination` tears down both streams.
  - WS disconnect transitions to `reconnecting`, REST fallback fires.
- **Widget tests:**
  - `MemberAvatarMarker` renders heading rotation correctly.
  - Stale state reduces opacity to 50%.

Use the existing mockito pattern for mocks. Mock the WS data source as a controllable `StreamController`.

---

## Non-Goals for This Task (explicitly out of scope)

- Lag detection UI overlay — surface the `LAG` chip if backend sends it, but don't build the full alert screen.
- Arrival celebrations / haptics.
- Route polyline rendering between member and destination.
- Offline publish queue — if offline, drop the update.
- iOS background location permission beyond foreground-while-in-use.
- Direct Firebase RTDB connections — explicitly forbidden by the architecture.

---

## Acceptance Criteria

Run through this checklist before considering the task complete:

1. On a physical device, I can start a journey, and a second device signed in as a different user (joined to that journey) sees my avatar moving smoothly on their map within ~1 second of my device moving.
2. Both devices see each other; neither shows its own avatar as a convoy marker (only the built-in user puck).
3. Killing the network on one device for 10s and restoring it: the other device's view pauses, falls back to REST polling silently, then resumes WS streaming on reconnect — no crash, no stuck ghost markers.
4. Force-quitting the WS connection (or restarting the backend) triggers exponential backoff reconnect; UI shows `RECONNECTING` banner; positions stay visible from REST polling.
5. Ending the journey tears down both streams cleanly and navigates to summary.
6. No publishes exceed 1/sec even under a fast GPS stream (verify with a counter).
7. `flutter analyze` passes with zero warnings.
8. All new tests pass; existing tests remain green.
9. `ServiceLocator` initializes cleanly with no missing dependencies.
10. No Firebase RTDB imports anywhere in the code.

---

## Constraints & Reminders

- **The mobile app never connects to Firebase RTDB, Firestore, or Redis directly.** All state flows through the backend.
- **Do not introduce WebSocket polling on top of WS** — use Socket.IO's built-in reconnection. REST polling is only the *fallback* when WS is fully disconnected.
- **Do not modify backend code** as part of this task. If the WebSocket contract is unclear, stop and ask Wesley to share `location.gateway.ts`.
- **Preserve existing patterns:** `Failure`-based error returns, ChangeNotifier provider pattern, ServiceLocator DI, feature-first structure, entity/model split.
- **Do not** add third-party packages beyond those listed.
- **Ask before assuming** if anything about `features/journeys/` provider or `MapProvider` API would block clean integration.

---

## Deliverables

1. All new files listed under the scope section, fully implemented.
2. Modified files: `pubspec.yaml`, `lib/core/di/service_locator.dart`, `lib/features/maps/presentation/tulink_map_screen.dart`.
3. Tests covering the new code.
4. A short `docs/CONVOY_COORDINATION.md` covering: WS event contract used, publish cadence rules, REST fallback strategy, reconnect/backoff behavior, and how to debug (e.g. enabling Socket.IO verbose logs).
5. A summary at the end listing every assumption made about the WS gateway contract (event names, auth payload shape, namespace) so Wesley can verify against `location.gateway.ts`.

Begin by reading `CLAUDE.md`, `lib/core/di/service_locator.dart`, `lib/features/journeys/presentation/providers/journey_provider.dart`, and `lib/features/maps/presentation/tulink_map_screen.dart` so your implementation matches existing patterns exactly. **Before writing any WebSocket code, ask Wesley to share `src/modules/location/location.gateway.ts` from the backend if it isn't already available** — guessing the contract will waste a debugging cycle.
