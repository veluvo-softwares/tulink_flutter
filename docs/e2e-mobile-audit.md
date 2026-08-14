# Tulink Mobile End-to-End Audit

## Executive Summary

**Overall readiness verdict: BLOCKED**

The current map-first branch builds and launches, and the redesigned map home is substantially functional. Destination search, long destination names, destination-derived journey names, route preview/framing, destination markers, companion selection/removal, draft cancellation, tab switching, join-code validation, profile navigation, and session restoration were exercised successfully on iOS simulators.

Release readiness cannot be established because a verified disposable second user was not available. The development backend correctly gated the new account behind email verification, but this audit had no test inbox or verification-link capture mechanism. Invitation acceptance/decline, valid-code joining, and the full two-user live/reconnect/leave/end lifecycle therefore remain blocked rather than passed.

The audit found **0 P0, 2 P1, 7 P2, and 2 P3 findings**. The highest risks are an unreadable/incompletely migrated Journey History path and failed-login UX that clears the form without durable visible feedback. Authentication, history/details, location gates, and live-journey widgets still contain substantial legacy dark/red/orange and Rajdhani/Inter styling.

Major flows successfully completed:

- Clean launch and registration through the email-verification gate.
- Required-field and invalid-email validation.
- Correct login to the verification gate and session restoration after termination.
- Verification resend cooldown and sign-out/back behavior.
- Mapbox map load, tab switching, camera/map-state retention, and empty Invites state.
- Destination search, long-name handling, route line, marker, camera framing, companion add/remove, draft cancellation, and tab persistence.
- Invalid/empty/repeated join-code handling and sheet dismissal.
- History overlay, collapsed overlay header, Journey Details navigation, and Go Again draft creation.
- Profile display, scrolling, View Journeys, sign-out cancellation, and map-state return.
- Location-denied Start Journey gate without creating server data.

## Remediation Update — 2026-08-14

The redesign was checkpointed in `7ba1bdb`, then the audit findings were
addressed in isolated remediation commits. The following findings are resolved
in source and covered by static/unit/build verification:

- `TUL-E2E-001`: Journey History, Journey Details, shared journey cards, and
  status presentation now use the warm semantic theme with readable app bars.
- `TUL-E2E-002`: authentication loading no longer replaces the login subtree;
  failed login retains both fields and displays a durable inline error. A
  focused widget regression test covers the in-flight and failed states.
- `TUL-E2E-003`: login, registration, password recovery, and email verification
  now use the Tulink brand mark, Manrope hierarchy, semantic surfaces, and
  labelled password/sign-out controls.
- `TUL-E2E-004`: unsupported Edit, Notifications, Privacy, Linked Accounts, and
  Help rows were removed. Profile now advertises only working actions.
- `TUL-E2E-005`: voice navigation is restored from local storage before the app
  renders and persisted on change. A focused provider test covers restore/save.
- `TUL-E2E-006`: location sheets use the light theme, current Tulink naming,
  semantic actions, and a single framework drag handle.
- `TUL-E2E-007`: reachable live-map and convoy overlays now use the semantic
  light palette and inherit Manrope. A misleading hard-coded marathon header
  and its non-functional settings control were removed.
- `TUL-E2E-008`: partially remediated in the touched flows through labelled icon
  controls, semantic journey rows, and grouped settings; a dedicated full-app
  screen-reader audit is still recommended.
- `TUL-E2E-011`: the auth gate now switches only during one-time initialization,
  so resend/sign-out loading cannot dispose and recreate the verification UI.
  A simulator rerun is still recommended for the original timing anomaly.

Verification after remediation:

- `flutter test`: 177 passed, 14 explicitly skipped native/live integration
  cases, 0 failed.
- `flutter build ios --simulator --debug --no-codesign`: succeeded.
- Focused `dart analyze` runs: no compile errors; repository-wide pre-existing
  lint/documentation debt remains as described in `TUL-E2E-009`.

The overall release verdict remains **BLOCKED** until the environment supplies
a verified disposable second account or inbox/verification-link capture. The
invitation, valid join-code, two-user live journey, reconnect, leave/end, push
routing, and network-interruption scenarios below have not been converted from
Blocked to Pass by source changes alone.

Flows blocked by environment or test-account constraints:

- Email verification completion for disposable User B.
- Duplicate-account registration after verification.
- Verified User B access to Map/Journeys/Invites.
- User A invites User B; refresh/badge/details/accept/decline.
- Valid and expired journey-code joining.
- Two-user live journey, movement, participant rendering, sockets, reconnect, background/foreground, leave/end/cancel propagation, and post-sign-out room cleanup.
- Push-notification tap routing.
- Offline/network interruption tests; simulator connectivity was not modified because it would affect broader host state.

## Environment

| Item | Value |
|---|---|
| Audit date/time | 2026-08-14, approximately 18:41–19:17 EAT (Africa/Nairobi) |
| Git branch | `mr/mobile-brand-redesign` |
| Git commit | `f0285afd2f25babd89f84e5fc07a1cf1e41f4f00` |
| Worktree | Dirty before audit; preserved. Existing modified/untracked app, asset, design-audit, and test files were not staged, reverted, discarded, or committed. |
| Flutter | 3.41.9 stable, framework `00b0c91f06` |
| Dart | 3.11.5 |
| Xcode | 26.0 (from Flutter diagnostic output) |
| Primary simulator / User A | iPhone 17 Pro, iOS 26.0; pre-existing verified session used read-only except for local draft/permission/preference tests |
| Secondary simulator / User B | iPhone 16 Pro, iOS 18.6; clean install and newly created disposable unverified account |
| App bundle | `xyz.tulink.app` |
| App/backend environment | Development: `https://api.dev.tulink.xyz`; confirmed in `AppConfig` defaults and captured runtime requests. No production endpoint was used. |
| Build | Fresh debug iOS-simulator build from the current dirty worktree; installed on both simulators |
| Mobile MCP | Available and used for device discovery, launch, taps, typing, swipes, UI inspection, screenshots, termination, install, and crash-list inspection |
| Crash reports | No TuLink/Runner crash report appeared on either simulator |
| Evidence root | `/private/tmp/tulink-e2e-audit/` |
| Test identities | User A and User B only; no credentials, tokens, OTPs, or private profile values are included in this report |

The audit created one disposable development-backend account (User B). No existing account or journey was edited or deleted. User A's server journeys were only viewed; all draft creation was cancelled before Start Journey.

## Flow Coverage Matrix

| Flow | Simulator/User | Result | Evidence | Notes |
|---|---|---|---|---|
| Fresh build/install | Both | Pass | `/private/tmp/tulink-e2e-audit/flutter-build-ios-simulator.log` | Fresh debug build installed successfully on both devices. |
| Initial clean launch | User B | Pass | `/private/tmp/tulink-e2e-audit/secondary-fresh-auth.png` | Login screen rendered; legacy styling finding applies. |
| Existing session restoration | User A | Pass | `/private/tmp/tulink-e2e-audit/primary-console-launch.png` | Existing verified session returned directly to map. |
| Empty login fields | User B | Pass | `/private/tmp/tulink-e2e-audit/auth-empty-submit.png` | Both required errors rendered. |
| Invalid email validation | User B | Pass | `/private/tmp/tulink-e2e-audit/auth-invalid-submit.png` | Invalid email blocked submission. |
| Password visibility | User B | Pass with issue | `/private/tmp/tulink-e2e-audit/auth-keyboard-invalid.png` | Value toggled, but the icon button has no accessible label. |
| Keyboard/layout on login | User B | Pass with issue | `/private/tmp/tulink-e2e-audit/auth-keyboard-invalid.png` | Core fields remain reachable; lower actions are hidden while keyboard is open. |
| Forgot-password entry/empty validation | User B | Pass | `/private/tmp/tulink-e2e-audit/forgot-password.png` | Entry route and empty validation worked; reset delivery was not triggered. |
| Sign-up required fields | User B | Pass | `/private/tmp/tulink-e2e-audit/signup-empty-validation.png` | All four required-field errors rendered. |
| Successful account creation | User B | Pass | `/private/tmp/tulink-e2e-audit/signup-user-b-result.png` | Development account created and gated at verification. |
| Email verification gate | User B | Pass | `/private/tmp/tulink-e2e-audit/signup-user-b-result.png` | Unverified user could not reach the application. |
| Resend verification cooldown | User B | Pass with anomaly | `/private/tmp/tulink-e2e-audit/verification-resend-cooldown.png` | One run briefly showed `Resend in 0s` plus `Signing out...`; relaunch/retry correctly counted from 60 seconds. |
| Verification session restoration | User B | Pass | `/private/tmp/tulink-e2e-audit/user-b-relaunch-after-resend.png` | Reopen returned to verification gate. |
| Verification back/sign out | User B | Pass | `/private/tmp/tulink-e2e-audit/verify-back-signout.png` | Returned to login successfully. |
| Correct login after sign out | User B | Pass | `/private/tmp/tulink-e2e-audit/login-correct-user-b.png` | Correct credentials returned to verification gate. |
| Incorrect password | User B | Fail | `/private/tmp/tulink-e2e-audit/login-incorrect-password.png` | Form reset and no durable error remained; see TUL-E2E-002. |
| Unknown account | User B | Fail | `/private/tmp/tulink-e2e-audit/login-unknown-account-feedback.png` | Same form-reset/no-durable-feedback behavior; see TUL-E2E-002. |
| Duplicate account | User B | Blocked | — | Verification-capable disposable inbox was unavailable; no repeated account mutation was attempted. |
| Mapbox map load | User A | Pass | `/private/tmp/tulink-e2e-audit/primary-console-launch.png` | Streets map loaded without Mapbox error. |
| Map header/logo/profile/join controls | User A | Pass | `/private/tmp/tulink-e2e-audit/primary-console-launch.png` | Controls visible and accessible labels mostly present. |
| Map/Journeys/Invites navigation | User A | Pass | `/private/tmp/tulink-e2e-audit/journeys-tab.png`, `/private/tmp/tulink-e2e-audit/invites-tab.png` | Tab navigation worked. |
| Map retained across tabs | User A | Pass | `/private/tmp/tulink-e2e-audit/map-return-after-tabs.png` | Map/camera and draft state remained available. |
| Invites empty state | User A | Pass | `/private/tmp/tulink-e2e-audit/invites-tab.png` | Empty state was clear and rebranded. |
| Journeys list/overlay | User A | Pass | `/private/tmp/tulink-e2e-audit/journeys-tab.png` | History items and map preview loaded. |
| Collapsed journey overlay | User A | Pass | `/private/tmp/tulink-e2e-audit/journeys-overlay-collapsed.png` | Header remained visible after swipe down. |
| Search destination | User A | Pass | `/private/tmp/tulink-e2e-audit/destination-search-results.png` | Expected result returned. |
| Long destination name | User A | Pass | `/private/tmp/tulink-e2e-audit/new-destination-draft.png` | Header ellipsized and draft title wrapped without overflow. |
| Destination-derived journey name | User A | Pass | `/private/tmp/tulink-e2e-audit/new-destination-draft.png` | Draft name derived from selected destination. |
| Destination marker/polyline/framing | User A | Pass | `/private/tmp/tulink-e2e-audit/new-destination-draft.png` | Marker and teal route rendered and were framed around overlays. |
| Add/remove/change companion | User A | Pass | `/private/tmp/tulink-e2e-audit/companion-search-user-b.png`, `/private/tmp/tulink-e2e-audit/go-again-companion-selected.png` | User B could be selected, deselected, and restored in local draft. |
| Cancel/restart draft | User A | Pass | `/private/tmp/tulink-e2e-audit/map-return-after-tabs.png` | Cancel returned to home; no journey was created. |
| Draft across tabs | User A | Pass | `/private/tmp/tulink-e2e-audit/go-again-companion-selected.png` | Destination and companion survived tab switches. |
| Start Journey permission gate | User A | Pass with issue | `/private/tmp/tulink-e2e-audit/location-start-permission-prompt.png` | Server creation was blocked while location denied; legacy styling finding applies. |
| Successful Start Journey | User A/B | Blocked | — | Would mutate a non-disposable verified account; User B remained unverified. |
| Duplicate Start taps | User A/B | Blocked | — | Same account constraint. Code contains `_isStarting` guard but runtime not marked passed. |
| Route-fetch/offline failure | Both | Blocked | — | Host connectivity was not interrupted; no safe app-scoped network toggle was available. |
| Location permission denied launch | User A | Pass with issue | `/private/tmp/tulink-e2e-audit/location-permission-revoked-launch.png` | Map remains usable with fallback/cached origin; action-level gate appears only on Start. |
| Join code empty | User A | Pass | `/private/tmp/tulink-e2e-audit/join-code-empty.png` | Inline 10-character validation displayed. |
| Join code malformed/invalid | User A | Pass | `/private/tmp/tulink-e2e-audit/join-code-invalid-server.png` | Backend 404 normalized to `Journey code not found`. |
| Repeated invalid join submission | User A | Pass | `/private/tmp/tulink-e2e-audit/runtime-actionable-sanitized.log` | Repeated 404s caused no crash or duplicate state. |
| Close join-code overlay | User A | Pass | `/private/tmp/tulink-e2e-audit/join-code-dismissed.png` | Swipe dismissal returned safely to map. |
| Valid/expired/padded join code | Both | Blocked | — | No disposable live journey/code was available. Input normalization was not marked passed from source alone. |
| Invitation receive/badge/details/accept | Both | Blocked | — | User B could not pass verification. |
| Invitation decline | Both | Blocked | — | User B could not pass verification. |
| Notification-tap routing | Both | Blocked | — | No simulator push payload/test harness was available. |
| Two-user live journey | Both | Blocked | — | Verified second user unavailable. |
| Participant identity/self-filtering | Both | Blocked at runtime | `/private/tmp/tulink-e2e-audit/flutter-test.log` | Unit tests cover self-filtering, but no live runtime pass was claimed. |
| Background/reconnect/network interruption | Both | Blocked | — | No live two-user journey; connectivity was not globally interrupted. |
| Leave/end/cancel propagation | Both | Blocked | — | No disposable verified live journey. |
| History full-screen path | User A | Fail | `/private/tmp/tulink-e2e-audit/profile-view-journeys-legacy.png` | Header/title are effectively invisible and design is legacy; see TUL-E2E-001. |
| Journey details | User A | Fail visual / Pass functional | `/private/tmp/tulink-e2e-audit/journey-history-card-tap.png` | Opens correctly but is entirely legacy dark/orange. |
| Go Again draft | User A | Pass with issue | `/private/tmp/tulink-e2e-audit/go-again-draft.png` | Destination/companions restored; route has no loading state while async preview resolves. |
| Profile core display | User A | Pass | `/private/tmp/tulink-e2e-audit/profile-initial.png` | Name/email/initials/verification/stats rendered; private values omitted here. |
| Profile back to map | User A | Pass | `/private/tmp/tulink-e2e-audit/map-return-after-tabs.png` | Existing map state returned. |
| Profile scroll | User A | Pass | `/private/tmp/tulink-e2e-audit/profile-settings.png` | All settings and sign-out row reachable. |
| View Journeys from profile | User A | Fail visual | `/private/tmp/tulink-e2e-audit/profile-view-journeys-legacy.png` | Routes into incomplete legacy migration. |
| Voice switch | User A | Fail persistence | `/private/tmp/tulink-e2e-audit/profile-settings.png` | Toggle works in-session but resets after app restart; see TUL-E2E-005. |
| Notifications/Privacy/Linked/Help/Edit | User A | Fail/incomplete | `/private/tmp/tulink-e2e-audit/profile-settings.png` | All are Coming Soon placeholders using raw SnackBars. |
| Sign-out confirmation cancel | User A | Pass | `/private/tmp/tulink-e2e-audit/signout-confirmation.png` | Cancel preserved the session. |
| Sign-out socket cleanup | User A | Blocked | — | Full sign-out was not performed on the non-disposable verified session. Source calls `stopUserChannel` first, but runtime pass was not claimed. |
| Smaller-screen visual pass | User B / iPhone 16 Pro | Pass with issues | `/private/tmp/tulink-e2e-audit/auth-empty-submit.png` | Auth errors compress lower content close to/below safe area; no RenderFlex warning captured. |

## Findings

### P0

No P0 crash, data-loss, security/privacy, or confirmed core-flow impossibility was observed. No TuLink crash report, Flutter red screen, or RenderFlex exception was captured.

### TUL-E2E-001 — P1 — Profile “View Journeys” opens an unreadable legacy Journey History

Preconditions:

- User A is signed in with journey history.

Steps:

1. Open Profile from the map header.
2. Tap View journeys.
3. Inspect the app bar, list, and a journey detail.

Expected:

Journey history and details use the warm-sand/white/teal/orange map-first design with a readable header and Manrope hierarchy.

Actual:

Journey History uses carbon-black cards and old electric-red/orange tokens. Because the global AppBar theme now supplies dark foreground text, the `JOURNEY HISTORY` title and back icon are nearly black on black. Journey Details remains a full legacy dark/orange screen.

Frequency: 1/1.

User impact: A primary profile action opens a visually broken, difficult-to-navigate screen and makes the rebrand feel incomplete.

Evidence:

- `/private/tmp/tulink-e2e-audit/profile-view-journeys-legacy.png`
- `/private/tmp/tulink-e2e-audit/journey-history-card-tap.png`

Likely location:

- `/Users/wesleynyamu/Code/tulink_flutter/lib/features/analytics/presentation/screens/journey_history_screen.dart:32`
- `/Users/wesleynyamu/Code/tulink_flutter/lib/features/analytics/presentation/screens/journey_details_screen.dart:55`
- `/Users/wesleynyamu/Code/tulink_flutter/lib/core/theme/app_theme.dart:86`

Probable root cause (inference): Compatibility color aliases preserved legacy dark bodies while the global light AppBar foreground migrated to ink, creating a mixed-theme contrast failure.

Recommended fix: Rebuild both analytics screens using semantic light tokens and Manrope; explicitly migrate loading, empty, error, cancelled, completed, map-preview, and back-navigation states together.

Suggested regression test: Widget/golden tests for history loading/empty/error/populated and details completed/cancelled on the current light theme, including a contrast assertion for app-bar foreground/background.

### TUL-E2E-002 — P1 — Failed login clears credentials without durable error feedback

Preconditions:

- User B is on Login.

Steps:

1. Enter a valid-format unknown email or the disposable account email.
2. Enter an incorrect password.
3. Submit using the keyboard Done action.
4. Observe the form after the request completes.

Expected:

The entered email remains available, the password behavior is predictable, and an accessible error explains incorrect credentials/unknown account long enough to act on it.

Actual:

In both failed cases the form returned empty. No inline error or durable accessible announcement remained. The implementation emits a raw SnackBar attached to an inline auth screen, contrary to the required CarToast pattern.

Frequency: 2/2 failed-login attempts.

User impact: Users must re-enter credentials and may not understand whether the account, password, or network failed.

Evidence:

- `/private/tmp/tulink-e2e-audit/login-incorrect-password.png`
- `/private/tmp/tulink-e2e-audit/login-unknown-account-feedback.png`

Likely location:

- `/Users/wesleynyamu/Code/tulink_flutter/lib/features/auth/presentation/screens/auth_screen.dart:205`
- `/Users/wesleynyamu/Code/tulink_flutter/lib/features/auth/presentation/screens/auth_screen.dart:230`
- `/Users/wesleynyamu/Code/tulink_flutter/lib/main.dart` (reactive inline auth-screen ownership)

Probable root cause (inference): AuthProvider state changes cause the inline AuthScreen to rebuild/remount while failure feedback is owned by that transient subtree; the raw SnackBar does not provide persistent form state.

Recommended fix: Preserve controller state across failed attempts, map failures to CarToast plus an inline semantic error region, and keep focus/keyboard behavior deterministic.

Suggested regression test: Widget test submitting wrong and unknown credentials via both button and `TextInputAction.done`, asserting controller retention and an accessible error message.

### TUL-E2E-003 — P2 — Authentication and verification surfaces still use the legacy design language

Preconditions: Signed-out or unverified user.

Steps: Open Login, Sign Up, Forgot Password, and Verify Email.

Expected: Warm-sand/white/teal/orange semantic palette and Manrope hierarchy consistent with map home/profile.

Actual: Screens use carbon black, the old red TL mark/orange verification icon, old spacing and dark cards. This creates a hard visual discontinuity before the map-first experience.

Frequency: All four inspected auth surfaces.

User impact: High-traffic onboarding appears to belong to an older product and weakens confidence in the redesign.

Evidence:

- `/private/tmp/tulink-e2e-audit/secondary-fresh-auth.png`
- `/private/tmp/tulink-e2e-audit/sign-up-initial.png`
- `/private/tmp/tulink-e2e-audit/forgot-password.png`
- `/private/tmp/tulink-e2e-audit/login-correct-user-b.png`

Likely location:

- `/Users/wesleynyamu/Code/tulink_flutter/lib/features/auth/presentation/screens/auth_screen.dart:42`
- `/Users/wesleynyamu/Code/tulink_flutter/lib/features/auth/presentation/screens/sign_up_screen.dart:45`
- `/Users/wesleynyamu/Code/tulink_flutter/lib/features/auth/presentation/screens/forgot_password_screen.dart:39`
- `/Users/wesleynyamu/Code/tulink_flutter/lib/features/auth/presentation/screens/verify_email_screen.dart:64`

Probable root cause (inference): The map-first branch migrated the theme and main shell first while compatibility aliases intentionally kept unmigrated auth screens readable.

Recommended fix: Migrate the entire auth family as one design slice, including validation, keyboard, loading, social auth, resend cooldown, and error states.

Suggested regression test: Golden tests at iPhone 16 Pro dimensions for login, validation-expanded login, keyboard-open login, sign-up, forgot password, and verification cooldown.

### TUL-E2E-004 — P2 — Profile advertises incomplete settings and edit actions as working affordances

Preconditions: User A is on Profile.

Steps: Tap either Edit profile control, Notifications, Privacy, Linked accounts, and Help & support.

Expected: A functioning destination, a clearly disabled/labelled future feature, or an approved informational toast.

Actual: Every item is a tappable chevron/action but only shows `coming soon` through a raw SnackBar. The visual treatment implies completed functionality.

Frequency: 5/5 affordances.

User impact: Confusing dead ends and false product promises; raw SnackBars also violate the project toast contract.

Evidence: `/private/tmp/tulink-e2e-audit/profile-settings.png`

Likely location:

- `/Users/wesleynyamu/Code/tulink_flutter/lib/features/profile/presentation/screens/profile_screen.dart:49`
- `/Users/wesleynyamu/Code/tulink_flutter/lib/features/profile/presentation/screens/profile_screen.dart:124`
- `/Users/wesleynyamu/Code/tulink_flutter/lib/features/profile/presentation/screens/profile_screen.dart:172`

Probable root cause (inference): Visual redesign shipped ahead of the destination screens and retained placeholder callbacks.

Recommended fix: Implement destinations or remove/disable the affordances with explicit availability copy; use CarToastService for informational feedback.

Suggested regression test: Interaction tests for every settings row asserting a route, external action, or explicit disabled semantics.

### TUL-E2E-005 — P2 — Voice-navigation preference does not persist

Preconditions: User A is signed in.

Steps:

1. Open Profile and disable Voice navigation.
2. Terminate and relaunch the app.
3. Return to Profile.

Expected: The switch remains disabled.

Actual: It returns to enabled after relaunch.

Frequency: 1/1.

User impact: Users may unexpectedly hear navigation audio after explicitly disabling it.

Evidence: `/private/tmp/tulink-e2e-audit/profile-settings.png`

Likely location: `/Users/wesleynyamu/Code/tulink_flutter/lib/features/maps/presentation/providers/navigation_provider.dart:195`

Probable root cause (inference): `setVoiceEnabled` changes only the in-memory VoiceInstructionService and never reads/writes persistent settings.

Recommended fix: Persist the preference in an existing local settings store and initialize NavigationProvider from it before rendering Profile/navigation.

Suggested regression test: Provider/integration test toggling, recreating provider/service locator, and asserting the restored value.

### TUL-E2E-006 — P2 — Location permission sheets are an unmigrated duplicate-handle dark flow

Preconditions: Location permission denied and a journey draft is ready.

Steps: Tap Start journey.

Expected: A single-handle warm-sand semantic permission sheet consistent with the map-first flow and current `Tulink` spelling.

Actual: A carbon-black/orange sheet appears, uses `Tu-Link` spelling, and shows both the theme-provided drag handle and a second custom handle.

Frequency: 1/1 denied Start test.

User impact: Permission recovery is visually inconsistent at a high-friction moment and the double handle looks broken.

Evidence: `/private/tmp/tulink-e2e-audit/location-start-permission-prompt.png`

Likely location:

- `/Users/wesleynyamu/Code/tulink_flutter/lib/core/widgets/location_access_sheet.dart:78`
- `/Users/wesleynyamu/Code/tulink_flutter/lib/core/widgets/location_access_sheet.dart:114`
- `/Users/wesleynyamu/Code/tulink_flutter/lib/core/widgets/location_access_sheet.dart:185`
- `/Users/wesleynyamu/Code/tulink_flutter/lib/core/theme/app_theme.dart:170`

Probable root cause (inference): The sheet predates the light-theme migration and manually draws a handle now also supplied globally.

Recommended fix: Convert to semantic light tokens, standardize product spelling, and retain only one drag-handle implementation.

Suggested regression test: Golden/interaction tests for first-run priming, denied, denied-forever, and services-off variants.

### TUL-E2E-007 — P2 — Live-journey presentation remains on Rajdhani/Inter and legacy dark/red tokens

Preconditions: Source inventory; runtime live journey was blocked by the verified-second-user constraint.

Steps: Inspect active map/convoy presentation components used by `/mapview`.

Expected: Manrope and the map-first semantic palette throughout live state.

Actual: Convoy status, progress, metrics, member markers, turn instructions, and live-map panels still explicitly use carbon black/electric red and GoogleFonts Rajdhani/Inter.

Frequency: Systematic across the live-journey component inventory.

User impact: The most important real-time flow is likely to switch back to the prior design language when entered.

Evidence: Source inventory; live runtime visual confirmation is a residual gap.

Likely location:

- `/Users/wesleynyamu/Code/tulink_flutter/lib/features/maps/presentation/tulink_map_screen.dart:2154`
- `/Users/wesleynyamu/Code/tulink_flutter/lib/features/convoy/presentation/widgets/journey_progress_card.dart:76`
- `/Users/wesleynyamu/Code/tulink_flutter/lib/features/convoy/presentation/widgets/convoy_bottom_sheet.dart:29`
- `/Users/wesleynyamu/Code/tulink_flutter/lib/features/convoy/presentation/widgets/convoy_metrics_bottom_sheet.dart:63`
- `/Users/wesleynyamu/Code/tulink_flutter/lib/features/convoy/presentation/widgets/convoy_status_bar.dart:69`

Probable root cause (inference): The redesign concentrated on Home/Profile and left the active convoy slice on compatibility aliases.

Recommended fix: Migrate the complete live state in one pass, including reconnect/error/ended/leave/leader-only controls and member markers.

Suggested regression test: Golden tests for solo leader, two-member convoy, reconnecting, disconnected, participant-left, arrived, ended, and overflow-name states.

### TUL-E2E-008 — P2 — Multiple interactive controls have incomplete accessibility semantics

Preconditions: VoiceOver-style element inspection through mobile automation.

Steps: Inspect Login password toggle, Verify Email back button, Profile settings, and Journey History cards.

Expected: Meaningful button labels, roles, values, and hints for all interactive controls.

Actual: Password visibility and Verify Email back controls are exposed as unlabeled buttons. Several tappable settings/history rows are exposed primarily as StaticText instead of a clear button action.

Frequency: Reproducible on inspected screens.

User impact: Screen-reader users cannot reliably discover or understand important actions.

Evidence:

- `/private/tmp/tulink-e2e-audit/auth-keyboard-invalid.png`
- `/private/tmp/tulink-e2e-audit/user-b-relaunch-after-resend.png`
- `/private/tmp/tulink-e2e-audit/profile-settings.png`

Likely location:

- `/Users/wesleynyamu/Code/tulink_flutter/lib/features/auth/presentation/screens/auth_screen.dart:119`
- `/Users/wesleynyamu/Code/tulink_flutter/lib/features/auth/presentation/screens/verify_email_screen.dart`
- `/Users/wesleynyamu/Code/tulink_flutter/lib/features/profile/presentation/widgets/settings_menu_item.dart:30`
- `/Users/wesleynyamu/Code/tulink_flutter/lib/features/analytics/presentation/screens/journey_history_screen.dart:161`

Probable root cause (inference): Visual InkWell/IconButton composition was not paired with explicit Semantics/tooltip labels and merged row actions.

Recommended fix: Add labels, toggled values, hints, and `button` semantics; verify traversal order and announcements with VoiceOver.

Suggested regression test: SemanticsTester assertions for labels/roles/toggled state plus a manual VoiceOver pass.

### TUL-E2E-009 — P2 — Static quality gates fail at large scale

Preconditions: Current dirty worktree exactly as tested.

Steps: Run non-writing format check and analyzers.

Expected: Format check and analyzer pass.

Actual: 102 of 198 Dart files would be reformatted. `flutter analyze` crashes in the installed toolchain before analysis. Fallback `dart analyze` completes with 2,813 issues: 48 warnings, 2,765 info, 0 analyzer errors.

Frequency: 1/1.

User impact: High noise hides regressions, prevents reliable CI gating, and increases migration risk.

Evidence:

- `/private/tmp/tulink-e2e-audit/dart-format.log`
- `/private/tmp/tulink-e2e-audit/flutter-analyze.log`
- `/private/tmp/tulink-e2e-audit/flutter-analyze-crash.log`
- `/private/tmp/tulink-e2e-audit/dart-analyze.log`

Likely location: Repository-wide; current map screen alone includes unused imports/fields and inference warnings.

Probable root cause (inference): Long-lived lint debt plus a Flutter/Dart analysis-server invocation mismatch in this local SDK.

Recommended fix: Repair/replace the local SDK analysis-server installation, establish an agreed warning baseline, then reduce and gate lint debt incrementally.

Suggested regression test: CI jobs for `dart format --output=none --set-exit-if-changed`, `flutter analyze`, and `flutter test` on a pinned Flutter SDK.

### TUL-E2E-010 — P3 — Route-preview loading is visually silent while Start remains enabled

Preconditions: Tap Go Again or select a destination with a slower route response.

Steps: Observe the draft immediately, then after route response.

Expected: A visible route-loading state or disabled Start until preview resolution completes.

Actual: The draft and Start button render immediately; marker/route/framing appear later with no loading explanation. The eventual route rendered successfully.

Frequency: Observed on Go Again; destination search also uses the same async sequence.

User impact: Users may think route generation failed or start before visually confirming the route.

Evidence:

- `/private/tmp/tulink-e2e-audit/go-again-draft.png`
- `/private/tmp/tulink-e2e-audit/location-start-permission-prompt.png` (later route visible behind sheet)

Likely location:

- `/Users/wesleynyamu/Code/tulink_flutter/lib/features/home/presentation/screens/home_screen.dart:431`
- `/Users/wesleynyamu/Code/tulink_flutter/lib/features/home/presentation/screens/home_screen.dart:250`
- `/Users/wesleynyamu/Code/tulink_flutter/lib/features/home/presentation/screens/home_screen.dart:706`

Probable root cause (inference): `_destination` is committed before awaiting `_showDestinationOnMap`, and the ready sheet tracks only `_isStarting`, not route-preview state.

Recommended fix: Track route-preview loading/failure explicitly; disable or relabel Start only if route confirmation is a product requirement.

Suggested regression test: Delayed/failing MapRepository widget tests asserting loading, success, and fallback UI.

### TUL-E2E-011 — P3 — Resend verification briefly entered an inconsistent `0s`/Signing out state

Preconditions: Newly registered User B on Verify Email.

Steps: Tap Resend verification email immediately after registration.

Expected: Button becomes disabled at `Resend in 60s` and counts down.

Actual: One run showed `Resend in 0s` together with `Signing out...` and remained there until termination. After relaunch, resend behaved correctly from 60 seconds.

Frequency: 1 anomalous run; 1 clean retry.

User impact: Intermittent confusion and apparent hang on a security-critical gate.

Evidence:

- `/private/tmp/tulink-e2e-audit/verification-resend-cooldown.png`
- `/private/tmp/tulink-e2e-audit/user-b-relaunch-after-resend.png`

Likely location:

- `/Users/wesleynyamu/Code/tulink_flutter/lib/features/auth/presentation/providers/email_verification_provider.dart:125`
- `/Users/wesleynyamu/Code/tulink_flutter/lib/features/auth/presentation/providers/email_verification_provider.dart:153`
- `/Users/wesleynyamu/Code/tulink_flutter/lib/features/auth/presentation/screens/verify_email_screen.dart`

Probable root cause (inference): A race between verification polling/auth-session state and resend UI initialization; not proven because the retry did not reproduce.

Recommended fix: Add structured state-transition logging, prevent polling/resend overlap from triggering sign-out UI, and make cooldown initialization atomic.

Suggested regression test: Fake-timer provider tests that overlap poll and resend completion, plus an integration test immediately resending after registration.

## Legacy or Incomplete Redesign Inventory

Confirmed visually:

- Login: carbon-black background, legacy red TL mark, old auth layout.
- Sign Up: carbon-black legacy form and social-auth layout.
- Forgot Password: legacy dark screen.
- Verify Email: carbon-black/orange screen.
- Profile → Journey History: legacy dark cards; unreadable light-theme AppBar foreground collision.
- Journey Details: legacy dark/orange map/stats design.
- Location priming/required sheets: dark/orange, old `Tu-Link` spelling, duplicate drag handles.
- Profile edit, Notifications, Privacy, Linked accounts, and Help & support: visually active but incomplete Coming Soon states.

Confirmed from active source paths and semantic-token/font inventory:

- Legacy journey creation/preview/invite screens: `create_journey_screen.dart`, `journey_preview_screen.dart`, `invite_participants_screen.dart`.
- Standalone invitations screen: `invitations_screen.dart`.
- Active live map panels in `tulink_map_screen.dart`.
- `journey_progress_card.dart`, `convoy_bottom_sheet.dart`, `convoy_status_bar.dart`, `convoy_metrics_bottom_sheet.dart`.
- `driver_marker.dart`, `member_avatar_marker.dart`, `turn_instruction_card.dart`, `map_header_overlay.dart`, `map_journey_overlay.dart`.
- Shared `journey_info_card.dart`, `status_indicator.dart`, `shimmer_widgets.dart`, and `undefined_route_screen.dart` retain compatibility tokens.
- Older home widgets (`dashboard_card.dart`, `journey_card.dart`, `journeys_card.dart`, `recent_journey_item.dart`) retain legacy styling even if not all are active in the new shell.
- `main.dart` still references compatibility palette values for non-migrated startup states.

Feedback pattern migration is incomplete. Raw SnackBars remain in:

- Auth login and sign-up.
- Profile Coming Soon actions.
- Legacy create journey and journey preview actions.
- Active map reconnect/refresh/end/leave feedback.

These violate the project requirement to use `CarToastService.showSuccess/showError/showInfo`.

Font migration is incomplete. The global theme uses bundled Manrope, but active live-journey/convoy widgets still explicitly request GoogleFonts Rajdhani and Inter.

## Runtime and Console Findings

### Actionable application/runtime observations

- Three CoreLocation `kCLErrorDomain error 0` update failures were captured on the primary simulator. The map remained usable through fallback/cached origin behavior. Evidence: `/private/tmp/tulink-e2e-audit/runtime-actionable-sanitized.log`.
- Two expected HTTP 404 responses occurred for the deliberately invalid journey-code submissions; UI normalized these to `Journey code not found` and remained stable.
- No Flutter exception, red screen, RenderFlex overflow, Mapbox render error, or TuLink crash report was captured.
- No stale-cache warning or socket failure was observed during tested non-live flows.

### Harmless/environmental simulator noise

- Firebase Crashlytics startup banner.
- Mapbox telemetry/network activity.
- CoreSimulator unified-log background-task chatter.
- Simulator location update failure when no simulated movement/fix was available.
- The first direct Mobile MCP launch checks returned to SpringBoard before a console-attached launch was used; the app remained stable when launched through `simctl --console`, so this was treated as tooling/launch timing rather than an app crash.

The verbose raw unified log was removed after extracting a sanitized actionable excerpt because it contained unnecessary network/session context. The valid report evidence is `/private/tmp/tulink-e2e-audit/runtime-actionable-sanitized.log`.

## Automated Test Results

| Command | Result | Totals / details | Evidence |
|---|---|---|---|
| `dart format --output=none --set-exit-if-changed lib test` | Fail | 198 files checked; 102 would change; no files modified | `/private/tmp/tulink-e2e-audit/dart-format.log` |
| `flutter analyze` | Tool crash | Analysis server snapshot invocation exited 64 before project analysis | `/private/tmp/tulink-e2e-audit/flutter-analyze.log`, `/private/tmp/tulink-e2e-audit/flutter-analyze-crash.log` |
| `dart analyze` | Fail | 2,813 issues: 48 warnings, 2,765 info, 0 errors | `/private/tmp/tulink-e2e-audit/dart-analyze.log` |
| `flutter test` | Pass with skips | 175 passed, 0 failed, 14 skipped | `/private/tmp/tulink-e2e-audit/flutter-test.log` |
| Focused tests | Included in full suite | Auth integration-style tests, join-code sheet, journey provider/repository/model, invites provider, convoy sockets/provider/self-filtering, maps route/interpolation, token/network/toast tests | `/private/tmp/tulink-e2e-audit/flutter-test.log` |
| `flutter build ios --simulator --debug` | Pass | Built `build/ios/iphonesimulator/Runner.app` | `/private/tmp/tulink-e2e-audit/flutter-build-ios-simulator.log` |

There is no repository `integration_test/` directory. The file `test/features/auth/integration/auth_integration_test.dart` runs inside the normal Flutter test suite and does not replace a device-driven integration harness.

## Residual Test Gaps

- User B could not be verified because no disposable inbox/link-capture mechanism was supplied. This is the principal blocker.
- The audit did not use or disclose any existing credentials to place User A on the second device.
- Invitation badge refresh, accept/decline, valid and expired codes, and participant-state synchronization remain untested at runtime.
- No live journey was created on User A because that account was not disposable and the instructions prohibited modifying existing account/journey data.
- Two-user live route, movement, leader/member markers, current-user de-duplication, ETA/distance/progress, foreground/background, kill/reopen, reconnect, connectivity interruption, leave, end/cancel, and socket cleanup remain blocked.
- Push-notification tap routing was not testable without a simulator push payload and verified recipient.
- Successful password-reset delivery was not tested to avoid sending mail to an unknown/non-test inbox.
- Duplicate registration was not repeated against the disposable address because the first account remained unverified and no safe deletion/reset path was established.
- Device-wide offline mode was not used because the available controls were not app-scoped and could affect unrelated host work.
- Smaller-screen coverage used iPhone 16 Pro; no iPhone SE-class runtime was available in the installed simulator set.
- Screen-reader behavior was inspected through element roles/labels, not a full manual VoiceOver audio traversal.

Blocked states are not counted as passes.

## Recommended Remediation Order

### 1. Release blockers

1. Provide a development email-capture/verification mechanism and rerun the full two-user matrix.
2. Repair Journey History/Details theme and app-bar contrast before broader testing.
3. Fix failed-login state retention and durable, accessible error feedback.

### 2. Core-flow failures

1. Complete invitation, valid-code, and two-user live-journey runtime validation after verified test users exist.
2. Replace Profile Coming Soon affordances with real destinations or explicitly disabled states.
3. Add route-preview loading/failure UI and confirm duplicate Start protection on device.

### 3. Reliability and state recovery

1. Persist voice-navigation preference.
2. Investigate the intermittent verification resend/sign-out race.
3. Add structured, redacted runtime logging for auth, route preview, invitation, and socket state transitions.
4. Add device integration tests for restart, reconnect, background/foreground, and sign-out cleanup.

### 4. Visual/theme inconsistencies

1. Migrate Auth, Verification, History, Details, and Location sheets.
2. Migrate the full live-map/convoy component family from compatibility aliases and Rajdhani/Inter to semantic tokens and Manrope.
3. Remove duplicate drag handles and standardize `Tulink` naming.
4. Replace all raw SnackBars with CarToastService.

### 5. Accessibility and polish

1. Label password visibility and verification back controls.
2. Merge row semantics for settings/history cards and expose button/toggle state correctly.
3. Verify keyboard-expanded auth scrolling and safe-area behavior on an SE-class device.
4. Restore clean format/analyzer gates on a pinned, healthy Flutter SDK.

## Final Verdict

The map-first home and draft-journey interaction are promising and suitable for continued internal development testing, but the rebrand and redesigned process flows are **not ready for broader testing or release sign-off**. The visible migration is incomplete on authentication, history/details, location recovery, and likely the live journey. More importantly, the audit could not validate the product's defining multi-user lifecycle without a verified disposable second user.

Do not begin remediation from this report without explicit approval. The repository was not fixed, staged, committed, reverted, or cleaned during this audit.
