# Fix: Leader Shows DISCONNECTED After Starting Journey

## Branch
`fix/convoy-reroute-and-member-visibility`

## Symptom
When a member fetches journey data immediately after the leader starts a journey, the
leader's participant record shows `connectionStatus: "DISCONNECTED"` even though the
journey is `ACTIVE`. Example log captured on that branch:

```json
{
  "participants": [{
    "userId": "nkKXmDFoSFa7bO6ZbGLGdVIp7eY2",
    "role": "LEADER",
    "status": "ACTIVE",
    "connectionStatus": "DISCONNECTED"
  }]
}
```

---

## Root Cause

`connectionStatus` in Firestore is only set to `CONNECTED` when a client completes the
WebSocket `join-journey` handshake (backend `handleJoinJourney` →
`participantService.updateConnectionStatus`).

### The timing gap

In `journey_preview_screen.dart:_onCountdownComplete` the sequence is:

```
1. await startJourney()          ← REST call; sets journey ACTIVE, broadcasts journey-started
2. startCoordination()           ← NOT awaited; WebSocket connect starts in background
3. await Future.delayed(500ms)
4. Navigator.pushReplacementNamed('/mapview')
```

Step 1 fires `journey-started` to the WebSocket room. Members waiting in the room receive
it immediately and fetch journey data. Step 2 begins the WebSocket connection
asynchronously — the leader won't be `CONNECTED` in Firestore for another **400ms–1600ms**
(TCP handshake + Firebase token verify + Firestore `isParticipant` read + Firestore write).
During that window any journey-details fetch shows the leader as `DISCONNECTED`.

### Contributing factor: leader never pre-joins

`home_screen.dart:_preJoinActiveJourneyRoom` explicitly skips leaders:

```dart
if (journey.leaderId != userId) {   // leaders excluded
    convoyProvider.joinJourneyRoom(journey.id);
}
```

The leader has no WebSocket connection at all until `startCoordination` fires in step 2.

---

## What the current branch already fixes (do not redo)

| File | What changed |
|------|-------------|
| `convoy_websocket_data_source.dart` | Unsafe `data as Map` cast crashes → safe `is! Map` guards; nested `location` object unwrap; `joinJourney` now awaits `joined-journey` confirmation (Completer + 10s timeout); server `error` event handler added |
| `convoy_remote_data_source.dart` | Same nested-coordinate unwrap for REST path |
| `location_update_dto.dart` | `ConvoySnapshotDto.fromJson` accepts `participants` OR `locations` key |
| `convoy_provider.dart` | `startCoordination` guard requires `_isPublishing`; skips `_startConvoyStream` if already subscribed (preserves existing `joinJourneyRoom` stream) |
| `invitations_screen.dart` | Fetches journey status after accept; routes ACTIVE → map, PENDING → preview |
| `convoy_route_line.dart` | Removed dead convoy route-line drawing code |
| `navigation_provider.dart` | Clears stale segment index on new route load |
| `tulink_map_screen.dart` | Reroute uses in-hand GPS position; removed route-line rendering |

---

## Remaining fix — two files, two changes

### Change 1 — `lib/features/journeys/presentation/pages/journey_preview_screen.dart`

**Where:** `initState`, inside the existing `addPostFrameCallback`.

**What:** Call `joinJourneyRoom` for the leader immediately when the preview screen opens.
This starts the WebSocket connection in the background while the leader views the screen
and completes the countdown (5+ seconds of runway on the normal path).

```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  context.read<JourneyProvider>().fetchJourneyById(widget.journeyId);

  // Pre-join the WebSocket room so the leader is CONNECTED in Firestore
  // before startJourney() fires. startCoordination() later detects
  // _isSubscribed == true and only adds GPS publishing on top.
  context.read<ConvoyProvider>().joinJourneyRoom(widget.journeyId);
});
```

**Why `joinJourneyRoom` is safe here:**
- It is idempotent — calling it when already subscribed is a no-op
  (`if (_currentJourneyId == journeyId && _isSubscribed) return`)
- `startCoordination` (called after the countdown) checks `_isSubscribed` and skips
  `_startConvoyStream`, so the existing connection is preserved; it only adds GPS publishing

---

### Change 2 — `lib/features/journeys/presentation/pages/journey_preview_screen.dart`

**Where:** `_onCountdownComplete`, **before** the `startJourney()` REST call.

**What:** Add a bounded wait (max 1.5 s) for the WebSocket connection to be ready. This
closes the race window when the leader taps Skip immediately after landing on the screen
(minimum ~400–600 ms from `initState` to `_onCountdownComplete` via Skip).

```dart
Future<void> _onCountdownComplete() async {
  if (!mounted) return;

  // Wait up to 1.5 s for the background joinJourneyRoom to complete its
  // WebSocket handshake. If it doesn't connect in time we still proceed —
  // the DISCONNECTED window will be small and the socket keeps retrying.
  final convoy = context.read<ConvoyProvider>();
  if (convoy.connectionState != ConvoyConnectionState.connected) {
    final deadline = DateTime.now().add(const Duration(milliseconds: 1500));
    while (mounted &&
           DateTime.now().isBefore(deadline) &&
           convoy.connectionState != ConvoyConnectionState.connected) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  setState(() { _isStartingJourney = true; });

  try {
    final success = await context.read<JourneyProvider>().startJourney(widget.journeyId);
    // ... rest of existing logic unchanged ...
```

**Remove** the `await Future.delayed(const Duration(milliseconds: 500))` that currently
sits between `startCoordination()` and the `Navigator.pushReplacementNamed` call — it was
compensating for this exact gap and is no longer needed.

**Behaviour by scenario:**

| Scenario | Outcome |
|----------|---------|
| Normal 5-second countdown | Connection established well before wait; exits immediately |
| Skip on fast network | WebSocket joins in ~400 ms; wait exits in 1–2 poll cycles |
| Skip on slow network | Wait expires at 1.5 s; journey starts anyway; window is small |
| WebSocket fails entirely | Wait expires; REST start proceeds; fallback REST polling covers coordination |

---

### Optional Change 3 — `lib/features/home/presentation/screens/home_screen.dart`

**Where:** `_preJoinActiveJourneyRoom`.

**What:** Remove the leader exclusion so leaders also pre-join from the home screen.
This covers the edge case where a leader navigates back to the home screen after creating
a journey and then returns to the preview screen.

```dart
void _preJoinActiveJourneyRoom() {
  final journeyProvider = context.read<JourneyProvider>();
  final convoyProvider = context.read<ConvoyProvider>();

  for (final journey in journeyProvider.activeJourneys) {
    // Pre-join for both leaders and members — only skip journeys that are
    // not yet PENDING/ACTIVE or that we are already coordinating.
    convoyProvider.joinJourneyRoom(journey.id);
    break;
  }
}
```

This is lower priority — Change 1 and 2 already solve the common path.

---

## Files to touch

| File | Change |
|------|--------|
| `lib/features/journeys/presentation/pages/journey_preview_screen.dart` | Add `joinJourneyRoom` in `initState` post-frame callback; add bounded wait at top of `_onCountdownComplete`; remove `Future.delayed(500ms)` |
| `lib/features/home/presentation/screens/home_screen.dart` | (Optional) Remove `leaderId != userId` guard in `_preJoinActiveJourneyRoom` |

## Imports needed in `journey_preview_screen.dart`

`ConvoyConnectionState` is already accessible via `ConvoyProvider.connectionState`
(returns a `ConvoyConnectionState` enum). No new imports required — `ConvoyProvider` is
already imported.

---

## Testing checklist

- [ ] Leader creates journey, waits on preview screen, normal 5-second countdown → leader
      appears CONNECTED in Firestore before `journey-started` fires
- [ ] Leader taps Skip immediately → bounded wait closes gap; leader CONNECTED before or
      very shortly after REST start
- [ ] Member accepts invitation to PENDING journey → navigates to preview screen →
      receives `journey-started` → navigates to map (existing flow, unchanged)
- [ ] Member accepts invitation to already-ACTIVE journey → goes directly to map
      (handled by `invitations_screen.dart` changes already on branch)
- [ ] No duplicate WebSocket connections when both `joinJourneyRoom` and
      `startCoordination` are called for the same journey
