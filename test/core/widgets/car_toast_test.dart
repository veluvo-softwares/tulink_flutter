import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tulink_flutter/core/widgets/car_toast.dart';

void main() {
  testWidgets('can be disposed while its animation sequence is waiting', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: CarToast(message: 'Journey invitation received')),
    );
    await tester.pump(const Duration(milliseconds: 900));

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(seconds: 3));

    expect(tester.takeException(), isNull);
  });
}
