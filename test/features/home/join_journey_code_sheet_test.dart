import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/core/theme/app_theme.dart';
import 'package:tulink_flutter/features/home/presentation/screens/home_screen.dart';

void main() {
  testWidgets('code sheet can close after typing without a controller error', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.tulinkTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const JoinJourneyCodeSheet(),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ABCD234567');

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    expect(find.byType(JoinJourneyCodeSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
