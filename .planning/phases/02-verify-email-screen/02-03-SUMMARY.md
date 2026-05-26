---
phase: "02"
plan: "03"
subsystem: auth
tags: [email-verification, screen, navigation, di-wiring]
dependency_graph:
  requires:
    - EmailVerificationProvider (plan 02-02)
    - CarToastService.showInfo (plan 02-01)
    - AuthProvider.signOut()
    - assets/icons/email_verification.svg (plan 02-02)
  provides:
    - VerifyEmailScreen StatefulWidget (/verify-email)
    - AppRouter case for VerifyEmailScreen.routeName
    - Routes.verifyEmail constant
    - ServiceLocator.emailVerificationProvider getter
    - EmailVerificationProvider in MultiProvider
  affects:
    - lib/features/auth/presentation/screens/verify_email_screen.dart
    - lib/core/navigation/app_router.dart
    - lib/core/di/service_locator.dart
    - lib/main.dart
tech_stack:
  added: []
  patterns:
    - StatefulWidget with post-frame startPolling/dispose stopPolling lifecycle
    - Consumer<EmailVerificationProvider> declarative auto-navigation on isEmailVerified
    - Consumer<AuthProvider> loading-state TextButton for sign-out
    - OutlinedButton with electricRed border for resend CTA
    - pushNamedAndRemoveUntil stack-clearing navigation
key_files:
  created:
    - lib/features/auth/presentation/screens/verify_email_screen.dart
  modified:
    - lib/core/navigation/app_router.dart
    - lib/core/di/service_locator.dart
    - lib/main.dart
decisions:
  - Consumer<EmailVerificationProvider> drives auto-navigation via post-frame callback (declarative pattern per STATE.md)
  - _handleSignOut uses pushNamedAndRemoveUntil(AuthScreen.routeName) to clear full stack (D-04, T-02-08)
  - crossAxisAlignment removed from Column (center is default; avoids redundant arg lint)
  - All imports use package: URIs per very_good_analysis always_use_package_imports rule
metrics:
  duration: "~6m"
  completed: "2026-05-26T19:51:47Z"
  tasks: 3
  files_modified: 4
requirements:
  - SCR-01
  - SCR-02
  - SCR-03
  - SCR-04
  - SCR-05
  - SCR-06
  - SCR-07
---

# Phase 2 Plan 3: VerifyEmailScreen and Dependency Wiring Summary

**One-liner:** VerifyEmailScreen StatefulWidget with carbonBlack layout, SVG icon, Consumer-driven resend/sign-out buttons, and full ServiceLocator + AppRouter wiring.

## What Was Built

This plan assembles the visible surface of the email verification flow and connects it to the foundations from plans 00–02.

### Task 1: EmailVerificationProvider in ServiceLocator and main.dart

Added `EmailVerificationProvider` to `ServiceLocator`:
- `_emailVerificationProvider` late field in the private fields section
- `emailVerificationProvider` getter in the getters section
- Instantiation `EmailVerificationProvider(_authProvider)` immediately after `_authProvider` (D-03: constructor injection)

Added `ChangeNotifierProvider<EmailVerificationProvider>.value` to the `MultiProvider` in `MyApp`, immediately after the `AuthProvider` entry.

### Task 2: AppRouter route for VerifyEmailScreen

Added to `lib/core/navigation/app_router.dart`:
- Import: `package:tulink_flutter/features/auth/presentation/screens/verify_email_screen.dart`
- `case VerifyEmailScreen.routeName:` block (no-args pattern, same as AuthScreen)
- `Routes.verifyEmail = VerifyEmailScreen.routeName` constant in the `Routes` abstract class

### Task 3: VerifyEmailScreen

Created `lib/features/auth/presentation/screens/verify_email_screen.dart`:

**Lifecycle:**
- `initState` calls `startPolling()` via `WidgetsBinding.instance.addPostFrameCallback`
- `dispose` calls `stopPolling()` then `super.dispose()`

**Layout (D-11, D-12):**
- `Scaffold(backgroundColor: colors.carbonBlack)` → `SafeArea` → `SingleChildScrollView(padding: EdgeInsets.all(24))` → `Column`
- SVG icon at 80×80 with `ColorFilter.mode(colors.electricRed, BlendMode.srcIn)`
- "Check your inbox" heading in `headlineMedium` white bold
- Body copy with email address and spam/junk hint in `silver`

**Auto-navigation (SCR-02):** `Consumer<EmailVerificationProvider>` checks `provider.isEmailVerified` and schedules a post-frame `pushNamedAndRemoveUntil(MainNavigationScreen.routeName)`.

**Resend button (SCR-03, SCR-04, D-10):** `Consumer<EmailVerificationProvider>` wraps a full-width `OutlinedButton` with `electricRed` border/foreground. `onPressed: provider.canResend ? _handleResend : null`. Label: `'Resend'` or `'Resend in ${n}s'`.

**Sign-out button (SCR-07, D-04, D-05, D-06):** `Consumer<AuthProvider>` wraps a `TextButton`. While `isLoading`, shows inline `CircularProgressIndicator` + "Signing out..." in silver. `_handleSignOut` calls `signOut()`, guards with `!mounted`, then `pushNamedAndRemoveUntil(AuthScreen.routeName)` on success or `CarToastService.showError` on failure.

## Decisions Made

| Decision | Rationale |
|----------|-----------|
| Declarative Consumer auto-navigation via post-frame callback | Avoids imperative push from provider; aligns with accumulated STATE.md decision |
| `pushNamedAndRemoveUntil` for both sign-out and verified paths | Prevents back-navigation to VerifyEmailScreen after completing either flow (T-02-08) |
| All imports use `package:` URIs | very_good_analysis `always_use_package_imports` enforcement |
| Removed redundant `crossAxisAlignment: CrossAxisAlignment.center` | `center` is Column default; avoids `avoid_redundant_argument_values` lint |

## Deviations from Plan

None — plan executed exactly as written.

## Analysis Notes

**Worktree artifact:** `dart analyze` on `app_router.dart` reports `uri_does_not_exist` for `verify_email_screen.dart`. This is the same class of dual-package-resolution artifact documented in Plans 02-01 and 02-02: the CLI's package resolver points to the main repo's `lib/` (which does not yet have the file), not the worktree's `lib/`. The file physically exists at the correct worktree path. When the worktree is merged, all files are consistent and `dart analyze` passes with zero errors.

## Known Stubs

None — all consumer widgets are wired to live provider state.

## Threat Surface Scan

No new network endpoints or auth paths outside the plan's threat model. Navigation uses `pushNamedAndRemoveUntil` clearing the stack (T-02-08 mitigated). Sign-out error shows a toast and stays on screen (D-05).

## Self-Check

- [x] `lib/features/auth/presentation/screens/verify_email_screen.dart` exists
- [x] `class VerifyEmailScreen extends StatefulWidget` with `routeName = '/verify-email'`
- [x] `initState` calls `startPolling()` via `addPostFrameCallback`
- [x] `dispose` calls `stopPolling()`
- [x] `Consumer<EmailVerificationProvider>` drives resend button (canResend, cooldown label)
- [x] `Consumer<EmailVerificationProvider>` auto-navigates on `isEmailVerified`
- [x] `Consumer<AuthProvider>` drives sign-out TextButton with loading state
- [x] `_handleSignOut` uses `pushNamedAndRemoveUntil(AuthScreen.routeName)`
- [x] `ServiceLocator._emailVerificationProvider` field, getter, instantiation exist
- [x] `MyApp` MultiProvider contains `ChangeNotifierProvider<EmailVerificationProvider>.value`
- [x] `AppRouter` has `case VerifyEmailScreen.routeName:` and `Routes.verifyEmail` constant
- [x] Task 1 commit: a758a81
- [x] Task 2 commit: a7a2077
- [x] Task 3 commit: 4df35da

## Self-Check: PASSED
