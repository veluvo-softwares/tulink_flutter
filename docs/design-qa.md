# Tulink Map-First Navigation — Design QA

- Device: iPhone 17 Pro simulator, 402 x 874 logical pixels
- Implementation captures: 1206 x 2622 pixels at 3x density
- Reference captures: 852–853 x 1844–1846 pixels
- Normalization: each reference and implementation pair was fitted to an equal 1200-pixel height and inspected as one combined image.

## Visual Truth and Evidence

| Surface | Reference | Implementation | Combined comparison |
| --- | --- | --- | --- |
| Journeys | `/Users/wesleynyamu/.codex/generated_images/019ffb25-4328-79b1-848b-b4c7eb0f146d/exec-bb9e2dd8-46d7-4119-8dc2-13d62e48da78.png` | `/private/tmp/tulink-map-overlays/journeys-layout-final.png` | `/private/tmp/tulink-map-overlays/compare-journeys-final.png` |
| Invites | `/Users/wesleynyamu/.codex/generated_images/019ffb25-4328-79b1-848b-b4c7eb0f146d/exec-abd3733a-147e-43c5-8488-e8c2d0fc5558.png` | `/private/tmp/tulink-map-overlays/invites.png` | `/private/tmp/tulink-map-overlays/compare-invites-final.png` |
| Journey creation | `/Users/wesleynyamu/.codex/generated_images/019ffb25-4328-79b1-848b-b4c7eb0f146d/exec-37c0fbfc-0fef-4c0e-9003-8ccaf732f1cc.png` | `/private/tmp/tulink-map-overlays/map-draft-layout-final.png` | `/private/tmp/tulink-map-overlays/compare-map-draft-final.png` |
| Profile theme | `/private/tmp/tulink-map-overlays/map-final.png` | `/private/tmp/tulink-map-overlays/profile-themed.png` | `/private/tmp/tulink-map-overlays/compare-profile-theme-final.png` |

## Required Fidelity Surfaces

- One persistent Mapbox map remains behind Map, Journeys, and Invites.
- The logo/search/profile control retains its compact Google Maps-inspired hierarchy.
- Journeys uses a draggable warm-sand overlay, route preview, latest-journey emphasis, and a `Go again` action.
- Invites uses the same draggable overlay language with real loading, error, populated, and empty states plus accept/decline actions.
- Journey creation is destination-first: selecting a destination names the trip, draws the real route and marker, then asks only for companions before `Start journey`.
- Existing Tulink brand assets, Manrope fonts, colors, Mapbox integration, authenticated profile data, and standard icon library are used.
- Profile uses the same warm sand, white outlined surfaces, deep teal actions, route teal accents, orange semantic highlights, Manrope hierarchy, and rounded geometry as the approved map-first home.

## Findings and Iteration History

No actionable P0, P1, or P2 visual findings remain.

1. The initial route camera placed the destination marker underneath the search surface. The route-fit top inset changed from 120 to 180 logical pixels; the final combined journey-creation comparison shows the marker clearly below the search control.
2. The first Journeys title was too large relative to the selected design. The overlay title was reduced from 31 to 26 logical pixels and re-captured with real journey data.
3. The first creation sheet was taller than the visual target. Companions now sit in one `Going with` row and redundant safe-area padding was removed; the map has more usable height.
4. The live test account currently has no pending invitations, so the implementation evidence captures the production empty state instead of the populated reference state. The populated card, accept, decline, loading, and error branches remain implemented and covered by the same overlay geometry.
5. The former Profile screen used the legacy carbon-black, steel, and electric-red presentation. It was migrated to the approved semantic theme, connected to the real profile image and verification state, and recaptured beside the approved map home. These are different app states, so the comparison evaluates shared tokens, typography, component rhythm, and visual language rather than pixel-for-pixel layout.

The full-view combined comparisons make typography, sheet height, navigation placement, route visibility, button geometry, and map-to-overlay balance readable without separate focused crops.

## Interaction and Runtime Verification

- Native iOS debug build is running on the iPhone 17 Pro simulator.
- Mapbox, journey history, active journeys, invitations, routing, authenticated profile data, and WebSocket delivery reconnect successfully; observed API responses were 200.
- Destination selection, real route preview, companion selection, journey start, repeat journey, invitation accept/decline, push-to-Invites fallback, and persistent bottom navigation remain connected to existing behavior.
- Profile back navigation, edit affordances, real journey statistics, journey-history navigation, voice-navigation switch, settings placeholders, and sign-out confirmation remain interactive.
- Focused home tests: 1 passed, 0 failed.
- Full Flutter suite from this implementation pass: 175 passed, 14 expected platform/native skips, 0 failed.
- Static analysis: no errors or warnings; 21 existing style-level info lints.
- No new Flutter exceptions appeared during the visual pass. Simulator logs still contain pre-existing cached-journey cast warnings, unavailable APNs token messages, and Flutter's native-assets `SdkRoot` hot-reload warning.

## Follow-up Polish

- [P3] Exercise the populated Invites state on an account with pending invitations for a same-state runtime screenshot.
- [P3] Consider a custom Mapbox style later to reduce label density without changing the approved flow.

final result: passed
