import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:tulink_flutter/features/maps/presentation/widgets/map_style_selector.dart';

void main() {
  test('map styles use the expected Mapbox styles', () {
    expect(TulinkMapStyle.streets.styleUri, MapboxStyles.MAPBOX_STREETS);
    expect(TulinkMapStyle.terrain.styleUri, MapboxStyles.OUTDOORS);
    expect(TulinkMapStyle.satellite.styleUri, MapboxStyles.SATELLITE_STREETS);
  });

  testWidgets('selects a different map type', (tester) async {
    TulinkMapStyle? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapStyleSelector(
            selectedStyle: TulinkMapStyle.streets,
            onSelected: (value) => selected = value,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Change map type'));
    await tester.pumpAndSettle();

    expect(find.text('Streets'), findsOneWidget);
    expect(find.text('Terrain'), findsOneWidget);
    expect(find.text('Satellite'), findsOneWidget);

    await tester.tap(find.text('Terrain'));
    await tester.pumpAndSettle();

    expect(selected, TulinkMapStyle.terrain);
  });
}
