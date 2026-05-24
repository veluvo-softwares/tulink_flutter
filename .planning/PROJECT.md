# Email Verification Flow

## What This Is

A security gate that prevents unverified users from accessing TuLink after registration or login. When a user's `emailVerified` field is `false`, the app intercepts the auth flow and shows a dedicated screen prompting them to check their inbox. The screen auto-polls for verification in the background and lets users resend the verification link with a 60-second cooldown.

## Core Value

Unverified users cannot reach the app — verified users flow through without friction.

## Requirements

### Validated

- ✓ `UserEntity.isEmailVerified` field exists — existing
- ✓ Auth flow (signIn, signUp, signOut, token refresh) — existing
- ✓ `CarToastService` for success/error toasts — existing
- ✓ `Failure` hierarchy with typed error handling — existing
- ✓ `AuthRepository` / `AuthProvider` / `AuthApiService` pattern — existing
- ✓ `AppRouter` with `generateRoute` for screen registration — existing

### Active

- [ ] **VER-01**: Verify Email screen displays user's email address and inbox prompt
- [ ] **VER-02**: Screen auto-polls backend in background; navigates home when `emailVerified` becomes `true`
- [ ] **VER-03**: Resend button calls `POST /auth/send-email-verification` with Bearer token
- [ ] **VER-04**: Resend button disabled for 60s after each tap with live countdown display
- [ ] **VER-05**: Friendly error toasts for resend failures (401, 400, generic)
- [ ] **VER-06**: "Already verified" backend response shows info toast then proceeds to home
- [ ] **VER-07**: After `signIn`: if `emailVerified=false` → navigate to VerifyEmailScreen instead of home
- [ ] **VER-08**: After `signUp`: if `emailVerified=false` → navigate to VerifyEmailScreen
- [ ] **VER-09**: `HomePage` gate updated — `isSignedIn && !isEmailVerified` → VerifyEmailScreen

### Out of Scope

- Deep link re-entry from email client — user chose background polling instead
- Social auth (OAuth) email verification — app uses email/password only
- Email change verification — separate flow, not part of this feature
- OTP / code-based verification — backend uses link-based verification

## Context

**Codebase:** Flutter app with clean architecture (data / domain / presentation), Provider (`ChangeNotifier`) for state, GetIt for DI, Dio for HTTP.

**Auth layer today:**
- `lib/features/auth/domain/entities/user_entity.dart` — `isEmailVerified` field already present
- `lib/features/auth/domain/repositories/auth_repository.dart` — has `verifyEmail({token})` (deep-link path, not resend)
- `lib/features/auth/presentation/providers/auth_provider.dart` — `signIn`/`signUp` return `true` even when `emailVerified=false`; no verification gate exists yet
- `lib/main.dart` `HomePage` — currently gates only on `isSignedIn`, not `isEmailVerified`

**API contract:**
- Resend: `POST /auth/send-email-verification` — Bearer token required, no request body
- Re-check: `GET /auth/profile` (existing `getCurrentUser`) — returns fresh `emailVerified` status
- Poll interval chosen: 5 seconds (balance between responsiveness and API load)

## Constraints

- **Tech stack**: Dart / Flutter only — no new state management libraries
- **Theming**: Must use `TulinkColors` (dark theme — `carbonBlack`, `electricRed`, `silver`) and existing `AppTheme`
- **Toast pattern**: Must use `CarToastService.showSuccess/showError/showInfo` — no raw SnackBars
- **Architecture**: New code follows clean-arch layers; `sendEmailVerification` added to `AuthRepository` and implemented in data layer

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Auto-poll (5s interval) instead of deep link | User chose; simpler UX, no URL scheme setup needed | — Pending |
| 60s resend cooldown | Prevent spam; matches common UX pattern | — Pending |
| Poll via existing `getCurrentUser` endpoint | No new endpoint needed; returns fresh `emailVerified` | — Pending |
| Gate in `HomePage` Consumer + `AuthProvider` after signIn/signUp | Minimal surface area; consistent with existing auth gate pattern | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-05-24 after initialization*
