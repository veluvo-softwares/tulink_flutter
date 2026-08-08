import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/core/navigation/navigation_helper.dart';

void main() {
  testWidgets('returning home preserves the root navigator route', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: Scaffold(
          body: Builder(
            builder: (homeContext) => TextButton(
              key: const Key('open-details'),
              onPressed: () {
                Navigator.of(homeContext).push(
                  MaterialPageRoute<void>(
                    builder: (detailContext) => Scaffold(
                      body: TextButton(
                        key: const Key('done'),
                        onPressed: () =>
                            NavigationHelper.toHomeAndClearStack(detailContext),
                        child: const Text('Done'),
                      ),
                    ),
                  ),
                );
              },
              child: const Text('Home'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-details')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('done')), findsOneWidget);

    await tester.tap(find.byKey(const Key('done')));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(navigatorKey.currentState!.canPop(), isFalse);
  });

  testWidgets('returning home twice is idempotent and keeps the root mounted', (
    tester,
  ) async {
    // Cancelling a journey returns home from two independent paths: the
    // explicit cancel handler and the journey-ended socket echo. Two raw
    // pop()s emptied the navigator and produced a black screen.
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: Scaffold(
          body: Builder(
            builder: (homeContext) => TextButton(
              key: const Key('open-preview'),
              onPressed: () {
                Navigator.of(homeContext).push(
                  MaterialPageRoute<void>(
                    builder: (previewContext) => Scaffold(
                      body: TextButton(
                        key: const Key('cancel'),
                        onPressed: () {
                          // Both callers fire for a single cancel.
                          NavigationHelper.toHomeAndClearStack(previewContext);
                          NavigationHelper.toHomeAndClearStack(previewContext);
                        },
                        child: const Text('Cancel'),
                      ),
                    ),
                  ),
                );
              },
              child: const Text('Home'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-preview')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cancel')), findsOneWidget);

    await tester.tap(find.byKey(const Key('cancel')));
    await tester.pumpAndSettle();

    // The root survives both calls — no empty navigator, no black screen.
    expect(find.text('Home'), findsOneWidget);
    expect(navigatorKey.currentState!.canPop(), isFalse);
  });
}
