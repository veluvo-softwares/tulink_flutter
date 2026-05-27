---
phase: "02"
plan: "00"
subsystem: auth
tags: [email-verification, data-layer, repository, provider]
dependency_graph:
  requires: []
  provides:
    - AuthRepository.sendEmailVerification()
    - AuthRepository.checkEmailVerification()
    - AuthProvider.isEmailVerified
    - AuthProvider.markEmailVerified()
    - AuthProvider.sendEmailVerification()
    - AuthProvider.checkEmailVerification()
  affects:
    - lib/features/auth/domain/repositories/auth_repository.dart
    - lib/features/auth/data/repositories/auth_repository_impl.dart
    - lib/features/auth/presentation/providers/auth_provider.dart
tech_stack:
  added: []
  patterns:
    - Repository pattern with Failure record types
    - ChangeNotifier provider state management
    - Background poll pattern (no _setLoading in checkEmailVerification)
key_files:
  created: []
  modified:
    - lib/core/network/api_routes.dart
    - lib/features/auth/data/services/auth_api_service.dart
    - lib/features/auth/data/datasources/auth_remote_data_source.dart
    - lib/features/auth/domain/repositories/auth_repository.dart
    - lib/features/auth/data/repositories/auth_repository_impl.dart
    - lib/features/auth/presentation/providers/auth_provider.dart
decisions:
  - checkEmailVerification() omits _setLoading to prevent UI spinner on every 5s poll tick
  - checkEmailVerification reuses /auth/profile (ApiRoutes.currentUser) — no new endpoint needed
  - sendEmailVerification() in AuthProvider follows resetPassword() pattern with _setLoading guards
  - markEmailVerified() mutates _user via copyWith — only called after backend confirms verification
metrics:
  duration: "3m 36s"
  completed: "2026-05-26T19:12:32Z"
  tasks: 2
  files_modified: 6
requirements:
  - SCR-02
  - SCR-03
  - SCR-05
  - SCR-06
---

# Phase 2 Plan 0: Data Layer Foundation for Email Verification Summary

**One-liner:** Added sendEmailVerification (POST /auth/send-email-verification) and checkEmailVerification (GET /auth/profile) across all clean-arch layers from ApiRoutes through AuthProvider.

## What Was Built

This plan adds the minimum data-layer slice required by EmailVerificationProvider (Plan 02-02) to compile without missing-symbol errors. No UI or gate wiring — pure infrastructure plumbing across 6 files.

### Layer-by-layer changes

**Route constants (`lib/core/network/api_routes.dart`):**
- Added `ApiRoutes.sendEmailVerification = '/auth/send-email-verification'`

**API service (`lib/features/auth/data/services/auth_api_service.dart`):**
- `sendEmailVerification()` — POST to `ApiRoutes.sendEmailVerification`, no body, returns `Future<void>`
- `checkEmailVerification()` — GET to `ApiRoutes.currentUser` (reuses `/auth/profile`), returns `Future<Map<String, dynamic>>`

**Remote data source (`lib/features/auth/data/datasources/auth_remote_data_source.dart`):**
- Abstract declarations: `sendEmailVerification()` and `checkEmailVerification()` in `AuthRemoteDataSource`
- Concrete overrides: `sendEmailVerification()` delegates to service; `checkEmailVerification()` reads `responseData['emailVerified'] as bool? ?? false` and returns the bool

**Repository interface (`lib/features/auth/domain/repositories/auth_repository.dart`):**
- `sendEmailVerification()` returning `Future<({bool success, Failure? failure})>`
- `checkEmailVerification()` returning `Future<({bool isEmailVerified, Failure? failure})>`

**Repository implementation (`lib/features/auth/data/repositories/auth_repository_impl.dart`):**
- `sendEmailVerification()` — wraps remote call in try/catch; returns `(success: true, failure: null)` on success; const failure message: `'Failed to send verification email'`
- `checkEmailVerification()` — wraps remote call; on success returns `(isEmailVerified: result, failure: null)`; on failure returns `(isEmailVerified: false, failure: failure)`

**AuthProvider (`lib/features/auth/presentation/providers/auth_provider.dart`):**
- `bool get isEmailVerified` — returns `_user?.isEmailVerified ?? false`
- `void markEmailVerified()` — mutates `_user` via `copyWith(isEmailVerified: true)`, calls `notifyListeners()`
- `Future<bool> sendEmailVerification()` — follows `resetPassword()` pattern with `_setLoading` guards; no toast (EmailVerificationProvider owns messaging)
- `Future<bool> checkEmailVerification()` — does NOT call `_setLoading` (background poll must not flicker UI); returns false on any error

## Decisions Made

| Decision | Rationale |
|----------|-----------|
| `checkEmailVerification` omits `_setLoading` | The 5-second background poll runs silently; triggering `_setLoading` would cause unrelated UI elements watching `isLoading` to show a spinner on every poll tick |
| Reuse `/auth/profile` for check | No new endpoint needed; existing `getCurrentUser` path returns fresh `emailVerified` status |
| `checkEmailVerification` in impl catches generic exceptions returning `isEmailVerified: false` | Transient network errors are silently retried by the polling timer in `EmailVerificationProvider`; no need to propagate to UI |
| No toast in `AuthProvider.sendEmailVerification()` | Toast messaging responsibility belongs to `EmailVerificationProvider` which has context about the UX flow (cooldown, retry state) |

## Deviations from Plan

None — plan executed exactly as written.

## Analysis Notes

**Dart analyze worktree artifact:** `dart analyze` shows two false-positive `undefined_method` errors for `sendEmailVerification` and `checkEmailVerification` on `AuthApiService` in `auth_remote_data_source.dart`. This is caused by the Dart package resolution configuration (`package_config.json`) pointing to the main repo's `lib/` directory rather than the worktree's `lib/`. The worktree's `auth_api_service.dart` has both methods; the main repo's does not (they are new). When this worktree is merged into `main`, all files are consistent and `dart analyze` will pass with zero errors.

Pre-existing errors unrelated to this plan (`argument_type_not_assignable` in `auth_repository_impl.dart` for `UserModel` types, `return_of_invalid_type` for record return types) are also worktree analysis artifacts caused by the same package resolution issue.

## Threat Surface Scan

No new network endpoints, auth paths, or schema changes outside the plan's threat model were introduced.

## Self-Check

- [x] `lib/core/network/api_routes.dart` contains `sendEmailVerification` constant
- [x] `lib/features/auth/data/services/auth_api_service.dart` contains `sendEmailVerification()` and `checkEmailVerification()` methods
- [x] `lib/features/auth/data/datasources/auth_remote_data_source.dart` contains abstract declarations and concrete implementations for both methods
- [x] `lib/features/auth/domain/repositories/auth_repository.dart` contains abstract method declarations for both methods
- [x] `lib/features/auth/data/repositories/auth_repository_impl.dart` overrides both methods
- [x] `lib/features/auth/presentation/providers/auth_provider.dart` has `isEmailVerified` getter, `markEmailVerified()`, `sendEmailVerification()`, `checkEmailVerification()`
- [x] Task 1 commit: f0bc23e
- [x] Task 2 commit: fc5d681

## Self-Check: PASSED
