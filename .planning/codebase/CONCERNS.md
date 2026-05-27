# Codebase Concerns

**Analysis Date:** 2026-05-24

---

## Tech Debt

**Deprecated `AppConstants` still in active use:**
- Issue: `AppConstants` class is fully `@Deprecated` and marked for removal, but `ServiceLocator` still reads `AppConstants.authBoxName` to open and recover the Hive auth box.
- Files: `lib/core/constants/app_constants.dart`, `lib/core/di/service_locator.dart` (lines 138, 144–145)
- Impact: Calling deprecated API is a compile warning, and the migration to `StorageKeys` is incomplete. A future removal will break boot.
- Fix approach: Replace `AppConstants.authBoxName` with `StorageKeys.authBox` and delete `app_constants.dart`.

**Duplicate API route definitions:**
- Issue: Two near-identical route files co-exist — `lib/core/network/api_endpoints.dart` (142 lines) and `lib/core/network/api_routes.dart` (86 lines). Both declare routes like `resetPassword`, `notifications`, etc. Their contents diverge silently.
- Files: `lib/core/network/api_endpoints.dart`, `lib/core/network/api_routes.dart`
- Impact: Different call sites import different files; a route updated in one file is not reflected in the other. Already causing route drift (e.g., `downloadFile` vs `downloadMedia`).
- Fix approach: Consolidate into a single `ApiRoutes` class; migrate all import sites and delete `api_endpoints.dart`.

**Scaffolded but empty notifications feature:**
- Issue: The entire `lib/features/notifications/` tree (data, domain, presentation layers with subdirectories) contains zero `.dart` files. Storage keys, API endpoints, and routes for notifications are defined, but no implementation exists.
- Files: `lib/features/notifications/` (empty directory tree), `lib/core/constants/storage_keys.dart`, `lib/core/network/api_routes.dart`
- Impact: Notifications are referenced in API routes and storage keys but silently never delivered or displayed to users.
- Fix approach: Implement notification feature or remove the empty scaffolding to avoid confusion.

**Mock data in production local data source:**
- Issue: `JourneyLocalDataSourceImpl` returns a hardcoded list of fake journeys (Miami→Orlando, Rio→Sao Paulo, Tokyo→Kyoto, etc.) with a simulated 800 ms `Future.delayed`. It is wired into the live DI graph.
- Files: `lib/features/home/data/datasources/journey_local_data_source.dart`
- Impact: Any UI path consuming `getRecentJourneys()` shows fictional data. Users and testers may not realize they are seeing test fixtures.
- Fix approach: Implement real local caching with Hive or replace the call site with the remote data source; remove simulated delay.

**`auth_form_example.dart` and `example_responses.dart` live in production lib:**
- Issue: Demo widgets and example API response constructors are under `lib/`, not `test/` or `docs/`, and ship in the app binary.
- Files: `lib/features/auth/presentation/widgets/auth_form_example.dart`, `lib/core/network/models/example_responses.dart`
- Impact: Binary size increase; risk of example code being accidentally used in real UI.
- Fix approach: Move to `test/fixtures/` or delete if unused.

**Production and staging URLs commented out — no multi-environment support:**
- Issue: `AppConfig.baseUrl` and `AppConfig.webSocketUrl` have production and staging cases commented out; all environments resolve to `https://api.dev.tulink.xyz`.
- Files: `lib/core/config/app_config.dart` (lines 26–29, 70–74)
- Impact: Releasing to production will hit the development API unless the config is uncommented and a build pipeline flag (`FLUTTER_ENV=production`) is wired up.
- Fix approach: Uncomment production/staging cases and document the `--dart-define=FLUTTER_ENV=production` flag in CI.

---

## Known Bugs

**`ConvoyMetricsBottomSheet` "End Journey" is a stub:**
- Symptoms: Tapping "End Journey" from the metrics bottom sheet shows a SnackBar reading "End journey functionality coming soon!" instead of calling the actual `endJourney` flow.
- Files: `lib/features/maps/presentation/tulink_map_screen.dart` (lines 1064–1069)
- Trigger: Leader opens the convoy metrics sheet and taps End Journey.
- Workaround: Leader must use the main End Journey confirmation dialog (reachable via the status bar long-press route).

**WebSocket resync-data event is silently discarded:**
- Symptoms: Server sends `resync-data` after the client requests `request-resync`. The payload is received but the `// TODO: Handle resync updates` block is dead-commented; the actual location updates in the payload are never applied.
- Files: `lib/features/convoy/data/datasources/convoy_websocket_data_source.dart` (lines 464–470)
- Trigger: Client reconnects and calls `requestResync(fromSequence)` — any missed positions are ignored.
- Workaround: None; convoy positions silently lag after a reconnect until the next live update fires.

**Member name displays raw `userId` in convoy bottom sheet:**
- Symptoms: The convoy members list and the member tap handler show the Firebase/backend UID string (e.g., `abc123xyz`) instead of a human-readable name.
- Files: `lib/features/convoy/presentation/widgets/convoy_bottom_sheet.dart` (lines 217, 232)
- Trigger: Opening convoy member list during any active journey.
- Workaround: None; the name lookup is acknowledged with two TODO comments but not implemented.

**Map tap to center on member position is a no-op:**
- Symptoms: Tapping a convoy member in the member list closes the bottom sheet but does not move the camera.
- Files: `lib/features/maps/presentation/tulink_map_screen.dart` (line 818)
- Trigger: User taps any member in the convoy bottom sheet.
- Workaround: None currently.

**Forgot password button shows nothing:**
- Symptoms: The "Forgot Password?" button in `AuthScreen` has a `// TODO: Implement forgot password` comment and no action handler. Tapping it is a silent no-op.
- Files: `lib/features/auth/presentation/screens/auth_screen.dart` (line 198)
- Trigger: Tap "Forgot Password?" on the login screen.
- Workaround: The backend reset-password endpoint exists (`ApiRoutes.resetPassword`) and `AuthProvider.resetPassword()` is implemented; only the UI trigger is missing.

---

## Security Considerations

**`.env` bundled as a Flutter asset:**
- Risk: `pubspec.yaml` lists `.env` in the `assets` section (line 109). The Mapbox access token and any other secrets in `.env` are embedded in the compiled APK/IPA and extractable with standard tools.
- Files: `pubspec.yaml` (line 109), `lib/main.dart` (line 53), `lib/core/config/app_config.dart` (line 66)
- Current mitigation: `.env` is in `.gitignore`, so it is not committed.
- Recommendations: Use compile-time `--dart-define` flags for secrets rather than a bundled asset file; remove `.env` from the `assets` list.

**Mapbox token exposed via asset bundle:**
- Risk: `MAPBOX_ACCESS_TOKEN` is read from the `.env` asset bundle, making it trivially extractable from a release build.
- Files: `lib/core/config/app_config.dart` (line 66)
- Current mitigation: Mapbox tokens can be restricted by bundle ID in the Mapbox dashboard.
- Recommendations: Restrict the token to the app's bundle ID and rotate it; ideally switch to `--dart-define=MAPBOX_ACCESS_TOKEN=...` in CI so no file exists in the bundle.

**Unsafe dynamic casts on token storage (no schema validation):**
- Risk: `TokenManager` decodes stored JSON with bare `as Map<String, dynamic>`, `as String`, and `as int` casts — no `is`-check before casting. If the secure storage entry is corrupted or written by a different app version, this throws a `TypeError` caught generically, resulting in silent token corruption.
- Files: `lib/core/auth/token_manager.dart` (lines 85–87, 108–110, 151–152, 324–344)
- Current mitigation: Outer `catch (e)` blocks convert errors to `TokenFailure.tokenCorrupted`, which logs the user out.
- Recommendations: Add explicit `is` checks or use `tryParse` patterns before casting; version the stored token schema.

---

## Performance Bottlenecks

**Multiple simultaneous GPS streams during active journey:**
- Problem: At runtime, up to three independent GPS streams can run in parallel: `_cameraFollowSubscription` in `TulinkMapScreen`, `_positionSubscription` in `NavigationProvider`, and `_locationSubscription` in `ConvoyProvider`. All three use `LocationAccuracy.high` with no sharing.
- Files: `lib/features/maps/presentation/tulink_map_screen.dart` (line 778), `lib/features/maps/presentation/providers/navigation_provider.dart` (line 96), `lib/features/convoy/presentation/providers/convoy_provider.dart` (line 249)
- Cause: Each provider independently subscribes to `Geolocator.getPositionStream()`. On Android this keeps the GPS hardware active at full accuracy continuously, draining battery.
- Improvement path: Centralise GPS into a single shared stream (e.g., a `LocationService` singleton that broadcasts to multiple listeners), eliminating duplicate hardware requests.

**`WidgetsBinding.instance.addPostFrameCallback` called on every `build()`:**
- Problem: `TulinkMapScreen.build()` unconditionally calls `addPostFrameCallback` (line 1116) on every rebuild, scheduling `_checkAndStartConvoyCoordination`, `_handleArrivalEvent`, and `_handleJourneyEndedEvent` after each frame. These checks involve provider reads and conditional side effects.
- Files: `lib/features/maps/presentation/tulink_map_screen.dart` (lines 1115–1121)
- Cause: The pattern was chosen to avoid calling providers from `build()`, but the accumulation of scheduled callbacks on high-frequency rebuilds wastes frame budget.
- Improvement path: Move event-handling logic to `didChangeDependencies()` with state-tracked flags so it only fires when relevant data actually changes.

**REST fallback polling at 3-second interval:**
- Problem: When the WebSocket disconnects, `ConvoyRepositoryImpl` starts a `Timer.periodic(Duration(seconds: 3))` that polls the REST snapshot endpoint.
- Files: `lib/features/convoy/data/repositories/convoy_repository_impl.dart` (line 183)
- Cause: Fallback mechanism to bridge WebSocket outages. However, at 3 seconds per cycle across all active journeys, this creates significant backend load and battery drain if the WebSocket stays down.
- Improvement path: Apply exponential backoff starting at 3 s (matching the WebSocket reconnect delay pattern already implemented in `convoy_websocket_data_source.dart`).

**`tulink_map_screen.dart` is 1,542 lines — a God Widget:**
- Problem: A single `StatefulWidget` manages map lifecycle, route drawing, convoy marker updates, camera follow, navigation progress, journey-end handling, arrival detection, and all associated dialogs.
- Files: `lib/features/maps/presentation/tulink_map_screen.dart`
- Cause: Features were incrementally added to the same file.
- Improvement path: Extract distinct responsibilities into mixins or sub-controllers (e.g., `MapRouteController`, `MapMarkerController`, `MapNavigationController`) and reduce the widget to an orchestration shell.

---

## Fragile Areas

**WebSocket reconnect loop with short-lived connection circuit breaker:**
- Files: `lib/features/convoy/data/datasources/convoy_websocket_data_source.dart` (lines 94–111)
- Why fragile: The short-lived connection counter (`_shortLivedConnections`) is stored in the `ConvoyWebSocketDataSourceImpl` instance. Because this instance is created fresh each time the user is provisioned in `ServiceLocator`, a new instance starts with a clear counter, defeating the circuit breaker on app restart. Separately, the `_connectedAt` timestamp can remain stale between reconnect cycles if the disconnect fires before `onConnect`.
- Safe modification: Add a test for the circuit-breaker logic; treat `_connectedAt = null` at disconnect time to avoid stale timestamps.
- Test coverage: No existing tests cover the reconnect/circuit-breaker path.

**Hive `auth_box` schema migration deletes data silently:**
- Files: `lib/core/di/service_locator.dart` (lines 138–146)
- Why fragile: On any Hive type error at boot, the recovery path deletes the entire `auth_box` and recreates it. This logs the user out silently — no user-facing message, no crash report. The condition triggers whenever the persisted `UserModel` schema diverges from the registered adapter, which can happen after any model field change.
- Safe modification: Version the `UserModelAdapter` (increment `typeId`); migrate fields rather than deleting the box; surface the failure to the user with a message.
- Test coverage: No test covers the Hive error-recovery path.

**`print()` throughout critical paths (no structured logging):**
- Files: `lib/features/maps/presentation/tulink_map_screen.dart`, `lib/features/maps/presentation/providers/navigation_provider.dart`, `lib/features/convoy/data/datasources/convoy_websocket_data_source.dart`, `lib/features/convoy/data/repositories/convoy_repository_impl.dart`, `lib/core/di/service_locator.dart`, `lib/core/network/dio_client.dart`, `lib/core/services/location_permission_service.dart`, `lib/features/maps/data/datasources/route_remote_data_source.dart`
- Why fragile: `print()` calls are active in release builds (Flutter does not strip them). A centralized `AppLogger` / `Logger` wrapper exists at `lib/core/utils/logger.dart` and `lib/core/logging/auth_logger.dart` but is not used in the hottest code paths. This means production logs are unstructured, cannot be filtered by severity, and cannot be routed to a crash reporting service.
- Safe modification: Replace all `print()`/bare `debugPrint()` calls with the existing `AppLogger` methods; set `Logger` filter to `ProductionFilter` for release builds.

**Convoy provider `dispose()` is async but called synchronously:**
- Files: `lib/features/convoy/presentation/providers/convoy_provider.dart` (line 622)
- Why fragile: `dispose()` calls `super.dispose()` at the end of a method that also calls several `await _*Subscription?.cancel()` operations — however `ChangeNotifier.dispose()` itself is synchronous and the `await` calls inside the async `dispose` body may not complete before the provider is garbage-collected. The current pattern is `void dispose()` (not `Future<void>`), so the cancellations run unawaited.
- Safe modification: Extract async teardown into a `stopAll()` method called explicitly before `dispose()`, or document that the subscriptions may outlive the object by one event cycle.

---

## Scaling Limits

**Invite polling is HTTP-based (60-second timer):**
- Current capacity: One REST request per 60 seconds per active home screen user.
- Limit: With many concurrent users the invite endpoint will receive O(users) requests per minute regardless of invite activity.
- Scaling path: Switch to WebSocket push events for invites (the convoy WS infrastructure already exists) or use server-sent events; eliminate polling.

**Single WebSocket namespace for all journeys:**
- Current capacity: All journey rooms share one Socket.IO connection per client; the backend routes events per `journeyId` room.
- Limit: Not a client-side limit per se, but if the backend uses a single node process without Redis adapter, horizontal scaling is blocked.
- Scaling path: Ensure the backend WebSocket transport uses a Redis pub/sub adapter; this is a backend concern but the Flutter client should be tested against multi-node topologies.

---

## Dependencies at Risk

**`hive: ^2.2.3` / `hive_flutter: ^1.1.0` — end-of-active-development:**
- Risk: Hive v2 is no longer actively maintained for new features; the recommended migration path in the Dart ecosystem is Isar or ObjectBox for complex use cases. The current usage (auth box only) is minimal but the library is aging.
- Impact: Future Flutter SDK upgrades may expose compatibility issues.
- Migration plan: For the current lightweight usage (single auth box storing a JSON blob), migrating to `flutter_secure_storage` exclusively (already a dependency) or `shared_preferences` is straightforward.

**`socket_io_client: ^2.0.3+1` — pinned minor:**
- Risk: Socket.IO v5 is available; v2 client may not support all v5 server features, and the backend version is not locked in this repo.
- Impact: If the backend upgrades Socket.IO, the client handshake may fail silently.
- Migration plan: Verify backend Socket.IO version; upgrade client to match; add a Socket.IO version compatibility test.

---

## Missing Critical Features

**No push notifications infrastructure:**
- Problem: The `lib/features/notifications/` directory tree exists but contains zero implementation files. Firebase Messaging, local notifications, or any push delivery mechanism is absent from `pubspec.yaml` and the codebase.
- Blocks: Journey-start alerts for members who are not on the preview screen, arrival alerts, invite notifications when the app is backgrounded.

**No background location / foreground service:**
- Problem: GPS publishing (`ConvoyProvider._locationSubscription`) uses an in-process stream. On iOS and Android, once the app is backgrounded, location updates are throttled or suspended.
- Blocks: Convoy members who background the app will stop broadcasting positions. The server will show them as stale or disconnected.

**Profile editing not implemented:**
- Problem: `ProfileScreen` (541 lines) displays user data and analytics, but contains no edit/save functionality — no name change, no avatar upload, no settings persistence beyond sign-out.
- Blocks: Users cannot update any profile information after registration.

**Forgot password UI wiring missing:**
- Problem: Backend endpoint (`POST /auth/reset-password`) and `AuthProvider.resetPassword()` are implemented, but the forgot-password button in `AuthScreen` has no action (line 198 TODO).
- Blocks: Users who forget their password have no self-service recovery path from the app.

---

## Test Coverage Gaps

**No tests for any screen or widget:**
- What's not tested: All presentation-layer widgets and screens — `TulinkMapScreen`, `HomeScreen`, `JourneyPreviewScreen`, `InviteParticipantsScreen`, `ProfileScreen`, `AuthScreen`.
- Files: `lib/features/maps/presentation/`, `lib/features/home/presentation/`, `lib/features/journeys/presentation/`
- Risk: Regressions in UI behaviour (e.g., the convoy marker update logic, journey-start auto-navigation flow) go undetected.
- Priority: High

**No tests for `ConvoyRepositoryImpl` or WebSocket data source:**
- What's not tested: The REST/WebSocket coordination layer, fallback polling activation, reconnect logic, circuit-breaker behaviour, and event demultiplexing.
- Files: `lib/features/convoy/data/repositories/convoy_repository_impl.dart`, `lib/features/convoy/data/datasources/convoy_websocket_data_source.dart`
- Risk: Silent regressions in real-time position sharing — the most critical user-facing feature.
- Priority: High

**No tests for `TokenManager`:**
- What's not tested: Token expiry calculation, concurrent refresh deduplication via `Completer`, `onAuthLost` callback, and token corruption recovery.
- Files: `lib/core/auth/token_manager.dart`
- Risk: Auth edge cases (expired token mid-journey, corrupted secure storage) can lock users out or silently fail to refresh.
- Priority: High

**`widget_test.dart` expects non-existent UI strings:**
- What's not tested: The smoke test looks for `'TuLink Flutter'` and `'Clean Architecture Demo'` which no longer exist in the app shell — the test would fail if run.
- Files: `test/widget_test.dart` (lines 36–37)
- Risk: The test suite has a broken smoke test masking the fact that no widget tests are running.
- Priority: Medium

**No integration or E2E tests:**
- What's not tested: The full user journey from sign-in through journey creation, convoy coordination, and arrival.
- Files: `test/features/auth/integration/auth_integration_test.dart` — only auth integration exists.
- Risk: Cross-feature interactions (journey start triggering WebSocket join, arrival event triggering navigation away) are only manually verifiable.
- Priority: Medium

---

*Concerns audit: 2026-05-24*
