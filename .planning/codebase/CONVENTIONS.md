# Code Conventions
*Mapped: 2026-05-24*

## Language & Style

- **Language:** Dart (Flutter)
- **Lint ruleset:** `package:very_good_analysis/analysis_options.yaml` — strict linting enforced via `analysis_options.yaml`
- **Formatting:** Standard `dart format` (implicit via very_good_analysis)

## Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Files | `snake_case.dart` | `auth_provider.dart` |
| Classes | `PascalCase` | `AuthProvider`, `ServerFailure` |
| Variables/params | `camelCase` | `_isLoading`, `tokenType` |
| Private fields | Leading `_` + camelCase | `_authRepository`, `_user` |
| Constants | `camelCase` | `AppConstants.appName` |
| Feature dirs | `snake_case` | `features/convoy/` |

## Architecture Patterns

- **Clean Architecture** with three layers: `data`, `domain`, `presentation`
- **Repository pattern** — domain defines abstract repos; data layer implements them
- **Use Case pattern** — `UseCase<Type, Params>` and `NoParamsUseCase<Type>` base classes in `lib/core/usecases/usecase.dart`
- **DI via GetIt** — service locator at `lib/core/di/service_locator.dart`

## Error Handling

- **Custom Result type** using Dart records (no external Either library):
  ```dart
  typedef Result<T> = ({T? data, Failure? failure});
  typedef BoolResult = ({bool success, Failure? failure});
  ```
- **Failure hierarchy** — all failures extend `Failure extends Equatable`:
  - `ServerFailure` — HTTP errors, factory `fromStatusCode()`
  - `NetworkFailure` — connectivity issues
  - `CacheFailure` — local storage errors
  - `ValidationFailure` — field-level errors with `fieldErrors` map
  - `AuthFailure` — auth errors, `isRetryable` / `requiresReauth` flags
  - `TokenFailure` — token lifecycle errors
  - `SearchFailure` — search service errors
  - `ConvoyFailure` — real-time location/convoy errors
- Failures are immutable with `copyWith()` on every subclass
- **Never throw** from use cases or repositories — return `Result<T>` or `BoolResult`

## State Management

- **`ChangeNotifier`** (flutter Provider pattern) for all feature providers
- Private state fields with public getters only:
  ```dart
  bool _isLoading = false;
  bool get isLoading => _isLoading;
  ```
- Helper methods `_setLoading(bool)`, `_setFailure(Failure?)` used consistently
- Providers injected via DI, registered in service locator

## Logging

- Custom logger at `lib/core/utils/logger.dart`
- Feature-specific logger: `lib/core/logging/auth_logger.dart`
- `print()` still used in provider methods (debug artifact — not cleaned up)

## Comments & Documentation

- Doc comments (`///`) on public APIs and abstract classes
- Inline comments for non-obvious logic
- No file-level `library` directive except in `result.dart` (marked `library result;`)

## Import Order (very_good_analysis enforced)

1. `dart:` core
2. `package:flutter/`
3. Third-party packages
4. Local relative imports (`../../../../core/...`)
