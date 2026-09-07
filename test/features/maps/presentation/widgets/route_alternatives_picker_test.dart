import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/features/maps/data/models/route_result_model.dart';
import 'package:tulink_flutter/features/maps/presentation/widgets/route_alternatives_picker.dart';

void main() {
  RouteResultModel route(double distance, double duration) => RouteResultModel(
    coordinates: const [
      [36.8, -1.2],
      [36.9, -1.3],
    ],
    distanceMetres: distance,
    durationSeconds: duration,
    steps: const [],
  );

  testWidgets('shows route metrics and selects an alternative', (tester) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RouteAlternativesPicker(
            routes: [route(9500, 700), route(10200, 820)],
            selectedIndex: selected,
            onSelected: (value) => selected = value,
          ),
        ),
      ),
    );

    expect(find.text('Choose your route'), findsOneWidget);
    expect(find.text('2 options'), findsOneWidget);
    expect(find.text('Fastest'), findsOneWidget);
    expect(find.text('12 min'), findsOneWidget);
    expect(find.text('+2 min'), findsOneWidget);

    await tester.tap(find.byKey(const Key('route-option-1')));
    expect(selected, 1);
  });

  testWidgets('fits three choices in a horizontally scrollable picker', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: RouteAlternativesPicker(
              routes: [route(9500, 700), route(10200, 820), route(11000, 900)],
              selectedIndex: 0,
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.byType(ListView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
