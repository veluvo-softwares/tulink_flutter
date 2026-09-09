import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/core/layout/tulink_breakpoints.dart';

void main() {
  Widget probe(Size size, ValueChanged<bool> onWide) {
    return MediaQuery(
      data: MediaQueryData(size: size),
      child: Builder(
        builder: (context) {
          onWide(TulinkBreakpoints.isWideLandscape(context));
          return const SizedBox.shrink();
        },
      ),
    );
  }

  testWidgets('uses wide layout for landscape tablet and Mac-sized windows', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      probe(const Size(1194, 834), (value) => result = value),
    );
    expect(result, isTrue);
  });

  testWidgets('keeps the phone layout below the wide breakpoint', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      probe(const Size(844, 390), (value) => result = value),
    );
    expect(result, isFalse);
  });

  testWidgets('keeps the portrait tablet layout when height is dominant', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      probe(const Size(834, 1194), (value) => result = value),
    );
    expect(result, isFalse);
  });
}
