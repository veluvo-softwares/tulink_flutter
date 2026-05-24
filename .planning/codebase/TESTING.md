# Testing
*Mapped: 2026-05-24*

## Framework

- **`flutter_test`** — primary test framework (built-in Flutter SDK)
- **`mockito`** (expected, via DI patterns) — mocking; not explicitly confirmed in test files
- No integration test runner beyond `flutter_test` observed

## Test Structure

```
test/
├── widget_test.dart                          # Default Flutter widget smoke test
├── core/
│   ├── network/
│   │   └── api_handler_test.dart             # Unit tests for ApiHandler
│   └── errors/
│       └── failure_test.dart                 # Unit tests for Failure hierarchy
├── features/
│   └── auth/
│       ├── data/services/
│       │   └── auth_api_service_test.dart    # Service layer unit tests
│       └── integration/
│           └── auth_integration_test.dart    # Integration tests
└── unit/
    └── features/
        └── convoy/
            └── models/
                └── member_position_model_test.dart  # Model unit tests
```

## Coverage

- **Low coverage** — only 7 test files for a large codebase (~50+ Dart files)
- No tests for: providers, use cases, repositories, navigation, maps, journeys, invites, analytics
- Auth and core networking are the best-covered areas

## Test Patterns

### Unit Tests (api_handler_test.dart)
```dart
group('ApiHandler Tests', () {
  test('should handle successful API response', () async {
    final mockResponse = Response<Map<String, dynamic>>(...);
    final result = await ApiHandler.performApiCall<String>(...);
    expect(result, equals('success'));
  });
});
```
- Uses `group()` + `test()` structure
- `setUp()` used for shared test fixtures
- Direct construction (no mocking framework observed in these files)

### Service Tests (auth_api_service_test.dart)
- Tests endpoint string correctness (not HTTP behavior)
- Tests `ApiQueryBuilder` query string construction
- Does **not** mock HTTP — tests structural contracts only

### Key Testing Gaps

| Area | Status |
|------|--------|
| Providers (ChangeNotifier) | No tests |
| Use cases | No tests |
| Repository implementations | No tests |
| Navigation/routing | No tests |
| Convoy/real-time features | Model test only |
| Map & navigation features | No tests |

## Running Tests

```bash
flutter test                          # Run all tests
flutter test test/core/               # Run core tests only
flutter test --coverage               # Generate coverage report
```

## Mocking Strategy

- No mocking library confirmed in `pubspec.yaml` (mockito/mocktail not yet added)
- Tests use real objects or minimal constructors
- Integration test (`auth_integration_test.dart`) likely hits real endpoints or uses dio mocks
